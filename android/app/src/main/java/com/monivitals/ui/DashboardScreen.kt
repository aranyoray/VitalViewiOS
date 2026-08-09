//
//  DashboardScreen.kt
//  MoniVitals (Android)
//
//  Live ECG / PPG / BioZ strips (Canvas over ring buffers) plus metric tiles: HR, SpO₂
//  (estimate), PAT, BP (uncalibrated unless a model exists), contact, motion. No
//  diagnostic/clinical language — values are estimates.
//
//  Mirrors ios/MoniVitals/Views/DashboardView.swift.
//

package com.monivitals.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.monivitals.R
import com.monivitals.model.MetricsSource
import com.monivitals.source.ConnectionState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(vm: AppViewModel) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(
                            // Decorative — the "MoniVitals" wordmark beside it is the label.
                            painter = painterResource(id = R.mipmap.ic_launcher),
                            contentDescription = null,
                            modifier = Modifier.size(28.dp),
                        )
                        Spacer(Modifier.padding(4.dp))
                        Text(
                            "MoniVitals",
                            fontWeight = FontWeight.Bold,
                            color = MV.navy,
                            style = MaterialTheme.typography.titleLarge,
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
                actions = { ConnectionPill(vm.connectionState); Spacer(Modifier.padding(6.dp)) },
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
            if (vm.connectionState != ConnectionState.CONNECTED) {
                val message = if (vm.connectionState == ConnectionState.UNSUPPORTED) {
                    "The vitals stream is unavailable on this device."
                } else {
                    "Starting the vitals stream…"
                }
                Text(
                    message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .mvCard()
                        .padding(14.dp),
                )
            }

            RecordingProvenanceCard(vm)

            Text(
                "Model: ${vm.modelName}",
                style = MaterialTheme.typography.labelSmall,
                color = MV.inkMuted,
            )

            metricTiles(vm)

            WaveformStrip("ECG (256 Hz)", vm.buffers.ecg, windowSec = 4.0, color = MV.ecg, heightDp = 130)
            WaveformStrip("PPG green (100 Hz)", vm.buffers.ppgGreen, windowSec = 6.0, color = MV.ppg, heightDp = 110)
            WaveformStrip("BioZ ΔZ (64 Hz)", vm.buffers.biozDz, windowSec = 6.0, color = MV.bioz, heightDp = 100)
        }
    }
}

@Composable
private fun metricTiles(vm: AppViewModel) {
    val m = vm.liveMetrics
    val calibrated = vm.currentCalibration != null
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Provenance-accurate SpO₂ note: the recorded reference is only shown verbatim when
        // the reference source is selected; the on-device model produces an *estimate*.
        val spo2Note = if (vm.settings.metricsSource == MetricsSource.APP) "Estimate" else "Recorded reference"
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            MetricTile("Heart rate", Fmt.bpm(m?.hrBpm), "bpm", icon = Icons.Filled.MonitorHeart, tint = MV.magenta, modifier = Modifier.weight(1f))
            MetricTile("SpO₂", Fmt.pct(m?.spo2Pct), "%", note = spo2Note, icon = Icons.Filled.WaterDrop, tint = MV.navy, modifier = Modifier.weight(1f))
            MetricTile("PAT", Fmt.patMs(m?.patUs), "ms", note = "R–pulse interval", icon = Icons.Filled.Timer, tint = MV.navy, modifier = Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            MetricTile("SBP", Fmt.opt(m?.sbpMmHg), "mmHg", note = if (calibrated) "estimate" else "uncalibrated", icon = Icons.Filled.Speed, tint = MV.warn, modifier = Modifier.weight(1f))
            MetricTile("DBP", Fmt.opt(m?.dbpMmHg), "mmHg", note = if (calibrated) "estimate" else "uncalibrated", icon = Icons.Filled.Speed, tint = MV.warn, modifier = Modifier.weight(1f))
            // Warming up → "—" (not a solid "0", which reads like a real measured zero).
            MetricTile("Contact", Fmt.int(m?.contactQuality), "/100", icon = Icons.Filled.Fingerprint, tint = MV.bioz, modifier = Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            MetricTile("Motion", Fmt.int(m?.motion), "/255", icon = Icons.AutoMirrored.Filled.DirectionsWalk, tint = MV.pink, modifier = Modifier.weight(1f))
            MetricTile("Source", "Real", note = if (vm.settings.metricsSource == MetricsSource.APP) "Model" else "Reference", icon = Icons.Filled.GraphicEq, tint = MV.navy, modifier = Modifier.weight(1f))
            Spacer(Modifier.weight(1f))
        }
    }
}

/** Provenance card for the real recorded biosignal being replayed through the DSP. */
@Composable
private fun RecordingProvenanceCard(vm: AppViewModel) {
    val name = vm.recordingName ?: return
    val hr = vm.referenceHR
    val spo2 = vm.referenceSpO2
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .mvCard()
            .padding(14.dp),
    ) {
        Text(
            "Real recording",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            name,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            color = MV.navy,
        )
        if (hr != null && spo2 != null) {
            Text(
                "Recorded reference: ${Fmt.bpm(hr)} bpm · ${Fmt.pct(spo2)}% SpO₂",
                style = MaterialTheme.typography.labelSmall,
                color = MV.inkMuted,
            )
        }
    }
}
