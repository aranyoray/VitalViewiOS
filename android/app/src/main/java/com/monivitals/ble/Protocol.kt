//
//  Protocol.kt
//  MoniVitals (Android)
//
//  BLE GATT protocol constants — the single source of truth is docs/BLE_PROTOCOL.md.
//  Firmware, web app, iOS app, and this Android app must all agree with that document.
//  All multi-byte fields are little-endian.
//
//  Ported from ios/MoniVitals/BLE/Protocol.swift (== web/src/ble/protocol.ts).
//

package com.monivitals.ble

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID
import kotlin.math.abs

/** Stream kinds carried over their own characteristics. */
@Serializable
enum class StreamKind {
    @SerialName("ecg") ECG,
    @SerialName("bioz") BIOZ,
    @SerialName("ppg") PPG;

    companion object {
        val allCases: List<StreamKind> = listOf(ECG, BIOZ, PPG)
    }
}

object BLEProtocol {
    /** Base 128-bit service UUID. */
    val serviceUUID: UUID = UUID.fromString("f0010000-1a2b-4c3d-8e5f-000000000000")

    /** Characteristic UUIDs keyed by purpose. */
    object CharUUID {
        val control: UUID = UUID.fromString("f0010001-1a2b-4c3d-8e5f-000000000000")
        val ecg: UUID = UUID.fromString("f0010002-1a2b-4c3d-8e5f-000000000000")
        val bioz: UUID = UUID.fromString("f0010003-1a2b-4c3d-8e5f-000000000000")
        val ppg: UUID = UUID.fromString("f0010004-1a2b-4c3d-8e5f-000000000000")
        val metrics: UUID = UUID.fromString("f0010005-1a2b-4c3d-8e5f-000000000000")
    }

    /** Standard Battery Service (16-bit UUIDs expanded to their 128-bit form). */
    val batteryServiceUUID: UUID = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")
    val batteryLevelUUID: UUID = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")

    /** Client Characteristic Configuration Descriptor (for enabling notifications). */
    val cccdUUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    /** Control characteristic opcodes (first payload byte on write). */
    object Opcode {
        const val START: Byte = 0x01
        const val STOP: Byte = 0x02
        const val SET_RATE: Byte = 0x03
        const val SYNC_CLOCK: Byte = 0x04
        const val GET_INFO: Byte = 0x05
    }

    /** Status notification message types (first payload byte). */
    object StatusMsg {
        const val STATUS: Int = 0x10
        const val INFO: Int = 0x11
        const val CLOCK: Int = 0x12
    }

    /** Stream ids (used in SET_RATE and conceptually in the START bitmask). */
    fun streamId(stream: StreamKind): Byte = when (stream) {
        StreamKind.ECG -> 0
        StreamKind.BIOZ -> 1
        StreamKind.PPG -> 2
    }

    /** START bitmask bit for a stream. */
    fun streamBit(stream: StreamKind): Int = when (stream) {
        StreamKind.ECG -> 0x01
        StreamKind.BIOZ -> 0x02
        StreamKind.PPG -> 0x04
    }

    const val allStreamsMask: Int = 0x01 or 0x02 or 0x04

    /** Rate-code → Hz tables, per docs/BLE_PROTOCOL.md. */
    fun rateCodes(stream: StreamKind): List<Int> = when (stream) {
        StreamKind.ECG -> listOf(128, 256, 512)
        StreamKind.BIOZ -> listOf(32, 64, 128)
        StreamKind.PPG -> listOf(50, 100, 200, 400)
    }

    /** Default sample rate (Hz) per stream. */
    fun defaultRateHz(stream: StreamKind): Int = when (stream) {
        StreamKind.ECG -> 256
        StreamKind.BIOZ -> 64
        StreamKind.PPG -> 100
    }

    /** Default samples-per-packet used by the firmware / mock encoder (parsers derive K). */
    fun defaultK(stream: StreamKind): Int = when (stream) {
        StreamKind.ECG -> 20
        StreamKind.BIOZ -> 16
        StreamKind.PPG -> 12
    }

    /** Error-flag bits in the STATUS message. */
    object ErrorFlag {
        const val leadOff: Int = 0x01
        const val ppgSaturation: Int = 0x02
        const val bufferOverflow: Int = 0x04
    }

    /** Invalid sentinels used in the metrics packet. */
    object Sentinel {
        const val u16: Int = 0xffff
        const val i32Min: Int = -2_147_483_648
        const val i16Min: Int = -32_768
    }

    /** Resolve a rate code to Hz, falling back to the stream default. */
    fun rate(stream: StreamKind, code: Int): Int {
        val codes = rateCodes(stream)
        return if (code in codes.indices) codes[code] else defaultRateHz(stream)
    }

    /** Resolve a Hz value to its rate code (nearest match), for SET_RATE. */
    fun code(stream: StreamKind, hz: Int): Int {
        val codes = rateCodes(stream)
        var best = 0
        var bestErr = Int.MAX_VALUE
        for (i in codes.indices) {
            val err = abs(codes[i] - hz)
            if (err < bestErr) {
                bestErr = err
                best = i
            }
        }
        return best
    }
}
