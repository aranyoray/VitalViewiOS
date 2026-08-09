//
//  WaveformStrip.swift
//  MoniVitals
//
//  Live waveform strip rendered with Canvas. Reads directly from a non-reactive
//  WaveBuffer on a timer-driven redraw — high-rate sample data never goes through
//  @Published state, so the rest of SwiftUI is not re-rendered per sample. A local
//  @State tick advances ~30×/s and forces just this view's Canvas to repaint.
//
//  Used for the live ECG / PPG / BioZ strips (NOT Swift Charts, which is reserved for
//  recorded/static plots). The sample rate shown in each strip's title is derived from
//  the active source.
//

import SwiftUI

struct WaveformStrip: View {
    let title: String
    let buffer: WaveBuffer
    /// Window length shown, in seconds.
    var windowSec: Double = 4
    var color: Color = MV.ecg
    /// Optional second buffer drawn faintly behind (e.g. raw ECG under gated ECG).
    var underlay: WaveBuffer? = nil
    var underlayColor: Color = MV.inkMuted.opacity(0.4)
    var height: CGFloat = 120

    @State private var tick: Int = 0
    /// Only redraw while the strip is on screen — TabView keeps off-screen tabs
    /// alive, so without this the 30 Hz repaint would run forever for every strip.
    @State private var isActive = false
    private let redraw = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ChipLabel(text: title, color: color)
                Spacer()
                if !hasSignal {
                    Text("warming up…")
                        .font(.caption2)
                        .foregroundStyle(MV.inkMuted)
                        .transition(.opacity)
                }
            }
            Canvas { ctx, size in
                _ = tick // depend on the tick so the Canvas repaints on every timer fire
                drawGrid(in: ctx, size: size)
                if let underlay {
                    draw(buffer: underlay, in: ctx, size: size, color: underlayColor, lineWidth: 1)
                }
                draw(buffer: buffer, in: ctx, size: size, color: color, lineWidth: 1.5)
            }
            .frame(height: height)
            .background(MV.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MV.separator, lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) live waveform")
        }
        .onReceive(redraw) { _ in if isActive { tick &+= 1 } }
        .onAppear { isActive = true }
        .onDisappear { isActive = false }
    }

    /// True once at least a couple of samples have arrived to draw a line.
    private var hasSignal: Bool { buffer.length > 1 }

    /// Faint horizontal grid + centre baseline for a calmer, oscilloscope-like read.
    private func drawGrid(in ctx: GraphicsContext, size: CGSize) {
        let rows = 4
        for r in 1..<rows {
            let y = size.height * CGFloat(r) / CGFloat(rows)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            let isCenter = r == rows / 2
            ctx.stroke(line,
                       with: .color(MV.separator.opacity(isCenter ? 0.9 : 0.5)),
                       style: StrokeStyle(lineWidth: isCenter ? 1 : 0.5))
        }
    }

    private func draw(buffer: WaveBuffer, in ctx: GraphicsContext, size: CGSize,
                      color: Color, lineWidth: CGFloat) {
        guard let latest = buffer.latestT() else { return }
        let windowUs = windowSec * DSPConstants.usPerS
        let from = latest - windowUs
        let (ts, vs) = buffer.window(from: from)
        guard ts.count > 1 else { return }

        // Auto-scale vertically to the visible window with a small margin.
        var lo = Double.infinity, hi = -Double.infinity
        for v in vs {
            if v < lo { lo = v }
            if v > hi { hi = v }
        }
        if !(hi > lo) { hi = lo + 1 }
        let margin = (hi - lo) * 0.1
        lo -= margin
        hi += margin

        let w = Double(size.width)
        let h = Double(size.height)
        func x(_ t: Double) -> Double { (t - from) / windowUs * w }
        func y(_ v: Double) -> Double { h - (v - lo) / (hi - lo) * h }

        var path = Path()
        path.move(to: CGPoint(x: x(ts[0]), y: y(vs[0])))
        for i in 1..<ts.count {
            path.addLine(to: CGPoint(x: x(ts[i]), y: y(vs[i])))
        }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
    }
}
