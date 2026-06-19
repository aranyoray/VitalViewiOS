//
//  ReviewView.swift
//  VitalView
//
//  List recorded sessions, plot their stored waveforms with Swift Charts (static data,
//  so Charts is appropriate here), and export each as a CSV bundle via a share sheet.
//

import Charts
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sessions: [Session] = []

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text("No recorded sessions yet.").foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    NavigationLink(value: session.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(session.subjectCode) · \(session.label.rawValue)").font(.headline)
                            Text(session.startedAt).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { model.deleteSession(sessions[i].id) }
                    reload()
                }
            }
            .navigationTitle("Review")
            .navigationDestination(for: String.self) { id in
                SessionDetailView(sessionId: id)
            }
            .onAppear(perform: reload)
            .refreshable { reload() }
        }
    }

    private func reload() {
        sessions = Store.shared.listSessions()
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    @EnvironmentObject private var model: AppModel
    let sessionId: String

    @State private var streams = SessionStreams()
    @State private var session: Session?
    @State private var exportURL: URL?
    @State private var showShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let s = session {
                    metaCard(s)
                }
                chart(title: "ECG", count: min(streams.ecg.ecg.count, 4000),
                      values: streams.ecg.ecg.prefix(4000).map(Double.init), color: .green)
                chart(title: "PPG green", count: min(streams.ppg.green.count, 4000),
                      values: streams.ppg.green.prefix(4000).map(Double.init), color: .pink)
                chart(title: "BioZ ΔZ", count: min(streams.bioz.dz.count, 4000),
                      values: streams.bioz.dz.prefix(4000).map(Double.init), color: .cyan)
            }
            .padding()
        }
        .navigationTitle("Session")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportURL = model.exportSession(sessionId)
                    showShare = exportURL != nil
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ActivityView(items: [url])
            }
        }
        .onAppear {
            session = Store.shared.getSession(sessionId)
            streams = Store.shared.readSessionStreams(sessionId)
        }
    }

    private func metaCard(_ s: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(s.subjectCode) · \(s.label.rawValue)").font(.headline)
            Text("Started \(s.startedAt)").font(.caption).foregroundStyle(.secondary)
            if let ended = s.endedAt {
                Text("Ended \(ended)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Metrics source: \(s.metricsSource.rawValue)").font(.caption).foregroundStyle(.secondary)
            Text("ECG \(streams.ecg.ecg.count) · PPG \(streams.ppg.green.count) · BioZ \(streams.bioz.dz.count) samples")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    @ViewBuilder
    private func chart(title: String, count: Int, values: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if values.count > 1 {
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("i", i), y: .value("v", v))
                            .foregroundStyle(color)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 140)
            } else {
                Text("No data").font(.caption).foregroundStyle(.secondary)
            }
            if count < values.count {
                Text("Showing first \(count) samples.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
