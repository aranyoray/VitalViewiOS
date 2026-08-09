//
//  Theme.kt
//  MoniVitals (Android)
//
//  Material 3 theme. The app is always LIGHT and uses the MoniVitals brand palette
//  (dark mode, system preference, and dynamic color are intentionally ignored).
//

package com.monivitals.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.Offset
import com.monivitals.model.AppSettings

/** MoniVitals brand palette + shared brand accents used across screens. */
object MV {
    val navy = Color(0xFF261A64)
    val navyDeep = Color(0xFF060151)
    val magenta = Color(0xFFD6236D)
    val pink = Color(0xFFBE3A74)

    val bg = Color(0xFFFFFFFF)
    val surface = Color(0xFFF6F7FB)
    val surfaceAlt = Color(0xFFEEF0F7)
    val separator = Color(0xFFE2E4EE)
    val ink = Color(0xFF1B1440)
    val inkMuted = Color(0xFF6B6785)

    val good = Color(0xFF1E9E6A)
    val warn = Color(0xFFE08A00)
    val bad = Color(0xFFE5484D)

    // Waveform trace colors.
    val ecg = Color(0xFF261A64)
    val ppg = Color(0xFFD6236D)
    val bioz = Color(0xFF17A2A2)

    /** navy → magenta accent gradient for headers / hero surfaces. */
    val brandGradient: Brush
        get() = Brush.linearGradient(
            colors = listOf(navy, magenta),
            start = Offset(0f, 0f),
            end = Offset(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY),
        )
}

private val LightColors = lightColorScheme(
    primary = MV.magenta,
    onPrimary = Color(0xFFFFFFFF),
    secondary = MV.navy,
    onSecondary = Color(0xFFFFFFFF),
    background = MV.bg,
    onBackground = MV.ink,
    surface = MV.surface,
    onSurface = MV.ink,
    surfaceVariant = MV.surfaceAlt,
    onSurfaceVariant = MV.inkMuted,
    outline = MV.separator,
    error = MV.bad,
)

@Composable
fun MoniVitalsTheme(theme: AppSettings.Theme, content: @Composable () -> Unit) {
    // Always light; the brand palette drives the whole app (theme arg retained for API
    // compatibility with existing call sites).
    MaterialTheme(
        colorScheme = LightColors,
        content = content,
    )
}
