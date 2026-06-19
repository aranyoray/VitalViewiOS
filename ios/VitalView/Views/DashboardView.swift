//
//  DashboardView.swift
//  VitalView
//
//  Live ECG / PPG / BioZ strips (Canvas + TimelineView over ring buffers) plus metric
//  tiles: HR, SpO₂ (estimate), PAT, BP (uncalibrated unless a model exists), contact,
//  motion. No diagnostic/clinical language — values are estimates.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.connectionState != .connected {
                        notConnectedBanner
                    }

                    metricTiles

                    WaveformStrip(title: "ECG (256 Hz)", buffer: model.buffers.ecg,
                                  windowSec: 4, color: .green, height: 130)
                    WaveformStrip(title: "PPG green (100 Hz)", buffer: model.buffers.ppgGreen,
                                  windowSec: 6, color: .pink, height: 110)
                    WaveformStrip(title: "BioZ ΔZ (64 Hz)", buffer: model.buffers.biozDz,
                                  windowSec: 6, color: .cyan, height: 100)
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ConnectionPill(state: model.connectionState) }
            }
        }
    }

    private var metricTiles: some View {
        let m = model.liveMetrics
        let calibrated = model.currentCalibration != nil
        return LazyVGrid(columns: columns, spacing: 12) {
            MetricTile(title: "Heart rate", value: Fmt.bpm(m?.hrBpm), unit: "bpm",
                       systemImage: "heart.fill", tint: .red)
            MetricTile(title: "SpO₂", value: Fmt.pct(m?.spo2Pct), unit: "%",
                       note: "estimate", systemImage: "drop.fill", tint: .blue)
            MetricTile(title: "PAT", value: Fmt.patMs(m?.patUs), unit: "ms",
                       systemImage: "timer", tint: .purple)
            MetricTile(title: "SBP", value: Fmt.opt(m?.sbpMmHg), unit: "mmHg",
                       note: calibrated ? "estimate" : "uncalibrated",
                       systemImage: "gauge.medium", tint: .orange)
            MetricTile(title: "DBP", value: Fmt.opt(m?.dbpMmHg), unit: "mmHg",
                       note: calibrated ? "estimate" : "uncalibrated",
                       systemImage: "gauge.low", tint: .orange)
            MetricTile(title: "Contact", value: "\(m?.contactQuality ?? 0)", unit: "/100",
                       systemImage: "hand.point.up.left.fill", tint: .teal)
            MetricTile(title: "Motion", value: "\(m?.motion ?? 0)", unit: "/255",
                       systemImage: "figure.walk", tint: .yellow)
            MetricTile(title: "Source", value: model.settings.metricsSource == .app ? "App" : "Firmware",
                       systemImage: "function")
        }
    }

    private var notConnectedBanner: some View {
        HStack {
            Image(systemName: "info.circle")
            Text("Connect a device (or Mock) and start streaming to see live signals.")
                .font(.callout)
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
