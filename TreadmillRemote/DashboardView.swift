import SwiftUI
import UIKit

struct DashboardView: View {
    @Bindable var manager: TreadmillManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ConnectionBanner(manager: manager)
                    NearbyDevices(manager: manager)
                    SpeedGauge(manager: manager)
                    SpeedAdjustments(manager: manager)
                        .disabled(!manager.canSendCommands)
                    TransportControls(manager: manager)
                        .disabled(!manager.canSendCommands)
                    EmergencyStopButton(manager: manager)
                        .disabled(!manager.canSendCommands)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Treadmill Remote")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        ConsoleLogView(manager: manager)
                    } label: {
                        Label("Console", systemImage: "terminal")
                    }
                    NavigationLink {
                        SettingsInspectorView(manager: manager)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .alert("Bluetooth Error", isPresented: Binding(
                get: { manager.lastError != nil },
                set: { if !$0 { manager.lastError = nil } }
            )) {
                Button("OK") {
                    manager.lastError = nil
                }
            } message: {
                Text(manager.lastError ?? "Unknown Bluetooth error")
            }
        }
    }
}

private struct ConnectionBanner: View {
    let manager: TreadmillManager

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(manager.connectionState.statusColor)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.connectionState.rawValue)
                    .font(.headline)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Haptics.medium()
                manager.connectOrScan()
            } label: {
                if manager.connectionState == .scanning || manager.connectionState == .connecting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(manager.connectionState == .scanning ? "Scanning" : "Connecting")
                    }
                } else {
                    Text(manager.connectionState == .connected ? "Disconnect" : "Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.connectionState == .scanning || manager.connectionState == .connecting)
            .accessibilityHint("Scans for nearby BLE treadmills when disconnected")
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var statusMessage: String {
        switch manager.connectionState {
        case .connected where manager.canSendCommands:
            "Ready for treadmill commands"
        case .connected:
            "Connected; looking for configured GATT controls"
        default:
            "Tap Connect to find a treadmill"
        }
    }
}

private struct NearbyDevices: View {
    let manager: TreadmillManager

    var body: some View {
        if manager.connectionState == .scanning || !manager.nearbyPeripherals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Nearby devices")
                        .font(.headline)
                    Spacer()
                    if manager.connectionState == .scanning {
                        Text("Listening...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(manager.nearbyPeripherals.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if manager.nearbyPeripherals.isEmpty {
                    Text("No BLE devices found yet. Keep the treadmill powered on and nearby.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("RSSI is a relative radio reading, not a distance measurement. Confirm the device name and GATT match before connecting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.nearbyPeripherals) { peripheral in
                        Button {
                            Haptics.light()
                            manager.connect(to: peripheral.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "wave.3.right.circle.fill")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peripheral.name)
                                        .font(.body.weight(.semibold))
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
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .disabled(manager.connectionState == .connected || manager.connectionState == .connecting)
                    }
                }
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct SpeedGauge: View {
    let manager: TreadmillManager

    var body: some View {
        VStack(spacing: 8) {
            Text(manager.isRunning ? "RUNNING" : "READY")
                .font(.caption.weight(.bold))
                .foregroundStyle(manager.isRunning ? .green : .secondary)
                .tracking(1.5)
            Text(manager.targetSpeed, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text("mph / kmh")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Session \(formattedDuration(manager.elapsedTime))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Treadmill speed")
        .accessibilityValue("\(manager.targetSpeed, format: .number.precision(.fractionLength(1))) miles per hour, session \(formattedDuration(manager.elapsedTime))")
    }
}

private struct SpeedAdjustments: View {
    let manager: TreadmillManager

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SpeedButton(title: "-0.5") {
                    changeSpeed(by: -0.5)
                }
                SpeedButton(title: "-0.1") {
                    changeSpeed(by: -0.1)
                }
                SpeedButton(title: "+0.1") {
                    changeSpeed(by: 0.1)
                }
                SpeedButton(title: "+0.5") {
                    changeSpeed(by: 0.5)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                ForEach([1.0, 2.0, 3.0], id: \.self) { preset in
                    Button {
                        Haptics.light()
                        manager.setSpeed(preset)
                    } label: {
                        Text(preset, format: .number.precision(.fractionLength(1)))
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .tint(manager.targetSpeed == preset ? .accentColor : .secondary)
                    .accessibilityLabel("Set speed to \(preset, format: .number.precision(.fractionLength(1)))")
                }
            }
        }
    }

    private func changeSpeed(by amount: Double) {
        Haptics.light()
        manager.setSpeed(manager.targetSpeed + amount)
    }
}

private struct SpeedButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Adjust speed \(title)")
    }
}

private struct TransportControls: View {
    let manager: TreadmillManager

    var body: some View {
        HStack(spacing: 12) {
            TransportButton(title: "Start", systemImage: "play.fill", tint: .green) {
                Haptics.medium()
                manager.send(.start)
            }
            TransportButton(title: "Pause", systemImage: "pause.fill", tint: .orange) {
                Haptics.medium()
                manager.send(.pause)
            }
            TransportButton(title: "Stop", systemImage: "stop.fill", tint: .red) {
                Haptics.heavy()
                manager.send(.stop)
            }
        }
    }
}

private struct TransportButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .accessibilityLabel(title)
    }
}

private struct EmergencyStopButton: View {
    let manager: TreadmillManager

    var body: some View {
        Button {
            Haptics.heavy()
            manager.send(.stop)
        } label: {
            Label("EMERGENCY STOP", systemImage: "exclamationmark.octagon.fill")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 68)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .accessibilityHint("Immediately sends the configured stop frame")
    }
}

private extension ConnectionState {
    var statusColor: Color {
        switch self {
        case .connected:
            .green
        case .scanning, .connecting:
            .yellow
        case .disconnected:
            .red
        }
    }
}

@MainActor
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}

private func formattedDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration))
    return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
}
