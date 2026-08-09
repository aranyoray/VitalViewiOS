//
//  MockSource.swift
//  MoniVitals
//
//  Synthetic data source: drives realistic packets on timers with no hardware, so the
//  entire app — dashboard, recording, calibration, gating, export — is demoable. Emits
//  typed packets with already-monotonic device timestamps.
//
//  Ported from web/src/source/MockSource.ts. Uses GCD timers on a serial queue; elapsed
//  time uses a monotonic clock (systemUptime) and the clock offset uses wall time, to
//  mirror the web's performance.now()/Date.now() split.
//

import Foundation

private let TICK_MS = 40.0
private let METRICS_MS = 500.0

private final class StreamState {
    var rateHz: Int
    var k: Int
    var nextIndex: Int = 0
    var seq: Int = 0
    init(rateHz: Int, k: Int) {
        self.rateHz = rateHz
        self.k = k
    }
}

final class MockSource: BaseDataSource {
    override var isMock: Bool { true }
    private var _clockOffsetUs: Double? = nil
    override var clockOffsetUs: Double? { _clockOffsetUs }
    private var _deviceName: String? = "MoniVitals Mock"
    override var deviceName: String? { _deviceName }

    private var signal: MockSignal
    private var streams: [StreamKind: StreamState]
    private var enabledMask: UInt8 = 0
    private var running = false
    private var startUptime: TimeInterval = 0
    private var batteryPct = 100.0
    private var tickTimer: DispatchSourceTimer?
    private var metricsTimer: DispatchSourceTimer?
    private var statusTimer: DispatchSourceTimer?
    private var lastMetricsDeviceUs = 0.0
    private let contact: ContactMotionEstimator
    private let queue = DispatchQueue(label: "com.monivitals.mocksource")

    init(_ params: MockParams = .default) {
        self.signal = MockSignal(params)
        self.contact = ContactMotionEstimator(fsBioz: Double(params.biozRateHz))
        self.streams = [
            .ecg: StreamState(rateHz: BLEProtocol.defaultRateHz(.ecg), k: BLEProtocol.defaultK(.ecg)),
            .bioz: StreamState(rateHz: BLEProtocol.defaultRateHz(.bioz), k: BLEProtocol.defaultK(.bioz)),
            .ppg: StreamState(rateHz: BLEProtocol.defaultRateHz(.ppg), k: BLEProtocol.defaultK(.ppg)),
        ]
        super.init()
    }

    /// Live-adjust the synthetic signal (HR/PAT/SpO2/etc.) from Settings.
    /// `signal.p` is read by the emission timers on `queue`, so mutate it there.
    func setParams(_ mutate: @escaping (inout MockParams) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            mutate(&self.signal.p)
        }
    }

    func getParams() -> MockParams { queue.sync { signal.p } }

    /// Inject a motion burst now (drives the motion/gating demo).
    func injectMotion(durationMs: Double = 2000, severity: Double = 4) {
        queue.async { [weak self] in
            guard let self else { return }
            let now = self.deviceNowUs()
            self.signal.p.motionBursts.append(
                MotionBurst(startUs: now, endUs: now + durationMs * 1000, severity: severity))
        }
    }

    override func connect() {
        setState(.connecting)
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.setState(.connected)
            self.startUptime = ProcessInfo.processInfo.systemUptime
            self.emitInfo()
            self.statusTimer = self.makeTimer(intervalMs: 1000) { [weak self] in self?.emitStatus() }
        }
    }

    override func disconnect() {
        stop()
        statusTimer?.cancel()
        statusTimer = nil
        setState(.disconnected)
    }

    override func start(streamMask: UInt8) {
        queue.async { [weak self] in
            guard let self else { return }
            self.enabledMask = streamMask
            self.startUptime = ProcessInfo.processInfo.systemUptime
            self.lastMetricsDeviceUs = 0
            for s in self.streams.values {
                s.nextIndex = 0
                s.seq = 0
            }
            self.contact.reset()
            self.running = true
            self.tickTimer = self.makeTimer(intervalMs: TICK_MS) { [weak self] in self?.tick() }
            self.metricsTimer = self.makeTimer(intervalMs: METRICS_MS) { [weak self] in self?.emitMetrics() }
        }
    }

    override func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false
            self.tickTimer?.cancel()
            self.metricsTimer?.cancel()
            self.tickTimer = nil
            self.metricsTimer = nil
        }
    }

    override func setRate(_ stream: StreamKind, hz: Int) {
        queue.async { [weak self] in
            guard let self, let s = self.streams[stream] else { return }
            s.rateHz = hz
            if self.running { s.nextIndex = Int(self.elapsedS() * Double(hz)) }
            switch stream {
            case .bioz: self.signal.p.biozRateHz = hz
            case .ecg: self.signal.p.ecgRateHz = hz
            case .ppg: self.signal.p.ppgRateHz = hz
            }
        }
    }

    override func syncClock() {
        queue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            let deviceTus = self.deviceNowUs()
            self._clockOffsetUs = Date().timeIntervalSince1970 * 1_000_000 - deviceTus
        }
    }

    override func getInfo() {
        queue.async { [weak self] in self?.emitInfo() }
    }

    // MARK: - internals

    private func makeTimer(intervalMs: Double, _ work: @escaping () -> Void) -> DispatchSourceTimer {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(Int(intervalMs)),
                   repeating: .milliseconds(Int(intervalMs)))
        t.setEventHandler(handler: work)
        t.resume()
        return t
    }

    private func emitInfo() {
        events.info.send(InfoMessage(
            firmwareVersion: "1.0.0-mock",
            deviceId: "mock00000001",
            capabilities: Int(BLEProtocol.streamBit(.ecg) | BLEProtocol.streamBit(.bioz) | BLEProtocol.streamBit(.ppg))
        ))
        events.battery.send(Int(batteryPct))
    }

    private func elapsedS() -> Double {
        ProcessInfo.processInfo.systemUptime - startUptime
    }

    private func deviceNowUs() -> Double {
        (elapsedS() * DSPConstants.usPerS).rounded()
    }

    private func tick() {
        if !running { return }
        let elapsed = elapsedS()
        if enabledMask & BLEProtocol.streamBit(.ecg) != 0 { tickEcg(elapsed) }
        if enabledMask & BLEProtocol.streamBit(.bioz) != 0 { tickBioz(elapsed) }
        if enabledMask & BLEProtocol.streamBit(.ppg) != 0 { tickPpg(elapsed) }
    }

    private func tickEcg(_ elapsedS: Double) {
        guard let s = streams[.ecg] else { return }
        let target = Int(elapsedS * Double(s.rateHz))
        while s.nextIndex < target {
            let count = min(s.k, target - s.nextIndex)
            let first = s.nextIndex
            let tUs = (Double(first) * DSPConstants.usPerS / Double(s.rateHz)).rounded()
            var samples = [Int32](repeating: 0, count: count)
            for i in 0..<count {
                let t = (Double(first + i) * DSPConstants.usPerS / Double(s.rateHz)).rounded()
                samples[i] = Int32(signal.ecgAt(t).rounded())
            }
            events.ecg.send(EcgPacket(seq: s.seq, tUs: tUs, sampleRateHz: s.rateHz, samples: samples))
            s.nextIndex += count
            s.seq = (s.seq + 1) & 0xffff
        }
    }

    private func tickBioz(_ elapsedS: Double) {
        guard let s = streams[.bioz] else { return }
        let target = Int(elapsedS * Double(s.rateHz))
        while s.nextIndex < target {
            let count = min(s.k, target - s.nextIndex)
            let first = s.nextIndex
            let tUs = (Double(first) * DSPConstants.usPerS / Double(s.rateHz)).rounded()
            let z0 = Int32(signal.z0At(tUs).rounded())
            var dz = [Int32](repeating: 0, count: count)
            for i in 0..<count {
                let t = (Double(first + i) * DSPConstants.usPerS / Double(s.rateHz)).rounded()
                dz[i] = Int32(signal.dzAt(t).rounded())
                contact.pushDz(Double(dz[i]))
            }
            contact.pushZ0(Double(z0))
            events.bioz.send(BiozPacket(seq: s.seq, tUs: tUs, sampleRateHz: s.rateHz, z0Milliohm: z0, dz: dz))
            s.nextIndex += count
            s.seq = (s.seq + 1) & 0xffff
        }
    }

    private func tickPpg(_ elapsedS: Double) {
        guard let s = streams[.ppg] else { return }
        let target = Int(elapsedS * Double(s.rateHz))
        while s.nextIndex < target {
            let count = min(s.k, target - s.nextIndex)
            let first = s.nextIndex
            let tUs = (Double(first) * DSPConstants.usPerS / Double(s.rateHz)).rounded()
            var green = [UInt32](repeating: 0, count: count)
            var red = [UInt32](repeating: 0, count: count)
            var ir = [UInt32](repeating: 0, count: count)
            for i in 0..<count {
                let t = (Double(first + i) * DSPConstants.usPerS / Double(s.rateHz)).rounded()
                green[i] = UInt32(max(0, signal.greenAt(t).rounded()))
                red[i] = UInt32(max(0, signal.redAt(t).rounded()))
                ir[i] = UInt32(max(0, signal.irAt(t).rounded()))
            }
            events.ppg.send(PpgPacket(seq: s.seq, tUs: tUs, sampleRateHz: s.rateHz, green: green, red: red, ir: ir))
            s.nextIndex += count
            s.seq = (s.seq + 1) & 0xffff
        }
    }

    private func emitMetrics() {
        if !running { return }
        let tUs = deviceNowUs()
        let beats = signal.rPeakTimes(lastMetricsDeviceUs, tUs)
        lastMetricsDeviceUs = tUs
        events.metrics.send(MetricsPacket(
            tUs: tUs,
            hrBpm: signal.p.hrBpm,
            spo2Pct: signal.p.spo2Target,
            contactQuality: contact.contactQuality(),
            motion: contact.motion(),
            patUs: signal.p.patMs * 1000,
            sbpMmHg: nil, // firmware reports BP uncalibrated; calibration is per-subject in-app
            dbpMmHg: nil,
            rpeak: !beats.isEmpty
        ))
    }

    private func emitStatus() {
        // Slow battery drain for realism.
        batteryPct = max(0, batteryPct - 0.05)
        events.battery.send(Int(batteryPct.rounded()))
        events.status.send(StatusMessage(
            streamingMask: running ? enabledMask : 0,
            ecgRateCode: 1,
            biozRateCode: 1,
            ppgRateCode: 1,
            tUs: deviceNowUs(),
            batteryPct: Int(batteryPct.rounded()),
            errorFlags: 0
        ))
    }
}
