//
//  RootView.swift
//  VitalView
//
//  The main TabView across Connect / Dashboard / Recorder / Calibration / Gating /
//  Review / Settings. Every screen is reachable without hardware via Mock mode.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            ConnectView()
                .tabItem { Label("Connect", systemImage: "antenna.radiowaves.left.and.right") }

            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "waveform.path.ecg") }

            RecorderView()
                .tabItem { Label("Recorder", systemImage: "record.circle") }

            CalibrationView()
                .tabItem { Label("Calibrate", systemImage: "slider.horizontal.3") }

            GatingView()
                .tabItem { Label("Gating", systemImage: "scissors") }

            ReviewView()
                .tabItem { Label("Review", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
