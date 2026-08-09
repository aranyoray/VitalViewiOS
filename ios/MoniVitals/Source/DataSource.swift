//
//  DataSource.swift
//  MoniVitals
//
//  The single interface that the UI talks to. The signal sources (ReplaySource, which
//  plays the bundled real recording, and MockSource, a synthetic generator) implement it,
//  so every screen works without hardware. Packets delivered to consumers carry EXTENDED
//  device timestamps (see Timebase.swift).
//
//  Mirrors web/src/source/DataSource.ts. Event delivery uses Combine subjects so the
//  AppModel can subscribe with backpressure-free sinks (the high-rate packet handlers
//  push into non-reactive ring buffers, not @Published state).
//

import Combine
import Foundation

/// Connection lifecycle, mirroring the web `ConnectionState` union.
enum ConnectionState: String {
    case disconnected
    case unsupported
    case scanning
    case connecting
    case connected
    case reconnecting
}

/// Optional detail attached to a connection-state change.
struct ConnectionDetail {
    var error: String?
}

/// Combine subjects a `DataSource` publishes on. The AppModel subscribes to these.
/// Subjects are `Void`-failing PassthroughSubjects (events only, no completion).
final class DataSourceEvents {
    let ecg = PassthroughSubject<EcgPacket, Never>()
    let bioz = PassthroughSubject<BiozPacket, Never>()
    let ppg = PassthroughSubject<PpgPacket, Never>()
    /// Source-provided reference metrics (optional; the app computes its own in parallel).
    let metrics = PassthroughSubject<MetricsPacket, Never>()
    let status = PassthroughSubject<StatusMessage, Never>()
    let info = PassthroughSubject<InfoMessage, Never>()
    let battery = PassthroughSubject<Int, Never>()
    /// (stream, newly dropped packet count) from seq gaps.
    let dropped = PassthroughSubject<(StreamKind, Int), Never>()
    let connection = PassthroughSubject<(ConnectionState, ConnectionDetail?), Never>()
}

/// The data-source abstraction implemented by `ReplaySource` (bundled real recording) and
/// `MockSource` (standalone synthetic source).
protocol DataSource: AnyObject {
    var isMock: Bool { get }
    var state: ConnectionState { get }
    /// offset = hostNowUs − deviceTus, or nil before SYNC_CLOCK.
    var clockOffsetUs: Double? { get }
    var deviceName: String? { get }

    /// The Combine event hub for this source.
    var events: DataSourceEvents { get }

    func connect()
    func disconnect()
    func start(streamMask: UInt8)
    func stop()
    func setRate(_ stream: StreamKind, hz: Int)
    func syncClock()
    func getInfo()
}

/// Shared base providing the event hub + connection-state plumbing.
class BaseDataSource: DataSource {
    let events = DataSourceEvents()
    private(set) var stateValue: ConnectionState = .disconnected

    var isMock: Bool { false }
    var clockOffsetUs: Double? { nil }
    var deviceName: String? { nil }

    var state: ConnectionState { stateValue }

    func setState(_ state: ConnectionState, detail: ConnectionDetail? = nil) {
        stateValue = state
        events.connection.send((state, detail))
    }

    // Subclasses override these.
    func connect() {}
    func disconnect() {}
    func start(streamMask: UInt8) {}
    func stop() {}
    func setRate(_ stream: StreamKind, hz: Int) {}
    func syncClock() {}
    func getInfo() {}
}
