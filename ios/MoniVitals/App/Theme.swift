//
//  Theme.swift
//  MoniVitals
//
//  Single source of truth for the MoniVitals light theme + brand palette.
//  Derived from the logo: deep indigo navy + vivid magenta on white.
//  Every view should use `MV.*` tokens instead of hardcoded/system colors.
//
//  MoniVitals is a research / educational tool, NOT a medical device.
//

import SwiftUI

// MARK: - Hex color init

extension Color {
    /// Create a Color from a 24-bit hex value, e.g. `Color(hex: 0x261A64)`.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Brand palette (MV = MoniVitals)

enum MV {
    // Brand
    static let navy       = Color(hex: 0x261A64)   // primary indigo
    static let navyDeep   = Color(hex: 0x060151)   // gradient end / emphasis
    static let magenta    = Color(hex: 0xD6236D)   // vivid accent (heartbeat)
    static let pink       = Color(hex: 0xBE3A74)   // mid gradient

    // Surfaces (light theme)
    static let bg         = Color(hex: 0xFFFFFF)   // app background
    static let surface    = Color(hex: 0xF6F7FB)   // cards / grouped panels
    static let surfaceAlt = Color(hex: 0xEEF0F7)   // nested fills
    static let separator  = Color(hex: 0xE2E4EE)

    // Text
    static let ink        = Color(hex: 0x1B1440)   // primary text (navy-black)
    static let inkMuted   = Color(hex: 0x6B6785)   // secondary text

    // Semantic status
    static let good       = Color(hex: 0x1E9E6A)   // ok / connected / good contact
    static let warn       = Color(hex: 0xE08A00)   // caution
    static let bad        = Color(hex: 0xE5484D)   // error / lead-off

    // Waveform traces (distinguishable on white)
    static let ecg        = Color(hex: 0x261A64)   // ECG — navy
    static let ppg        = Color(hex: 0xD6236D)   // PPG — magenta
    static let bioz       = Color(hex: 0x17A2A2)   // BioZ — teal

    // Primary tint used app-wide (nav bars, buttons, controls)
    static let accent     = magenta

    // Spacing scale (use these, not magic numbers).
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32

    // Corner radii.
    static let rCard: CGFloat = 18
    static let rTile: CGFloat = 16
    static let rControl: CGFloat = 12

    // Rounded numeric style for metric values.
    static func number(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    // The signature navy→magenta gradient (the logo "M").
    static let brandGradient = LinearGradient(
        colors: [navy, magenta],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Reusable view styling

extension View {
    /// Standard MoniVitals card: white surface, soft rounded corners, hairline border,
    /// and a gentle elevation shadow.
    func mvCard(padding: CGFloat = 16, radius: CGFloat = MV.rCard) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(MV.surface)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(MV.separator, lineWidth: 1)
            )
    }

    /// Apply the MoniVitals light theme globally (tint + forced light scheme).
    func mvTheme() -> some View {
        self
            .tint(MV.accent)
            .preferredColorScheme(.light)
    }
}
