//
//  SettingsView.swift
//  VitalView
//
//  Stream rates, gating thresholds, calibration model, metrics source (firmware vs app),
//  theme, and data management. Mirrors the web Settings screen.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                metricsSourceSection
                streamRatesSection
                gatingSection
                calibrationSection
                appearanceSection
                if model.isMock { mockSection }
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    private var metricsSourceSection: some View {
        Section("Metrics source") {
            Picker("Compute metrics", selection: Binding(
                get: { model.settings.metricsSource },
                set: { v in model.updateSettings { $0.metricsSource = v } }
            )) {
                Text("App (on-device DSP)").tag(MetricsSource.app)
                Text("Firmware").tag(MetricsSource.firmware)
            }
            Text("The app computes its own metrics so the algorithms can be iterated without reflashing the device.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var streamRatesSection: some View {
        Section("Stream sample rates") {
            ForEach(StreamKind.allCases, id: \.self) { stream in
                Picker(stream.rawValue.uppercased(), selection: Binding(
                    get: { model.settings.streamRates[stream] ?? BLEProtocol.defaultRateHz(stream) },
                    set: { hz in model.updateSettings { $0.streamRates[stream] = hz } }
                )) {
                    ForEach(BLEProtocol.rateCodes(stream), id: \.self) { hz in
                        Text("\(hz) Hz").tag(hz)
                    }
                }
            }
        }
    }

    private var gatingSection: some View {
        Section("Gating thresholds") {
            stepperRow("Motion threshold", value: Binding(
                get: { model.settings.motionThresh },
                set: { v in model.updateSettings { $0.motionThresh = v } }
            ), step: 1.0e5, range: 1.0e6...2.0e7)
            stepperRow("Contact threshold", value: Binding(
                get: { model.settings.contactThresh },
                set: { v in model.updateSettings { $0.contactThresh = v } }
            ), step: 1.0e5, range: 1.0e6...1.0e7)
            Picker("Window", selection: Binding(
                get: { model.settings.gatingWindowMs },
                set: { v in model.updateSettings { $0.gatingWindowMs = v } }
            )) {
                ForEach([250.0, 500.0, 1000.0], id: \.self) { Text("\(Int($0)) ms").tag($0) }
            }
        }
    }

    private var calibrationSection: some View {
        Section("Calibration model") {
            Picker("PAT→BP model", selection: Binding(
                get: { model.settings.calibModel },
                set: { v in model.updateSettings { $0.calibModel = v } }
            )) {
                Text("Linear in 1/PAT").tag(CalibModel.linearInvPAT)
                Text("Linear in PAT").tag(CalibModel.linearPAT)
            }
            if let cal = model.currentCalibration {
                LabeledContent("Active model", value: cal.model.rawValue)
                LabeledContent("SBP coeffs", value: String(format: "%.1f, %.1f", cal.coeffs.sbp[0], cal.coeffs.sbp[1]))
                LabeledContent("DBP coeffs", value: String(format: "%.1f, %.1f", cal.coeffs.dbp[0], cal.coeffs.dbp[1]))
            } else {
                Text("No calibration for the current subject (BP shown as uncalibrated).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: Binding(
                get: { model.settings.theme },
                set: { v in model.updateSettings { $0.theme = v } }
            )) {
                Text("System").tag(AppSettings.Theme.system)
                Text("Light").tag(AppSettings.Theme.light)
                Text("Dark").tag(AppSettings.Theme.dark)
            }
            // Units: timestamps are always device microseconds in exports (per spec);
            // metrics are displayed in conventional units (bpm, %, ms, mmHg).
            LabeledContent("Units", value: "bpm · % · ms · mmHg")
        }
    }

    private var mockSection: some View {
        Section("Mock signal") {
            mockStepper("Heart rate", suffix: "bpm", get: { model.mockHrBpm }, set: { v in
                model.setMockParams { $0.hrBpm = v }
            }, step: 1, range: 40...180)
            mockStepper("PAT", suffix: "ms", get: { model.mockPatMs }, set: { v in
                model.setMockParams { $0.patMs = v }
            }, step: 5, range: 80...350)
            mockStepper("SpO₂ target", suffix: "%", get: { model.mockSpo2 }, set: { v in
                model.setMockParams { $0.spo2Target = v }
            }, step: 1, range: 85...100)
            Button { model.injectMockMotion() } label: {
                Label("Inject motion burst", systemImage: "bolt.fill")
            }
        }
    }

    private var dataSection: some View {
        Section("Data management") {
            LabeledContent("Subjects", value: "\(model.subjects.count)")
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete all local data", systemImage: "trash")
            }
            .confirmationDialog("Delete all subjects, sessions, calibrations and recordings? This cannot be undone.",
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { model.deleteAllData() }
                Button("Cancel", role: .cancel) {}
            }
            Text("All data is stored locally on this device only.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text("VitalView is a research / educational tool, NOT a medical device. SpO₂ and blood-pressure values are uncalibrated estimates. It mirrors the VitalView web app and shares the DSP spec in docs/.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: helpers

    private func stepperRow(_ title: String, value: Binding<Double>, step: Double,
                            range: ClosedRange<Double>) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title, value: "\(Int(value.wrappedValue))")
        }
    }

    private func mockStepper(_ title: String, suffix: String, get: @escaping () -> Double,
                             set: @escaping (Double) -> Void, step: Double,
                             range: ClosedRange<Double>) -> some View {
        Stepper(value: Binding(get: get, set: set), in: range, step: step) {
            LabeledContent(title, value: "\(Int(get())) \(suffix)")
        }
    }
}
