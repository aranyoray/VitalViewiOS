//
//  UIHelpers.kt
//  MoniVitals (Android)
//
//  Shared formatting helpers and small reusable composables (metric tiles, status pills,
//  section cards, labeled rows) plus the share-sheet helper. Colors are driven from the
//  (always-light) MaterialTheme.colorScheme + the MV brand object. Deliberately avoids any
//  diagnostic/clinical language — values are labeled as estimates and the app is a research
//  tool.
//

package com.monivitals.ui

import android.content.Context
import android.content.Intent
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.monivitals.source.ConnectionState
import java.io.File
import java.util.Locale

// MARK: - Formatting

object Fmt {
    fun opt(v: Double?, decimals: Int = 0, suffix: String = ""): String {
        if (v == null) return "—"
        return String.format(Locale.US, "%.${decimals}f", v) + suffix
    }

    fun bpm(v: Double?): String = opt(v, 0)
    fun pct(v: Double?): String = opt(v, 0)

    /** Nullable integer — renders "—" (not "0") while a metric is still warming up. */
    fun int(v: Int?, suffix: String = ""): String = if (v == null) "—" else "$v$suffix"

    fun patMs(patUs: Double?): String {
        if (patUs == null) return "—"
        return String.format(Locale.US, "%.0f", patUs / 1000)
    }

    fun duration(ms: Double): String {
        val totalSec = (ms / 1000).toInt()
        return String.format(Locale.US, "%02d:%02d", totalSec / 60, totalSec % 60)
    }
}

// MARK: - Shared card treatment

/**
 * The MoniVitals card look, matching iOS `mvCard`: a soft elevation shadow under a
 * [MV.surface] fill with 16dp rounded corners and a 1dp hairline separator border.
 * Apply this to any surface that should read as a card; wrap your own padding inside.
 */
fun Modifier.mvCard(radius: Dp = 16.dp): Modifier = this
    .shadow(3.dp, RoundedCornerShape(radius), clip = false)
    .background(MV.surface, RoundedCornerShape(radius))
    .border(1.dp, MV.separator, RoundedCornerShape(radius))

// MARK: - Icon badge

/** Tinted, rounded icon chip used at the top-left of metric tiles (mirrors iOS IconBadge). */
@Composable
fun IconBadge(icon: ImageVector, tint: Color, size: Dp = 26.dp) {
    Box(
        modifier = Modifier
            .size(size)
            .background(tint.copy(alpha = 0.14f), RoundedCornerShape(8.dp)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(size * 0.55f))
    }
}

// MARK: - Empty state

/**
 * A friendly empty-state block: a tinted [IconBadge], a short title, and a supporting line,
 * all inside an [mvCard]. Used when a list/section has nothing to show yet so the screen
 * never reads as broken or blank.
 */
@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    message: String,
    tint: Color = MV.navy,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .mvCard()
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        IconBadge(icon = icon, tint = tint, size = 40.dp)
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            message,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}

// MARK: - Section card

/** A titled card container used by the settings-style list screens. */
@Composable
fun SectionCard(title: String, content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .mvCard()
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        content()
    }
}

// MARK: - Labeled rows

@Composable
fun LabeledRow(label: String, trailing: @Composable () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
        trailing()
    }
}

@Composable
fun LabeledValue(label: String, value: String) {
    LabeledRow(label) {
        Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// MARK: - Metric tile

@Composable
fun MetricTile(
    title: String,
    value: String,
    unit: String = "",
    note: String? = null,
    icon: ImageVector? = null,
    tint: Color = MaterialTheme.colorScheme.onSurface,
    modifier: Modifier = Modifier,
) {
    // One coherent spoken label for the whole tile (TalkBack reads a single sentence
    // instead of four disjoint fragments). "—" is read as "no reading yet".
    val spoken = buildString {
        append(title)
        append(": ")
        append(if (value == "—") "no reading yet" else "$value $unit".trim())
        if (note != null) { append(", "); append(note) }
    }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 118.dp)
            .mvCard()
            .padding(12.dp)
            .clearAndSetSemantics { contentDescription = spoken },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (icon != null) IconBadge(icon = icon, tint = tint, size = 26.dp)
            Text(
                title,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Row(verticalAlignment = Alignment.Bottom) {
            // Crossfade the numeric value so a warm-up "—" → live reading transition
            // reads as a gentle change rather than a hard flash.
            AnimatedContent(
                targetState = value,
                transitionSpec = {
                    (fadeIn(tween(220)) togetherWith fadeOut(tween(120)))
                },
                label = "metric-value",
            ) { v ->
                Text(
                    v,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (unit.isNotEmpty()) {
                Text(
                    " $unit",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (note != null) {
            Text(
                note,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Spacer(Modifier.height(0.dp))
    }
}

// MARK: - Connection pill

@Composable
fun ConnectionPill(state: ConnectionState) {
    // User-facing status only: Live / Starting / Paused / Unavailable. Underlying
    // protocol states (Scanning, Connecting) are surfaced as "Starting" so no
    // connection/BLE jargon leaks to the user.
    val (label, color) = when (state) {
        ConnectionState.CONNECTED -> "Live" to MV.good
        ConnectionState.SCANNING -> "Starting" to MV.warn
        ConnectionState.CONNECTING -> "Starting" to MV.warn
        ConnectionState.RECONNECTING -> "Starting" to MV.warn
        ConnectionState.DISCONNECTED -> "Paused" to MV.inkMuted
        ConnectionState.UNSUPPORTED -> "Unavailable" to MV.bad
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape)
            // Hairline border so the pill separates from the white top bar (the surfaceVariant
            // fill is nearly the same value as the background).
            .border(1.dp, MV.separator, CircleShape)
            .padding(horizontal = 10.dp, vertical = 5.dp)
            .clearAndSetSemantics { contentDescription = "Stream status: $label" },
    ) {
        Column(modifier = Modifier.size(8.dp).background(color, CircleShape)) {}
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurface)
    }
}

// MARK: - Share sheet

/** Share an exported bundle .zip via the system share sheet, using FileProvider. */
fun shareFile(context: Context, file: File) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "application/zip"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Share session bundle"))
}
