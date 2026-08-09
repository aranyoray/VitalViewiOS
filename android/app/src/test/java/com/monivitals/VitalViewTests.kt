//
//  MoniVitalsTests.kt
//  MoniVitals (Android)
//
//  JVM unit tests mirroring the iOS MoniVitalsTests / web Vitest suite: parser round-trips,
//  calibration OLS math, and the DSP validated against the mock signal's exact ground
//  truth (HR / PAT). These exercise the pure ble/dsp/source layers with no Android deps.
//

package com.monivitals

import com.monivitals.ble.Encoders
import com.monivitals.ble.EcgPacket
import com.monivitals.ble.Parsers
import com.monivitals.ble.PpgPacket
import com.monivitals.dsp.CalibModel
import com.monivitals.dsp.DSPConstants
import com.monivitals.dsp.MetricsEngine
import com.monivitals.dsp.RefPair
import com.monivitals.dsp.fitCalibration
import com.monivitals.source.MockParams
import com.monivitals.source.MockSignal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.roundToLong

class ParserRoundTripTests {
    @Test
    fun ecgRoundTrips() {
        val original = EcgPacket(seq = 42, tUs = 1_234_567.0, sampleRateHz = 256, samples = intArrayOf(-5, 0, 100, -2048, 32767))
        val parsed = Parsers.parseEcg(Encoders.encodeEcg(original))
        assertEquals(original.seq, parsed.seq)
        assertEquals(original.tUs, parsed.tUs, 0.0)
        assertEquals(original.sampleRateHz, parsed.sampleRateHz)
        assertTrue(original.samples.contentEquals(parsed.samples))
    }

    @Test
    fun ppgRoundTrips() {
        val original = PpgPacket(
            seq = 7, tUs = 9_000_000.0, sampleRateHz = 100,
            green = longArrayOf(120000, 121000, 119500),
            red = longArrayOf(80000, 80500, 79800),
            ir = longArrayOf(90000, 90500, 89800),
        )
        val parsed = Parsers.parsePpg(Encoders.encodePpg(original))
        assertEquals(original.seq, parsed.seq)
        assertTrue(original.green.contentEquals(parsed.green))
        assertTrue(original.red.contentEquals(parsed.red))
        assertTrue(original.ir.contentEquals(parsed.ir))
    }
}

class CalibrationTests {
    @Test
    fun olsRecoversKnownLine() {
        // SBP = 100 + 50*(1/PAT_s). Build pairs from that exact relationship.
        val pairs = listOf(0.20, 0.25, 0.30, 0.35).map { patS ->
            val sbp = 100 + 50 * (1 / patS)
            RefPair(patUs = patS * 1e6, sbp = sbp, dbp = sbp - 40)
        }
        val fit = fitCalibration(pairs, CalibModel.LINEAR_INV_PAT)
        assertNotNull(fit)
        fit!!
        assertEquals(100.0, fit.coeffs.sbp[0], 0.5)
        assertEquals(50.0, fit.coeffs.sbp[1], 0.5)
        assertTrue("R should be ~1 for a perfect line", fit.r > 0.999)
    }
}

class MockGroundTruthTests {
    /** Feed the deterministic mock signal through the engine and check HR + PAT. */
    @Test
    fun engineRecoversHrAndPat() {
        val params = MockParams.default.copy(hrBpm = 72.0, patMs = 210.0)
        val signal = MockSignal(params)
        val engine = MetricsEngine()

        val durationS = 8.0
        val ecgFs = params.ecgRateHz
        val ppgFs = params.ppgRateHz

        // Build ECG (20/pkt) and PPG (12/pkt) packets, then feed them in device-time order
        // — the mock source interleaves streams, and the PAT estimator prunes old R-peaks,
        // so feet must arrive alongside (not after) their R-peaks to pair.
        val events = mutableListOf<Pair<Double, () -> Unit>>()

        val ecgK = 20
        val ecgTotal = (durationS * ecgFs).toInt()
        var i = 0; var seq = 0
        while (i < ecgTotal) {
            val count = minOf(ecgK, ecgTotal - i)
            val first = i
            val tUs = (first.toDouble() * DSPConstants.usPerS / ecgFs).roundToLong().toDouble()
            val samples = IntArray(count) { j ->
                val t = ((first + j).toDouble() * DSPConstants.usPerS / ecgFs).roundToLong().toDouble()
                signal.ecgAt(t).roundToInt()
            }
            val pkt = EcgPacket(seq = seq++, tUs = tUs, sampleRateHz = ecgFs, samples = samples)
            events.add(tUs to { engine.ingestEcg(pkt) })
            i += count
        }

        val ppgK = 12
        val ppgTotal = (durationS * ppgFs).toInt()
        i = 0; seq = 0
        while (i < ppgTotal) {
            val count = minOf(ppgK, ppgTotal - i)
            val first = i
            val tUs = (first.toDouble() * DSPConstants.usPerS / ppgFs).roundToLong().toDouble()
            val green = LongArray(count) { j ->
                val t = ((first + j).toDouble() * DSPConstants.usPerS / ppgFs).roundToLong().toDouble()
                maxOf(0L, signal.greenAt(t).roundToLong())
            }
            val red = LongArray(count) { j ->
                val t = ((first + j).toDouble() * DSPConstants.usPerS / ppgFs).roundToLong().toDouble()
                maxOf(0L, signal.redAt(t).roundToLong())
            }
            val ir = LongArray(count) { j ->
                val t = ((first + j).toDouble() * DSPConstants.usPerS / ppgFs).roundToLong().toDouble()
                maxOf(0L, signal.irAt(t).roundToLong())
            }
            val pkt = PpgPacket(seq = seq++, tUs = tUs, sampleRateHz = ppgFs, green = green, red = red, ir = ir)
            events.add(tUs to { engine.ingestPpg(pkt) })
            i += count
        }

        events.sortBy { it.first }
        for (e in events) e.second()

        val snap = engine.snapshot((durationS * DSPConstants.usPerS))
        assertNotNull("HR should be available after 8 s", snap.hrBpm)
        assertNotNull("PAT should be available after 8 s", snap.patUs)
        assertTrue("HR ${snap.hrBpm} should be near 72 bpm", abs(snap.hrBpm!! - 72.0) < 4.0)
        val patMs = snap.patUs!! / 1000
        assertTrue("PAT $patMs ms should be near 210 ms", abs(patMs - 210.0) < 40.0)
    }
}
