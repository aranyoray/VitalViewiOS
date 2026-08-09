//
//  OnboardingScreen.kt
//  MoniVitals (Android)
//
//  First-run gate: the "NOT a medical device" disclaimer and a human-subjects consent
//  acknowledgement. Acceptance is persisted (via AppViewModel/AppSettings), so this screen
//  is shown only once. It is unavoidable on first launch.
//
//  Mirrors ios/MoniVitals/App/OnboardingView.swift.
//

package com.monivitals.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.monivitals.R

@Composable
fun OnboardingScreen(vm: AppViewModel) {
    var disclaimerChecked by remember { mutableStateOf(false) }
    var consentChecked by remember { mutableStateOf(false) }

    Scaffold(containerColor = MaterialTheme.colorScheme.background) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Image(
                    painter = painterResource(id = R.mipmap.ic_launcher),
                    contentDescription = "MoniVitals",
                    modifier = Modifier.size(120.dp),
                )
                Text(
                    "MoniVitals",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = MV.navy,
                )
            }
            Text(
                "An on-device ECG / BioZ / PPG vitals explorer running on real recorded biosignals.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Section("Not a medical device") {
                Text(
                    "MoniVitals is a research, science-fair, and educational tool. It is NOT a " +
                        "medical device and must not be used for diagnosis or any clinical decision. " +
                        "Heart rate, SpO₂, pulse arrival time, and blood pressure are uncalibrated " +
                        "estimates derived from recorded biosignals and experimental algorithms.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                CheckRow("I understand this is not a medical device.", disclaimerChecked) { disclaimerChecked = it }
            }

            Section("Human-subjects research consent") {
                Text(
                    "If you record sessions involving people, you are responsible for obtaining " +
                        "appropriate consent and following any applicable study protocol or " +
                        "institutional guidance. Subjects are identified only by a non-identifying " +
                        "code; data is stored locally on this device and is not uploaded anywhere.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                CheckRow("I will obtain consent and handle data responsibly.", consentChecked) { consentChecked = it }
            }

            Button(
                onClick = { vm.acceptOnboarding() },
                enabled = disclaimerChecked && consentChecked,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Continue")
            }
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(16.dp))
            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
        content()
    }
}

@Composable
private fun CheckRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Checkbox(checked = checked, onCheckedChange = onChange)
        Text(label, style = MaterialTheme.typography.bodyMedium)
    }
}
