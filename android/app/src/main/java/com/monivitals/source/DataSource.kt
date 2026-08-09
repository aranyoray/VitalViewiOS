//
//  DataSource.kt
//  MoniVitals (Android)
//
//  The single interface that the UI talks to. The replay source (real recorded biosignal)
//  and the synthetic mock source both implement it, so every screen works without hardware.
//  Packets delivered to consumers carry EXTENDED device timestamps (see Timebase).
//
//  Mirrors ios/MoniVitals/Source/DataSource.swift. Event delivery uses SharedFlow (the
//  Combine PassthroughSubject equivalent); handlers push high-rate samples into
//  non-reactive ring buffers rather than reactive state.
//

package com.monivitals.source

import com.monivitals.ble.BiozPacket
import com.monivitals.ble.EcgPacket
import com.monivitals.ble.InfoMessage
import com.monivitals.ble.MetricsPacket
import com.monivitals.ble.PpgPacket
import com.monivitals.ble.StatusMessage
import com.monivitals.ble.StreamKind
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow

/** Connection lifecycle, mirroring the web `ConnectionState` union. */
enum class ConnectionState {
    DISCONNECTED,
    UNSUPPORTED,
    SCANNING,
    CONNECTING,
    CONNECTED,
    RECONNECTING,
}

/** Optional detail attached to a connection-state change. */
data class ConnectionDetail(val error: String? = null)

private fun <T> streamFlow(): MutableSharedFlow<T> =
    MutableSharedFlow(extraBufferCapacity = 512, onBufferOverflow = BufferOverflow.DROP_OLDEST)

/**
 * SharedFlows a `DataSource` publishes on. The ViewModel collects these. Emission uses
 * `tryEmit` from any thread (BLE binder thread or timer thread), matching the buffered,
 * non-suspending semantics of a Combine PassthroughSubject.
 */
class DataSourceEvents {
    val ecg = streamFlow<EcgPacket>()
    val bioz = streamFlow<BiozPacket>()
    val ppg = streamFlow<PpgPacket>()

    /** Firmware-computed metrics (optional; the app computes its own in parallel). */
    val metrics = streamFlow<MetricsPacket>()
    val status = streamFlow<StatusMessage>()
    val info = streamFlow<InfoMessage>()
    val battery = streamFlow<Int>()

    /** (stream, newly dropped packet count) from seq gaps. */
    val dropped = streamFlow<Pair<StreamKind, Int>>()
    val connection = streamFlow<Pair<ConnectionState, ConnectionDetail?>>()
}

/** The data-source abstraction implemented by `ReplaySource` (real recorded biosignal) and
 *  `MockSource` (synthetic), so the app runs standalone with no hardware. */
interface DataSource {
    val isMock: Boolean
    val state: ConnectionState

    /** offset = hostNowUs − deviceTus, or null before SYNC_CLOCK. */
    val clockOffsetUs: Double?
    val deviceName: String?

    /** The event hub for this source. */
    val events: DataSourceEvents

    fun connect()
    fun disconnect()
    fun start(streamMask: Int)
    fun stop()
    fun setRate(stream: StreamKind, hz: Int)
    fun syncClock()
    fun getInfo()
}

/** Shared base providing the event hub + connection-state plumbing. */
abstract class BaseDataSource : DataSource {
    override val events = DataSourceEvents()

    private var stateValue: ConnectionState = ConnectionState.DISCONNECTED

    override val isMock: Boolean get() = false
    override val clockOffsetUs: Double? get() = null
    override val deviceName: String? get() = null

    override val state: ConnectionState get() = stateValue

    protected fun setState(state: ConnectionState, detail: ConnectionDetail? = null) {
        stateValue = state
        events.connection.tryEmit(state to detail)
    }

    // Subclasses override these.
    override fun connect() {}
    override fun disconnect() {}
    override fun start(streamMask: Int) {}
    override fun stop() {}
    override fun setRate(stream: StreamKind, hz: Int) {}
    override fun syncClock() {}
    override fun getInfo() {}
}
