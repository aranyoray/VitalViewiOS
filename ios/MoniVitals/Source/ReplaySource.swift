//
//  ReplaySource.swift
//  MoniVitals
//
//  Replays a REAL recorded biosignal (PhysioNet BIDMC: ECG lead II + PPG) bundled with
//  the app, so the DSP computes heart rate and pulse-arrival-time from genuine waveforms
//  instead of a self-encoding synthetic signal. The recording loops seamlessly with
//  monotonically increasing device timestamps.
//
//  Notes on fidelity:
//   • ECG + PPG are the real recording.
//   • The dataset has single-wavelength PPG, so red/IR are synthesized from the real PPG
//     shape at the AC ratio implied by the recording's own SpO2 reading — the SpO2 tile
//     therefore reflects the RECORDED reference value, and is labeled as such.
//   • Bioimpedance has no open real counterpart, so a light synthetic ΔZ drives the
//     contact/movement indicators (clearly a simulated channel).
//
//  MoniVitals is a research / educational tool, NOT a medical device.
//

import Foundation

/// The bundled recording (see Resources/bidmc_sample.json, produced from PhysioNet BIDMC).
private struct Recording: Decodable {
    let source: String
    let fs: Int
    let refHR: Double
    let refSpO2: Double
    let spo2Ratio: Double
    let ppgMean: Double
    let ecg: [Double]
    let ppg: [Double]
}

final class ReplaySource: BaseDataSource {
    override var isMock: Bool { true }

    private var _deviceName: String?
    override var deviceName: String? { _deviceName }
    private var _clockOffsetUs: Double?
    override var clockOffsetUs: Double? { _clockOffsetUs }

    /// Recorded reference values (for display as ground-truth comparison).
    let referenceHR: Double
    let referenceSpO2: Double
    let recordingName: String
    /// Sample rate of the recording (all streams are replayed at this rate).
    let recordingFs: Int

    private let rec: Recording
    private let fs: Int
    private let n: Int
    private let ppgDc = 120_000.0
    private let ppgGain = 100_000.0

    private var emitted = 0            // total ECG/PPG samples emitted (monotonic)
    private var running = false
    private var startUptime: TimeInterval = 0
    private var seqEcg = 0, seqPpg = 0, seqBioz = 0
    private var batteryPct = 100.0
    private var tickTimer: DispatchSourceTimer?
    private var metricsTimer: DispatchSourceTimer?
    private var statusTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.monivitals.replaysource")

    private static let tickMs = 40.0
    private static let metricsMs = 500.0

    /// Loads the bundled recording. Returns nil (instead of crashing) if the asset is
    /// missing, unreadable, or empty, so the app can degrade gracefully on launch.
    static func make() -> ReplaySource? {
        guard let url = Bundle.main.url(forResource: "bidmc_sample", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Recording.self, from: raw),
              !decoded.ecg.isEmpty, decoded.fs > 0 else {
            return nil
        }
        return ReplaySource(recording: decoded)
    }

    private init(recording decoded: Recording) {
        rec = decoded
        fs = decoded.fs
        n = decoded.ecg.count
        referenceHR = decoded.refHR
        referenceSpO2 = decoded.refSpO2
        recordingName = decoded.source
        recordingFs = decoded.fs
        super.init()
        _deviceName = decoded.source
    }

    // MARK: - Lifecycle

    override func connect() {
        setState(.connecting)
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.setState(.connected)
            self.startUptime = ProcessInfo.processInfo.systemUptime
            self.emitInfo()
            self.statusTimer = self.makeTimer(intervalMs: 1000) { [weak self] in self?.emitStatus() }
        }
    }

    override func disconnect() {
        stop()
        statusTimer?.cancel(); statusTimer = nil
        setState(.disconnected)
    }

    override func start(streamMask: UInt8) {
        queue.async { [weak self] in
            guard let self else { return }
            self.emitted = 0
            self.seqEcg = 0; self.seqPpg = 0; self.seqBioz = 0
            self.startUptime = ProcessInfo.processInfo.systemUptime
            self.running = true
            self.tickTimer = self.makeTimer(intervalMs: Self.tickMs) { [weak self] in self?.tick() }
            self.metricsTimer = self.makeTimer(intervalMs: Self.metricsMs) { [weak self] in self?.emitMetrics() }
        }
    }

    override func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false
            self.tickTimer?.cancel(); self.metricsTimer?.cancel()
            self.tickTimer = nil; self.metricsTimer = nil
        }
    }

    override func syncClock() {
        queue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            self._clockOffsetUs = Date().timeIntervalSince1970 * 1_000_000 - self.deviceUs(self.emitted)
        }
    }

    override func getInfo() { queue.async { [weak self] in self?.emitInfo() } }

    // MARK: - Emission

    private func tick() {
        guard running else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
        let target = Int(elapsed * Double(fs))            // total samples that should exist by now
        guard target > emitted else { return }
        let count = target - emitted
        let firstTus = deviceUs(emitted)

        var ecg = [Int32](repeating: 0, count: count)
        var green = [UInt32](repeating: 0, count: count)
        var red = [UInt32](repeating: 0, count: count)
        var ir = [UInt32](repeating: 0, count: count)
        var dz = [Int32](repeating: 0, count: count)

        for i in 0..<count {
            let s = emitted + i
            let j = s % n                                  // loop the recording
            ecg[i] = Int32(rec.ecg[j].rounded())
            let ac = (rec.ppg[j] - rec.ppgMean) * ppgGain  // real PPG AC
            green[i] = UInt32(max(0, ppgDc + ac))
            ir[i]    = UInt32(max(0, ppgDc + ac))          // IR AC == green AC
            red[i]   = UInt32(max(0, ppgDc + ac * rec.spo2Ratio)) // red AC scaled → SpO2 ref
            // Light synthetic bioimpedance ΔZ (pulsatile at the recorded HR) + tiny noise.
            let tSec = Double(s) / Double(fs)
            dz[i] = Int32((400.0 * sin(2 * .pi * (rec.refHR / 60.0) * tSec)
                           + 40.0 * sin(tSec * 53.7)).rounded())
        }

        events.ecg.send(EcgPacket(seq: seqEcg, tUs: firstTus, sampleRateHz: fs, samples: ecg))
        events.ppg.send(PpgPacket(seq: seqPpg, tUs: firstTus, sampleRateHz: fs, green: green, red: red, ir: ir))
        events.bioz.send(BiozPacket(seq: seqBioz, tUs: firstTus, sampleRateHz: fs,
                                    z0Milliohm: 300_000, dz: dz))
        seqEcg = (seqEcg + 1) & 0xffff
        seqPpg = (seqPpg + 1) & 0xffff
        seqBioz = (seqBioz + 1) & 0xffff
        emitted = target
    }

    private func emitMetrics() {
        guard running else { return }
        // Firmware/reference metrics: the recording's own HR + SpO2 readings.
        events.metrics.send(MetricsPacket(
            tUs: deviceUs(emitted),
            hrBpm: rec.refHR,
            spo2Pct: rec.refSpO2,
            contactQuality: 100,
            motion: 0,
            patUs: nil,
            sbpMmHg: nil,
            dbpMmHg: nil,
            rpeak: false
        ))
    }

    private func emitInfo() {
        events.info.send(InfoMessage(firmwareVersion: "bidmc-replay",
                                     deviceId: "bidmc00000001",
                                     capabilities: 0x7))
        events.battery.send(Int(batteryPct))
    }

    private func emitStatus() {
        events.battery.send(Int(batteryPct))
        events.status.send(StatusMessage(streamingMask: running ? 0x7 : 0,
                                         ecgRateCode: 1, biozRateCode: 1, ppgRateCode: 1,
                                         tUs: deviceUs(emitted), batteryPct: Int(batteryPct),
                                         errorFlags: 0))
    }

    private func deviceUs(_ sampleIndex: Int) -> Double {
        (Double(sampleIndex) * DSPConstants.usPerS / Double(fs)).rounded()
    }

    private func makeTimer(intervalMs: Double, _ work: @escaping () -> Void) -> DispatchSourceTimer {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(Int(intervalMs)),
                   repeating: .milliseconds(Int(intervalMs)))
        t.setEventHandler(handler: work)
        t.resume()
        return t
    }
}
