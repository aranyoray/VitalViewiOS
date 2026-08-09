//
//  Timebase.kt
//  MoniVitals (Android)
//
//  Device-clock handling. `t_us` is a uint32 microsecond counter that wraps every
//  ≈71.6 min; the extender turns it into a monotonic 64-bit-safe value per stream.
//  See docs/BLE_PROTOCOL.md#clock-synchronization.
//
//  Ported from ios/MoniVitals/Source/Timebase.swift (== web/src/source/timebase.ts).
//

package com.monivitals.source

import com.monivitals.ble.StreamKind

private const val WRAP = 4_294_967_296.0 // 2^32

/** Extends a wrapping uint32 µs counter to a monotonically increasing value. */
class TimebaseExtender {
    private var epoch = 0.0
    private var lastRaw: Double? = null

    fun extend(raw: Double): Double {
        val last = lastRaw
        if (last != null && raw < last && last - raw > WRAP / 2) {
            epoch += 1 // a genuine wrap (large backward jump), not jitter
        }
        lastRaw = raw
        return epoch * WRAP + raw
    }

    fun reset() {
        epoch = 0.0
        lastRaw = null
    }
}

/** Per-stream sequence tracking to count dropped packets (seq is uint16). */
class SeqTracker {
    private var last: Int? = null
    var dropped = 0
        private set

    /** Update with a new packet seq; returns the number of packets dropped before it. */
    fun update(seq: Int): Int {
        val l = last
        if (l == null) {
            last = seq
            return 0
        }
        val gap = (seq - l - 1 + 0x10000) % 0x10000
        last = seq
        dropped += gap
        return gap
    }

    fun reset() {
        last = null
        dropped = 0
    }
}

/** Holds the per-stream extenders + trackers and the host↔device clock offset. */
class Timebase {
    val extenders: Map<StreamKind, TimebaseExtender> = mapOf(
        StreamKind.ECG to TimebaseExtender(),
        StreamKind.BIOZ to TimebaseExtender(),
        StreamKind.PPG to TimebaseExtender(),
    )
    val trackers: Map<StreamKind, SeqTracker> = mapOf(
        StreamKind.ECG to SeqTracker(),
        StreamKind.BIOZ to SeqTracker(),
        StreamKind.PPG to SeqTracker(),
    )

    /** offset = hostNowUs − deviceTus, set on SYNC_CLOCK. */
    var offsetUs: Double? = null

    fun setOffsetFromDevice(deviceTus: Double) {
        offsetUs = System.currentTimeMillis() * 1000.0 - deviceTus
    }

    fun reset() {
        for (k in StreamKind.allCases) {
            extenders[k]?.reset()
            trackers[k]?.reset()
        }
        offsetUs = null
    }
}
