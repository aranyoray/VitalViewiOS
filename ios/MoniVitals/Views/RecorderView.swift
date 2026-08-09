//
//  RecorderView.swift
//  MoniVitals
//
//  Pick a profile + label, save/finish short demo clip, watch its live duration,
//  per-stream sample counters, drop friendly markers, add a "Sample reading"
//  (SBP/DBP) used to fit PAT→BP estimate.
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
            ScrollView {
                VStack(alignment: .leading, spacing: MV.s20) {
                    subjectCard
                    setupCard
                    if model.recording != nil {
                        liveCard
                        annotationCard
                    }
                }
                .padding(MV.s16)
            }
            .background(MV.bg)
            .navigationTitle("Save a Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Save a Clip").font(.headline).foregroundStyle(MV.navy)
                }
                ToolbarItem(placement: .topBarTrailing) { ConnectionPill(state: model.connectionState) }
            }
            .sheet(isPresented: $showSubjectSheet) { SubjectPickerSheet() }
            .sheet(isPresented: $showCuffSheet) { CuffReadingSheet() }
        }
    }

    private var subjectCard: some View {
        VStack(alignment: .leading, spacing: MV.s12) {
            SectionHeader(title: "Profile", subtitle: "Who this clip belongs to")
            Button {
                showSubjectSheet = true
            } label: {
                HStack(spacing: MV.s12) {
                    IconBadge(systemName: "person.crop.circle", tint: MV.navy, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected profile").font(.caption).foregroundStyle(MV.inkMuted)
                        Text(model.currentSubjectCode ?? "None yet")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(MV.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(MV.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .mvCard(padding: MV.s12)
            }
            .buttonStyle(.plain)
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: MV.s12) {
            SectionHeader(title: "Clip", subtitle: "Label the session, then start")
            VStack(alignment: .leading, spacing: MV.s16) {
                HStack(spacing: MV.s8) {
                    IconBadge(systemName: "tag", tint: MV.navy, size: 26)
                    Text("Label").font(.subheadline.weight(.medium)).foregroundStyle(MV.ink)
                    Spacer()
                    Picker("Label", selection: $label) {
                        ForEach(SessionLabel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(MV.accent)
                    .disabled(model.recording != nil)
                }

                VStack(alignment: .leading, spacing: MV.s8) {
                    Text("Notes (optional)").font(.caption.weight(.medium)).foregroundStyle(MV.inkMuted)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .disabled(model.recording != nil)
                        .padding(MV.s12)
                        .background(RoundedRectangle(cornerRadius: MV.rControl).fill(MV.surfaceAlt))
                        .overlay(RoundedRectangle(cornerRadius: MV.rControl).stroke(MV.separator, lineWidth: 1))
                }

                if model.recording == nil {
                    Button {
                        model.startRecording(label: label, notes: notes)
                    } label: {
                        Label("Save a clip", systemImage: "record.circle")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.currentSubjectCode == nil || model.connectionState != .connected)
                } else {
                    Button {
                        model.stopRecording()
                    } label: {
                        Label("Finish clip", systemImage: "stop.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .foregroundStyle(MV.bad)
                }
            }
            .mvCard()
        }
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: MV.s12) {
            SectionHeader(title: "Recording now", subtitle: "Live counters for this clip")
            VStack(alignment: .leading, spacing: MV.s12) {
                statRow(icon: "clock", tint: MV.magenta, "Duration", Fmt.duration(model.recordDurationMs))
                Divider().overlay(MV.separator)
                statRow(icon: "waveform.path.ecg", tint: MV.navy, "ECG samples", "\(model.recordCounts[.ecg] ?? 0)")
                statRow(icon: "waveform.path", tint: MV.bioz, "BioZ samples", "\(model.recordCounts[.bioz] ?? 0)")
                statRow(icon: "drop.fill", tint: MV.magenta, "PPG samples", "\(model.recordCounts[.ppg] ?? 0)")
                Divider().overlay(MV.separator)
                statRow(icon: "scissors", tint: MV.inkMuted, "Skipped (E/B/P)",
                        "\(model.dropped[.ecg] ?? 0)/\(model.dropped[.bioz] ?? 0)/\(model.dropped[.ppg] ?? 0)")
                statRow(icon: "stethoscope", tint: MV.warn, "Sample readings", "\(model.cuffReadingCount)")
            }
            .mvCard()
        }
    }

    private func statRow(icon: String, tint: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: MV.s8) {
            IconBadge(systemName: icon, tint: tint, size: 24)
            Text(title).font(.subheadline).foregroundStyle(MV.ink)
            Spacer()
            Text(value).font(MV.number(15)).foregroundStyle(MV.ink)
        }
    }

    private var annotationCard: some View {
        VStack(alignment: .leading, spacing: MV.s12) {
            SectionHeader(title: "Markers", subtitle: "Note what's happening in the clip")
            VStack(spacing: MV.s8) {
                markerButton("Add sample reading…", "stethoscope", MV.warn) { showCuffSheet = true }
                markerButton("Add marker", "mappin", MV.navy) { model.addMarker(.marker) }
                markerButton("Movement started", "figure.walk.motion", MV.pink) { model.addMarker(.motionStart) }
                markerButton("Movement stopped", "figure.stand", MV.pink) { model.addMarker(.motionStop) }
                markerButton("Note bumpy patch", "waveform.path", MV.bioz) { model.addMarker(.artifact) }
            }
            .mvCard()
        }
    }

    private func markerButton(_ title: String, _ icon: String, _ tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MV.s12) {
                IconBadge(systemName: icon, tint: tint, size: 28)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(MV.ink)
                Spacer()
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold)).foregroundStyle(MV.inkMuted)
            }
            .padding(.vertical, MV.s8)
            .padding(.horizontal, MV.s4)
        }
        .buttonStyle(PressableRowStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Profile picker / creator

struct SubjectPickerSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var newCode = ""
    @State private var ageBand = "18-25"
    @State private var notes = ""

    private let ageBands = ["<18", "18-25", "26-35", "36-45", "46-55", "56-65", "65+"]

    var body: some View {
        NavigationStack {
            List {
                Section("Your Profiles") {
                    if model.subjects.isEmpty {
                        Text("No profiles yet. Add one below to start saving clips.")
                            .foregroundStyle(MV.inkMuted)
                    }
                    ForEach(model.subjects) { s in
                        Button {
                            model.selectSubject(s.code)
                            dismiss()
                        } label: {
                            HStack(spacing: MV.s12) {
                                IconBadge(systemName: "person.crop.circle", tint: MV.navy, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.code).font(.subheadline.weight(.semibold)).foregroundStyle(MV.ink)
                                    Text(s.ageBand).font(.caption).foregroundStyle(MV.inkMuted)
                                }
                                Spacer()
                                if model.currentSubjectCode == s.code {
                                    Image(systemName: "checkmark").foregroundStyle(MV.accent)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(MV.surface)

                Section("New Profile (no personal details)") {
                    TextField("Nickname, e.g. S01", text: $newCode)
                        .textInputAutocapitalization(.characters)
                    Picker("Age band", selection: $ageBand) {
                        ForEach(ageBands, id: \.self) { Text($0) }
                    }
                    TextField("Notes (optional)", text: $notes)
                    Button("Add profile") {
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
                .listRowBackground(MV.surface)
            }
            .scrollContentBackground(.hidden)
            .background(MV.bg)
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { model.refreshSubjects() }
    }
}

// MARK: - Sample reading capture

struct CuffReadingSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var sbp = "120"
    @State private var dbp = "80"

    var body: some View {
        NavigationStack {
            List {
                Section("Sample Reading") {
                    TextField("Systolic (SBP)", text: $sbp)
                        .keyboardType(.numberPad)
                    TextField("Diastolic (DBP)", text: $dbp)
                        .keyboardType(.numberPad)
                }
                .listRowBackground(MV.surface)

                Section {
                    Text("Saved with the current pulse timing so the demo can learn how a blood-pressure estimate might be fitted.")
                        .font(.caption).foregroundStyle(MV.inkMuted)
                }
                .listRowBackground(MV.surface)
            }
            .scrollContentBackground(.hidden)
            .background(MV.bg)
            .navigationTitle("Sample Reading")
            .navigationBarTitleDisplayMode(.inline)
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
