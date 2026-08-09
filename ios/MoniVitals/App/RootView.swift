//
//  RootView.swift
//  MoniVitals
//
//  The main TabView across Dashboard / Save / Calibrate / Signal / Clips /
//  Settings. The app replays a bundled real recording on launch (no hardware required).
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "waveform.path.ecg") }

            RecorderView()
                .tabItem { Label("Save", systemImage: "record.circle") }

            CalibrationView()
                .tabItem { Label("Calibrate", systemImage: "slider.horizontal.3") }

            GatingView()
                .tabItem { Label("Signal", systemImage: "scissors") }

            ReviewView()
                .tabItem { Label("Clips", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear { model.begin() }
    }
}
