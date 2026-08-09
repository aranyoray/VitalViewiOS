//
//  Store.swift
//  MoniVitals
//
//  Dependency-free, local-first persistence (no cloud sync). Mirrors the responsibilities
//  of the web Dexie database (web/src/model/db.ts + repository.ts) but stores data as
//  JSON files under Application Support:
//
//      <AppSupport>/MoniVitals/
//        subjects.json          [Subject]
//        sessions.json          [Session]
//        calibrations.json      [Calibration]
//        annotations.json       [Annotation]
//        chunks/<sessionId>.json     [StreamChunk]   (high-rate sample blocks)
//        metrics/<sessionId>.json    [MetricsRecord]
//
//  Per-session sample data lives in its own file so listing/deleting sessions never
//  loads every waveform. All access is serialized on a private queue.
//

import Foundation

/// Concatenated, contiguous streams for a session (replay / export).
struct SessionStreams {
    struct Ecg { var t: [Double]; var ecg: [Int32] }
    struct Bioz { var t: [Double]; var z0: [Int32]; var dz: [Int32] }
    struct Ppg { var t: [Double]; var green: [UInt32]; var red: [UInt32]; var ir: [UInt32] }
    var ecg = Ecg(t: [], ecg: [])
    var bioz = Bioz(t: [], z0: [], dz: [])
    var ppg = Ppg(t: [], green: [], red: [], ir: [])
}

/// The local data store. A single shared instance is used by the app.
final class Store {
    static let shared = Store()

    private let queue = DispatchQueue(label: "com.monivitals.store")
    private let fm = FileManager.default
    private let root: URL
    private let chunksDir: URL
    private let metricsDir: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    private init() {
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        root = base.appendingPathComponent("MoniVitals", isDirectory: true)
        chunksDir = root.appendingPathComponent("chunks", isDirectory: true)
        metricsDir = root.appendingPathComponent("metrics", isDirectory: true)
        encoder = JSONEncoder()
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        try? fm.createDirectory(at: chunksDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: metricsDir, withIntermediateDirectories: true)
    }

    // MARK: - file helpers

    private func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    private func load<T: Decodable>(_ url: URL, default def: T) -> T {
        guard let data = try? Data(contentsOf: url) else { return def }
        return (try? decoder.decode(T.self, from: data)) ?? def
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        if let data = try? encoder.encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func nextId(_ items: [Int?]) -> Int {
        (items.compactMap { $0 }.max() ?? 0) + 1
    }

    // MARK: - Subjects

    func upsertSubject(_ s: Subject) {
        queue.sync {
            var all: [Subject] = load(url("subjects.json"), default: [])
            all.removeAll { $0.code == s.code }
            all.append(s)
            save(all, to: url("subjects.json"))
        }
    }

    /// Subjects, newest first (by createdAt) — matches the web `listSubjects`.
    func listSubjects() -> [Subject] {
        queue.sync {
            let all: [Subject] = load(url("subjects.json"), default: [])
            return all.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func getSubject(_ code: String) -> Subject? {
        queue.sync {
            let all: [Subject] = load(url("subjects.json"), default: [])
            return all.first { $0.code == code }
        }
    }

    func deleteSubject(_ code: String) {
        // Delete the subject's sessions + calibrations, then the subject.
        let sessions = listSessions().filter { $0.subjectCode == code }
        for s in sessions { deleteSession(s.id) }
        queue.sync {
            var cals: [Calibration] = load(url("calibrations.json"), default: [])
            cals.removeAll { $0.subjectCode == code }
            save(cals, to: url("calibrations.json"))
            var subs: [Subject] = load(url("subjects.json"), default: [])
            subs.removeAll { $0.code == code }
            save(subs, to: url("subjects.json"))
        }
    }

    // MARK: - Sessions

    func createSession(_ s: Session) {
        queue.sync {
            var all: [Session] = load(url("sessions.json"), default: [])
            all.removeAll { $0.id == s.id }
            all.append(s)
            save(all, to: url("sessions.json"))
        }
    }

    func endSession(_ id: String, endedAt: String) {
        queue.sync {
            var all: [Session] = load(url("sessions.json"), default: [])
            if let idx = all.firstIndex(where: { $0.id == id }) {
                all[idx].endedAt = endedAt
                save(all, to: url("sessions.json"))
            }
        }
    }

    func getSession(_ id: String) -> Session? {
        queue.sync {
            let all: [Session] = load(url("sessions.json"), default: [])
            return all.first { $0.id == id }
        }
    }

    /// Sessions, newest first (by startedAt).
    func listSessions() -> [Session] {
        queue.sync {
            let all: [Session] = load(url("sessions.json"), default: [])
            return all.sorted { $0.startedAt > $1.startedAt }
        }
    }

    func deleteSession(_ id: String) {
        queue.sync {
            var sessions: [Session] = load(url("sessions.json"), default: [])
            sessions.removeAll { $0.id == id }
            save(sessions, to: url("sessions.json"))
            var annos: [Annotation] = load(url("annotations.json"), default: [])
            annos.removeAll { $0.sessionId == id }
            save(annos, to: url("annotations.json"))
            try? fm.removeItem(at: chunksDir.appendingPathComponent("\(id).json"))
            try? fm.removeItem(at: metricsDir.appendingPathComponent("\(id).json"))
        }
    }

    // MARK: - Annotations

    @discardableResult
    func addAnnotation(_ a: Annotation) -> Int {
        queue.sync {
            var all: [Annotation] = load(url("annotations.json"), default: [])
            var item = a
            item.id = nextId(all.map { $0.id })
            all.append(item)
            save(all, to: url("annotations.json"))
            return item.id!
        }
    }

    func listAnnotations(_ sessionId: String) -> [Annotation] {
        queue.sync {
            let all: [Annotation] = load(url("annotations.json"), default: [])
            return all.filter { $0.sessionId == sessionId }.sorted { $0.tUs < $1.tUs }
        }
    }

    // MARK: - Calibrations

    @discardableResult
    func saveCalibration(_ c: Calibration) -> Int {
        queue.sync {
            var all: [Calibration] = load(url("calibrations.json"), default: [])
            var item = c
            item.id = nextId(all.map { $0.id })
            all.append(item)
            save(all, to: url("calibrations.json"))
            return item.id!
        }
    }

    func latestCalibration(_ subjectCode: String) -> Calibration? {
        listCalibrations(subjectCode).last
    }

    func listCalibrations(_ subjectCode: String) -> [Calibration] {
        queue.sync {
            let all: [Calibration] = load(url("calibrations.json"), default: [])
            return all.filter { $0.subjectCode == subjectCode }.sorted { $0.createdAt < $1.createdAt }
        }
    }

    // MARK: - Metrics

    func addMetrics(_ m: MetricsRecord) {
        queue.sync {
            let file = metricsDir.appendingPathComponent("\(m.sessionId).json")
            var all: [MetricsRecord] = load(file, default: [])
            var item = m
            item.id = nextId(all.map { $0.id })
            all.append(item)
            save(all, to: file)
        }
    }

    func listMetrics(_ sessionId: String) -> [MetricsRecord] {
        queue.sync {
            let file = metricsDir.appendingPathComponent("\(sessionId).json")
            let all: [MetricsRecord] = load(file, default: [])
            return all.sorted { $0.tUs < $1.tUs }
        }
    }

    // MARK: - Stream chunks

    func addChunk(_ chunk: StreamChunk) {
        queue.sync {
            let file = chunksDir.appendingPathComponent("\(chunk.sessionId).json")
            var all: [StreamChunk] = load(file, default: [])
            var item = chunk
            item.id = nextId(all.map { $0.id })
            all.append(item)
            save(all, to: file)
        }
    }

    private func chunks(_ sessionId: String) -> [StreamChunk] {
        let file = chunksDir.appendingPathComponent("\(sessionId).json")
        let all: [StreamChunk] = load(file, default: [])
        return all.sorted { $0.tStartUs < $1.tStartUs }
    }

    /// Concatenate stored chunks back into contiguous per-stream arrays.
    func readSessionStreams(_ sessionId: String) -> SessionStreams {
        queue.sync {
            let all = chunks(sessionId)
            var out = SessionStreams()
            for c in all where c.stream == .ecg {
                out.ecg.t += c.t
                out.ecg.ecg += c.ecg ?? []
            }
            for c in all where c.stream == .bioz {
                out.bioz.t += c.t
                out.bioz.z0 += c.z0 ?? []
                out.bioz.dz += c.dz ?? []
            }
            for c in all where c.stream == .ppg {
                out.ppg.t += c.t
                out.ppg.green += c.green ?? []
                out.ppg.red += c.red ?? []
                out.ppg.ir += c.ir ?? []
            }
            return out
        }
    }

    /// Wipe every stored table (Settings → data management).
    func deleteAllData() {
        queue.sync {
            for name in ["subjects.json", "sessions.json", "calibrations.json", "annotations.json"] {
                try? fm.removeItem(at: url(name))
            }
            try? fm.removeItem(at: chunksDir)
            try? fm.removeItem(at: metricsDir)
            try? fm.createDirectory(at: chunksDir, withIntermediateDirectories: true)
            try? fm.createDirectory(at: metricsDir, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Recorder

/// Buffers live samples and flushes them to the store in ~2 s chunks. One instance per
/// active recording session. Robust to mid-stream disconnects (flush on stop).
/// Mirrors the web `Recorder` (web/src/model/repository.ts).
final class Recorder {
    let sessionId: String
    private(set) var counts: [StreamKind: Int] = [.ecg: 0, .bioz: 0, .ppg: 0]

    private final class BufferState {
        var tStartUs: Double? = nil
        var rate = 0
        var t: [Double] = []
        var a: [Double] = [] // ecg samples | z0 | green
        var b: [Double] = [] // dz | red
        var c: [Double] = [] // ir
    }

    private var buffers: [StreamKind: BufferState] = [
        .ecg: BufferState(), .bioz: BufferState(), .ppg: BufferState(),
    ]
    private let flushSamples: [StreamKind: Int] = [.ecg: 512, .bioz: 128, .ppg: 800]
    private let store: Store

    init(sessionId: String, store: Store = .shared) {
        self.sessionId = sessionId
        self.store = store
    }

    func ingestEcg(_ p: EcgPacket) {
        let buf = buffers[.ecg]!
        if buf.tStartUs == nil { buf.tStartUs = p.tUs }
        buf.rate = p.sampleRateHz
        let dt = DSPConstants.usPerS / Double(p.sampleRateHz)
        for i in 0..<p.samples.count {
            buf.t.append(p.tUs + (Double(i) * dt).rounded())
            buf.a.append(Double(p.samples[i]))
        }
        counts[.ecg, default: 0] += p.samples.count
        if buf.a.count >= flushSamples[.ecg]! { flush(.ecg) }
    }

    func ingestBioz(_ p: BiozPacket) {
        let buf = buffers[.bioz]!
        if buf.tStartUs == nil { buf.tStartUs = p.tUs }
        buf.rate = p.sampleRateHz
        let dt = DSPConstants.usPerS / Double(p.sampleRateHz)
        for i in 0..<p.dz.count {
            buf.t.append(p.tUs + (Double(i) * dt).rounded())
            buf.a.append(Double(p.z0Milliohm)) // forward-filled z0
            buf.b.append(Double(p.dz[i]))
        }
        counts[.bioz, default: 0] += p.dz.count
        if buf.a.count >= flushSamples[.bioz]! { flush(.bioz) }
    }

    func ingestPpg(_ p: PpgPacket) {
        let buf = buffers[.ppg]!
        if buf.tStartUs == nil { buf.tStartUs = p.tUs }
        buf.rate = p.sampleRateHz
        let dt = DSPConstants.usPerS / Double(p.sampleRateHz)
        for i in 0..<p.green.count {
            buf.t.append(p.tUs + (Double(i) * dt).rounded())
            buf.a.append(Double(p.green[i]))
            buf.b.append(Double(p.red[i]))
            buf.c.append(Double(p.ir[i]))
        }
        counts[.ppg, default: 0] += p.green.count
        if buf.a.count >= flushSamples[.ppg]! { flush(.ppg) }
    }

    /// Persist buffered samples for one stream as a StreamChunk.
    func flush(_ stream: StreamKind) {
        let buf = buffers[stream]!
        guard !buf.a.isEmpty, let tStart = buf.tStartUs else { return }
        var chunk = StreamChunk(id: nil, sessionId: sessionId, stream: stream,
                                tStartUs: tStart, sampleRateHz: buf.rate, t: buf.t)
        switch stream {
        case .ecg:
            chunk.ecg = buf.a.map { Int32($0) }
        case .bioz:
            chunk.z0 = buf.a.map { Int32($0) }
            chunk.dz = buf.b.map { Int32($0) }
        case .ppg:
            chunk.green = buf.a.map { UInt32($0) }
            chunk.red = buf.b.map { UInt32($0) }
            chunk.ir = buf.c.map { UInt32($0) }
        }
        buffers[stream] = BufferState()
        store.addChunk(chunk)
    }

    func flushAll() {
        for s in StreamKind.allCases { flush(s) }
    }
}
