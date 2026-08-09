//
//  DesignSystem.swift
//  MoniVitals
//
//  Small shared UI building blocks so every screen shares one visual language:
//  tinted icon badges, section headers, chips, and button styles. Built on the MV
//  palette + spacing tokens in Theme.swift.
//

import SwiftUI

/// A tinted, rounded icon chip used in tiles and rows.
struct IconBadge: View {
    let systemName: String
    var tint: Color = MV.accent
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

/// A consistent section heading with an optional supporting line.
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(MV.navy)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(MV.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small pill chip (used for a waveform's colored label, tags, etc.).
struct ChipLabel: View {
    let text: String
    var color: Color = MV.navy

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(MV.ink)
        }
    }
}

/// Full-width prominent action button.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: MV.rControl, style: .continuous)
                    .fill(MV.accent)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary (tinted, low-emphasis) action button.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: MV.rControl, style: .continuous)
                    .fill(MV.accent.opacity(0.12))
            )
            .foregroundStyle(MV.accent)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A subtle press treatment for full-width tappable rows (marker rows, list-style
/// buttons) that use `.plain` today and give no touch feedback.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: MV.rControl, style: .continuous)
                    .fill(MV.accent.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
