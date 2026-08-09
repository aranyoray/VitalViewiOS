//
//  Packets.kt
//  MoniVitals (Android)
//
//  Typed representations of decoded BLE stream + control packets.
//  Ported from ios/MoniVitals/BLE/Packets.swift (== web/src/ble/packets.ts).
//
//  Note: `tUs` is mutable so the source layer can replace the raw uint32 device time
//  with an extended 64-bit-safe value (see Timebase).
//

package com.monivitals.ble

// MARK: - Stream packets

data class EcgPacket(
    val seq: Int,
    /** Device timestamp (µs) of the FIRST sample in the packet. */
    var tUs: Double,
    val sampleRateHz: Int,
    /** Signed ADC counts. */
    val samples: IntArray,
)

data class BiozPacket(
    val seq: Int,
    var tUs: Double,
    val sampleRateHz: Int,
    /** Baseline impedance (mΩ). */
    val z0Milliohm: Int,
    /** ΔZ samples. */
    val dz: IntArray,
)

data class PpgPacket(
    val seq: Int,
    var tUs: Double,
    val sampleRateHz: Int,
    /** Green / red / IR channels (18-bit data right-justified). */
    val green: LongArray,
    val red: LongArray,
    val ir: LongArray,
)

data class MetricsPacket(
    val tUs: Double,
    /** beats/min, null if invalid. */
    val hrBpm: Double?,
    /** percent (estimate), null if invalid. */
    val spo2Pct: Double?,
    val contactQuality: Int, // 0..100
    val motion: Int, // 0..255
    /** Pulse arrival time in microseconds, null if invalid. */
    val patUs: Double?,
    val sbpMmHg: Double?,
    val dbpMmHg: Double?,
    val rpeak: Boolean,
)

// MARK: - Control messages

data class StatusMessage(
    val streamingMask: Int,
    val ecgRateCode: Int,
    val biozRateCode: Int,
    val ppgRateCode: Int,
    val tUs: Double,
    val batteryPct: Int,
    val errorFlags: Int,
)

data class InfoMessage(
    val firmwareVersion: String, // "major.minor.patch"
    val deviceId: String, // hex
    val capabilities: Int,
)

data class ClockMessage(val tUs: Double)

/** A decoded control-characteristic message. */
sealed interface ControlMessage {
    data class Status(val msg: StatusMessage) : ControlMessage
    data class Info(val msg: InfoMessage) : ControlMessage
    data class Clock(val msg: ClockMessage) : ControlMessage
}
