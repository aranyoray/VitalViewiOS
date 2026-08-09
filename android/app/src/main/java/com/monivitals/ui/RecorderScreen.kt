//
//  RecorderScreen.kt
//  MoniVitals (Android)
//
//  Select a subject + label, Start/Stop a recording, watch live duration, per-stream
//  sample counters, and dropped-packet counts, drop annotation markers, and capture a
//  "Cuff reading" (SBP/DBP) — the ground-truth used for PAT→BP calibration.
//
//  Mirrors ios/MoniVitals/Views/RecorderView.swift.
//

package com.monivitals.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.monivitals.ble.StreamKind
import com.monivitals.model.AnnotationType
import com.monivitals.model.SessionLabel
import com.monivitals.model.Subject
import com.monivitals.source.ConnectionState
import java.time.Instant

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun RecorderScreen(vm: AppViewModel) {
    var label by remember { mutableStateOf(SessionLabel.REST) }
    var notes by remember { mutableStateOf("") }
    var showSubjectSheet by remember { mutableStateOf(false) }
    var showCuffSheet by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Recorder", color = MV.navy, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) },
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
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionCard("Subject") {
                OutlinedButton(onClick = { showSubjectSheet = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("Selected subject: ${vm.currentSubjectCode ?: "none"}")
                }
            }

            SectionCard("Session") {
                Text("Label", style = MaterialTheme.typography.labelMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SessionLabel.allCases.forEach { l ->
                        FilterChip(
                            selected = label == l,
                            onClick = { if (vm.recording == null) label = l },
                            label = { Text(l.rawValue) },
                            enabled = vm.recording == null,
                        )
                    }
                }
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("Notes (optional)") },
                    enabled = vm.recording == null,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (vm.recording == null) {
                    Button(
                        onClick = { vm.startRecording(label, notes) },
                        enabled = vm.currentSubjectCode != null && vm.connectionState == ConnectionState.CONNECTED,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Start recording")
                    }
                    // Explain why the button is disabled instead of leaving the user guessing.
                    val hint = when {
                        vm.currentSubjectCode == null -> "Select a subject above to start recording."
                        vm.connectionState != ConnectionState.CONNECTED -> "Waiting for the vitals stream to start…"
                        else -> null
                    }
                    if (hint != null) {
                        Text(
                            hint,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                } else {
                    OutlinedButton(onClick = { vm.stopRecording() }, modifier = Modifier.fillMaxWidth()) {
                        Text("Stop recording")
                    }
                }
            }

            if (vm.recording != null) {
                SectionCard("Live") {
                    LabeledValue("Duration", Fmt.duration(vm.recordDurationMs))
                    LabeledValue("ECG samples", "${vm.recordCounts[StreamKind.ECG] ?: 0}")
                    LabeledValue("BioZ samples", "${vm.recordCounts[StreamKind.BIOZ] ?: 0}")
                    LabeledValue("PPG samples", "${vm.recordCounts[StreamKind.PPG] ?: 0}")
                    LabeledValue(
                        "Dropped (E/B/P)",
                        "${vm.dropped[StreamKind.ECG] ?: 0}/${vm.dropped[StreamKind.BIOZ] ?: 0}/${vm.dropped[StreamKind.PPG] ?: 0}",
                    )
                    LabeledValue("Cuff readings", "${vm.cuffReadingCount}")
                }

                SectionCard("Annotations") {
                    Button(onClick = { showCuffSheet = true }, modifier = Modifier.fillMaxWidth()) { Text("Cuff reading…") }
                    OutlinedButton(onClick = { vm.addMarker(AnnotationType.MARKER) }, modifier = Modifier.fillMaxWidth()) { Text("Marker") }
                    OutlinedButton(onClick = { vm.addMarker(AnnotationType.MOTION_START) }, modifier = Modifier.fillMaxWidth()) { Text("Motion start") }
                    OutlinedButton(onClick = { vm.addMarker(AnnotationType.MOTION_STOP) }, modifier = Modifier.fillMaxWidth()) { Text("Motion stop") }
                    OutlinedButton(onClick = { vm.addMarker(AnnotationType.ARTIFACT) }, modifier = Modifier.fillMaxWidth()) { Text("Artifact") }
                }
            }
        }
    }

    if (showSubjectSheet) {
        SubjectPickerDialog(vm, onDismiss = { showSubjectSheet = false })
    }
    if (showCuffSheet) {
        CuffReadingDialog(vm, onDismiss = { showCuffSheet = false })
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun SubjectPickerDialog(vm: AppViewModel, onDismiss: () -> Unit) {
    var newCode by remember { mutableStateOf("") }
    var ageBand by remember { mutableStateOf("18-25") }
    var notes by remember { mutableStateOf("") }
    val ageBands = listOf("<18", "18-25", "26-35", "36-45", "46-55", "56-65", "65+")

    androidx.compose.runtime.LaunchedEffect(Unit) { vm.refreshSubjects() }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
        title = { Text("Subjects") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text("Existing subjects", style = MaterialTheme.typography.labelMedium)
                if (vm.subjects.isEmpty()) {
                    Text("No subjects yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                vm.subjects.forEach { s ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(
                            onClick = { vm.selectSubject(s.code); onDismiss() },
                            modifier = Modifier.fillMaxWidth().padding(4.dp),
                        ) {
                            Text("${s.code}  ·  ${s.ageBand}" + if (vm.currentSubjectCode == s.code) "  ✓" else "")
                        }
                    }
                }

                Text("New subject (non-identifying code)", style = MaterialTheme.typography.labelMedium)
                OutlinedTextField(value = newCode, onValueChange = { newCode = it }, label = { Text("Code, e.g. S01") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = notes, onValueChange = { notes = it }, label = { Text("Notes (optional)") }, modifier = Modifier.fillMaxWidth())
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ageBands.forEach { b ->
                        FilterChip(selected = ageBand == b, onClick = { ageBand = b }, label = { Text(b) })
                    }
                }
                Button(
                    onClick = {
                        val code = newCode.trim()
                        if (code.isNotEmpty()) {
                            vm.saveSubject(Subject(code = code, ageBand = ageBand, sex = null, notes = notes, createdAt = Instant.now().toString()))
                            vm.selectSubject(code)
                            onDismiss()
                        }
                    },
                    enabled = newCode.trim().isNotEmpty(),
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Add subject") }
            }
        },
    )
}

@Composable
private fun CuffReadingDialog(vm: AppViewModel, onDismiss: () -> Unit) {
    var sbp by remember { mutableStateOf("120") }
    var dbp by remember { mutableStateOf("80") }
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                val s = sbp.toDoubleOrNull()
                val d = dbp.toDoubleOrNull()
                if (s != null && d != null) vm.addCuffReading(s, d)
                onDismiss()
            }) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
        title = { Text("Cuff reading") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(value = sbp, onValueChange = { sbp = it }, label = { Text("Systolic (SBP)") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                OutlinedTextField(value = dbp, onValueChange = { dbp = it }, label = { Text("Diastolic (DBP)") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                Text(
                    "Captured at the current device time and, when a PAT is available, added as a calibration pair.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
    )
}
