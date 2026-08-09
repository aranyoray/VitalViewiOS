//
//  GatingScreen.kt
//  MoniVitals (Android)
//
//  The project's core thesis, visualized: raw ECG vs BioZ-gated ECG side by side, plus the
//  percentage of "good" segments. The motion / contact thresholds are adjustable and feed
//  back into Settings (and the live engine). Blanked (bad-window) samples are not drawn.
//
//  Mirrors ios/MoniVitals/Views/GatingView.swift.
//

package com.monivitals.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.filled.GridOn
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import com.monivitals.dsp.DSPConstants
import com.monivitals.dsp.TimedSeries
import com.monivitals.dsp.gateEcg
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GatingScreen(vm: AppViewModel) {
    var windowSec by remember { mutableStateOf(8.0) }
    var raw by remember { mutableStateOf<List<Double?>>(emptyList()) }
    var gated by remember { mutableStateOf<List<Double?>>(emptyList()) }
    var goodPct by remember { mutableStateOf(0.0) }
    var windowCount by remember { mutableStateOf(0) }

    LaunchedEffect(windowSec) {
        while (true) {
            val latest = vm.buffers.ecg.latestT()
            if (latest != null) {
                val from = latest - windowSec * DSPConstants.usPerS
                val ecgW = vm.buffers.ecg.window(from)
                val dzW = vm.buffers.biozDz.window(from)
                val z0W = vm.buffers.z0.window(from)
                val res = gateEcg(
                    ecg = TimedSeries(ecgW.first.toList(), ecgW.second.toList()),
                    dz = TimedSeries(dzW.first.toList(), dzW.second.toList()),
                    z0 = TimedSeries(z0W.first.toList(), z0W.second.toList()),
                    windowMs = vm.settings.gatingWindowMs,
                    motionThresh = vm.settings.motionThresh,
                    contactThresh = vm.settings.contactThresh,
                )
                raw = ecgW.second.map { it as Double? }
                gated = res.gatedEcg
                goodPct = res.goodPct
                windowCount = res.windows.size
            }
            delay(500)
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Gating", color = MV.navy, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) },
                colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
                actions = { ConnectionPill(vm.connectionState); androidx.compose.foundation.layout.Spacer(Modifier.padding(6.dp)) },
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
            Text(
                "BioZ-gated ECG cleaning. A window is flagged bad when ΔZ variance or " +
                    "|Z₀ − baseline| exceeds the thresholds below; bad windows are blanked.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                MetricTile("Good segments", String.format(java.util.Locale.US, "%.0f", goodPct), "%", icon = Icons.Filled.Verified, tint = MV.good, modifier = Modifier.weight(1f))
                MetricTile("Windows", "$windowCount", icon = Icons.Filled.GridOn, tint = MV.navy, modifier = Modifier.weight(1f))
            }

            GateStrip("Raw ECG", raw, MV.inkMuted)
            GateStrip("Gated ECG", gated, MV.ecg)

            SectionCard("Thresholds") {
                Text("Motion threshold: ${vm.settings.motionThresh.toInt()} (ΔZ variance)", style = MaterialTheme.typography.labelSmall)
                Slider(
                    value = vm.settings.motionThresh.toFloat(),
                    onValueChange = { v -> vm.updateSettings { it.copy(motionThresh = v.toDouble()) } },
                    valueRange = 1.0e6f..2.0e7f,
                )
                Text("Contact threshold: ${vm.settings.contactThresh.toInt()} (|Z₀ − baseline| mΩ)", style = MaterialTheme.typography.labelSmall)
                Slider(
                    value = vm.settings.contactThresh.toFloat(),
                    onValueChange = { v -> vm.updateSettings { it.copy(contactThresh = v.toDouble()) } },
                    valueRange = 1.0e6f..1.0e7f,
                )
                Text("Display window: ${windowSec.toInt()} s", style = MaterialTheme.typography.labelSmall)
                Slider(value = windowSec.toFloat(), onValueChange = { windowSec = it.toDouble() }, valueRange = 4f..16f, steps = 11)
                if (vm.isMockSource) {
                    OutlinedButton(onClick = { vm.injectMockMotion() }, modifier = Modifier.fillMaxWidth()) {
                        Text("Inject motion burst (mock)")
                    }
                }
            }
        }
    }
}

@Composable
private fun GateStrip(title: String, samples: List<Double?>, color: Color) {
    val bg = MaterialTheme.colorScheme.surface
    val border = MaterialTheme.colorScheme.outline
    Column {
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(110.dp)
                .background(bg, RoundedCornerShape(8.dp))
                .border(1.dp, border, RoundedCornerShape(8.dp)),
        ) {
            val present = samples.filterNotNull()
            if (present.size <= 1) return@Canvas
            var lo = present.min(); var hi = present.max()
            if (hi <= lo) hi = lo + 1
            val margin = (hi - lo) * 0.1
            lo -= margin; hi += margin

            val w = size.width; val h = size.height
            val n = samples.size.toDouble()
            fun x(i: Int) = (i / maxOf(1.0, n - 1) * w).toFloat()
            fun y(v: Double) = (h - (v - lo) / (hi - lo) * h).toFloat()

            val path = Path()
            var penDown = false
            for (i in samples.indices) {
                val v = samples[i]
                if (v != null) {
                    if (penDown) path.lineTo(x(i), y(v)) else { path.moveTo(x(i), y(v)); penDown = true }
                } else {
                    penDown = false
                }
            }
            drawPath(path, color = color, style = Stroke(width = 1.3f * density))
        }
    }
}
