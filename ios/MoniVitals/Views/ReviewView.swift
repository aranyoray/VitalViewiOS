//
//  ReviewView.swift
//  MoniVitals
//
//  List saved clips, plot their stored waveforms with Swift Charts (static data,
//  so Charts is appropriate here), and share each as a CSV bundle via a share sheet.
//

import Charts
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sessions: [Session] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MV.s20) {
                    if sessions.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: MV.s12) {
                            SectionHeader(title: "Saved clips",
                                          subtitle: "\(sessions.count) saved on this phone")
                            VStack(spacing: MV.s12) {
                                ForEach(sessions) { session in
                                    sessionRow(session)
                                }
                            }
                        }
                    }
                }
                .padding(MV.s16)
            }
            .background(MV.bg)
            .navigationTitle("Saved Clips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Saved Clips").font(.headline).foregroundStyle(MV.navy)
                }
            }
            .navigationDestination(for: String.self) { id in
                SessionDetailView(sessionId: id)
            }
            .onAppear(perform: reload)
            .refreshable { reload() }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        NavigationLink(value: session.id) {
            HStack(spacing: MV.s12) {
                IconBadge(systemName: "waveform.path.ecg", tint: MV.navy, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.subjectCode) · \(session.label.rawValue)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(MV.ink)
                    Text(session.startedAt).font(.caption).foregroundStyle(MV.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(MV.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .mvCard(padding: MV.s12)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                model.deleteSession(session.id)
                reload()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: MV.s12) {
            IconBadge(systemName: "tray", tint: MV.navy, size: 56)
            Text("No saved clips yet")
                .font(.headline).foregroundStyle(MV.ink)
            Text("Tap Save a Clip on the Save tab to keep one.")
                .font(.subheadline).foregroundStyle(MV.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MV.s32)
        .mvCard()
        .padding(.top, MV.s24)
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
            VStack(alignment: .leading, spacing: MV.s20) {
                if let s = session {
                    metaCard(s)
                }

                VStack(alignment: .leading, spacing: MV.s12) {
                    SectionHeader(title: "Waveforms", subtitle: "Stored samples from this clip")
                    chart(title: "ECG", color: MV.ecg,
                          count: min(streams.ecg.ecg.count, 4000),
                          values: streams.ecg.ecg.prefix(4000).map(Double.init))
                    chart(title: "PPG Green", color: MV.ppg,
                          count: min(streams.ppg.green.count, 4000),
                          values: streams.ppg.green.prefix(4000).map(Double.init))
                    chart(title: "BioZ ΔZ", color: MV.bioz,
                          count: min(streams.bioz.dz.count, 4000),
                          values: streams.bioz.dz.prefix(4000).map(Double.init))
                }
            }
            .padding(MV.s16)
        }
        .background(MV.bg)
        .navigationTitle("Clip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Clip").font(.headline).foregroundStyle(MV.navy)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportURL = model.exportSession(sessionId)
                    showShare = exportURL != nil
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share clip as CSV")
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
        HStack(alignment: .top, spacing: MV.s12) {
            IconBadge(systemName: "doc.text", tint: MV.navy, size: 34)
            VStack(alignment: .leading, spacing: MV.s4) {
                Text("\(s.subjectCode) · \(s.label.rawValue)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(MV.ink)
                Text("Started \(s.startedAt)").font(.caption).foregroundStyle(MV.inkMuted)
                if let ended = s.endedAt {
                    Text("Ended \(ended)").font(.caption).foregroundStyle(MV.inkMuted)
                }
                Text("Metrics from: \(s.metricsSource == .app ? "App" : "Recording")")
                    .font(.caption).foregroundStyle(MV.inkMuted)
                Text("ECG \(streams.ecg.ecg.count) · PPG \(streams.ppg.green.count) · BioZ \(streams.bioz.dz.count) samples")
                    .font(.caption).foregroundStyle(MV.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mvCard()
    }

    @ViewBuilder
    private func chart(title: String, color: Color, count: Int, values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: MV.s8) {
            ChipLabel(text: title, color: color)
            if values.count > 1 {
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("i", i), y: .value("v", v))
                            .foregroundStyle(color)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(MV.separator)
                        AxisTick().foregroundStyle(MV.separator)
                        AxisValueLabel().foregroundStyle(MV.inkMuted)
                    }
                }
                .frame(height: 140)
            } else {
                Text("Nothing here just yet.").font(.caption).foregroundStyle(MV.inkMuted)
            }
            if count < values.count {
                Text("Showing first \(count) samples.").font(.caption2).foregroundStyle(MV.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mvCard()
    }
}
