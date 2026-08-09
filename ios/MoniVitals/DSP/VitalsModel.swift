//
//  VitalsModel.swift
//  MoniVitals
//
//  The on-device inference interface that turns raw biosignal packets into a
//  `MetricsSnapshot`. This is the seam where a learned model (CoreML) could later
//  replace the deterministic pipeline: today it is backed by the DSP `MetricsEngine`
//  (Pan-Tompkins R-peak detection, PPG foot detection, ratio-of-ratios SpO2, and a
//  per-subject PAT→BP fit), exposed behind a swappable model contract.
//
//  MoniVitals is a research / educational tool, NOT a medical device.
//

import Foundation

/// A swappable biosignal inference model. Implementations ingest streamed packets and
/// produce a fused metrics snapshot on demand.
protocol VitalsModel: AnyObject {
    /// Human-readable model identity (shown in the UI).
    var name: String { get }
    /// Recent detected R-peak / PPG-foot times (µs) for waveform markers.
    var recentRPeaks: [Double] { get }
    var recentFeet: [Double] { get }

    func setCalibration(_ fit: CalibCoeffs?)
    func setMotionThresh(_ thresh: Double)

    func ingestEcg(_ p: EcgPacket)
    func ingestBioz(_ p: BiozPacket)
    func ingestPpg(_ p: PpgPacket)

    /// Run inference and return the fused metrics at the given device timestamp.
    func infer(at tUs: Double) -> MetricsSnapshot

    func reset()
}

/// The default on-device model: the deterministic DSP pipeline.
extension MetricsEngine: VitalsModel {
    var name: String { "MoniVitals DSP Model v1 · on-device" }

    func infer(at tUs: Double) -> MetricsSnapshot { snapshot(tUs) }
}
