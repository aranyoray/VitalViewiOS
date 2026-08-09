//
//  Models.kt
//  MoniVitals (Android)
//
//  Local-first data model. Subjects are identified only by a non-PII code.
//  Mirrors ios/MoniVitals/Model/Models.swift (== web/src/model/types.ts). All persisted
//  types are @Serializable (the kotlinx.serialization equivalent of Codable).
//

package com.monivitals.model

import com.monivitals.ble.StreamKind
import com.monivitals.dsp.BpCoeffs
import com.monivitals.dsp.CalibCoeffs
import com.monivitals.dsp.CalibModel
import com.monivitals.dsp.DSPConstants
import com.monivitals.dsp.RefPair
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class SessionLabel {
    @SerialName("rest") REST,
    @SerialName("seated") SEATED,
    @SerialName("walking") WALKING,
    @SerialName("post-exercise") POST_EXERCISE,
    @SerialName("other") OTHER;

    val rawValue: String
        get() = when (this) {
            REST -> "rest"
            SEATED -> "seated"
            WALKING -> "walking"
            POST_EXERCISE -> "post-exercise"
            OTHER -> "other"
        }

    companion object {
        val allCases = listOf(REST, SEATED, WALKING, POST_EXERCISE, OTHER)
    }
}

@Serializable
enum class AnnotationType {
    @SerialName("cuff_reading") CUFF_READING,
    @SerialName("motion_start") MOTION_START,
    @SerialName("motion_stop") MOTION_STOP,
    @SerialName("artifact") ARTIFACT,
    @SerialName("marker") MARKER;

    val rawValue: String
        get() = when (this) {
            CUFF_READING -> "cuff_reading"
            MOTION_START -> "motion_start"
            MOTION_STOP -> "motion_stop"
            ARTIFACT -> "artifact"
            MARKER -> "marker"
        }
}

@Serializable
enum class MetricsSource {
    @SerialName("app") APP,
    @SerialName("firmware") FIRMWARE;

    /** On-disk serialization value — MUST stay stable for stored sessions/settings. */
    val rawValue: String get() = if (this == APP) "app" else "firmware"

    /** User-facing label (no protocol jargon leaked to the UI). */
    val displayName: String get() = if (this == APP) "On-device model" else "Reference"
}

/** A study subject, identified only by a non-identifying code. */
@Serializable
data class Subject(
    val code: String, // primary key, non-identifying
    val ageBand: String,
    val sex: String? = null,
    val notes: String = "",
    val createdAt: String, // ISO-8601
) {
    val id: String get() = code
}

/** Gating thresholds captured per session. */
@Serializable
data class GatingConfig(
    val motionThresh: Double,
    val contactThresh: Double,
    val windowMs: Double,
)

/** A recording session. */
@Serializable
data class Session(
    val id: String,
    val subjectCode: String,
    val label: SessionLabel,
    val deviceId: String,
    val firmwareVersion: String,
    val startedAt: String,
    val endedAt: String? = null,
    val notes: String = "",
    val metricsSource: MetricsSource,
    val gating: GatingConfig,
    /** Calibration snapshot at session start (or null). */
    val calibrationSnapshot: Calibration? = null,
)

/**
 * One stored block of samples; timestamps are explicit (extended device µs).
 * Per-sample arrays are stored as lists so the class is serializable.
 */
@Serializable
data class StreamChunk(
    val id: Int? = null,
    val sessionId: String,
    val stream: StreamKind,
    val tStartUs: Double,
    val sampleRateHz: Int,
    /** Per-sample device timestamps (µs). */
    val t: List<Double>,
    /** ECG only. */
    val ecg: List<Int>? = null,
    /** BioZ only (z0 forward-filled per sample). */
    val z0: List<Int>? = null,
    val dz: List<Int>? = null,
    /** PPG only. */
    val green: List<Long>? = null,
    val red: List<Long>? = null,
    val ir: List<Long>? = null,
)

/** A persisted metrics row. */
@Serializable
data class MetricsRecord(
    val id: Int? = null,
    val sessionId: String,
    val tUs: Double,
    val hrBpm: Double? = null,
    val spo2Pct: Double? = null,
    val contactQuality: Int,
    val motion: Int,
    val patUs: Double? = null,
    val sbpMmHg: Double? = null,
    val dbpMmHg: Double? = null,
)

/** A timestamped annotation (markers + cuff readings). */
@Serializable
data class Annotation(
    val id: Int? = null,
    val sessionId: String,
    val tUs: Double,
    val type: AnnotationType,
    val sbp: Double? = null,
    val dbp: Double? = null,
    val text: String? = null,
)

/**
 * A stored per-subject PAT→BP calibration. Implements `CalibCoeffs` so `predictBp` can
 * run directly on it.
 */
@Serializable
data class Calibration(
    val id: Int? = null,
    val subjectCode: String,
    override val model: CalibModel,
    override val coeffs: BpCoeffs,
    val referencePairs: List<RefPair>,
    val rmseSbp: Double,
    val rmseDbp: Double,
    val r: Double,
    val createdAt: String,
) : CalibCoeffs

/** App settings (persisted as JSON). */
@Serializable
data class AppSettings(
    val metricsSource: MetricsSource = MetricsSource.APP,
    val motionThresh: Double = DSPConstants.motionThresh,
    val contactThresh: Double = DSPConstants.contactThresh,
    val gatingWindowMs: Double = DSPConstants.motionWindowMs,
    val calibModel: CalibModel = CalibModel.LINEAR_INV_PAT,
    val streamRates: Map<StreamKind, Int> = mapOf(
        StreamKind.ECG to 256,
        StreamKind.BIOZ to 64,
        StreamKind.PPG to 100,
    ),
    val theme: Theme = Theme.LIGHT,
    val consentAccepted: Boolean = false,
    val disclaimerAcknowledged: Boolean = false,
) {
    @Serializable
    enum class Theme {
        @SerialName("dark") DARK,
        @SerialName("light") LIGHT,
        @SerialName("system") SYSTEM,
    }
}
