//
//  MetricsEngine.swift
//  VitalView
//
//  Ties the detectors together into a live metrics engine. Ingests decoded stream
//  packets (with extended device timestamps) and produces a metrics snapshot — the
//  app-side equivalent of the firmware Metrics packet, so algorithms can be iterated
//  without reflashing.
//
//  Ported from web/src/dsp/engine.ts.
//

import Foundation

/// App-computed metrics at a point in time (the same fields as a MetricsPacket).
struct MetricsSnapshot {
    var tUs: Double
    var hrBpm: Double?
    var spo2Pct: Double?
    var contactQuality: Int
    var motion: Int
    var patUs: Double?
    var sbpMmHg: Double?
    var dbpMmHg: Double?
    var rpeak: Bool
}

final class MetricsEngine {
    private var rpeakDetector: RPeakDetector?
    private var foot: PpgFootDetector?
    private var contact: ContactMotionEstimator?
    private var spo2: Spo2Estimator?
    private let pat = PatEstimator()
    private let hr = HeartRateEstimator()
    private var ecgFs = 0
    private var ppgFs = 0
    private var biozFs = 0
    private var rpeakFlag = false
    private var calib: CalibCoeffs?
    private var motionThresh: Double?

    /// Recent detected event times (µs), capped — for waveform markers.
    private(set) var recentRPeaks: [Double] = []
    private(set) var recentFeet: [Double] = []

    func setCalibration(_ fit: CalibCoeffs?) {
        calib = fit
    }

    func setMotionThresh(_ thresh: Double) {
        motionThresh = thresh
        contact?.setMotionThresh(thresh)
    }

    func ingestEcg(_ p: EcgPacket) {
        if rpeakDetector == nil || ecgFs != p.sampleRateHz {
            rpeakDetector = RPeakDetector(fs: Double(p.sampleRateHz))
            ecgFs = p.sampleRateHz
        }
        let dt = DSPConstants.usPerS / Double(p.sampleRateHz)
        for i in 0..<p.samples.count {
            let t = p.tUs + (Double(i) * dt).rounded()
            if let r = rpeakDetector?.process(Double(p.samples[i]), t) {
                hr.addRPeak(r)
                pat.addRPeak(r)
                rpeakFlag = true
                pushCapped(&recentRPeaks, r)
            }
        }
    }

    func ingestBioz(_ p: BiozPacket) {
        if contact == nil || biozFs != p.sampleRateHz {
            contact = ContactMotionEstimator(fsBioz: Double(p.sampleRateHz),
                                             motionThresh: motionThresh ?? DSPConstants.motionThresh)
            biozFs = p.sampleRateHz
        }
        contact?.pushZ0(Double(p.z0Milliohm))
        for i in 0..<p.dz.count { contact?.pushDz(Double(p.dz[i])) }
    }

    func ingestPpg(_ p: PpgPacket) {
        if foot == nil || ppgFs != p.sampleRateHz {
            foot = PpgFootDetector(fs: Double(p.sampleRateHz))
            spo2 = Spo2Estimator(fs: Double(p.sampleRateHz))
            ppgFs = p.sampleRateHz
        }
        let dt = DSPConstants.usPerS / Double(p.sampleRateHz)
        for i in 0..<p.green.count {
            let t = p.tUs + (Double(i) * dt).rounded()
            if let f = foot?.process(Double(p.green[i]), t) {
                pat.addFoot(f)
                pushCapped(&recentFeet, f)
            }
            spo2?.push(Double(p.red[i]), Double(p.ir[i]))
        }
    }

    /// Produce a metrics snapshot at the given device timestamp.
    func snapshot(_ tUs: Double) -> MetricsSnapshot {
        let patUs = pat.medianUs()
        var sbp: Double? = nil
        var dbp: Double? = nil
        if let patUs, let calib {
            let bp = predictBp(patUs, calib)
            sbp = bp.sbp.rounded()
            dbp = bp.dbp.rounded()
        }
        let snap = MetricsSnapshot(
            tUs: tUs,
            hrBpm: hr.bpm(),
            spo2Pct: spo2?.estimate(),
            contactQuality: contact?.contactQuality() ?? 0,
            motion: contact?.motion() ?? 0,
            patUs: patUs,
            sbpMmHg: sbp,
            dbpMmHg: dbp,
            rpeak: rpeakFlag
        )
        rpeakFlag = false
        return snap
    }

    func reset() {
        rpeakDetector = nil
        foot = nil
        contact = nil
        spo2 = nil
        pat.reset()
        hr.reset()
        ecgFs = 0
        ppgFs = 0
        biozFs = 0
        rpeakFlag = false
        recentRPeaks.removeAll()
        recentFeet.removeAll()
    }
}

private func pushCapped(_ arr: inout [Double], _ v: Double, cap: Int = 64) {
    arr.append(v)
    if arr.count > cap { arr.removeFirst() }
}
