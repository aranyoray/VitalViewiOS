//
//  SettingsView.swift
//  MoniVitals
//
//  Stream rates, signal-quality controls, fit model, metrics source, theme, and data
//  management, plus the demo-signal sliders. Mirrors the web Settings screen.
//
//  Kept as a Form (not converted to card ScrollView): it is dense with system
//  Pickers/Steppers whose native behaviors we want to preserve. Instead it wears the
//  light theme — hidden scroll background, MV.bg canvas, and MV.surface rows — so it
//  reads like the rest of the app.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                modelSection
                metricsSourceSection
                if model.isTunableSignal { streamRatesSection }
                gatingSection
                calibrationSection
                appearanceSection
                if model.isTunableSignal { mockSection }
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(MV.bg)
            .tint(MV.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings").font(.headline).foregroundStyle(MV.navy)
                }
            }
        }
    }

    private var modelSection: some View {
        Section("Model") {
            HStack(spacing: MV.s12) {
                IconBadge(systemName: "cpu", tint: MV.navy, size: 28)
                Text("Model: \(model.modelName)")
                    .font(.callout).foregroundStyle(MV.ink)
            }
        }
        .listRowBackground(MV.surface)
    }

    private var metricsSourceSection: some View {
        Section("Metrics Source") {
            Picker("Compute metrics", selection: Binding(
                get: { model.settings.metricsSource },
                set: { v in model.updateSettings { $0.metricsSource = v } }
            )) {
                Text("App (on-device)").tag(MetricsSource.app)
                Text("Recording").tag(MetricsSource.firmware)
            }
            Text("The app can work out its own numbers, or simply show the ones that came with the recording.")
                .font(.caption2).foregroundStyle(MV.inkMuted)
        }
        .listRowBackground(MV.surface)
    }

    private var streamRatesSection: some View {
        Section("Stream Sample Rates") {
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
        .listRowBackground(MV.surface)
    }

    private var gatingSection: some View {
        Section("Signal Quality & Movement") {
            stepperRow("Movement sensitivity", value: Binding(
                get: { model.settings.motionThresh },
                set: { v in model.updateSettings { $0.motionThresh = v } }
            ), step: 1.0e5, range: 1.0e6...2.0e7)
            stepperRow("Contact sensitivity", value: Binding(
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
        .listRowBackground(MV.surface)
    }

    private var calibrationSection: some View {
        Section("Blood-Pressure Fit") {
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
                Text("No fit yet for this profile — add a few sample readings on the Calibrate tab to estimate blood pressure.")
                    .font(.caption2).foregroundStyle(MV.inkMuted)
            }
        }
        .listRowBackground(MV.surface)
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
        .listRowBackground(MV.surface)
    }

    private var mockSection: some View {
        Section("Demo Signal") {
            mockStepper("Heart rate", suffix: "bpm", get: { model.mockHrBpm }, set: { v in
                model.setMockParams { $0.hrBpm = v }
            }, step: 1, range: 40...180)
            mockStepper("Pulse arrival time", suffix: "ms", get: { model.mockPatMs }, set: { v in
                model.setMockParams { $0.patMs = v }
            }, step: 5, range: 80...350)
            mockStepper("SpO₂ target", suffix: "%", get: { model.mockSpo2 }, set: { v in
                model.setMockParams { $0.spo2Target = v }
            }, step: 1, range: 85...100)
            Button { model.injectMockMotion() } label: {
                Label("Add a little movement", systemImage: "bolt.fill")
            }
        }
        .listRowBackground(MV.surface)
    }

    private var dataSection: some View {
        Section("Your Data") {
            LabeledContent("Profiles", value: "\(model.subjects.count)")
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete all local data", systemImage: "trash")
            }
            .foregroundStyle(MV.bad)
            .confirmationDialog("Remove all profiles, clips, and readings from this phone? This can't be undone.",
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { model.deleteAllData() }
                Button("Cancel", role: .cancel) {}
            }
            Text("Everything stays on this phone — nothing is ever uploaded.")
                .font(.caption2).foregroundStyle(MV.inkMuted)
        }
        .listRowBackground(MV.surface)
    }

    private var aboutSection: some View {
        Section("About") {
            HStack(alignment: .top, spacing: MV.s12) {
                IconBadge(systemName: "sparkles", tint: MV.accent, size: 28)
                Text("MoniVitals is a friendly on-device demo — for fun and learning, not a medical device. It replays a bundled sample recording on your phone; nothing is measured from you, and every number is just an estimate.")
                    .font(.caption).foregroundStyle(MV.inkMuted)
            }
        }
        .listRowBackground(MV.surface)
    }

    // MARK: helpers

    private func stepperRow(_ title: String, value: Binding<Double>, step: Double,
                            range: ClosedRange<Double>) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title, value: String(format: "%.1f×10⁶", value.wrappedValue / 1_000_000))
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
