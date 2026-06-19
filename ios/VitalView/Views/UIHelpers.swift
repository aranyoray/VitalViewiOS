//
//  UIHelpers.swift
//  VitalView
//
//  Shared formatting helpers and small reusable views (metric tiles, status pills).
//  Deliberately avoids any diagnostic/clinical language — values are labeled as
//  estimates and the app is a research tool.
//

import SwiftUI

// MARK: - Formatting

enum Fmt {
    static func opt(_ v: Double?, decimals: Int = 0, suffix: String = "") -> String {
        guard let v else { return "—" }
        return String(format: "%.\(decimals)f", v) + suffix
    }

    static func bpm(_ v: Double?) -> String { opt(v, decimals: 0) }
    static func pct(_ v: Double?) -> String { opt(v, decimals: 0) }

    static func patMs(_ patUs: Double?) -> String {
        guard let patUs else { return "—" }
        return String(format: "%.0f", patUs / 1000)
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
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).foregroundStyle(tint) }
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title2.bold().monospacedDigit())
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Connection pill

struct ConnectionPill: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }

    private var label: String {
        switch state {
        case .disconnected: return "Disconnected"
        case .unsupported: return "Unsupported"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting"
        }
    }

    private var color: Color {
        switch state {
        case .connected: return .green
        case .scanning, .connecting, .reconnecting: return .orange
        case .disconnected: return .gray
        case .unsupported: return .red
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
