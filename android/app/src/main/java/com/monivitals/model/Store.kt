//
//  Store.kt
//  MoniVitals (Android)
//
//  Dependency-light, local-first persistence (no cloud sync). Mirrors the responsibilities
//  of the web Dexie database and the iOS JSON-file Store, storing data as JSON files under
//  the app's private files directory:
//
//      <filesDir>/MoniVitals/
//        subjects.json          [Subject]
//        sessions.json          [Session]
//        calibrations.json      [Calibration]
//        annotations.json       [Annotation]
//        chunks/<sessionId>.json     [StreamChunk]   (high-rate sample blocks)
//        metrics/<sessionId>.json    [MetricsRecord]
//
//  Per-session sample data lives in its own file so listing/deleting sessions never
//  loads every waveform. All access is serialized on a lock.
//
//  Ported from ios/MoniVitals/Model/Store.swift.
//

package com.monivitals.model

import android.content.Context
import kotlinx.serialization.json.Json
import java.io.File

/** Concatenated, contiguous streams for a session (replay / export). */
class SessionStreams {
    class Ecg { val t = mutableListOf<Double>(); val ecg = mutableListOf<Int>() }
    class Bioz { val t = mutableListOf<Double>(); val z0 = mutableListOf<Int>(); val dz = mutableListOf<Int>() }
    class Ppg {
        val t = mutableListOf<Double>()
        val green = mutableListOf<Long>()
        val red = mutableListOf<Long>()
        val ir = mutableListOf<Long>()
    }

    val ecg = Ecg()
    val bioz = Bioz()
    val ppg = Ppg()
}

class Store private constructor(baseDir: File) {
    private val lock = Any()
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; prettyPrint = false }

    private val root = File(baseDir, "MoniVitals")
    private val chunksDir = File(root, "chunks")
    private val metricsDir = File(root, "metrics")

    init {
        root.mkdirs()
        chunksDir.mkdirs()
        metricsDir.mkdirs()
    }

    companion object {
        @Volatile private var instance: Store? = null

        fun init(context: Context) {
            if (instance == null) {
                synchronized(this) {
                    if (instance == null) instance = Store(context.filesDir)
                }
            }
        }

        val shared: Store
            get() = instance ?: error("Store.init(context) must be called before Store.shared")
    }

    // MARK: - file helpers

    private fun file(name: String) = File(root, name)

    private val subjectsList = ListSerializer(Subject.serializer())
    private val sessionsList = ListSerializer(Session.serializer())
    private val calibsList = ListSerializer(Calibration.serializer())
    private val annosList = ListSerializer(Annotation.serializer())
    private val chunksList = ListSerializer(StreamChunk.serializer())
    private val metricsList = ListSerializer(MetricsRecord.serializer())

    private fun <T> load(f: File, serializer: kotlinx.serialization.KSerializer<List<T>>, def: List<T>): List<T> {
        if (!f.exists()) return def
        return try {
            json.decodeFromString(serializer, f.readText())
        } catch (e: Exception) {
            def
        }
    }

    private fun <T> save(value: List<T>, serializer: kotlinx.serialization.KSerializer<List<T>>, f: File) {
        try {
            val tmp = File(f.parentFile, f.name + ".tmp")
            tmp.writeText(json.encodeToString(serializer, value))
            tmp.renameTo(f)
        } catch (e: Exception) {
            // best-effort local store
        }
    }

    private fun nextId(items: List<Int?>): Int = (items.mapNotNull { it }.maxOrNull() ?: 0) + 1

    // MARK: - Subjects

    fun upsertSubject(s: Subject) = synchronized(lock) {
        val all = load(file("subjects.json"), subjectsList, emptyList()).toMutableList()
        all.removeAll { it.code == s.code }
        all.add(s)
        save(all, subjectsList, file("subjects.json"))
    }

    /** Subjects, newest first (by createdAt). */
    fun listSubjects(): List<Subject> = synchronized(lock) {
        load(file("subjects.json"), subjectsList, emptyList()).sortedByDescending { it.createdAt }
    }

    fun getSubject(code: String): Subject? = synchronized(lock) {
        load(file("subjects.json"), subjectsList, emptyList()).firstOrNull { it.code == code }
    }

    fun deleteSubject(code: String) {
        // Delete the subject's sessions + calibrations, then the subject.
        val sessions = listSessions().filter { it.subjectCode == code }
        for (s in sessions) deleteSession(s.id)
        synchronized(lock) {
            val cals = load(file("calibrations.json"), calibsList, emptyList()).toMutableList()
            cals.removeAll { it.subjectCode == code }
            save(cals, calibsList, file("calibrations.json"))
            val subs = load(file("subjects.json"), subjectsList, emptyList()).toMutableList()
            subs.removeAll { it.code == code }
            save(subs, subjectsList, file("subjects.json"))
        }
    }

    // MARK: - Sessions

    fun createSession(s: Session) = synchronized(lock) {
        val all = load(file("sessions.json"), sessionsList, emptyList()).toMutableList()
        all.removeAll { it.id == s.id }
        all.add(s)
        save(all, sessionsList, file("sessions.json"))
    }

    fun endSession(id: String, endedAt: String) = synchronized(lock) {
        val all = load(file("sessions.json"), sessionsList, emptyList()).toMutableList()
        val idx = all.indexOfFirst { it.id == id }
        if (idx >= 0) {
            all[idx] = all[idx].copy(endedAt = endedAt)
            save(all, sessionsList, file("sessions.json"))
        }
    }

    fun getSession(id: String): Session? = synchronized(lock) {
        load(file("sessions.json"), sessionsList, emptyList()).firstOrNull { it.id == id }
    }

    /** Sessions, newest first (by startedAt). */
    fun listSessions(): List<Session> = synchronized(lock) {
        load(file("sessions.json"), sessionsList, emptyList()).sortedByDescending { it.startedAt }
    }

    fun deleteSession(id: String) = synchronized(lock) {
        val sessions = load(file("sessions.json"), sessionsList, emptyList()).toMutableList()
        sessions.removeAll { it.id == id }
        save(sessions, sessionsList, file("sessions.json"))
        val annos = load(file("annotations.json"), annosList, emptyList()).toMutableList()
        annos.removeAll { it.sessionId == id }
        save(annos, annosList, file("annotations.json"))
        File(chunksDir, "$id.json").delete()
        File(metricsDir, "$id.json").delete()
    }

    // MARK: - Annotations

    fun addAnnotation(a: Annotation): Int = synchronized(lock) {
        val all = load(file("annotations.json"), annosList, emptyList()).toMutableList()
        val item = a.copy(id = nextId(all.map { it.id }))
        all.add(item)
        save(all, annosList, file("annotations.json"))
        item.id!!
    }

    fun listAnnotations(sessionId: String): List<Annotation> = synchronized(lock) {
        load(file("annotations.json"), annosList, emptyList())
            .filter { it.sessionId == sessionId }
            .sortedBy { it.tUs }
    }

    // MARK: - Calibrations

    fun saveCalibration(c: Calibration): Int = synchronized(lock) {
        val all = load(file("calibrations.json"), calibsList, emptyList()).toMutableList()
        val item = c.copy(id = nextId(all.map { it.id }))
        all.add(item)
        save(all, calibsList, file("calibrations.json"))
        item.id!!
    }

    fun latestCalibration(subjectCode: String): Calibration? = listCalibrations(subjectCode).lastOrNull()

    fun listCalibrations(subjectCode: String): List<Calibration> = synchronized(lock) {
        load(file("calibrations.json"), calibsList, emptyList())
            .filter { it.subjectCode == subjectCode }
            .sortedBy { it.createdAt }
    }

    // MARK: - Metrics

    fun addMetrics(m: MetricsRecord) = synchronized(lock) {
        val f = File(metricsDir, "${m.sessionId}.json")
        val all = load(f, metricsList, emptyList()).toMutableList()
        val item = m.copy(id = nextId(all.map { it.id }))
        all.add(item)
        save(all, metricsList, f)
    }

    fun listMetrics(sessionId: String): List<MetricsRecord> = synchronized(lock) {
        val f = File(metricsDir, "$sessionId.json")
        load(f, metricsList, emptyList()).sortedBy { it.tUs }
    }

    // MARK: - Stream chunks

    fun addChunk(chunk: StreamChunk) = synchronized(lock) {
        val f = File(chunksDir, "${chunk.sessionId}.json")
        val all = load(f, chunksList, emptyList()).toMutableList()
        val item = chunk.copy(id = nextId(all.map { it.id }))
        all.add(item)
        save(all, chunksList, f)
    }

    private fun chunks(sessionId: String): List<StreamChunk> {
        val f = File(chunksDir, "$sessionId.json")
        return load(f, chunksList, emptyList()).sortedBy { it.tStartUs }
    }

    /** Concatenate stored chunks back into contiguous per-stream arrays. */
    fun readSessionStreams(sessionId: String): SessionStreams = synchronized(lock) {
        val all = chunks(sessionId)
        val out = SessionStreams()
        for (c in all.filter { it.stream == com.monivitals.ble.StreamKind.ECG }) {
            out.ecg.t += c.t
            out.ecg.ecg += c.ecg ?: emptyList()
        }
        for (c in all.filter { it.stream == com.monivitals.ble.StreamKind.BIOZ }) {
            out.bioz.t += c.t
            out.bioz.z0 += c.z0 ?: emptyList()
            out.bioz.dz += c.dz ?: emptyList()
        }
        for (c in all.filter { it.stream == com.monivitals.ble.StreamKind.PPG }) {
            out.ppg.t += c.t
            out.ppg.green += c.green ?: emptyList()
            out.ppg.red += c.red ?: emptyList()
            out.ppg.ir += c.ir ?: emptyList()
        }
        out
    }

    /** Wipe every stored table (Settings → data management). */
    fun deleteAllData() = synchronized(lock) {
        for (name in listOf("subjects.json", "sessions.json", "calibrations.json", "annotations.json")) {
            file(name).delete()
        }
        chunksDir.deleteRecursively()
        metricsDir.deleteRecursively()
        chunksDir.mkdirs()
        metricsDir.mkdirs()
    }

    // Exposed for the CSV exporter (single-source access to the per-session dirs).
    internal fun chunksDir() = chunksDir
    internal fun metricsDir() = metricsDir
}

private fun <T> ListSerializer(elem: kotlinx.serialization.KSerializer<T>) =
    kotlinx.serialization.builtins.ListSerializer(elem)
