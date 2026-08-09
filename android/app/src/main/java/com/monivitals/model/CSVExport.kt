//
//  CSVExport.kt
//  MoniVitals (Android)
//
//  CSV session export (docs/CSV_FORMAT.md). Pure builders (testable without a store) plus
//  a store-reading entry point that writes a shareable .zip bundle.
//
//  Mirrors ios/MoniVitals/Model/CSVExport.swift (== web/src/model/csv.ts). Column order is
//  fixed; blank numeric cells denote "invalid / not available" (not zero). Numbers are
//  formatted the JavaScript way (integers without a trailing ".0") so output is
//  byte-comparable with the web export. The web app emits a .zip; iOS writes a folder;
//  Android zips the same files (identical contents) for a single shareable artifact.
//

package com.monivitals.model

import android.content.Context
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.math.abs

/** Everything needed to build a session bundle. */
data class BundleData(
    val session: Session,
    val subject: Subject?,
    val calibration: Calibration?,
    val streams: SessionStreams,
    val metrics: List<MetricsRecord>,
    val annotations: List<Annotation>,
)

object CSVExport {
    private val prettyJson = Json { prettyPrint = true }

    // MARK: - number / field formatting

    /**
     * Format a Double like JavaScript's `String(number)`: integers have no decimals,
     * other values use the shortest round-tripping representation.
     */
    fun jsNumber(x: Double): String {
        if (x.isNaN()) return "NaN"
        if (x == Math.rint(x) && abs(x) < 1e15) {
            return x.toLong().toString()
        }
        var s = String.format(Locale.ROOT, "%.15g", x)
        if (s.contains(".")) {
            while (s.endsWith("0")) s = s.dropLast(1)
            if (s.endsWith(".")) s = s.dropLast(1)
        }
        return s
    }

    /** RFC-4180 field escaping; null → empty cell. */
    fun csvEscape(v: String?): String {
        if (v == null) return ""
        return if (v.contains(",") || v.contains("\"") || v.contains("\n")) {
            "\"" + v.replace("\"", "\"\"") + "\""
        } else {
            v
        }
    }

    fun csvEscape(v: Double?): String = if (v == null) "" else jsNumber(v)

    private fun toCsv(header: List<String>, rows: List<List<String>>): String {
        val lines = mutableListOf(header.joinToString(","))
        for (row in rows) lines.add(row.joinToString(","))
        return lines.joinToString("\n") + "\n"
    }

    // MARK: - session_meta.json

    fun buildSessionMeta(d: BundleData): String {
        val root = buildJsonObject {
            put("schemaVersion", 1)
            put("session", buildJsonObject {
                put("id", d.session.id)
                put("subjectCode", d.session.subjectCode)
                put("label", d.session.label.rawValue)
                put("deviceId", d.session.deviceId)
                put("firmwareVersion", d.session.firmwareVersion)
                put("startedAt", d.session.startedAt)
                if (d.session.endedAt != null) put("endedAt", d.session.endedAt) else put("endedAt", JsonNull)
                put("notes", d.session.notes)
                put("metricsSource", d.session.metricsSource.rawValue)
                put("gating", buildJsonObject {
                    put("motionThresh", d.session.gating.motionThresh)
                    put("contactThresh", d.session.gating.contactThresh)
                    put("windowMs", d.session.gating.windowMs)
                })
            })
            val subj = d.subject
            put("subject", if (subj != null) {
                buildJsonObject {
                    put("code", subj.code)
                    put("ageBand", subj.ageBand)
                    if (subj.sex != null) put("sex", subj.sex) else put("sex", JsonNull)
                    put("notes", subj.notes)
                }
            } else {
                buildJsonObject { put("code", d.session.subjectCode) }
            })
            val cal = d.calibration
            if (cal != null) {
                put("calibration", buildJsonObject {
                    put("model", cal.model.rawValue)
                    put("coeffs", buildJsonObject {
                        put("sbp", buildJsonArray { cal.coeffs.sbp.forEach { add(JsonPrimitive(it)) } })
                        put("dbp", buildJsonArray { cal.coeffs.dbp.forEach { add(JsonPrimitive(it)) } })
                    })
                    put("rmseSbp", cal.rmseSbp)
                    put("rmseDbp", cal.rmseDbp)
                    put("r", cal.r)
                    put("createdAt", cal.createdAt)
                })
            } else {
                put("calibration", JsonNull)
            }
        }
        return prettyJson.encodeToString(kotlinx.serialization.json.JsonObject.serializer(), root)
    }

    // MARK: - bundle files

    /** Build the in-memory bundle: filename → file contents. */
    fun buildBundleFiles(d: BundleData): List<Pair<String, String>> {
        val s = d.streams

        val ecgRows = mutableListOf<List<String>>()
        for (i in s.ecg.t.indices) {
            ecgRows.add(listOf(jsNumber(s.ecg.t[i]), s.ecg.ecg[i].toString()))
        }

        val biozRows = mutableListOf<List<String>>()
        for (i in s.bioz.t.indices) {
            biozRows.add(listOf(jsNumber(s.bioz.t[i]), s.bioz.z0[i].toString(), s.bioz.dz[i].toString()))
        }

        val ppgRows = mutableListOf<List<String>>()
        for (i in s.ppg.t.indices) {
            ppgRows.add(listOf(jsNumber(s.ppg.t[i]), s.ppg.green[i].toString(), s.ppg.red[i].toString(), s.ppg.ir[i].toString()))
        }

        val metricsRows = d.metrics.map { m ->
            listOf(
                jsNumber(m.tUs),
                csvEscape(m.hrBpm),
                csvEscape(m.spo2Pct),
                m.contactQuality.toString(),
                m.motion.toString(),
                if (m.patUs == null) "" else jsNumber(m.patUs / 1000),
                csvEscape(m.sbpMmHg),
                csvEscape(m.dbpMmHg),
            )
        }

        val annoRows = d.annotations.map { a ->
            listOf(jsNumber(a.tUs), csvEscape(a.type.rawValue), csvEscape(a.sbp), csvEscape(a.dbp), csvEscape(a.text))
        }

        return listOf(
            "session_meta.json" to buildSessionMeta(d),
            "ecg.csv" to toCsv(listOf("t_us", "ecg"), ecgRows),
            "bioz.csv" to toCsv(listOf("t_us", "z0_milliohm", "dz"), biozRows),
            "ppg.csv" to toCsv(listOf("t_us", "green", "red", "ir"), ppgRows),
            "metrics.csv" to toCsv(
                listOf("t_us", "hr_bpm", "spo2_pct", "contact_quality", "motion", "pat_ms", "sbp_est", "dbp_est"),
                metricsRows,
            ),
            "annotations.csv" to toCsv(listOf("t_us", "type", "sbp", "dbp", "text"), annoRows),
        )
    }

    /** The bundle base name: `<label>_<first 8 of id>`. */
    fun bundleFolderName(session: Session): String =
        "${session.label.rawValue}_${session.id.take(8)}"

    // MARK: - store-reading entry point

    /**
     * Read a session from the store and write a .zip bundle into the app cache.
     * Returns the zip File (share it via FileProvider), or null on failure.
     */
    fun exportSession(sessionId: String, context: Context, store: Store = Store.shared): File? {
        val session = store.getSession(sessionId) ?: return null
        val subject = store.getSubject(session.subjectCode)
        val streams = store.readSessionStreams(sessionId)
        val metrics = store.listMetrics(sessionId)
        val annotations = store.listAnnotations(sessionId)
        val files = buildBundleFiles(
            BundleData(
                session = session,
                subject = subject,
                calibration = session.calibrationSnapshot,
                streams = streams,
                metrics = metrics,
                annotations = annotations,
            )
        )

        val name = bundleFolderName(session)
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val zipFile = File(dir, "$name.zip")
        return try {
            ZipOutputStream(zipFile.outputStream().buffered()).use { zos ->
                for ((fname, content) in files) {
                    zos.putNextEntry(ZipEntry("$name/$fname"))
                    zos.write(content.toByteArray(Charsets.UTF_8))
                    zos.closeEntry()
                }
            }
            zipFile
        } catch (e: Exception) {
            null
        }
    }
}
