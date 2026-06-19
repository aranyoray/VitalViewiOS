//
//  WaveformStrip.swift
//  VitalView
//
//  Live waveform strip rendered with Canvas inside a TimelineView. Reads directly from a
//  non-reactive WaveBuffer on each animation tick — high-rate sample data never goes
//  through @Published state, so SwiftUI is not re-rendered per sample.
//
//  Used for the 256 Hz ECG / 100 Hz PPG / 64 Hz BioZ live strips (NOT Swift Charts,
//  which is reserved for recorded/static plots).
//

import SwiftUI

struct WaveformStrip: View {
    let title: String
    let buffer: WaveBuffer
    /// Window length shown, in seconds.
    var windowSec: Double = 4
    var color: Color = .green
    /// Optional second buffer drawn faintly behind (e.g. raw ECG under gated ECG).
    var underlay: WaveBuffer? = nil
    var underlayColor: Color = .gray.opacity(0.4)
    var height: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                Canvas { ctx, size in
                    if let underlay {
                        draw(buffer: underlay, in: ctx, size: size, color: underlayColor, lineWidth: 1)
                    }
                    draw(buffer: buffer, in: ctx, size: size, color: color, lineWidth: 1.5)
                }
                .background(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: height)
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
