//
//  AppModel.swift
//  VitalView
//
//  Central application store (ObservableObject). Orchestrates the data source, the live
//  runtime (waveform ring buffers + MetricsEngine), recording, calibration, and settings.
//
//  High-rate sample data lives in the non-reactive `buffers`/`engine` (read directly by
//  the Canvas); only throttled metrics, counts, and connection state are @Published here.
//
//  Mirrors web/src/store/appStore.ts.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    // MARK: - Non-reactive runtime (mutated at full sample rate)
    let buffers = WaveBuffers()
    let engine = MetricsEngine()

    // MARK: - Settings
    @Published private(set) var settings: AppSettings

    // MARK: - Connection / source
    @Published private(set) var isMock = false
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var deviceName: String?
    @Published private(set) var batteryPct: Int?
    @Published private(set) var errorFlags: UInt8 = 0
    @Published private(set) var dropped: [StreamKind: Int] = [.ecg: 0, .bioz: 0, .ppg: 0]
    @Published private(set) var clockOffsetUs: Double?
    @Published private(set) var streaming = false

    // MARK: - Metrics
    @Published private(set) var appMetrics: MetricsSnapshot?
    @Published private(set) var firmwareMetrics: MetricsPacket?
    @Published private(set) var liveMetrics: MetricsSnapshot?

    // MARK: - Subjects / calibration
    @Published private(set) var subjects: [Subject] = []
    @Published private(set) var currentSubjectCode: String?
    @Published private(set) var currentCalibration: Calibration?
    @Published private(set) var calibrationPairs: [RefPair] = []

    // MARK: - Recording
    @Published private(set) var recording: Session?
    @Published private(set) var recordCounts: [StreamKind: Int] = [.ecg: 0, .bioz: 0, .ppg: 0]
    @Published private(set) var recordDurationMs: Double = 0
    @Published private(set) var cuffReadingCount = 0

    // MARK: - private
    private var source: DataSource?
    private var recorder: Recorder?
    private var recordingStartedAt: Date?
    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?
    private let store = Store.shared
    private let settingsKey = "vitalview.settings"

    private static let tickInterval = 0.25

    init() {
        settings = AppModel.loadSettings(key: "vitalview.settings")
        engine.setMotionThresh(settings.motionThresh)
        subjects = store.listSubjects()
    }

    // MARK: - Settings

    private static func loadSettings(key: String) -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return s
        }
        return AppSettings()
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var s = settings
        mutate(&s)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
        engine.setMotionThresh(s.motionThresh)
        // Push rate changes to a connected device.
        if let src = source {
            for (stream, hz) in s.streamRates where settings.streamRates[stream] != hz {
                src.setRate(stream, hz: hz)
            }
        }
        settings = s
    }

    /// First-run consent / disclaimer gate.
    var needsOnboarding: Bool {
        !(settings.consentAccepted && settings.disclaimerAcknowledged)
    }

    func acceptOnboarding() {
        updateSettings {
            $0.consentAccepted = true
            $0.disclaimerAcknowledged = true
        }
    }

    // MARK: - Connecting

    func connectMock() {
        teardownSource()
        let src = MockSource()
        engine.setMotionThresh(settings.motionThresh)
        source = src
        isMock = true
        deviceName = src.deviceName
        wire(src)
        src.connect()
        src.syncClock()
        // clockOffset becomes available shortly; reflect it on the next connection event.
    }

    func connectBle() {
        teardownSource()
        let src = BleSource()
        source = src
        isMock = false
        wire(src)
        src.connect()
    }

    func disconnect() {
        stopRecording()
        teardownSource()
        source = nil
        streaming = false
        connectionState = .disconnected
        firmwareMetrics = nil
    }

    // MARK: - Streaming

    func startStreaming() {
        guard let src = source else { return }
        resetRuntime()
        engine.setMotionThresh(settings.motionThresh)
        engine.setCalibration(currentCalibration)
        dropped = [.ecg: 0, .bioz: 0, .ppg: 0]
        src.start(streamMask: BLEProtocol.allStreamsMask)
        startTick()
        streaming = true
    }

    func stopStreaming() {
        source?.stop()
        stopTick()
        streaming = false
    }

    func setMockParams(_ mutate: @escaping (inout MockParams) -> Void) {
        (source as? MockSource)?.setParams(mutate)
        objectWillChange.send() // reflect mock-param changes in the Settings UI
    }

    func injectMockMotion() {
        (source as? MockSource)?.injectMotion()
    }

    /// Current mock parameters (defaults when no mock source is active), for Settings.
    private var mockParams: MockParams { (source as? MockSource)?.getParams() ?? .default }
    var mockHrBpm: Double { mockParams.hrBpm }
    var mockPatMs: Double { mockParams.patMs }
    var mockSpo2: Double { mockParams.spo2Target }

    // MARK: - Subjects

    func refreshSubjects() {
        subjects = store.listSubjects()
    }

    func saveSubject(_ s: Subject) {
        store.upsertSubject(s)
        refreshSubjects()
    }

    func selectSubject(_ code: String?) {
        let cal = code.flatMap { store.latestCalibration($0) }
        engine.setCalibration(cal)
        currentSubjectCode = code
        currentCalibration = cal
        calibrationPairs = []
    }

    // MARK: - Recording

    func startRecording(label: SessionLabel, notes: String) {
        guard let src = source, let subjectCode = currentSubjectCode else { return }
        if !streaming { startStreaming() }
        let session = Session(
            id: UUID().uuidString,
            subjectCode: subjectCode,
            label: label,
            deviceId: src.deviceName ?? "unknown",
            firmwareVersion: isMock ? "1.0.0-mock" : "unknown",
            startedAt: ISO8601DateFormatter().string(from: Date()),
            endedAt: nil,
            notes: notes,
            metricsSource: settings.metricsSource,
            gating: GatingConfig(motionThresh: settings.motionThresh,
                                 contactThresh: settings.contactThresh,
                                 windowMs: settings.gatingWindowMs),
            calibrationSnapshot: currentCalibration
        )
        store.createSession(session)
        recorder = Recorder(sessionId: session.id)
        recording = session
        recordingStartedAt = Date()
        recordCounts = [.ecg: 0, .bioz: 0, .ppg: 0]
        recordDurationMs = 0
        cuffReadingCount = 0
    }

    func stopRecording() {
        guard let session = recording, let rec = recorder else { return }
        rec.flushAll()
        store.endSession(session.id, endedAt: ISO8601DateFormatter().string(from: Date()))
        recorder = nil
        recording = nil
        recordingStartedAt = nil
    }

    func addCuffReading(sbp: Double, dbp: Double) {
        let tUs = buffers.latestDeviceUs()
        if let session = recording {
            store.addAnnotation(Annotation(id: nil, sessionId: session.id, tUs: tUs,
                                           type: .cuffReading, sbp: sbp, dbp: dbp, text: nil))
            cuffReadingCount += 1
        }
        // Capture a calibration pair if a PAT is currently available.
        if let pat = liveMetrics?.patUs {
            calibrationPairs.append(RefPair(patUs: pat, sbp: sbp, dbp: dbp))
        }
    }

    func addMarker(_ type: AnnotationType, text: String? = nil) {
        guard let session = recording else { return }
        store.addAnnotation(Annotation(id: nil, sessionId: session.id,
                                       tUs: buffers.latestDeviceUs(), type: type,
                                       sbp: nil, dbp: nil, text: text))
    }

    /// Export a session bundle to a temp folder; returns its URL for sharing.
    func exportSession(_ sessionId: String) -> URL? {
        try? CSVExport.exportSession(sessionId, store: store)
    }

    // MARK: - Calibration

    @discardableResult
    func addCalibrationPair(sbp: Double, dbp: Double) -> Bool {
        guard let pat = liveMetrics?.patUs else { return false }
        calibrationPairs.append(RefPair(patUs: pat, sbp: sbp, dbp: dbp))
        return true
    }

    func removeCalibrationPair(at index: Int) {
        guard calibrationPairs.indices.contains(index) else { return }
        calibrationPairs.remove(at: index)
    }

    func clearCalibrationPairs() {
        calibrationPairs = []
    }

    /// Current best-effort fit of the collected pairs (for live R/RMSE display).
    var currentFit: CalibrationFit? {
        fitCalibration(calibrationPairs, settings.calibModel)
    }

    @discardableResult
    func saveCalibrationFit() -> Bool {
        guard let subjectCode = currentSubjectCode,
              let fit = fitCalibration(calibrationPairs, settings.calibModel) else { return false }
        let cal = Calibration(
            id: nil,
            subjectCode: subjectCode,
            model: fit.model,
            coeffs: fit.coeffs,
            referencePairs: calibrationPairs,
            rmseSbp: fit.rmseSbp,
            rmseDbp: fit.rmseDbp,
            r: fit.r,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        store.saveCalibration(cal)
        engine.setCalibration(cal)
        currentCalibration = cal
        return true
    }

    // MARK: - Data management

    func deleteSession(_ id: String) {
        store.deleteSession(id)
    }

    func deleteAllData() {
        store.deleteAllData()
        subjects = []
        currentSubjectCode = nil
        currentCalibration = nil
        calibrationPairs = []
    }

    // MARK: - wiring

    private func wire(_ src: DataSource) {
        let ev = src.events

        ev.ecg
            .receive(on: DispatchQueue.main)
            .sink { [weak self] p in
                guard let self else { return }
                let dt = DSPConstants.usPerS / Double(p.sampleRateHz)
                for i in 0..<p.samples.count {
                    self.buffers.ecg.push(p.tUs + (Double(i) * dt).rounded(), Double(p.samples[i]))
                }
                self.engine.ingestEcg(p)
                self.recorder?.ingestEcg(p)
            }
            .store(in: &cancellables)

        ev.bioz
            .receive(on: DispatchQueue.main)
            .sink { [weak self] p in
                guard let self else { return }
                let dt = DSPConstants.usPerS / Double(p.sampleRateHz)
                for i in 0..<p.dz.count {
                    self.buffers.biozDz.push(p.tUs + (Double(i) * dt).rounded(), Double(p.dz[i]))
                }
                self.buffers.z0.push(p.tUs, Double(p.z0Milliohm))
                self.engine.ingestBioz(p)
                self.recorder?.ingestBioz(p)
            }
            .store(in: &cancellables)

        ev.ppg
            .receive(on: DispatchQueue.main)
            .sink { [weak self] p in
                guard let self else { return }
                let dt = DSPConstants.usPerS / Double(p.sampleRateHz)
                for i in 0..<p.green.count {
                    let t = p.tUs + (Double(i) * dt).rounded()
                    self.buffers.ppgGreen.push(t, Double(p.green[i]))
                    self.buffers.ppgRed.push(t, Double(p.red[i]))
                    self.buffers.ppgIr.push(t, Double(p.ir[i]))
                }
                self.engine.ingestPpg(p)
                self.recorder?.ingestPpg(p)
            }
            .store(in: &cancellables)

        ev.metrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] p in self?.firmwareMetrics = p }
            .store(in: &cancellables)

        ev.battery
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pct in self?.batteryPct = pct }
            .store(in: &cancellables)

        ev.status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s in
                guard let self else { return }
                self.errorFlags = s.errorFlags
                self.batteryPct = s.batteryPct
                // Keep the clock-sync indicator fresh once SYNC_CLOCK has completed.
                self.clockOffsetUs = self.source?.clockOffsetUs
            }
            .store(in: &cancellables)

        ev.dropped
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stream, count in
                guard let self, count > 0 else { return }
                self.dropped[stream, default: 0] += count
            }
            .store(in: &cancellables)

        ev.connection
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, _ in
                guard let self else { return }
                self.connectionState = state
                self.clockOffsetUs = self.source?.clockOffsetUs
                self.deviceName = self.source?.deviceName
            }
            .store(in: &cancellables)
    }

    private func teardownSource() {
        stopTick()
        cancellables.removeAll()
        source?.disconnect()
    }

    private func resetRuntime() {
        buffers.clear()
        engine.reset()
    }

    private func startTick() {
        stopTick()
        let timer = Timer(timeInterval: AppModel.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        let latest = buffers.latestDeviceUs()
        let app = engine.snapshot(latest)
        let live = AppModel.resolveLive(app: app, firmware: firmwareMetrics,
                                        settings: settings, calibration: currentCalibration)
        appMetrics = app
        liveMetrics = live
        if let rec = recorder, let start = recordingStartedAt {
            recordCounts = rec.counts
            recordDurationMs = Date().timeIntervalSince(start) * 1000
            store.addMetrics(MetricsRecord(
                id: nil, sessionId: rec.sessionId, tUs: live.tUs,
                hrBpm: live.hrBpm, spo2Pct: live.spo2Pct,
                contactQuality: live.contactQuality, motion: live.motion,
                patUs: live.patUs, sbpMmHg: live.sbpMmHg, dbpMmHg: live.dbpMmHg
            ))
        }
    }

    /// Resolve the metrics to display: pick the source per settings, overlay calibrated BP.
    static func resolveLive(app: MetricsSnapshot, firmware: MetricsPacket?,
                            settings: AppSettings, calibration: Calibration?) -> MetricsSnapshot {
        var base: MetricsSnapshot
        if settings.metricsSource == .firmware, let f = firmware {
            base = MetricsSnapshot(tUs: f.tUs, hrBpm: f.hrBpm, spo2Pct: f.spo2Pct,
                                   contactQuality: f.contactQuality, motion: f.motion,
                                   patUs: f.patUs, sbpMmHg: f.sbpMmHg, dbpMmHg: f.dbpMmHg,
                                   rpeak: f.rpeak)
        } else {
            base = app
        }
        if let cal = calibration, let pat = base.patUs {
            let x = cal.model == .linearPAT ? pat / 1e6 : 1 / (pat / 1e6)
            base.sbpMmHg = (cal.coeffs.sbp[0] + cal.coeffs.sbp[1] * x).rounded()
            base.dbpMmHg = (cal.coeffs.dbp[0] + cal.coeffs.dbp[1] * x).rounded()
        }
        return base
    }
}
