//
//  ReviewScreen.kt
//  MoniVitals (Android)
//
//  List recorded sessions, plot their stored waveforms (static Canvas), and export each as
//  a CSV bundle .zip via the system share sheet.
//
//  Mirrors ios/MoniVitals/Views/ReviewView.swift.
//

package com.monivitals.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.monivitals.model.Session
import com.monivitals.model.SessionStreams
import com.monivitals.model.Store
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReviewScreen(vm: AppViewModel) {
    var sessions by remember { mutableStateOf<List<Session>>(emptyList()) }
    var selectedId by remember { mutableStateOf<String?>(null) }

    fun reload() { sessions = Store.shared.listSessions() }
    LaunchedEffect(Unit) { reload() }

    val id = selectedId
    if (id != null) {
        SessionDetail(vm, id, onBack = { selectedId = null; reload() })
        return
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Review", color = MV.navy, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) },
                colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (sessions.isEmpty()) {
                EmptyState(
                    icon = Icons.Filled.List,
                    title = "No recordings yet",
                    message = "Recorded sessions will appear here. Start one from the Record tab.",
                )
            }
            sessions.forEach { s ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .mvCard()
                        .clickable { selectedId = s.id }
                        .padding(14.dp),
                ) {
                    Text("${s.subjectCode} · ${s.label.rawValue}", style = MaterialTheme.typography.titleSmall)
                    Text(s.startedAt, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SessionDetail(vm: AppViewModel, sessionId: String, onBack: () -> Unit) {
    val context = LocalContext.current
    var session by remember { mutableStateOf<Session?>(null) }
    var streams by remember { mutableStateOf(SessionStreams()) }

    LaunchedEffect(sessionId) {
        // Read the (bounded) recorded streams off the main thread to avoid StrictMode
        // disk-read violations / UI jank; publish results back on the composition thread.
        val loaded = withContext(Dispatchers.IO) {
            Store.shared.getSession(sessionId) to Store.shared.readSessionStreams(sessionId)
        }
        session = loaded.first
        streams = loaded.second
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Session", color = MV.navy, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) },
                colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = MV.navy) } },
                actions = {
                    IconButton(onClick = {
                        vm.exportSession(sessionId)?.let { shareFile(context, it) }
                    }) { Icon(Icons.Filled.Share, "Export", tint = MV.magenta) }
                },
            )
        },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            session?.let { s ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .mvCard()
                        .padding(14.dp),
                ) {
                    Text("${s.subjectCode} · ${s.label.rawValue}", style = MaterialTheme.typography.titleSmall)
                    Text("Started ${s.startedAt}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    s.endedAt?.let { Text("Ended $it", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    Text("Metrics source: ${s.metricsSource.displayName}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        "ECG ${streams.ecg.ecg.size} · PPG ${streams.ppg.green.size} · BioZ ${streams.bioz.dz.size} samples",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            StaticChart("ECG", streams.ecg.ecg.take(4000).map { it.toDouble() }, MV.ecg)
            StaticChart("PPG green", streams.ppg.green.take(4000).map { it.toDouble() }, MV.ppg)
            StaticChart("BioZ ΔZ", streams.bioz.dz.take(4000).map { it.toDouble() }, MV.bioz)
        }
    }
}

@Composable
private fun StaticChart(title: String, values: List<Double>, color: Color) {
    val bg = MaterialTheme.colorScheme.surface
    val border = MaterialTheme.colorScheme.outline
    Column {
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (values.size <= 1) {
            Text("No data", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            return
        }
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(140.dp)
                .background(bg, RoundedCornerShape(8.dp))
                .border(1.dp, border, RoundedCornerShape(8.dp)),
        ) {
            var lo = values.min(); var hi = values.max()
            if (hi <= lo) hi = lo + 1
            val margin = (hi - lo) * 0.1
            lo -= margin; hi += margin
            val w = size.width; val h = size.height
            val n = values.size.toDouble()
            fun x(i: Int) = (i / maxOf(1.0, n - 1) * w).toFloat()
            fun y(v: Double) = (h - (v - lo) / (hi - lo) * h).toFloat()
            val path = Path()
            path.moveTo(x(0), y(values[0]))
            for (i in 1 until values.size) path.lineTo(x(i), y(values[i]))
            drawPath(path, color = color, style = Stroke(width = 1.3f * density))
        }
    }
}
