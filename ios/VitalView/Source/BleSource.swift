//
//  BleSource.swift
//  VitalView
//
//  Live CoreBluetooth data source. Scans for the service UUID, connects, discovers the
//  stream characteristics, subscribes to notifications, parses them, extends device
//  timestamps, tracks dropped packets, writes control opcodes, and reconnects with
//  exponential backoff. See docs/BLE_PROTOCOL.md.
//
//  Mirrors web/src/source/BleSource.ts (which uses Web Bluetooth — unavailable on iOS,
//  which is exactly why this native source exists).
//

import CoreBluetooth
import Foundation

private let BACKOFF_MS: [Int] = [2000, 4000, 8000, 16000]

final class BleSource: BaseDataSource {
    override var isMock: Bool { false }
    private var _clockOffsetUs: Double? = nil
    override var clockOffsetUs: Double? { _clockOffsetUs }
    private var _deviceName: String? = nil
    override var deviceName: String? { _deviceName }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlChar: CBCharacteristic?
    private var batteryChar: CBCharacteristic?
    private let tb = Timebase()
    private var wantConnected = false
    private var lastStreamMask: UInt8 = 0
    private var reconnectAttempt = 0
    private var poweredOn = false
    private var pendingConnect = false
    private let bleQueue = DispatchQueue(label: "com.vitalview.blesource")

    private let delegateProxy = BleDelegateProxy()

    override init() {
        super.init()
        delegateProxy.owner = self
        central = CBCentralManager(delegate: delegateProxy, queue: bleQueue,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - DataSource

    override func connect() {
        wantConnected = true
        switch central.state {
        case .poweredOn:
            startScan()
        case .unsupported, .unauthorized:
            setState(.unsupported, detail: ConnectionDetail(error: "Bluetooth is not available on this device."))
        default:
            // Wait for centralManagerDidUpdateState to fire.
            pendingConnect = true
            setState(.scanning)
        }
    }

    override func disconnect() {
        wantConnected = false
        if let p = peripheral, let c = controlChar {
            p.writeValue(Data([BLEProtocol.Opcode.stop]), for: c, type: writeType(c))
        }
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        central.stopScan()
        setState(.disconnected)
    }

    override func start(streamMask: UInt8) {
        lastStreamMask = streamMask
        tb.reset()
        write(Data([BLEProtocol.Opcode.start, streamMask]))
    }

    override func stop() {
        write(Data([BLEProtocol.Opcode.stop]))
    }

    override func setRate(_ stream: StreamKind, hz: Int) {
        let code = UInt8(BLEProtocol.code(from: stream, hz: hz))
        write(Data([BLEProtocol.Opcode.setRate, BLEProtocol.streamId(stream), code]))
    }

    override func syncClock() {
        write(Data([BLEProtocol.Opcode.syncClock]))
    }

    override func getInfo() {
        write(Data([BLEProtocol.Opcode.getInfo]))
    }

    private func write(_ bytes: Data) {
        guard let p = peripheral, let c = controlChar else { return }
        p.writeValue(bytes, for: c, type: writeType(c))
    }

    private func writeType(_ c: CBCharacteristic) -> CBCharacteristicWriteType {
        c.properties.contains(.write) ? .withResponse : .withoutResponse
    }

    // MARK: - scanning / connecting

    private func startScan() {
        setState(.scanning)
        central.scanForPeripherals(withServices: [BLEProtocol.serviceUUID], options: nil)
    }

    fileprivate func handleStateUpdate() {
        poweredOn = central.state == .poweredOn
        if central.state == .unsupported || central.state == .unauthorized {
            setState(.unsupported, detail: ConnectionDetail(error: "Bluetooth is not available on this device."))
            return
        }
        if poweredOn && pendingConnect && wantConnected {
            pendingConnect = false
            startScan()
        }
    }

    fileprivate func handleDiscovered(_ peripheral: CBPeripheral) {
        // Connect to the first matching peripheral.
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = delegateProxy
        _deviceName = peripheral.name ?? "VitalView"
        setState(.connecting)
        central.connect(peripheral, options: nil)
    }

    fileprivate func handleConnected(_ peripheral: CBPeripheral) {
        peripheral.discoverServices([BLEProtocol.serviceUUID, BLEProtocol.batteryServiceUUID])
    }

    fileprivate func handleDisconnected() {
        controlChar = nil
        batteryChar = nil
        if !wantConnected { return }
        attemptReconnect()
    }

    private func attemptReconnect() {
        setState(.reconnecting)
        let wait = BACKOFF_MS[min(reconnectAttempt, BACKOFF_MS.count - 1)]
        reconnectAttempt += 1
        bleQueue.asyncAfter(deadline: .now() + .milliseconds(wait)) { [weak self] in
            guard let self, self.wantConnected else { return }
            if let p = self.peripheral {
                self.setState(.connecting)
                self.central.connect(p, options: nil)
            } else {
                self.startScan()
            }
        }
    }

    // MARK: - discovery

    fileprivate func handleServicesDiscovered(_ peripheral: CBPeripheral) {
        for service in peripheral.services ?? [] {
            if service.uuid == BLEProtocol.serviceUUID {
                peripheral.discoverCharacteristics([
                    BLEProtocol.CharUUID.control,
                    BLEProtocol.CharUUID.ecg,
                    BLEProtocol.CharUUID.bioz,
                    BLEProtocol.CharUUID.ppg,
                    BLEProtocol.CharUUID.metrics,
                ], for: service)
            } else if service.uuid == BLEProtocol.batteryServiceUUID {
                peripheral.discoverCharacteristics([BLEProtocol.batteryLevelUUID], for: service)
            }
        }
    }

    fileprivate func handleCharacteristicsDiscovered(_ peripheral: CBPeripheral, _ service: CBService) {
        for c in service.characteristics ?? [] {
            switch c.uuid {
            case BLEProtocol.CharUUID.control:
                controlChar = c
                peripheral.setNotifyValue(true, for: c)
            case BLEProtocol.CharUUID.ecg, BLEProtocol.CharUUID.bioz,
                 BLEProtocol.CharUUID.ppg, BLEProtocol.CharUUID.metrics:
                peripheral.setNotifyValue(true, for: c)
            case BLEProtocol.batteryLevelUUID:
                batteryChar = c
                peripheral.readValue(for: c)
                peripheral.setNotifyValue(true, for: c)
            default:
                break
            }
        }
        // Once the control characteristic is in place, finish the connection handshake.
        if service.uuid == BLEProtocol.serviceUUID, controlChar != nil {
            reconnectAttempt = 0
            setState(.connected)
            syncClock()
            getInfo()
            if lastStreamMask != 0 { start(streamMask: lastStreamMask) }
        }
    }

    // MARK: - notifications

    fileprivate func handleValue(_ characteristic: CBCharacteristic) {
        guard let value = characteristic.value else { return }
        switch characteristic.uuid {
        case BLEProtocol.CharUUID.ecg:
            var p = Parsers.parseEcg(value)
            events.dropped.send((.ecg, tb.trackers[.ecg]?.update(p.seq) ?? 0))
            p.tUs = tb.extenders[.ecg]?.extend(p.tUs) ?? p.tUs
            events.ecg.send(p)
        case BLEProtocol.CharUUID.bioz:
            var p = Parsers.parseBioz(value)
            events.dropped.send((.bioz, tb.trackers[.bioz]?.update(p.seq) ?? 0))
            p.tUs = tb.extenders[.bioz]?.extend(p.tUs) ?? p.tUs
            events.bioz.send(p)
        case BLEProtocol.CharUUID.ppg:
            var p = Parsers.parsePpg(value)
            events.dropped.send((.ppg, tb.trackers[.ppg]?.update(p.seq) ?? 0))
            p.tUs = tb.extenders[.ppg]?.extend(p.tUs) ?? p.tUs
            events.ppg.send(p)
        case BLEProtocol.CharUUID.metrics:
            events.metrics.send(Parsers.parseMetrics(value))
        case BLEProtocol.CharUUID.control:
            handleControl(value)
        case BLEProtocol.batteryLevelUUID:
            if let first = value.first { events.battery.send(Int(first)) }
        default:
            break
        }
    }

    private func handleControl(_ value: Data) {
        guard let msg = Parsers.parseControl(value) else { return }
        switch msg {
        case .clock(let m):
            tb.setOffsetFromDevice(m.tUs)
            _clockOffsetUs = tb.offsetUs
        case .status(let m):
            events.status.send(m)
            events.battery.send(m.batteryPct)
        case .info(let m):
            events.info.send(m)
        }
    }
}

// MARK: - Delegate proxy

/// Bridges the CoreBluetooth Objective-C delegate callbacks to the BleSource. Keeping
/// the conformance off `BleSource` itself avoids exposing CB delegate methods publicly.
private final class BleDelegateProxy: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var owner: BleSource?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        owner?.handleStateUpdate()
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        owner?.handleDiscovered(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        owner?.handleConnected(peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                         didFailToConnect peripheral: CBPeripheral,
                         error: Error?) {
        owner?.handleDisconnected()
    }

    func centralManager(_ central: CBCentralManager,
                         didDisconnectPeripheral peripheral: CBPeripheral,
                         error: Error?) {
        owner?.handleDisconnected()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        owner?.handleServicesDiscovered(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        owner?.handleCharacteristicsDiscovered(peripheral, service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        owner?.handleValue(characteristic)
    }
}
