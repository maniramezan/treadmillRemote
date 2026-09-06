import SwiftUI

struct SettingsInspectorView: View {
    @Bindable var manager: TreadmillManager

    var body: some View {
        Form {
            Section {
                Button {
                    Haptics.medium()
                    manager.scan()
                } label: {
                    Label(manager.connectionState == .scanning ? "Scanning..." : "Scan Nearby BLE Devices", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(manager.connectionState == .scanning)

                if manager.nearbyPeripherals.isEmpty {
                    Text("No peripherals discovered yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.nearbyPeripherals) { peripheral in
                        Button {
                            Haptics.light()
                            manager.connect(to: peripheral.id)
                        } label: {
                            PeripheralRow(peripheral: peripheral)
                        }
                        .tint(.primary)
                    }
                }
            } header: {
                Text("Nearby Devices")
            } footer: {
                Text("Candidates are limited to recognizable treadmill names, the configured service (\(manager.configuration.serviceUUID)), or the standard Fitness Machine Service (0x1826). Verify the name and GATT services before sending commands.")
            }

            Section("Target UUIDs") {
                UUIDField(title: "Service", text: $manager.configuration.serviceUUID)
                UUIDField(title: "Write characteristic", text: $manager.configuration.writeCharacteristicUUID)
                UUIDField(title: "Notify characteristic", text: $manager.configuration.notifyCharacteristicUUID)
                Picker("Checksum", selection: $manager.configuration.checksumMode) {
                    ForEach(ChecksumMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                TextField("Speed scale", value: $manager.configuration.speedScale, format: .number)
                    .keyboardType(.decimalPad)
                Text("Speed is encoded as an integer after multiplying by this scale. The default is hundredths (100).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                CommandEditor(title: "Start", text: $manager.configuration.startHex)
                CommandEditor(title: "Pause", text: $manager.configuration.pauseHex)
                CommandEditor(title: "Stop", text: $manager.configuration.stopHex)
                CommandEditor(title: "Speed set", text: $manager.configuration.speedHex)
            } header: {
                Text("Command Frames")
            } footer: {
                Text("FitShow frames use 02 header, 03 footer, and XOR checksum over the payload. This app uses control code 0A for pause. Speed frames can use {{SPEED}}, {{SPEED_LO}}, {{SPEED_HI}}, and {{CHECKSUM}} placeholders.")
            }

            Section("Discovered GATT") {
                if manager.gattServices.isEmpty {
                    Text("Connect to a peripheral to inspect services and characteristics.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.gattServices) { service in
                        GATTServiceRow(service: service)
                    }
                }
            }

            Section {
                Button("Restore Default Configuration", role: .destructive) {
                    manager.resetConfiguration()
                }
            }
        }
        .navigationTitle("Settings / GATT")
        .navigationBarTitleDisplayMode(.inline)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
    }
}

private struct PeripheralRow: View {
    let peripheral: DiscoveredPeripheral

    var body: some View {
        HStack {
            Image(systemName: "wave.3.right.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(peripheral.name)
                    .font(.headline)
                Text(peripheral.id.uuidString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(peripheral.matchReason)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                if !peripheral.advertisedServices.isEmpty {
                    Text("Advertises: \(peripheral.advertisedServices.joined(separator: ", "))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(peripheral.rssi) dBm")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct UUIDField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .font(.body.monospaced())
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
    }
}

private struct CommandEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField("AA 01 00 {{CHECKSUM}}", text: $text, axis: .vertical)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
    }
}

private struct GATTServiceRow: View {
    let service: GATTService

    var body: some View {
        DisclosureGroup {
            if service.characteristics.isEmpty {
                Text("Discovering characteristics...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.characteristics) { characteristic in
                    HStack {
                        Text(characteristic.id.uuidString)
                            .font(.caption.monospaced())
                        Spacer()
                        Text(characteristic.propertyDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        } label: {
            Label(service.id.uuidString, systemImage: "square.stack.3d.up")
                .font(.body.monospaced())
        }
    }
}
