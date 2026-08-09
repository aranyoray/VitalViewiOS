//
//  SettingsScreen.kt
//  MoniVitals (Android)
//
//  Stream rates, gating thresholds, calibration model, metrics source (on-device model vs
//  reference), theme, and data management. Mirrors ios/MoniVitals/Views/SettingsView.swift.
//

package com.monivitals.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.monivitals.ble.BLEProtocol
import com.monivitals.ble.StreamKind
import com.monivitals.dsp.CalibModel
import com.monivitals.model.AppSettings
import com.monivitals.model.MetricsSource
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SettingsScreen(vm: AppViewModel) {
    var showDeleteConfirm by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Settings", color = MV.navy, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) },
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
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionCard("Model") {
                Text("Model: ${vm.modelName}", style = MaterialTheme.typography.bodyMedium, color = MV.inkMuted)
            }

            SectionCard("Metrics source") {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(vm.settings.metricsSource == MetricsSource.APP, { vm.updateSettings { it.copy(metricsSource = MetricsSource.APP) } }, { Text("On-device model") })
                    FilterChip(vm.settings.metricsSource == MetricsSource.FIRMWARE, { vm.updateSettings { it.copy(metricsSource = MetricsSource.FIRMWARE) } }, { Text("Reference") })
                }
                Text("The app computes its own metrics with the on-device model so the algorithms can be iterated freely.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            // Stream sample rates are tunable only against a live-tunable source. The replay
            // source runs at the recording's fixed sample rate, so setRate() is a no-op there —
            // gate the control on isMockSource so users never see a slider that does nothing.
            if (vm.isMockSource) {
                SectionCard("Stream sample rates") {
                    StreamKind.allCases.forEach { stream ->
                        Text(stream.name, style = MaterialTheme.typography.labelMedium)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            val current = vm.settings.streamRates[stream] ?: BLEProtocol.defaultRateHz(stream)
                            BLEProtocol.rateCodes(stream).forEach { hz ->
                                FilterChip(
                                    selected = current == hz,
                                    onClick = { vm.updateSettings { it.copy(streamRates = it.streamRates.toMutableMap().also { m -> m[stream] = hz }) } },
                                    label = { Text("$hz Hz") },
                                )
                            }
                        }
                    }
                }
            }

            SectionCard("Gating thresholds") {
                Text("Motion threshold: ${"%.1f".format(vm.settings.motionThresh / 1_000_000)}×10⁶", style = MaterialTheme.typography.labelSmall)
                Slider(vm.settings.motionThresh.toFloat(), { v -> vm.updateSettings { it.copy(motionThresh = v.toDouble()) } }, valueRange = 1.0e6f..2.0e7f)
                Text("Contact threshold: ${"%.1f".format(vm.settings.contactThresh / 1_000_000)}×10⁶", style = MaterialTheme.typography.labelSmall)
                Slider(vm.settings.contactThresh.toFloat(), { v -> vm.updateSettings { it.copy(contactThresh = v.toDouble()) } }, valueRange = 1.0e6f..1.0e7f)
                Text("Window", style = MaterialTheme.typography.labelMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(250.0, 500.0, 1000.0).forEach { ms ->
                        FilterChip(vm.settings.gatingWindowMs == ms, { vm.updateSettings { it.copy(gatingWindowMs = ms) } }, { Text("${ms.toInt()} ms") })
                    }
                }
            }

            SectionCard("Calibration model") {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(vm.settings.calibModel == CalibModel.LINEAR_INV_PAT, { vm.updateSettings { it.copy(calibModel = CalibModel.LINEAR_INV_PAT) } }, { Text("Linear in 1/PAT") })
                    FilterChip(vm.settings.calibModel == CalibModel.LINEAR_PAT, { vm.updateSettings { it.copy(calibModel = CalibModel.LINEAR_PAT) } }, { Text("Linear in PAT") })
                }
                val cal = vm.currentCalibration
                if (cal != null) {
                    LabeledValue("Active model", cal.model.rawValue)
                    LabeledValue("SBP coeffs", String.format(Locale.US, "%.1f, %.1f", cal.coeffs.sbp[0], cal.coeffs.sbp[1]))
                    LabeledValue("DBP coeffs", String.format(Locale.US, "%.1f, %.1f", cal.coeffs.dbp[0], cal.coeffs.dbp[1]))
                } else {
                    Text("No calibration for the current subject (BP shown as uncalibrated).", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            SectionCard("Appearance") {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(vm.settings.theme == AppSettings.Theme.SYSTEM, { vm.updateSettings { it.copy(theme = AppSettings.Theme.SYSTEM) } }, { Text("System") })
                    FilterChip(vm.settings.theme == AppSettings.Theme.LIGHT, { vm.updateSettings { it.copy(theme = AppSettings.Theme.LIGHT) } }, { Text("Light") })
                    FilterChip(vm.settings.theme == AppSettings.Theme.DARK, { vm.updateSettings { it.copy(theme = AppSettings.Theme.DARK) } }, { Text("Dark") })
                }
                LabeledValue("Units", "bpm · % · ms · mmHg")
            }

            if (vm.isMockSource) {
                SectionCard("Mock signal") {
                    Text("Heart rate: ${vm.mockHrBpm.toInt()} bpm", style = MaterialTheme.typography.labelSmall)
                    Slider(vm.mockHrBpm.toFloat(), { v -> vm.setMockParams { it.hrBpm = v.toDouble() } }, valueRange = 40f..180f)
                    Text("PAT: ${vm.mockPatMs.toInt()} ms", style = MaterialTheme.typography.labelSmall)
                    Slider(vm.mockPatMs.toFloat(), { v -> vm.setMockParams { it.patMs = v.toDouble() } }, valueRange = 80f..350f)
                    Text("SpO₂ target: ${vm.mockSpo2.toInt()} %", style = MaterialTheme.typography.labelSmall)
                    Slider(vm.mockSpo2.toFloat(), { v -> vm.setMockParams { it.spo2Target = v.toDouble() } }, valueRange = 85f..100f)
                    OutlinedButton(onClick = { vm.injectMockMotion() }, modifier = Modifier.fillMaxWidth()) { Text("Inject motion burst") }
                }
            }

            SectionCard("Data management") {
                LabeledValue("Subjects", "${vm.subjects.size}")
                OutlinedButton(
                    onClick = { showDeleteConfirm = true },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Delete all local data", color = MaterialTheme.colorScheme.error) }
                Text("All data is stored locally on this device only.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            SectionCard("About") {
                Text(
                    "MoniVitals is a research / educational tool, NOT a medical device. SpO₂ and " +
                        "blood-pressure values are uncalibrated estimates. It mirrors the MoniVitals " +
                        "iOS and web apps and shares the DSP spec in docs/.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("Delete all data?") },
            text = { Text("Delete all subjects, sessions, calibrations and recordings? This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = { vm.deleteAllData(); showDeleteConfirm = false }) {
                    Text("Delete everything", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text("Cancel") } },
        )
    }
}
