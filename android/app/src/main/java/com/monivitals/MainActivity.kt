//
//  MainActivity.kt
//  MoniVitals (Android)
//
//  Single-activity Compose entry point. Hosts the shared AppViewModel and shows the
//  onboarding gate (NOT-a-medical-device disclaimer + human-subjects consent) on first
//  run. The app runs standalone on real recorded biosignals (replay) — no hardware needed.
//
//  MoniVitals is a research / educational tool, NOT a medical device.
//

package com.monivitals

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.monivitals.model.Store
import com.monivitals.ui.AppViewModel
import com.monivitals.ui.MoniVitalsTheme
import com.monivitals.ui.OnboardingScreen
import com.monivitals.ui.RootScreen

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Store.init(this)

        setContent {
            val vm: AppViewModel = viewModel()
            MoniVitalsTheme(theme = vm.settings.theme) {
                if (vm.needsOnboarding) {
                    OnboardingScreen(vm)
                } else {
                    RootScreen(vm)
                }
            }
        }
    }
}
