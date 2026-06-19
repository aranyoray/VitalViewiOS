//
//  RecorderView.swift
//  VitalView
//
//  Select a subject + label, Start/Stop a recording, watch live duration, per-stream
//  sample counters, and dropped-packet counts, drop annotation markers, and capture a
//  "Cuff reading" (SBP/DBP) — the ground-truth used for PAT→BP calibration.
//

import SwiftUI

struct RecorderView: View {
    @EnvironmentObject private var model: AppModel

    @State private var label: SessionLabel = .rest
    @State private var notes = ""
    @State private var showSubjectSheet = false
    @State private var showCuffSheet = false

    var body: some View {
        NavigationStack {
            List {
                subjectSection
                setupSection
                if model.recording != nil { liveSection; annotationSection }
            }
            .navigationTitle("Recorder")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ConnectionPill(state: model.connectionState) }
            }
            .sheet(isPresented: $showSubjectSheet) { SubjectPickerSheet() }
            .sheet(isPresented: $showCuffSheet) { CuffReadingSheet() }
        }
    }

    private var subjectSection: some View {
        Section("Subject") {
            Button {
                showSubjectSheet = true
            } label: {
                LabeledContent("Selected subject", value: model.currentSubjectCode ?? "none")
            }
        }
    }

    private var setupSection: some View {
        Section("Session") {
            Picker("Label", selection: $label) {
                ForEach(SessionLabel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .disabled(model.recording != nil)

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .disabled(model.recording != nil)

            if model.recording == nil {
                Button {
                    model.startRecording(label: label, notes: notes)
                } label: {
                    Label("Start recording", systemImage: "record.circle")
                }
                .disabled(model.currentSubjectCode == nil || model.connectionState != .connected)
            } else {
                Button(role: .destructive) {
                    model.stopRecording()
                } label: {
                    Label("Stop recording", systemImage: "stop.circle")
                }
            }
        }
    }

    private var liveSection: some View {
        Section("Live") {
            LabeledContent("Duration", value: Fmt.duration(model.recordDurationMs))
            LabeledContent("ECG samples", value: "\(model.recordCounts[.ecg] ?? 0)")
            LabeledContent("BioZ samples", value: "\(model.recordCounts[.bioz] ?? 0)")
            LabeledContent("PPG samples", value: "\(model.recordCounts[.ppg] ?? 0)")
            LabeledContent("Dropped (E/B/P)",
                           value: "\(model.dropped[.ecg] ?? 0)/\(model.dropped[.bioz] ?? 0)/\(model.dropped[.ppg] ?? 0)")
            LabeledContent("Cuff readings", value: "\(model.cuffReadingCount)")
        }
    }

    private var annotationSection: some View {
        Section("Annotations") {
            Button { showCuffSheet = true } label: {
                Label("Cuff reading…", systemImage: "stethoscope")
            }
            Button { model.addMarker(.marker) } label: {
                Label("Marker", systemImage: "mappin")
            }
            Button { model.addMarker(.motionStart) } label: {
                Label("Motion start", systemImage: "figure.walk.motion")
            }
            Button { model.addMarker(.motionStop) } label: {
                Label("Motion stop", systemImage: "figure.stand")
            }
            Button { model.addMarker(.artifact) } label: {
                Label("Artifact", systemImage: "exclamationmark.triangle")
            }
        }
    }
}

// MARK: - Subject picker / creator

struct SubjectPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var newCode = ""
    @State private var ageBand = "18-25"
    @State private var notes = ""

    private let ageBands = ["<18", "18-25", "26-35", "36-45", "46-55", "56-65", "65+"]

    var body: some View {
        NavigationStack {
            List {
                Section("Existing subjects") {
                    if model.subjects.isEmpty {
                        Text("No subjects yet.").foregroundStyle(.secondary)
                    }
                    ForEach(model.subjects) { s in
                        Button {
                            model.selectSubject(s.code)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(s.code).font(.headline)
                                    Text(s.ageBand).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.currentSubjectCode == s.code {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section("New subject (non-identifying code)") {
                    TextField("Code, e.g. S01", text: $newCode)
                        .textInputAutocapitalization(.characters)
                    Picker("Age band", selection: $ageBand) {
                        ForEach(ageBands, id: \.self) { Text($0) }
                    }
                    TextField("Notes (optional)", text: $notes)
                    Button("Add subject") {
                        let code = newCode.trimmingCharacters(in: .whitespaces)
                        guard !code.isEmpty else { return }
                        let subject = Subject(code: code, ageBand: ageBand, sex: nil, notes: notes,
                                              createdAt: ISO8601DateFormatter().string(from: Date()))
                        model.saveSubject(subject)
                        model.selectSubject(code)
                        dismiss()
                    }
                    .disabled(newCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Subjects")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            }
            .onAppear { model.refreshSubjects() }
        }
    }
}

// MARK: - Cuff reading capture

struct CuffReadingSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var sbp = "120"
    @State private var dbp = "80"

    var body: some View {
        NavigationStack {
            Form {
                Section("Reference cuff reading") {
                    TextField("Systolic (SBP)", text: $sbp)
                        .keyboardType(.numberPad)
                    TextField("Diastolic (DBP)", text: $dbp)
                        .keyboardType(.numberPad)
                }
                Section {
                    Text("Captured at the current device time and, when a PAT is available, added as a calibration pair.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cuff reading")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let s = Double(sbp), let d = Double(dbp) {
                            model.addCuffReading(sbp: s, dbp: d)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
