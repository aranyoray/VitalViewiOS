//
//  RootScreen.kt
//  MoniVitals (Android)
//
//  The main bottom-navigation scaffold across Dashboard / Recorder / Calibrate / Gating /
//  Review / Settings. The app runs standalone on real recorded biosignals (replay) —
//  streaming starts automatically on launch, so there is no connect step.
//
//  Mirrors ios/MoniVitals/App/RootView.swift.
//

package com.monivitals.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.FiberManualRecord
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow

private data class Tab(val label: String, val icon: ImageVector)

@Composable
fun RootScreen(vm: AppViewModel) {
    // Survive configuration changes (rotation) / process death so the user stays on the tab
    // they were viewing instead of being bounced back to Home.
    var selected by rememberSaveable { mutableIntStateOf(0) }

    // Standalone auto-start: connect the replay source once; streaming begins when it is live.
    LaunchedEffect(Unit) { vm.begin() }

    val tabs = listOf(
        Tab("Home", Icons.Filled.MonitorHeart),
        Tab("Record", Icons.Filled.FiberManualRecord),
        Tab("Calibrate", Icons.Filled.Tune),
        Tab("Gating", Icons.Filled.ContentCut),
        Tab("Review", Icons.Filled.List),
        Tab("Settings", Icons.Filled.Settings),
    )

    Scaffold(
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                tabs.forEachIndexed { i, tab ->
                    NavigationBarItem(
                        selected = selected == i,
                        onClick = { selected = i },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = {
                            Text(
                                tab.label,
                                style = MaterialTheme.typography.labelSmall,
                                maxLines = 1,
                                softWrap = false,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                        alwaysShowLabel = false,
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = MaterialTheme.colorScheme.primary,
                            selectedTextColor = MaterialTheme.colorScheme.primary,
                            indicatorColor = MaterialTheme.colorScheme.surfaceVariant,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    )
                }
            }
        },
    ) { inner ->
        Box(modifier = Modifier.fillMaxSize().padding(inner)) {
            when (selected) {
                0 -> DashboardScreen(vm)
                1 -> RecorderScreen(vm)
                2 -> CalibrationScreen(vm)
                3 -> GatingScreen(vm)
                4 -> ReviewScreen(vm)
                5 -> SettingsScreen(vm)
            }
        }
    }
}
