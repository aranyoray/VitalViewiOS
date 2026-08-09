//
//  CalibrationScreen.kt
//  MoniVitals (Android)
//
//  Collect PAT↔cuff reference pairs for the selected subject, fit a PAT→BP model (OLS),
//  show Pearson R and RMSE, plot a scatter with the fit line, and save / re-calibrate.
//  This is a coarse per-subject empirical fit for an educational demonstration — NOT a
//  validated clinical model.
//
//  Mirrors ios/MoniVitals/Views/CalibrationView.swift (Swift Charts → Compose Canvas).
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PersonOff
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.monivitals.dsp.CalibModel
import com.monivitals.dsp.predictor
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalibrationScreen(vm: AppViewModel) {
    var sbp by remember { mutableStateOf("120") }
    var dbp by remember { mutableStateOf("80") }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Calibration", color = MV.navy, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) },
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
            if (vm.currentSubjectCode == null) {
                EmptyState(
                    icon = Icons.Filled.PersonOff,
                    title = "No subject selected",
                    message = "Choose a subject in the Record tab to collect PAT↔cuff pairs and calibrate.",
                )
                return@Column
            }

            // Avoid an "— ms" that reads like a broken unit; show a friendly waiting state
            // until a PAT is actually available.
            val patText = if (vm.liveMetrics?.patUs == null) "Waiting for PAT…" else "${Fmt.patMs(vm.liveMetrics?.patUs)} ms"
            SectionCard("Add reference pair") {
                LabeledValue("Current PAT", patText)
                OutlinedTextField(value = sbp, onValueChange = { sbp = it }, label = { Text("Cuff SBP") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = dbp, onValueChange = { dbp = it }, label = { Text("Cuff DBP") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
                Button(
                    onClick = {
                        val s = sbp.toDoubleOrNull(); val d = dbp.toDoubleOrNull()
                        if (s != null && d != null) vm.addCalibrationPair(s, d)
                    },
                    enabled = vm.liveMetrics?.patUs != null,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Capture pair at current PAT") }
            }

            SectionCard("Reference pairs (${vm.calibrationPairs.size})") {
                if (vm.calibrationPairs.isEmpty()) {
                    Text("Collect at least 3 pairs across a range of PAT values for a usable fit.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                vm.calibrationPairs.forEachIndexed { idx, p ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                    ) {
                        Text(String.format(Locale.US, "PAT %.0f ms", p.patUs / 1000))
                        Text(String.format(Locale.US, "%.0f/%.0f mmHg", p.sbp, p.dbp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        // IconButton guarantees a 48dp touch target + a proper accessibility label,
                        // unlike a single-glyph text button.
                        androidx.compose.material3.IconButton(onClick = { vm.removeCalibrationPair(idx) }) {
                            androidx.compose.material3.Icon(
                                androidx.compose.material.icons.Icons.Filled.Close,
                                contentDescription = "Remove pair ${idx + 1}",
                                tint = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                }
                if (vm.calibrationPairs.isNotEmpty()) {
                    OutlinedButton(onClick = { vm.clearCalibrationPairs() }, modifier = Modifier.fillMaxWidth()) { Text("Clear pairs") }
                }
            }

            val fit = vm.currentFit
            SectionCard("Fit") {
                if (fit != null) {
                    LabeledValue("Model", fit.model.rawValue)
                    LabeledValue("Pearson R (SBP)", String.format(Locale.US, "%.3f", fit.r))
                    LabeledValue("RMSE SBP", String.format(Locale.US, "%.1f mmHg", fit.rmseSbp))
                    LabeledValue("RMSE DBP", String.format(Locale.US, "%.1f mmHg", fit.rmseDbp))
                    LabeledValue("Pairs", "${fit.n}")
                    Button(onClick = { vm.saveCalibrationFit() }, modifier = Modifier.fillMaxWidth()) {
                        Text(if (vm.currentCalibration == null) "Save calibration" else "Re-calibrate")
                    }
                } else {
                    Text("Need ≥ 2 pairs with differing PAT to fit.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                vm.currentCalibration?.let { cal ->
                    LabeledValue("Saved model", cal.model.rawValue)
                    LabeledValue("Saved R", String.format(Locale.US, "%.3f", cal.r))
                }
            }

            if (vm.calibrationPairs.size >= 2 && fit != null) {
                SectionCard("SBP vs predictor") {
                    val pts = vm.calibrationPairs.map { predictor(it.patUs, fit.model) to it.sbp }
                    ScatterFitChart(
                        points = pts,
                        a = fit.coeffs.sbp[0],
                        b = fit.coeffs.sbp[1],
                    )
                    Text(
                        if (fit.model == CalibModel.LINEAR_INV_PAT) "predictor = 1 / PAT(s)" else "predictor = PAT(s)",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            SectionCard("Disclaimer") {
                Text(
                    "Coarse per-subject empirical fit for an educational demonstration. Not a validated clinical model.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ScatterFitChart(points: List<Pair<Double, Double>>, a: Double, b: Double) {
    val pointColor = MV.magenta
    val lineColor = MV.navy
    val bg = MaterialTheme.colorScheme.surface
    val border = MaterialTheme.colorScheme.outline
    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(200.dp)
            .background(bg, RoundedCornerShape(8.dp))
            .border(1.dp, border, RoundedCornerShape(8.dp))
            .padding(8.dp),
    ) {
        if (points.isEmpty()) return@Canvas
        val xs = points.map { it.first }
        val ys = points.map { it.second }
        var xlo = xs.min(); var xhi = xs.max()
        var ylo = ys.min(); var yhi = ys.max()
        if (xhi <= xlo) xhi = xlo + 1
        if (yhi <= ylo) yhi = ylo + 1
        val xm = (xhi - xlo) * 0.1; val ym = (yhi - ylo) * 0.1
        xlo -= xm; xhi += xm; ylo -= ym; yhi += ym

        val w = size.width; val h = size.height
        fun px(x: Double) = ((x - xlo) / (xhi - xlo) * w).toFloat()
        fun py(y: Double) = (h - (y - ylo) / (yhi - ylo) * h).toFloat()

        // Fit line across the visible x range.
        drawLine(
            color = lineColor,
            start = androidx.compose.ui.geometry.Offset(px(xlo), py(a + b * xlo)),
            end = androidx.compose.ui.geometry.Offset(px(xhi), py(a + b * xhi)),
            strokeWidth = 2f * density,
        )
        // Scatter points.
        for (p in points) {
            drawCircle(color = pointColor, radius = 4f * density, center = androidx.compose.ui.geometry.Offset(px(p.first), py(p.second)))
        }
    }
}
