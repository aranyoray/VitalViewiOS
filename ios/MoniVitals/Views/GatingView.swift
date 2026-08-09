//
//  GatingView.swift
//  MoniVitals
//
//  The app's core idea, visualized: raw ECG vs cleaned ECG side by side, plus the
//  percentage of "good" segments. The movement / contact thresholds are adjustable and
//  feed back into Settings (and the live engine). Skipped (low-quality) samples are not
//  drawn in the cleaned strip.
//

import SwiftUI

struct GatingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var windowSec: Double = 8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MV.s20) {
                    intro

                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        gatedContent
                    }

                    controlsCard
                }
                .padding(MV.s16)
            }
            .background(MV.bg)
            .navigationTitle("Signal Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Signal Quality").font(.headline).foregroundStyle(MV.navy)
                }
                ToolbarItem(placement: .topBarTrailing) { ConnectionPill(state: model.connectionState) }
            }
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: MV.s12) {
            IconBadge(systemName: "wand.and.stars", tint: MV.bioz, size: 34)
            Text("This shows how the demo tidies up the ECG. When there is too much movement or the contact dips, that stretch is gently skipped so only the clean parts are drawn.")
                .font(.callout).foregroundStyle(MV.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mvCard()
    }

    private var gatedContent: some View {
        let result = computeGate()
        return VStack(alignment: .leading, spacing: MV.s16) {
            VStack(alignment: .leading, spacing: MV.s12) {
                SectionHeader(title: "Quality", subtitle: "Live from the current window")
                HStack(spacing: MV.s12) {
                    MetricTile(title: "Clean segments", value: String(format: "%.0f", result.goodPct),
                               unit: "%", systemImage: "checkmark.seal", tint: MV.good)
                    MetricTile(title: "Windows", value: "\(result.windows.count)",
                               systemImage: "square.grid.3x1.below.line.grid.1x2", tint: MV.navy)
                }
            }

            VStack(alignment: .leading, spacing: MV.s12) {
                SectionHeader(title: "Raw vs cleaned", subtitle: "Skipped stretches are left blank")
                VStack(alignment: .leading, spacing: MV.s16) {
                    GateStrip(title: "Raw ECG", samples: result.raw, color: MV.inkMuted)
                    GateStrip(title: "Cleaned ECG", samples: result.gated, color: MV.navy)
                }
                .mvCard()
            }
        }
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: MV.s12) {
            SectionHeader(title: "Sensitivity", subtitle: "Tune how strictly the signal is cleaned")
            VStack(alignment: .leading, spacing: MV.s20) {
                sliderRow(icon: "figure.walk", tint: MV.pink,
                          label: "Movement sensitivity",
                          value: Int(model.settings.motionThresh),
                          binding: Binding(
                            get: { model.settings.motionThresh },
                            set: { v in model.updateSettings { $0.motionThresh = v } }),
                          range: 1.0e6...2.0e7, step: 1.0e5)

                sliderRow(icon: "hand.point.up.left.fill", tint: MV.bioz,
                          label: "Contact sensitivity",
                          value: Int(model.settings.contactThresh),
                          binding: Binding(
                            get: { model.settings.contactThresh },
                            set: { v in model.updateSettings { $0.contactThresh = v } }),
                          range: 1.0e6...1.0e7, step: 1.0e5)

                sliderRow(icon: "clock", tint: MV.navy,
                          label: "Time shown",
                          value: Int(windowSec), suffix: " s",
                          binding: $windowSec, range: 4...16, step: 1)

                if model.isTunableSignal {
                    Button {
                        model.injectMockMotion()
                    } label: {
                        Label("Add a little movement", systemImage: "bolt.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .mvCard()
        }
    }

    private func sliderRow(icon: String, tint: Color, label: String, value: Int,
                           suffix: String = "", binding: Binding<Double>,
                           range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: MV.s8) {
            HStack(spacing: MV.s8) {
                IconBadge(systemName: icon, tint: tint, size: 26)
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(MV.ink)
                Spacer()
                Text("\(value)\(suffix)")
                    .font(MV.number(16)).foregroundStyle(MV.ink)
            }
            Slider(value: binding, in: range, step: step).tint(MV.accent)
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

    private var hasSignal: Bool { samples.compactMap { $0 }.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: MV.s8) {
            HStack {
                ChipLabel(text: title, color: color)
                Spacer()
                if !hasSignal {
                    Text("warming up…").font(.caption2).foregroundStyle(MV.inkMuted)
                }
            }
            Canvas { ctx, size in draw(in: ctx, size: size) }
                .frame(height: 110)
                .background(MV.surfaceAlt)
                .overlay(RoundedRectangle(cornerRadius: MV.rControl).stroke(MV.separator, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: MV.rControl))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title)")
        }
    }

    private func draw(in ctx: GraphicsContext, size: CGSize) {
        // Faint centre baseline for a calmer read.
        var base = Path()
        base.move(to: CGPoint(x: 0, y: size.height / 2))
        base.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        ctx.stroke(base, with: .color(MV.separator.opacity(0.7)), style: StrokeStyle(lineWidth: 0.5))

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
