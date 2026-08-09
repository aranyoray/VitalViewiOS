//
//  AppViewModel.kt
//  MoniVitals (Android)
//
//  Central application store. Orchestrates the data source, the live runtime (waveform
//  ring buffers + MetricsEngine), recording, calibration, and settings.
//
//  High-rate sample data lives in the non-reactive `buffers`/`engine` (read directly by
//  the Canvas); only throttled metrics, counts, and connection state are Compose state.
//
//  Mirrors ios/MoniVitals/Views/AppModel.swift (== web/src/store/appStore.ts).
//

package com.monivitals.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.monivitals.ble.BLEProtocol
import com.monivitals.ble.MetricsPacket
import com.monivitals.ble.StreamKind
import com.monivitals.dsp.DSPConstants
import com.monivitals.dsp.MetricsEngine
import com.monivitals.dsp.MetricsSnapshot
import com.monivitals.dsp.RefPair
import com.monivitals.dsp.CalibrationFit
import com.monivitals.dsp.fitCalibration
import com.monivitals.dsp.predictBp
import com.monivitals.model.AppSettings
import com.monivitals.model.Annotation
import com.monivitals.model.AnnotationType
import com.monivitals.model.Calibration
import com.monivitals.model.GatingConfig
import com.monivitals.model.MetricsRecord
import com.monivitals.model.MetricsSource
import com.monivitals.model.Session
import com.monivitals.model.SessionLabel
import com.monivitals.model.Store
import com.monivitals.model.Subject
import com.monivitals.source.ConnectionState
import com.monivitals.source.DataSource
import com.monivitals.source.MockParams
import com.monivitals.source.MockSource
import com.monivitals.source.ReplaySource
import com.monivitals.model.Recorder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID
import kotlin.math.roundToLong

class AppViewModel(app: Application) : AndroidViewModel(app) {
    // MARK: - Non-reactive runtime (mutated at full sample rate)
    val buffers = WaveBuffers()
    val engine = MetricsEngine()

    // MARK: - Settings
    var settings by mutableStateOf(loadSettings()); private set

    // MARK: - Connection / source
    var isMock by mutableStateOf(false); private set

    /**
     * True only when the active source is a live-tunable [MockSource] (not the ReplaySource,
     * which replays a fixed recording). Gates the mock-signal controls so the UI never shows
     * sliders/buttons that would silently no-op against a replay source.
     */
    var isMockSource by mutableStateOf(false); private set
    var connectionState by mutableStateOf(ConnectionState.DISCONNECTED); private set
    var deviceName by mutableStateOf<String?>(null); private set
    var batteryPct by mutableStateOf<Int?>(null); private set
    var errorFlags by mutableStateOf(0); private set
    var dropped by mutableStateOf(mapOf(StreamKind.ECG to 0, StreamKind.BIOZ to 0, StreamKind.PPG to 0)); private set
    var clockOffsetUs by mutableStateOf<Double?>(null); private set
    var streaming by mutableStateOf(false); private set

    // MARK: - Metrics
    var appMetrics by mutableStateOf<MetricsSnapshot?>(null); private set
    var firmwareMetrics by mutableStateOf<MetricsPacket?>(null); private set
    var liveMetrics by mutableStateOf<MetricsSnapshot?>(null); private set

    // MARK: - Subjects / calibration
    var subjects by mutableStateOf<List<Subject>>(emptyList()); private set
    var currentSubjectCode by mutableStateOf<String?>(null); private set
    var currentCalibration by mutableStateOf<Calibration?>(null); private set
    var calibrationPairs by mutableStateOf<List<RefPair>>(emptyList()); private set

    // MARK: - Recording
    var recording by mutableStateOf<Session?>(null); private set
    var recordCounts by mutableStateOf(mapOf(StreamKind.ECG to 0, StreamKind.BIOZ to 0, StreamKind.PPG to 0)); private set
    var recordDurationMs by mutableStateOf(0.0); private set
    var cuffReadingCount by mutableStateOf(0); private set

    // MARK: - Mock parameter mirrors (so Settings UI reflects live changes)
    var mockHrBpm by mutableStateOf(MockParams.default.hrBpm); private set
    var mockPatMs by mutableStateOf(MockParams.default.patMs); private set
    var mockSpo2 by mutableStateOf(MockParams.default.spo2Target); private set

    // MARK: - Recorded reference (real biosignal replay) provenance
    var referenceHR by mutableStateOf<Double?>(null); private set
    var referenceSpO2 by mutableStateOf<Double?>(null); private set
    var recordingName by mutableStateOf<String?>(null); private set

    // MARK: - private
    private var source: DataSource? = null
    private var recorder: Recorder? = null
    private var recordingStartedAt: Long? = null
    private val collectors = mutableListOf<Job>()
    private var tickJob: Job? = null
    private val store = Store.shared
    private val prefs = app.getSharedPreferences("monivitals", Application.MODE_PRIVATE)
    private val jsonCodec = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    init {
        engine.setMotionThresh(settings.motionThresh)
        subjects = store.listSubjects()
    }

    // MARK: - Settings

    private fun loadSettings(): AppSettings {
        val p = getApplication<Application>().getSharedPreferences("monivitals", Application.MODE_PRIVATE)
        val s = p.getString("settings", null) ?: return AppSettings()
        return try {
            Json { ignoreUnknownKeys = true; encodeDefaults = true }
                .decodeFromString(AppSettings.serializer(), s)
        } catch (e: Exception) {
            AppSettings()
        }
    }

    fun updateSettings(mutate: (AppSettings) -> AppSettings) {
        val old = settings
        val s = mutate(old)
        prefs.edit().putString("settings", jsonCodec.encodeToString(AppSettings.serializer(), s)).apply()
        engine.setMotionThresh(s.motionThresh)
        // Push rate changes to a live-tunable source. The replay source runs at a fixed
        // sample rate (setRate is a no-op there), so this only has an effect for a MockSource.
        source?.let { src ->
            for ((stream, hz) in s.streamRates) {
                if (old.streamRates[stream] != hz) src.setRate(stream, hz)
            }
        }
        settings = s
    }

    /** First-run consent / disclaimer gate. */
    val needsOnboarding: Boolean
        get() = !(settings.consentAccepted && settings.disclaimerAcknowledged)

    fun acceptOnboarding() {
        updateSettings { it.copy(consentAccepted = true, disclaimerAcknowledged = true) }
    }

    // MARK: - Connecting

    /** Name of the on-device inference model surfaced in the UI. */
    val modelName: String get() = engine.name

    private var started = false

    /**
     * Auto-start the standalone pipeline. Connects the Replay source (real recorded
     * biosignal) once and, when it reaches Connected, begins streaming automatically.
     * Safe to call repeatedly. Mirrors the iOS auto-start behaviour.
     */
    fun begin() {
        if (started) return
        started = true
        connectReplay()
    }

    private fun connectReplay() {
        teardownSource()
        // ReplaySource needs a Context to load the bundled recording from assets; use the
        // Application context (leak-safe, lives as long as the process).
        val src = ReplaySource(getApplication<Application>().applicationContext)
        engine.setMotionThresh(settings.motionThresh)
        source = src
        isMock = true
        isMockSource = false // ReplaySource replays a fixed recording; not live-tunable.
        deviceName = src.deviceName
        referenceHR = src.referenceHR
        referenceSpO2 = src.referenceSpO2
        recordingName = src.recordingName
        wire(src)
        src.connect()
        src.syncClock()
    }

    fun disconnect() {
        stopRecording()
        teardownSource()
        source = null
        streaming = false
        started = false
        connectionState = ConnectionState.DISCONNECTED
        firmwareMetrics = null
    }

    // MARK: - Streaming

    fun startStreaming() {
        val src = source ?: return
        resetRuntime()
        engine.setMotionThresh(settings.motionThresh)
        engine.setCalibration(currentCalibration)
        dropped = mapOf(StreamKind.ECG to 0, StreamKind.BIOZ to 0, StreamKind.PPG to 0)
        src.start(BLEProtocol.allStreamsMask)
        startTick()
        streaming = true
    }

    fun stopStreaming() {
        source?.stop()
        stopTick()
        streaming = false
    }

    fun setMockParams(mutate: (MockParams) -> Unit) {
        (source as? MockSource)?.setParams(mutate)
        val p = (source as? MockSource)?.getParams() ?: return
        mockHrBpm = p.hrBpm; mockPatMs = p.patMs; mockSpo2 = p.spo2Target
    }

    fun injectMockMotion() {
        (source as? MockSource)?.injectMotion()
    }

    // MARK: - Subjects

    fun refreshSubjects() {
        subjects = store.listSubjects()
    }

    fun saveSubject(s: Subject) {
        store.upsertSubject(s)
        refreshSubjects()
    }

    fun selectSubject(code: String?) {
        val cal = code?.let { store.latestCalibration(it) }
        engine.setCalibration(cal)
        currentSubjectCode = code
        currentCalibration = cal
        calibrationPairs = emptyList()
    }

    // MARK: - Recording

    fun startRecording(label: SessionLabel, notes: String) {
        val src = source ?: return
        val subjectCode = currentSubjectCode ?: return
        if (!streaming) startStreaming()
        val session = Session(
            id = UUID.randomUUID().toString(),
            subjectCode = subjectCode,
            label = label,
            deviceId = src.deviceName ?: "unknown",
            firmwareVersion = if (isMock) "1.0.0-mock" else "unknown",
            startedAt = Instant.now().toString(),
            endedAt = null,
            notes = notes,
            metricsSource = settings.metricsSource,
            gating = GatingConfig(settings.motionThresh, settings.contactThresh, settings.gatingWindowMs),
            calibrationSnapshot = currentCalibration,
        )
        store.createSession(session)
        recorder = Recorder(session.id)
        recording = session
        recordingStartedAt = System.currentTimeMillis()
        recordCounts = mapOf(StreamKind.ECG to 0, StreamKind.BIOZ to 0, StreamKind.PPG to 0)
        recordDurationMs = 0.0
        cuffReadingCount = 0
    }

    fun stopRecording() {
        val session = recording ?: return
        val rec = recorder ?: return
        // Stop feeding the recorder immediately, then flush + persist off the main thread.
        recorder = null
        recording = null
        recordingStartedAt = null
        viewModelScope.launch(Dispatchers.IO) {
            rec.finish()
            store.endSession(session.id, Instant.now().toString())
        }
    }

    fun addCuffReading(sbp: Double, dbp: Double) {
        val tUs = buffers.latestDeviceUs()
        recording?.let { session ->
            store.addAnnotation(Annotation(sessionId = session.id, tUs = tUs, type = AnnotationType.CUFF_READING, sbp = sbp, dbp = dbp))
            cuffReadingCount += 1
        }
        // Capture a calibration pair if a PAT is currently available.
        liveMetrics?.patUs?.let { pat ->
            calibrationPairs = calibrationPairs + RefPair(pat, sbp, dbp)
        }
    }

    fun addMarker(type: AnnotationType, text: String? = null) {
        val session = recording ?: return
        store.addAnnotation(Annotation(sessionId = session.id, tUs = buffers.latestDeviceUs(), type = type, text = text))
    }

    /** Export a session bundle (.zip) to the app cache; returns its File for sharing. */
    fun exportSession(sessionId: String): java.io.File? =
        com.monivitals.model.CSVExport.exportSession(sessionId, getApplication(), store)

    // MARK: - Calibration

    fun addCalibrationPair(sbp: Double, dbp: Double): Boolean {
        val pat = liveMetrics?.patUs ?: return false
        calibrationPairs = calibrationPairs + RefPair(pat, sbp, dbp)
        return true
    }

    fun removeCalibrationPair(index: Int) {
        if (index in calibrationPairs.indices) {
            calibrationPairs = calibrationPairs.toMutableList().also { it.removeAt(index) }
        }
    }

    fun clearCalibrationPairs() {
        calibrationPairs = emptyList()
    }

    /** Current best-effort fit of the collected pairs (for live R/RMSE display). */
    val currentFit: CalibrationFit?
        get() = fitCalibration(calibrationPairs, settings.calibModel)

    fun saveCalibrationFit(): Boolean {
        val subjectCode = currentSubjectCode ?: return false
        val fit = fitCalibration(calibrationPairs, settings.calibModel) ?: return false
        val cal = Calibration(
            id = null,
            subjectCode = subjectCode,
            model = fit.model,
            coeffs = fit.coeffs,
            referencePairs = calibrationPairs,
            rmseSbp = fit.rmseSbp,
            rmseDbp = fit.rmseDbp,
            r = fit.r,
            createdAt = Instant.now().toString(),
        )
        store.saveCalibration(cal)
        engine.setCalibration(cal)
        currentCalibration = cal
        return true
    }

    // MARK: - Data management

    fun deleteSession(id: String) {
        store.deleteSession(id)
    }

    fun deleteAllData() {
        store.deleteAllData()
        subjects = emptyList()
        currentSubjectCode = null
        currentCalibration = null
        calibrationPairs = emptyList()
    }

    // MARK: - wiring

    private fun wire(src: DataSource) {
        val ev = src.events
        val scope = viewModelScope

        collectors += scope.launch {
            ev.ecg.collect { p ->
                val dt = DSPConstants.usPerS / p.sampleRateHz
                for (i in p.samples.indices) {
                    buffers.ecg.push(p.tUs + (i * dt).roundToLong(), p.samples[i].toDouble())
                }
                engine.ingestEcg(p)
                recorder?.ingestEcg(p)
            }
        }
        collectors += scope.launch {
            ev.bioz.collect { p ->
                val dt = DSPConstants.usPerS / p.sampleRateHz
                for (i in p.dz.indices) {
                    buffers.biozDz.push(p.tUs + (i * dt).roundToLong(), p.dz[i].toDouble())
                }
                buffers.z0.push(p.tUs, p.z0Milliohm.toDouble())
                engine.ingestBioz(p)
                recorder?.ingestBioz(p)
            }
        }
        collectors += scope.launch {
            ev.ppg.collect { p ->
                val dt = DSPConstants.usPerS / p.sampleRateHz
                for (i in p.green.indices) {
                    val t = p.tUs + (i * dt).roundToLong()
                    buffers.ppgGreen.push(t, p.green[i].toDouble())
                    buffers.ppgRed.push(t, p.red[i].toDouble())
                    buffers.ppgIr.push(t, p.ir[i].toDouble())
                }
                engine.ingestPpg(p)
                recorder?.ingestPpg(p)
            }
        }
        collectors += scope.launch { ev.metrics.collect { firmwareMetrics = it } }
        collectors += scope.launch { ev.battery.collect { batteryPct = it } }
        collectors += scope.launch {
            ev.status.collect { s ->
                errorFlags = s.errorFlags
                batteryPct = s.batteryPct
                clockOffsetUs = source?.clockOffsetUs
            }
        }
        collectors += scope.launch {
            ev.dropped.collect { (stream, count) ->
                if (count > 0) dropped = dropped.toMutableMap().also { it[stream] = (it[stream] ?: 0) + count }
            }
        }
        collectors += scope.launch {
            ev.connection.collect { (state, _) ->
                connectionState = state
                clockOffsetUs = source?.clockOffsetUs
                deviceName = source?.deviceName
                // Auto-start streaming once the source goes live.
                if (state == ConnectionState.CONNECTED && !streaming) startStreaming()
            }
        }
    }

    private fun teardownSource() {
        stopTick()
        collectors.forEach { it.cancel() }
        collectors.clear()
        source?.disconnect()
    }

    private fun resetRuntime() {
        buffers.clear()
        engine.reset()
    }

    private fun startTick() {
        stopTick()
        tickJob = viewModelScope.launch {
            while (isActive) {
                delay(250)
                tick()
            }
        }
    }

    private fun stopTick() {
        tickJob?.cancel()
        tickJob = null
    }

    private fun tick() {
        val latest = buffers.latestDeviceUs()
        val app = engine.infer(latest)
        val live = resolveLive(app, firmwareMetrics, settings, currentCalibration)
        appMetrics = app
        liveMetrics = live
        val rec = recorder
        val start = recordingStartedAt
        if (rec != null && start != null) {
            recordCounts = rec.counts.toMap()
            recordDurationMs = (System.currentTimeMillis() - start).toDouble()
            val record = MetricsRecord(
                sessionId = rec.sessionId, tUs = live.tUs,
                hrBpm = live.hrBpm, spo2Pct = live.spo2Pct,
                contactQuality = live.contactQuality, motion = live.motion,
                patUs = live.patUs, sbpMmHg = live.sbpMmHg, dbpMmHg = live.dbpMmHg,
            )
            // Growing-file JSON write — keep it off the main thread.
            viewModelScope.launch(Dispatchers.IO) { store.addMetrics(record) }
        }
    }

    override fun onCleared() {
        super.onCleared()
        teardownSource()
    }

    companion object {
        /** Resolve the metrics to display: pick the source per settings, overlay calibrated BP. */
        fun resolveLive(
            app: MetricsSnapshot,
            firmware: MetricsPacket?,
            settings: AppSettings,
            calibration: Calibration?,
        ): MetricsSnapshot {
            var base: MetricsSnapshot = if (settings.metricsSource == MetricsSource.FIRMWARE && firmware != null) {
                MetricsSnapshot(
                    tUs = firmware.tUs, hrBpm = firmware.hrBpm, spo2Pct = firmware.spo2Pct,
                    contactQuality = firmware.contactQuality, motion = firmware.motion,
                    patUs = firmware.patUs, sbpMmHg = firmware.sbpMmHg, dbpMmHg = firmware.dbpMmHg,
                    rpeak = firmware.rpeak,
                )
            } else {
                app
            }
            val cal = calibration
            val pat = base.patUs
            if (cal != null && pat != null) {
                val bp = predictBp(pat, cal)
                base = base.copy(sbpMmHg = bp.first.roundToLong().toDouble(), dbpMmHg = bp.second.roundToLong().toDouble())
            }
            return base
        }
    }
}
