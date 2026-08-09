//
//  CalibrationView.swift
//  MoniVitals
//
//  Collect PAT↔reading pairs for the selected profile, fit a PAT→BP model (OLS),
//  show Pearson R and RMSE, plot a Swift Charts scatter with the fit line, and save /
//  re-fit. This is a coarse per-profile fit for a friendly, educational demo —
//  not a validated clinical model.
//

import Charts
import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sbp = "120"
    @State private var dbp = "80"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MV.s20) {
                    if model.currentSubjectCode == nil {
                        noProfileState
                    } else {
                        capturedCard
                        pairsCard
                        fitCard
                        chartCard
                        disclaimer
                    }
                }
                .padding(MV.s16)
            }
            .background(MV.bg)
            .navigationTitle("Calibrate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Calibrate").font(.headline).foregroundStyle(MV.navy)
                }
            }
        }
    }

    private var noProfileState: some View {
        VStack(spacing: MV.s12) {
            IconBadge(systemName: "person.crop.circle.badge.questionmark", tint: MV.navy, size: 56)
            Text("No profile selected")
                .font(.headline).foregroundStyle(MV.ink)
            Text("Pick a profile on the Save tab first, then come back here.")
                .font(.subheadline).foregroundStyle(MV.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MV.s32)
        .mvCard()
        .padding(.top, MV.s24)
    }

    private var capturedCard: some View {
        VStack(alignment: .leading, spacing: MV.s12) {
            SectionHeader(title: "Add a sample reading",
                          subtitle: "Pair the live pulse timing with a cuff reading")
            VStack(alignment: .leading, spacing: MV.s16) {
                HStack {
                    HStack(spacing: MV.s8) {
                        IconBadge(systemName: "timer", tint: MV.navy, size: 26)
                        Text("Current PAT").font(.subheadline).foregroundStyle(MV.ink)
                    }
                    Spacer()
                    Text(Fmt.patMs(model.liveMetrics?.patUs).appending(model.liveMetrics?.patUs == nil ? "" : " ms"))
                        .font(MV.number(18))
                        .foregroundStyle(model.liveMetrics?.patUs == nil ? MV.inkMuted : MV.ink)
                }

                HStack(spacing: MV.s12) {
                    fieldColumn(icon: "arrow.up", tint: MV.warn, label: "Sample SBP", text: $sbp)
                    fieldColumn(icon: "arrow.down", tint: MV.warn, label: "Sample DBP", text: $dbp)
                }

                Button {
                    if let s = Double(sbp), let d = Double(dbp) {
                        _ = model.addCalibrationPair(sbp: s, dbp: d)
                    }
                } label: {
                    Label("Add sample reading", systemImage: "plus.circle")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.liveMetrics?.patUs == nil)
            }
            .mvCard()
        }
    }

    private func fieldColumn(icon: String, tint: Color, label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: MV.s4) {
            HStack(spacing: 6) {
                IconBadge(systemName: icon, tint: tint, size: 22)
                Text(label).font(.caption.weight(.medium)).foregroundStyle(MV.inkMuted)
            }
            TextField(label, text: text)
                .keyboardType(.numberPad)
                .font(MV.number(18))
                .foregroundStyle(MV.ink)
                .padding(.vertical, MV.s8)
                .padding(.horizontal, MV.s12)
                .background(RoundedRectangle(cornerRadius: MV.rControl).fill(MV.surfaceAlt))
                .overlay(RoundedRectangle(cornerRadius: MV.rControl).stroke(MV.separator, lineWidth: 1))
        }
    }

    private var pairsCard: some View {
        VStack(alignment: .leading, spacing: MV.s12) {
            SectionHeader(title: "Sample readings (\(model.calibrationPairs.count))",
                          subtitle: "PAT paired with your cuff readings")
            VStack(alignment: .leading, spacing: MV.s12) {
                if model.calibrationPairs.isEmpty {
                    Text("Add at least three readings across a range of pulse-timing values for a nice fit.")
                        .font(.caption).foregroundStyle(MV.inkMuted)
                } else {
                    ForEach(Array(model.calibrationPairs.enumerated()), id: \.offset) { idx, p in
                        HStack(spacing: MV.s8) {
                            IconBadge(systemName: "timer", tint: MV.navy, size: 24)
                            Text(String(format: "PAT %.0f ms", p.patUs / 1000))
                                .font(.subheadline).foregroundStyle(MV.ink)
                            Spacer()
                            Text(String(format: "%.0f/%.0f mmHg", p.sbp, p.dbp))
                                .font(MV.number(15)).foregroundStyle(MV.inkMuted)
                            Button {
                                model.removeCalibrationPair(at: idx)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(MV.bad)
                            }
                            .buttonStyle(.plain)
                        }
                        if idx < model.calibrationPairs.count - 1 {
                            Divider().overlay(MV.separator)
                        }
                    }

                    Button(role: .destructive) { model.clearCalibrationPairs() } label: {
                        Text("Clear readings").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .foregroundStyle(MV.bad)
                }
            }
            .mvCard()
        }
    }

    private var fitCard: some View {
        VStack(alignment: .leading, spacing: MV.s12) {
            SectionHeader(title: "Fit", subtitle: "How well pulse timing tracks the readings")
            VStack(alignment: .leading, spacing: MV.s12) {
                if let fit = model.currentFit {
                    statRow("Model", fit.model.rawValue)
                    statRow("Pearson R (SBP)", String(format: "%.3f", fit.r))
                    statRow("RMSE SBP", String(format: "%.1f mmHg", fit.rmseSbp))
                    statRow("RMSE DBP", String(format: "%.1f mmHg", fit.rmseDbp))
                    statRow("Readings", "\(fit.n)")
                    Button {
                        _ = model.saveCalibrationFit()
                    } label: {
                        Label(model.currentCalibration == nil ? "Save fit" : "Update fit",
                              systemImage: "checkmark.seal")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Text("Add two or more readings with different pulse timing to see a fit.")
                        .font(.subheadline).foregroundStyle(MV.inkMuted)
                }
                if let cal = model.currentCalibration {
                    Divider().overlay(MV.separator)
                    statRow("Saved model", cal.model.rawValue)
                    statRow("Saved R", String(format: "%.3f", cal.r))
                }
            }
            .mvCard()
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(MV.inkMuted)
            Spacer()
            Text(value).font(MV.number(15)).foregroundStyle(MV.ink)
        }
    }

    @ViewBuilder
    private var chartCard: some View {
        if model.calibrationPairs.count >= 2, let fit = model.currentFit {
            VStack(alignment: .leading, spacing: MV.s12) {
                SectionHeader(title: "SBP vs predictor", subtitle: "Readings and the fitted line")
                VStack(alignment: .leading, spacing: MV.s8) {
                    Chart {
                        ForEach(Array(model.calibrationPairs.enumerated()), id: \.offset) { _, p in
                            let x = predictor(p.patUs, fit.model)
                            PointMark(x: .value("predictor", x), y: .value("SBP", p.sbp))
                                .foregroundStyle(MV.magenta)
                        }
                        // Fit line across the predictor range.
                        let xs = model.calibrationPairs.map { predictor($0.patUs, fit.model) }
                        if let lo = xs.min(), let hi = xs.max() {
                            ForEach([lo, hi], id: \.self) { x in
                                LineMark(x: .value("predictor", x),
                                         y: .value("fit", fit.coeffs.sbp[0] + fit.coeffs.sbp[1] * x))
                                    .foregroundStyle(MV.navy)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(MV.separator)
                            AxisTick().foregroundStyle(MV.separator)
                            AxisValueLabel().foregroundStyle(MV.inkMuted)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(MV.separator)
                            AxisTick().foregroundStyle(MV.separator)
                            AxisValueLabel().foregroundStyle(MV.inkMuted)
                        }
                    }
                    .frame(height: 200)
                    Text(fit.model == .linearInvPAT ? "predictor = 1 / PAT(s)" : "predictor = PAT(s)")
                        .font(.caption2).foregroundStyle(MV.inkMuted)
                }
                .mvCard()
            }
        }
    }

    private var disclaimer: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.caption2).foregroundStyle(MV.accent)
            Text("A simple, per-profile fit for fun and learning — not a medical device.")
                .font(.caption2).foregroundStyle(MV.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, MV.s4)
    }
}
