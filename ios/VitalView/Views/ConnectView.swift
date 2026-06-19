//
//  ConnectView.swift
//  VitalView
//
//  Choose Mock vs BLE, show connection status, battery, and dropped-packet counts.
//  Mirrors the web Connect screen. Mock mode makes every other screen reachable without
//  hardware.
//

import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("Data source") {
                    Button {
                        model.connectMock()
                    } label: {
                        Label("Connect Mock device", systemImage: "cpu")
                    }
                    Button {
                        model.connectBle()
                    } label: {
                        Label("Scan for BLE device", systemImage: "dot.radiowaves.left.and.right")
                    }
                    if model.connectionState != .disconnected {
                        Button(role: .destructive) {
                            model.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    }
                }

                Section("Status") {
                    LabeledContent("Connection") { ConnectionPill(state: model.connectionState) }
                    LabeledContent("Device", value: model.deviceName ?? "—")
                    LabeledContent("Source", value: model.isMock ? "Mock" : "Bluetooth")
                    LabeledContent("Battery", value: model.batteryPct.map { "\($0)%" } ?? "—")
                    LabeledContent("Clock offset") {
                        Text(model.clockOffsetUs == nil ? "not synced" : "synced")
                            .foregroundStyle(.secondary)
                    }
                    if model.errorFlags != 0 {
                        LabeledContent("Device flags") {
                            Text(errorFlagText).foregroundStyle(.orange)
                        }
                    }
                }

                Section("Streaming") {
                    if model.streaming {
                        Button(role: .destructive) { model.stopStreaming() } label: {
                            Label("Stop streaming", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            model.startStreaming()
                        } label: {
                            Label("Start streaming", systemImage: "play.fill")
                        }
                        .disabled(model.connectionState != .connected)
                    }
                }

                Section("Link quality (dropped packets)") {
                    LabeledContent("ECG", value: "\(model.dropped[.ecg] ?? 0)")
                    LabeledContent("BioZ", value: "\(model.dropped[.bioz] ?? 0)")
                    LabeledContent("PPG", value: "\(model.dropped[.ppg] ?? 0)")
                }

                if model.connectionState == .unsupported {
                    Section {
                        Text("Bluetooth is unavailable or not permitted on this device. You can still use Mock mode to explore every screen.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Connect")
        }
    }

    private var errorFlagText: String {
        var parts: [String] = []
        if model.errorFlags & BLEProtocol.ErrorFlag.leadOff != 0 { parts.append("lead-off") }
        if model.errorFlags & BLEProtocol.ErrorFlag.ppgSaturation != 0 { parts.append("PPG saturation") }
        if model.errorFlags & BLEProtocol.ErrorFlag.bufferOverflow != 0 { parts.append("buffer overflow") }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }
}
