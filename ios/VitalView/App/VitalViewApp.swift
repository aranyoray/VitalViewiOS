//
//  VitalViewApp.swift
//  VitalView
//
//  SwiftUI app entry point. Hosts the single shared AppModel and shows the onboarding
//  gate (NOT-a-medical-device disclaimer + human-subjects consent) on first run.
//
//  VitalView is a research / educational tool, NOT a medical device.
//

import SwiftUI

@main
struct VitalViewApp: App {
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
            .preferredColorScheme(colorScheme(for: model.settings.theme))
        }
    }

    private func colorScheme(for theme: AppSettings.Theme) -> ColorScheme? {
        switch theme {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}
