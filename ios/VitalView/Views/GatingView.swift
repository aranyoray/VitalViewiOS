//
//  GatingView.swift
//  VitalView
//
//  The project's core thesis, visualized: raw ECG vs BioZ-gated ECG side by side, plus
//  the percentage of "good" segments. The motion / contact thresholds are adjustable and
//  feed back into Settings (and the live engine). Blanked (bad-window) samples are not
//  drawn in the gated strip.
//

import SwiftUI

struct GatingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var windowSec: Double = 8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("BioZ-gated ECG cleaning. A window is flagged bad when ΔZ variance or |Z₀ − baseline| exceeds the thresholds below; bad windows are blanked.")
                        .font(.callout).foregroundStyle(.secondary)

                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        gatedContent
                    }

                    thresholdControls
                }
                .padding()
            }
            .navigationTitle("Gating")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ConnectionPill(state: model.connectionState) }
            }
        }
    }

    private var gatedContent: some View {
        let result = computeGate()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                MetricTile(title: "Good segments", value: String(format: "%.0f", result.goodPct),
                           unit: "%", systemImage: "checkmark.seal", tint: .green)
                MetricTile(title: "Windows", value: "\(result.windows.count)",
                           systemImage: "square.grid.3x1.below.line.grid.1x2")
            }
            GateStrip(title: "Raw ECG", samples: result.raw, color: .gray)
            GateStrip(title: "Gated ECG", samples: result.gated, color: .green)
        }
    }

    private var thresholdControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading) {
                Text("Motion threshold: \(Int(model.settings.motionThresh)) (ΔZ variance)")
                    .font(.caption)
                Slider(value: Binding(
                    get: { model.settings.motionThresh },
                    set: { v in model.updateSettings { $0.motionThresh = v } }
                ), in: 1.0e6...2.0e7, step: 1.0e5)
            }
            VStack(alignment: .leading) {
                Text("Contact threshold: \(Int(model.settings.contactThresh)) (|Z₀ − baseline| mΩ)")
                    .font(.caption)
                Slider(value: Binding(
                    get: { model.settings.contactThresh },
                    set: { v in model.updateSettings { $0.contactThresh = v } }
                ), in: 1.0e6...1.0e7, step: 1.0e5)
            }
            VStack(alignment: .leading) {
                Text("Display window: \(Int(windowSec)) s").font(.caption)
                Slider(value: $windowSec, in: 4...16, step: 1)
            }
            if model.isMock {
                Button {
                    model.injectMockMotion()
                } label: {
                    Label("Inject motion burst (mock)", systemImage: "bolt.fill")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// Snapshot the recent window from the buffers and run the pure gate function.
    private func computeGate() -> (raw: [Double?], gated: [Double?], windows: [GateWindow], goodPct: Double) {
        let latest = model.buffers.ecg.latestT()
        guard let latest else { return ([], [], [], 0) }
        let from = latest - windowSec * DSPConstants.usPerS
        let ecgW = model.buffers.ecg.window(from: from)
        let dzW = model.buffers.biozDz.window(from: from)
        let z0W = model.buffers.z0.window(from: from)
        let res = gateEcg(
            ecg: TimedSeries(t: ecgW.t, v: ecgW.v),
            dz: TimedSeries(t: dzW.t, v: dzW.v),
            z0: TimedSeries(t: z0W.t, v: z0W.v),
            windowMs: model.settings.gatingWindowMs,
            motionThresh: model.settings.motionThresh,
            contactThresh: model.settings.contactThresh
        )
        let raw: [Double?] = ecgW.v.map { Optional($0) }
        return (raw, res.gatedEcg, res.windows, res.goodPct)
    }
}

/// A static Canvas strip that draws an optional-valued series, breaking the line at nils.
private struct GateStrip: View {
    let title: String
    let samples: [Double?]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Canvas { ctx, size in draw(in: ctx, size: size) }
                .frame(height: 110)
                .background(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func draw(in ctx: GraphicsContext, size: CGSize) {
        let present = samples.compactMap { $0 }
        guard present.count > 1 else { return }
        var lo = present.min()!, hi = present.max()!
        if !(hi > lo) { hi = lo + 1 }
        let margin = (hi - lo) * 0.1
        lo -= margin; hi += margin

        let w = Double(size.width)
        let h = Double(size.height)
        let n = Double(samples.count)
        func x(_ i: Int) -> Double { Double(i) / max(1, n - 1) * w }
        func y(_ v: Double) -> Double { h - (v - lo) / (hi - lo) * h }

        var path = Path()
        var penDown = false
        for i in 0..<samples.count {
            if let v = samples[i] {
                let pt = CGPoint(x: x(i), y: y(v))
                if penDown { path.addLine(to: pt) } else { path.move(to: pt); penDown = true }
            } else {
                penDown = false // blank: break the stroke
            }
        }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
    }
}
