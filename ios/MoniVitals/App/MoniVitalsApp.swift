//
//  MoniVitalsApp.swift
//  MoniVitals
//
//  SwiftUI app entry point. Hosts the single shared AppModel and shows the onboarding
//  gate (NOT-a-medical-device disclaimer + human-subjects consent) on first run.
//
//  MoniVitals is a research / educational tool, NOT a medical device.
//

import SwiftUI

@main
struct MoniVitalsApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.needsOnboarding {
                    OnboardingView()
                } else {
                    RootView()
                }
            }
            .environmentObject(model)
            .mvTheme()
        }
    }
}
