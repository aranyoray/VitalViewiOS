//
//  Parsers.kt
//  MoniVitals (Android)
//
//  Binary → typed-packet parsers. Little-endian throughout. `K` (samples-per-packet) is
//  derived from the payload length so firmware may batch any count that fits.
//  See docs/BLE_PROTOCOL.md.
//
//  Ported from ios/MoniVitals/BLE/Parsers.swift (== web/src/ble/parsers.ts).
//

package com.monivitals.ble

/**
 * Little-endian reader over a ByteArray, mirroring the web `DataView` access pattern.
 * All `get*` calls assume the offset is within bounds (parsers derive K from length
 * first, exactly like the TypeScript/Swift implementations).
 */
class LEReader(private val data: ByteArray) {
    val byteLength: Int get() = data.size

    private fun byte(offset: Int): Int = data[offset].toInt() and 0xff

    fun getUInt8(offset: Int): Int = byte(offset)

    fun getUInt16(offset: Int): Int = byte(offset) or (byte(offset + 1) shl 8)

    fun getInt16(offset: Int): Int = getUInt16(offset).toShort().toInt()

    fun getUInt32(offset: Int): Long {
        return (byte(offset).toLong()) or
            (byte(offset + 1).toLong() shl 8) or
            (byte(offset + 2).toLong() shl 16) or
            (byte(offset + 3).toLong() shl 24)
    }

    fun getInt32(offset: Int): Int {
        return byte(offset) or
            (byte(offset + 1) shl 8) or
            (byte(offset + 2) shl 16) or
            (byte(offset + 3) shl 24)
    }
}

object Parsers {
    fun parseEcg(data: ByteArray): EcgPacket {
        val r = LEReader(data)
        val seq = r.getUInt16(0)
        val tUs = r.getUInt32(2).toDouble()
        val sampleRateHz = r.getUInt16(6)
        val k = maxOf(0, (r.byteLength - 8) shr 2)
        val samples = IntArray(k)
        for (i in 0 until k) {
            samples[i] = r.getInt32(8 + i * 4)
        }
        return EcgPacket(seq = seq, tUs = tUs, sampleRateHz = sampleRateHz, samples = samples)
    }

    fun parseBioz(data: ByteArray): BiozPacket {
        val r = LEReader(data)
        val seq = r.getUInt16(0)
        val tUs = r.getUInt32(2).toDouble()
        val sampleRateHz = r.getUInt16(6)
        val z0 = r.getInt32(8)
        val k = maxOf(0, (r.byteLength - 12) shr 2)
        val dz = IntArray(k)
        for (i in 0 until k) {
            dz[i] = r.getInt32(12 + i * 4)
        }
        return BiozPacket(seq = seq, tUs = tUs, sampleRateHz = sampleRateHz, z0Milliohm = z0, dz = dz)
    }

    fun parsePpg(data: ByteArray): PpgPacket {
        val r = LEReader(data)
        val seq = r.getUInt16(0)
        val tUs = r.getUInt32(2).toDouble()
        val sampleRateHz = r.getUInt16(6)
        val k = maxOf(0, (r.byteLength - 8) / 12)
        val green = LongArray(k)
        val red = LongArray(k)
        val ir = LongArray(k)
        for (i in 0 until k) {
            val o = 8 + i * 12
            green[i] = r.getUInt32(o)
            red[i] = r.getUInt32(o + 4)
            ir[i] = r.getUInt32(o + 8)
        }
        return PpgPacket(seq = seq, tUs = tUs, sampleRateHz = sampleRateHz, green = green, red = red, ir = ir)
    }

    fun parseMetrics(data: ByteArray): MetricsPacket {
        val r = LEReader(data)
        val tUs = r.getUInt32(0).toDouble()
        val hrRaw = r.getUInt16(4)
        val spo2Raw = r.getUInt16(6)
        val patRaw = r.getInt32(10)
        val sbpRaw = r.getInt16(14)
        val dbpRaw = r.getInt16(16)
        return MetricsPacket(
            tUs = tUs,
            hrBpm = if (hrRaw == BLEProtocol.Sentinel.u16) null else hrRaw / 10.0,
            spo2Pct = if (spo2Raw == BLEProtocol.Sentinel.u16) null else spo2Raw / 10.0,
            contactQuality = r.getUInt8(8),
            motion = r.getUInt8(9),
            patUs = if (patRaw == BLEProtocol.Sentinel.i32Min) null else patRaw.toDouble(),
            sbpMmHg = if (sbpRaw == BLEProtocol.Sentinel.i16Min) null else sbpRaw.toDouble(),
            dbpMmHg = if (dbpRaw == BLEProtocol.Sentinel.i16Min) null else dbpRaw.toDouble(),
            rpeak = r.getUInt16(18) != 0,
        )
    }

    /** Parse a control-characteristic notification, or null for unknown message types. */
    fun parseControl(data: ByteArray): ControlMessage? {
        val r = LEReader(data)
        return when (r.getUInt8(0)) {
            BLEProtocol.StatusMsg.STATUS -> ControlMessage.Status(
                StatusMessage(
                    streamingMask = r.getUInt8(1),
                    ecgRateCode = r.getUInt8(2),
                    biozRateCode = r.getUInt8(3),
                    ppgRateCode = r.getUInt8(4),
                    tUs = r.getUInt32(5).toDouble(),
                    batteryPct = r.getUInt8(9),
                    errorFlags = r.getUInt8(10),
                )
            )
            BLEProtocol.StatusMsg.INFO -> {
                val fw = "${r.getUInt8(1)}.${r.getUInt8(2)}.${r.getUInt8(3)}"
                val id = StringBuilder()
                for (i in 0 until 6) {
                    id.append(String.format("%02x", r.getUInt8(4 + i)))
                }
                ControlMessage.Info(
                    InfoMessage(
                        firmwareVersion = fw,
                        deviceId = id.toString(),
                        capabilities = r.getUInt16(10),
                    )
                )
            }
            BLEProtocol.StatusMsg.CLOCK -> ControlMessage.Clock(ClockMessage(tUs = r.getUInt32(1).toDouble()))
            else -> null
        }
    }
}
