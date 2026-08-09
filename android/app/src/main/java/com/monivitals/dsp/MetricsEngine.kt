//
//  MetricsEngine.kt
//  MoniVitals (Android)
//
//  Ties the detectors together into a live metrics engine. Ingests decoded stream
//  packets (with extended device timestamps) and produces a metrics snapshot — the
//  app-side equivalent of the firmware Metrics packet, so algorithms can be iterated
//  without reflashing.
//
//  Ported from ios/MoniVitals/DSP/MetricsEngine.swift (== web/src/dsp/engine.ts).
//

package com.monivitals.dsp

import com.monivitals.ble.BiozPacket
import com.monivitals.ble.EcgPacket
import com.monivitals.ble.PpgPacket
import kotlin.math.roundToLong

/** App-computed metrics at a point in time (the same fields as a MetricsPacket). */
data class MetricsSnapshot(
    val tUs: Double,
    val hrBpm: Double?,
    val spo2Pct: Double?,
    val contactQuality: Int,
    val motion: Int,
    val patUs: Double?,
    val sbpMmHg: Double?,
    val dbpMmHg: Double?,
    val rpeak: Boolean,
)

/**
 * On-device inference surface: turns a device timestamp into a [MetricsSnapshot]. The
 * MoniVitals DSP metrics engine implements this so the app treats it like a model.
 */
interface VitalsModel {
    val name: String
    fun infer(tUs: Double): MetricsSnapshot
}

class MetricsEngine : VitalsModel {
    override val name: String = "MoniVitals DSP Model v1 · on-device"

    /** Model inference at the given device timestamp (alias of [snapshot]). */
    override fun infer(tUs: Double): MetricsSnapshot = snapshot(tUs)

    private var rpeakDetector: RPeakDetector? = null
    private var foot: PpgFootDetector? = null
    private var contact: ContactMotionEstimator? = null
    private var spo2: Spo2Estimator? = null
    private val pat = PatEstimator()
    private val hr = HeartRateEstimator()
    private var ecgFs = 0
    private var ppgFs = 0
    private var biozFs = 0
    private var rpeakFlag = false
    private var calib: CalibCoeffs? = null
    private var motionThresh: Double? = null

    /** Recent detected event times (µs), capped — for waveform markers. */
    var recentRPeaks = mutableListOf<Double>()
        private set
    var recentFeet = mutableListOf<Double>()
        private set

    fun setCalibration(fit: CalibCoeffs?) {
        calib = fit
    }

    fun setMotionThresh(thresh: Double) {
        motionThresh = thresh
        contact?.setMotionThresh(thresh)
    }

    fun ingestEcg(p: EcgPacket) {
        if (rpeakDetector == null || ecgFs != p.sampleRateHz) {
            rpeakDetector = RPeakDetector(p.sampleRateHz.toDouble())
            ecgFs = p.sampleRateHz
        }
        val dt = DSPConstants.usPerS / p.sampleRateHz
        for (i in p.samples.indices) {
            val t = p.tUs + (i * dt).roundToLong()
            val r = rpeakDetector?.process(p.samples[i].toDouble(), t)
            if (r != null) {
                hr.addRPeak(r)
                pat.addRPeak(r)
                rpeakFlag = true
                pushCapped(recentRPeaks, r)
            }
        }
    }

    fun ingestBioz(p: BiozPacket) {
        if (contact == null || biozFs != p.sampleRateHz) {
            contact = ContactMotionEstimator(p.sampleRateHz.toDouble(), motionThresh ?: DSPConstants.motionThresh)
            biozFs = p.sampleRateHz
        }
        contact?.pushZ0(p.z0Milliohm.toDouble())
        for (i in p.dz.indices) contact?.pushDz(p.dz[i].toDouble())
    }

    fun ingestPpg(p: PpgPacket) {
        if (foot == null || ppgFs != p.sampleRateHz) {
            foot = PpgFootDetector(p.sampleRateHz.toDouble())
            spo2 = Spo2Estimator(p.sampleRateHz.toDouble())
            ppgFs = p.sampleRateHz
        }
        val dt = DSPConstants.usPerS / p.sampleRateHz
        for (i in p.green.indices) {
            val t = p.tUs + (i * dt).roundToLong()
            val f = foot?.process(p.green[i].toDouble(), t)
            if (f != null) {
                pat.addFoot(f)
                pushCapped(recentFeet, f)
            }
            spo2?.push(p.red[i].toDouble(), p.ir[i].toDouble())
        }
    }

    /** Produce a metrics snapshot at the given device timestamp. */
    fun snapshot(tUs: Double): MetricsSnapshot {
        val patUs = pat.medianUs()
        var sbp: Double? = null
        var dbp: Double? = null
        val c = calib
        if (patUs != null && c != null) {
            val bp = predictBp(patUs, c)
            sbp = bp.first.roundToLong().toDouble()
            dbp = bp.second.roundToLong().toDouble()
        }
        val snap = MetricsSnapshot(
            tUs = tUs,
            hrBpm = hr.bpm(),
            spo2Pct = spo2?.estimate(),
            contactQuality = contact?.contactQuality() ?: 0,
            motion = contact?.motion() ?: 0,
            patUs = patUs,
            sbpMmHg = sbp,
            dbpMmHg = dbp,
            rpeak = rpeakFlag,
        )
        rpeakFlag = false
        return snap
    }

    fun reset() {
        rpeakDetector = null
        foot = null
        contact = null
        spo2 = null
        pat.reset()
        hr.reset()
        ecgFs = 0
        ppgFs = 0
        biozFs = 0
        rpeakFlag = false
        recentRPeaks.clear()
        recentFeet.clear()
    }

    private fun pushCapped(arr: MutableList<Double>, v: Double, cap: Int = 64) {
        arr.add(v)
        if (arr.size > cap) arr.removeAt(0)
    }
}
