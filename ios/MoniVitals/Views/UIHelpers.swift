//
//  UIHelpers.swift
//  MoniVitals
//
//  Shared formatting helpers and small reusable views (metric tiles, status pills).
//  Deliberately avoids any diagnostic/clinical language — values are labeled as
//  estimates and the app is a friendly on-device demo.
//

import SwiftUI

// MARK: - Formatting

enum Fmt {
    /// The placeholder shown when a value is not yet available.
    static let none = "—"

    static func opt(_ v: Double?, decimals: Int = 0, suffix: String = "") -> String {
        // Guard against nil AND non-finite values (NaN/±inf) which would otherwise
        // format as "nan"/"inf" and leak into tiles.
        guard let v, v.isFinite else { return none }
        return String(format: "%.\(decimals)f", v) + suffix
    }

    static func bpm(_ v: Double?) -> String { opt(v, decimals: 0) }
    static func pct(_ v: Double?) -> String { opt(v, decimals: 0) }

    static func patMs(_ patUs: Double?) -> String {
        guard let patUs, patUs.isFinite else { return none }
        return String(format: "%.0f", patUs / 1000)
    }

    /// Format an optional integer-valued metric (contact/movement), returning the
    /// placeholder while the value is absent rather than a misleading "0".
    static func int(_ v: Int?) -> String {
        guard let v else { return none }
        return "\(v)"
    }

    static func duration(_ ms: Double) -> String {
        let totalSec = Int(ms / 1000)
        return String(format: "%02d:%02d", totalSec / 60, totalSec % 60)
    }
}

// MARK: - Metric tile

struct MetricTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var note: String? = nil
    var systemImage: String? = nil
    var tint: Color = MV.accent
    /// When true and the value is still the placeholder, show a subtle skeleton bar
    /// with a "warming up…" note instead of a bare "—".
    var warmsUp: Bool = false

    /// True while this tile is awaiting its first real value.
    private var isWarming: Bool { warmsUp && value == Fmt.none }

    var body: some View {
        VStack(alignment: .leading, spacing: MV.s8) {
            HStack(spacing: MV.s8) {
                if let systemImage { IconBadge(systemName: systemImage, tint: tint, size: 26) }
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MV.inkMuted)
                    .lineLimit(1)
            }
            if isWarming {
                SkeletonBar()
                    .frame(width: 46, height: 22)
                    .padding(.vertical, 1)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(MV.number(22))
                        .foregroundStyle(MV.ink)
                        .contentTransition(.numericText())
                    if !unit.isEmpty {
                        Text(unit).font(.caption.weight(.medium)).foregroundStyle(MV.inkMuted)
                    }
                }
            }
            if let note = displayNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(MV.inkMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .mvCard(padding: MV.s12, radius: MV.rTile)
        .animation(.easeInOut(duration: 0.25), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var displayNote: String? {
        isWarming ? "warming up…" : note
    }

    /// One combined VoiceOver phrase, e.g. "Heart rate, 92 bpm, recorded ~92".
    private var accessibilityText: String {
        if isWarming { return "\(title), warming up" }
        var parts = [title]
        if value == Fmt.none {
            parts.append("no reading yet")
        } else {
            parts.append(unit.isEmpty ? value : "\(value) \(unit)")
        }
        if let note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}

/// A soft shimmering placeholder used while a value warms up.
private struct SkeletonBar: View {
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(MV.surfaceAlt)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, MV.inkMuted.opacity(0.10), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .offset(x: shimmer ? 60 : -60)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Connection pill

struct ConnectionPill: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(MV.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(MV.surface))
        .overlay(Capsule().stroke(MV.separator, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal status")
        .accessibilityValue(label)
    }

    private var label: String {
        switch state {
        case .connected: return "Live"
        case .scanning, .connecting, .reconnecting: return "Starting…"
        case .disconnected, .unsupported: return "Paused"
        }
    }

    private var color: Color {
        switch state {
        case .connected: return MV.good
        case .scanning, .connecting, .reconnecting: return MV.warn
        case .disconnected, .unsupported: return MV.inkMuted
        }
    }
}

// MARK: - Share sheet (UIActivityViewController) for exporting a bundle folder

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
