//
//  Encoders.kt
//  MoniVitals (Android)
//
//  Typed-packet → binary encoders. Used by round-trip parser tests and available for a
//  firmware-identical byte path. Little-endian throughout.
//
//  Ported from ios/MoniVitals/BLE/Encoders.swift (== web/src/ble/encoders.ts).
//

package com.monivitals.ble

import kotlin.math.roundToInt
import kotlin.math.roundToLong

/** Little-endian byte writer, mirroring the web `DataView` set* pattern. */
class LEWriter(capacity: Int) {
    val data: ByteArray = ByteArray(capacity)

    fun setUInt8(offset: Int, value: Int) {
        data[offset] = (value and 0xff).toByte()
    }

    fun setUInt16(offset: Int, value: Int) {
        setUInt8(offset, value and 0xff)
        setUInt8(offset + 1, (value shr 8) and 0xff)
    }

    fun setInt16(offset: Int, value: Int) = setUInt16(offset, value and 0xffff)

    fun setUInt32(offset: Int, value: Long) {
        setUInt8(offset, (value and 0xff).toInt())
        setUInt8(offset + 1, ((value shr 8) and 0xff).toInt())
        setUInt8(offset + 2, ((value shr 16) and 0xff).toInt())
        setUInt8(offset + 3, ((value shr 24) and 0xff).toInt())
    }

    fun setInt32(offset: Int, value: Int) = setUInt32(offset, value.toLong() and 0xffffffffL)
}

object Encoders {
    /** uint32 truncation matching JS `x >>> 0` on a Double timestamp. */
    private fun u32(tUs: Double): Long = tUs.toLong() and 0xffffffffL

    fun encodeEcg(p: EcgPacket): ByteArray {
        val w = LEWriter(8 + p.samples.size * 4)
        w.setUInt16(0, p.seq and 0xffff)
        w.setUInt32(2, u32(p.tUs))
        w.setUInt16(6, p.sampleRateHz)
        for (i in p.samples.indices) w.setInt32(8 + i * 4, p.samples[i])
        return w.data
    }

    fun encodeBioz(p: BiozPacket): ByteArray {
        val w = LEWriter(12 + p.dz.size * 4)
        w.setUInt16(0, p.seq and 0xffff)
        w.setUInt32(2, u32(p.tUs))
        w.setUInt16(6, p.sampleRateHz)
        w.setInt32(8, p.z0Milliohm)
        for (i in p.dz.indices) w.setInt32(12 + i * 4, p.dz[i])
        return w.data
    }

    fun encodePpg(p: PpgPacket): ByteArray {
        val k = p.green.size
        val w = LEWriter(8 + k * 12)
        w.setUInt16(0, p.seq and 0xffff)
        w.setUInt32(2, u32(p.tUs))
        w.setUInt16(6, p.sampleRateHz)
        for (i in 0 until k) {
            val o = 8 + i * 12
            w.setUInt32(o, p.green[i])
            w.setUInt32(o + 4, p.red[i])
            w.setUInt32(o + 8, p.ir[i])
        }
        return w.data
    }

    fun encodeMetrics(p: MetricsPacket): ByteArray {
        val w = LEWriter(20)
        w.setUInt32(0, u32(p.tUs))
        w.setUInt16(4, if (p.hrBpm == null) BLEProtocol.Sentinel.u16 else (p.hrBpm * 10).roundToInt())
        w.setUInt16(6, if (p.spo2Pct == null) BLEProtocol.Sentinel.u16 else (p.spo2Pct * 10).roundToInt())
        w.setUInt8(8, p.contactQuality and 0xff)
        w.setUInt8(9, p.motion and 0xff)
        w.setInt32(10, if (p.patUs == null) BLEProtocol.Sentinel.i32Min else p.patUs.roundToInt())
        w.setInt16(14, if (p.sbpMmHg == null) BLEProtocol.Sentinel.i16Min else p.sbpMmHg.roundToInt())
        w.setInt16(16, if (p.dbpMmHg == null) BLEProtocol.Sentinel.i16Min else p.dbpMmHg.roundToInt())
        w.setUInt16(18, if (p.rpeak) 0x01 else 0x00)
        return w.data
    }

    fun encodeStatus(m: StatusMessage): ByteArray {
        val w = LEWriter(11)
        w.setUInt8(0, BLEProtocol.StatusMsg.STATUS)
        w.setUInt8(1, m.streamingMask)
        w.setUInt8(2, m.ecgRateCode)
        w.setUInt8(3, m.biozRateCode)
        w.setUInt8(4, m.ppgRateCode)
        w.setUInt32(5, u32(m.tUs))
        w.setUInt8(9, m.batteryPct)
        w.setUInt8(10, m.errorFlags)
        return w.data
    }

    fun encodeInfo(m: InfoMessage): ByteArray {
        val w = LEWriter(12)
        w.setUInt8(0, BLEProtocol.StatusMsg.INFO)
        val parts = m.firmwareVersion.split(".").map { it.toIntOrNull() ?: 0 }
        w.setUInt8(1, if (parts.size > 0) parts[0] else 0)
        w.setUInt8(2, if (parts.size > 1) parts[1] else 0)
        w.setUInt8(3, if (parts.size > 2) parts[2] else 0)
        val chars = m.deviceId.toCharArray()
        for (i in 0 until 6) {
            val start = i * 2
            var byteVal = 0
            if (start + 1 < chars.size) {
                val pair = "" + chars[start] + chars[start + 1]
                byteVal = pair.toIntOrNull(16) ?: 0
            }
            w.setUInt8(4 + i, byteVal)
        }
        w.setUInt16(10, m.capabilities)
        return w.data
    }

    // roundToLong kept available for callers that need 64-bit rounding parity.
    @Suppress("unused")
    private fun rl(x: Double): Long = x.roundToLong()
}
