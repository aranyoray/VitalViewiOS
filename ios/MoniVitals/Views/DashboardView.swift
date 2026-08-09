//
//  DashboardView.swift
//  MoniVitals
//
//  Live ECG / PPG / BioZ strips plus metric tiles: HR, SpO₂, PAT, BP, contact, movement.
//  Values are estimates from the current signal — no diagnostic/clinical language.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [
        GridItem(.flexible(), spacing: MV.s12),
        GridItem(.flexible(), spacing: MV.s12),
        GridItem(.flexible(), spacing: MV.s12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MV.s20) {
                    header

                    if model.connectionState == .unsupported { unavailableCard }

                    if model.recordingName != nil { recordingCard }

                    VStack(alignment: .leading, spacing: MV.s12) {
                        SectionHeader(title: "Vitals", subtitle: "Estimated live from the signals below")
                        metricTiles
                    }

                    VStack(alignment: .leading, spacing: MV.s12) {
                        SectionHeader(title: "Live signals")
                        WaveformStrip(title: "ECG · \(model.sampleRateHz(.ecg)) Hz", buffer: model.buffers.ecg,
                                      windowSec: 4, color: MV.ecg, height: 132)
                        WaveformStrip(title: "PPG · \(model.sampleRateHz(.ppg)) Hz", buffer: model.buffers.ppgGreen,
                                      windowSec: 6, color: MV.ppg, height: 112)
                        WaveformStrip(title: "BioZ · \(model.sampleRateHz(.bioz)) Hz", buffer: model.buffers.biozDz,
                                      windowSec: 6, color: MV.bioz, height: 100)
                    }

                    footnote
                }
                .padding(MV.s16)
            }
            .background(MV.bg)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: MV.s8) {
            HStack(spacing: MV.s12) {
                Image("Logo").resizable().scaledToFit().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MoniVitals").font(.title2.bold()).foregroundStyle(MV.navy)
                    Text("On-device biosignal demo").font(.caption).foregroundStyle(MV.inkMuted)
                }
                Spacer()
                ConnectionPill(state: model.connectionState)
            }
            HStack(spacing: 6) {
                Image(systemName: "cpu").font(.caption2)
                Text(model.modelName).font(.caption2)
            }
            .foregroundStyle(MV.inkMuted)
        }
    }

    private var unavailableCard: some View {
        HStack(alignment: .top, spacing: MV.s12) {
            IconBadge(systemName: "exclamationmark.triangle.fill", tint: MV.warn, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't load the recording").font(.subheadline.weight(.semibold)).foregroundStyle(MV.ink)
                Text("The bundled sample signal is missing or unreadable, so there's nothing to play right now. Try reinstalling the app.")
                    .font(.caption).foregroundStyle(MV.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mvCard(padding: MV.s12)
    }

    private var recordingCard: some View {
        HStack(spacing: MV.s12) {
            IconBadge(systemName: "waveform.path.ecg", tint: MV.navy, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Real recording").font(.subheadline.weight(.semibold)).foregroundStyle(MV.ink)
                Text(model.recordingName ?? "").font(.caption).foregroundStyle(MV.inkMuted)
                if let hr = model.referenceHR, let sp = model.referenceSpO2 {
                    Text("Recorded reference: \(Int(hr)) bpm · \(Int(sp))% SpO₂")
                        .font(.caption2).foregroundStyle(MV.inkMuted)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mvCard(padding: MV.s12)
    }

    // MARK: - Metrics

    private var metricTiles: some View {
        let m = model.liveMetrics
        let calibrated = model.currentCalibration != nil
        // Warm up only while the runtime is live but the first values haven't landed.
        let warming = model.connectionState == .connected
        return LazyVGrid(columns: columns, spacing: MV.s12) {
            MetricTile(title: "Heart rate", value: Fmt.bpm(m?.hrBpm), unit: "bpm",
                       note: model.referenceHR.map { "recorded ~\(Int($0))" },
                       systemImage: "heart.fill", tint: MV.magenta, warmsUp: warming)
            MetricTile(title: "SpO₂", value: Fmt.pct(m?.spo2Pct), unit: "%",
                       note: model.settings.metricsSource == .firmware ? "Recorded reference" : "Estimate",
                       systemImage: "drop.fill", tint: MV.navy, warmsUp: warming)
            MetricTile(title: "PAT", value: Fmt.patMs(m?.patUs), unit: "ms",
                       note: model.recordingName != nil ? "R–pulse interval" : nil,
                       systemImage: "timer", tint: MV.navy, warmsUp: warming)
            MetricTile(title: "SBP", value: Fmt.opt(m?.sbpMmHg), unit: "mmHg",
                       note: calibrated ? "Estimate" : "Add sample readings",
                       systemImage: "gauge.medium", tint: MV.warn)
            MetricTile(title: "DBP", value: Fmt.opt(m?.dbpMmHg), unit: "mmHg",
                       note: calibrated ? "Estimate" : "Add sample readings",
                       systemImage: "gauge.low", tint: MV.warn)
            MetricTile(title: "Contact", value: Fmt.int(m?.contactQuality), unit: "/100",
                       systemImage: "hand.point.up.left.fill", tint: MV.bioz, warmsUp: warming)
            MetricTile(title: "Movement", value: Fmt.int(m?.motion), unit: "/255",
                       systemImage: "figure.walk", tint: MV.pink, warmsUp: warming)
            MetricTile(title: "Source", value: model.recordingName != nil ? "Real" : "Demo",
                       unit: "", systemImage: "waveform", tint: MV.navy)
        }
    }

    private var footnote: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.caption2).foregroundStyle(MV.accent)
            Text("For fun and learning — not a medical device.")
                .font(.caption2).foregroundStyle(MV.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, MV.s4)
    }
}
