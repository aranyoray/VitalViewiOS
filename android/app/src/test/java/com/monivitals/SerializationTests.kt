//
//  SerializationTests.kt
//  MoniVitals (Android)
//
//  Guards the kotlinx.serialization model against runtime surprises — in particular the
//  enum-keyed `streamRates` map in AppSettings and the nested Calibration in a Session.
//

package com.monivitals

import com.monivitals.ble.StreamKind
import com.monivitals.dsp.BpCoeffs
import com.monivitals.dsp.CalibModel
import com.monivitals.dsp.RefPair
import com.monivitals.model.AppSettings
import com.monivitals.model.Calibration
import com.monivitals.model.GatingConfig
import com.monivitals.model.MetricsSource
import com.monivitals.model.Session
import com.monivitals.model.SessionLabel
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class SerializationTests {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Test
    fun appSettingsRoundTrips() {
        val s = AppSettings(
            metricsSource = MetricsSource.FIRMWARE,
            streamRates = mapOf(StreamKind.ECG to 512, StreamKind.BIOZ to 128, StreamKind.PPG to 200),
            theme = AppSettings.Theme.DARK,
            consentAccepted = true,
            disclaimerAcknowledged = true,
        )
        val back = json.decodeFromString(AppSettings.serializer(), json.encodeToString(AppSettings.serializer(), s))
        assertEquals(s, back)
        assertEquals(512, back.streamRates[StreamKind.ECG])
        assertEquals(200, back.streamRates[StreamKind.PPG])
    }

    @Test
    fun sessionWithCalibrationRoundTrips() {
        val cal = Calibration(
            id = 3, subjectCode = "S01", model = CalibModel.LINEAR_INV_PAT,
            coeffs = BpCoeffs(sbp = listOf(100.0, 50.0), dbp = listOf(60.0, 30.0)),
            referencePairs = listOf(RefPair(200000.0, 120.0, 80.0)),
            rmseSbp = 1.5, rmseDbp = 1.2, r = 0.98, createdAt = "2026-07-28T00:00:00Z",
        )
        val session = Session(
            id = "abc", subjectCode = "S01", label = SessionLabel.POST_EXERCISE,
            deviceId = "mock", firmwareVersion = "1.0.0-mock", startedAt = "2026-07-28T00:00:00Z",
            endedAt = null, notes = "n", metricsSource = MetricsSource.APP,
            gating = GatingConfig(4.0e6, 5.0e6, 500.0), calibrationSnapshot = cal,
        )
        val back = json.decodeFromString(Session.serializer(), json.encodeToString(Session.serializer(), session))
        assertEquals(session, back)
        assertEquals(SessionLabel.POST_EXERCISE, back.label)
        assertEquals(cal, back.calibrationSnapshot)
    }
}
