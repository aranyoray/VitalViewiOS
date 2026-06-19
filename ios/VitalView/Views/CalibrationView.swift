//
//  CalibrationView.swift
//  VitalView
//
//  Collect PAT↔cuff reference pairs for the selected subject, fit a PAT→BP model (OLS),
//  show Pearson R and RMSE, plot a Swift Charts scatter with the fit line, and save /
//  re-calibrate. This is a coarse per-subject empirical fit for an educational
//  demonstration — NOT a validated clinical model.
//

import Charts
import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sbp = "120"
    @State private var dbp = "80"

    var body: some View {
        NavigationStack {
            List {
                if model.currentSubjectCode == nil {
                    Section { Text("Select a subject in the Recorder tab first.").foregroundStyle(.secondary) }
                } else {
                    capturedSection
                    pairsSection
                    fitSection
                    chartSection
                    disclaimerSection
                }
            }
            .navigationTitle("Calibration")
        }
    }

    private var capturedSection: some View {
        Section("Add reference pair") {
            LabeledContent("Current PAT") {
                Text(Fmt.patMs(model.liveMetrics?.patUs).appending(model.liveMetrics?.patUs == nil ? "" : " ms"))
                    .foregroundStyle(model.liveMetrics?.patUs == nil ? .secondary : .primary)
            }
            TextField("Cuff SBP", text: $sbp).keyboardType(.numberPad)
            TextField("Cuff DBP", text: $dbp).keyboardType(.numberPad)
            Button {
                if let s = Double(sbp), let d = Double(dbp) {
                    _ = model.addCalibrationPair(sbp: s, dbp: d)
                }
            } label: {
                Label("Capture pair at current PAT", systemImage: "plus.circle")
            }
            .disabled(model.liveMetrics?.patUs == nil)
        }
    }

    private var pairsSection: some View {
        Section("Reference pairs (\(model.calibrationPairs.count))") {
            if model.calibrationPairs.isEmpty {
                Text("Collect at least 3 pairs across a range of PAT values for a usable fit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(model.calibrationPairs.enumerated()), id: \.offset) { idx, p in
                HStack {
                    Text(String(format: "PAT %.0f ms", p.patUs / 1000))
                    Spacer()
                    Text(String(format: "%.0f/%.0f mmHg", p.sbp, p.dbp)).foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                for i in offsets.sorted(by: >) { model.removeCalibrationPair(at: i) }
            }
            if !model.calibrationPairs.isEmpty {
                Button(role: .destructive) { model.clearCalibrationPairs() } label: {
                    Text("Clear pairs")
                }
            }
        }
    }

    private var fitSection: some View {
        Section("Fit") {
            if let fit = model.currentFit {
                LabeledContent("Model", value: fit.model.rawValue)
                LabeledContent("Pearson R (SBP)", value: String(format: "%.3f", fit.r))
                LabeledContent("RMSE SBP", value: String(format: "%.1f mmHg", fit.rmseSbp))
                LabeledContent("RMSE DBP", value: String(format: "%.1f mmHg", fit.rmseDbp))
                LabeledContent("Pairs", value: "\(fit.n)")
                Button {
                    _ = model.saveCalibrationFit()
                } label: {
                    Label(model.currentCalibration == nil ? "Save calibration" : "Re-calibrate",
                          systemImage: "checkmark.seal")
                }
            } else {
                Text("Need ≥ 2 pairs with differing PAT to fit.").foregroundStyle(.secondary)
            }
            if let cal = model.currentCalibration {
                LabeledContent("Saved model", value: cal.model.rawValue)
                LabeledContent("Saved R", value: String(format: "%.3f", cal.r))
            }
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if model.calibrationPairs.count >= 2, let fit = model.currentFit {
            Section("SBP vs predictor") {
                Chart {
                    ForEach(Array(model.calibrationPairs.enumerated()), id: \.offset) { _, p in
                        let x = predictor(p.patUs, fit.model)
                        PointMark(x: .value("predictor", x), y: .value("SBP", p.sbp))
                            .foregroundStyle(.orange)
                    }
                    // Fit line across the predictor range.
                    let xs = model.calibrationPairs.map { predictor($0.patUs, fit.model) }
                    if let lo = xs.min(), let hi = xs.max() {
                        ForEach([lo, hi], id: \.self) { x in
                            LineMark(x: .value("predictor", x),
                                     y: .value("fit", fit.coeffs.sbp[0] + fit.coeffs.sbp[1] * x))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .frame(height: 200)
                Text(fit.model == .linearInvPAT ? "predictor = 1 / PAT(s)" : "predictor = PAT(s)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var disclaimerSection: some View {
        Section {
            Text("Coarse per-subject empirical fit for an educational demonstration. Not a validated clinical model.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
