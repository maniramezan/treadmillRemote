import CoreBluetooth
import Foundation
import Observation

@MainActor
@Observable
final class TreadmillManager: NSObject {
    var connectionState: ConnectionState = .disconnected
    var nearbyPeripherals: [DiscoveredPeripheral] = []
    var gattServices: [GATTService] = []
    var logs: [HexLogEntry] = []
    var configuration: TreadmillConfiguration {
        didSet {
            configurationStore.save(configuration)
        }
    }
    var targetSpeed = 0.0
    var isRunning = false
    var elapsedTime: TimeInterval = 0
    var lastError: String?
    var selectedPeripheralID: UUID?
    var canSendCommands: Bool {
        connectionState == .connected && discoveredTargetService && writeCharacteristic != nil
    }

    private let configurationStore = TreadmillConfigurationStore()
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var discoveredTargetService = false
    private var activeServiceUUID: CBUUID?
    private var peripheralReferences: [UUID: CBPeripheral] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var sessionClockTask: Task<Void, Never>?
    private var sessionStartedAt: Date?

    override init() {
        configuration = configurationStore.load()
        super.init()
    }

    func connectOrScan() {
        switch connectionState {
        case .connected, .connecting:
            disconnect()
        case .disconnected, .scanning:
            scan()
        }
    }

    func scan() {
        centralManager?.stopScan()
        connectionState = .scanning
        nearbyPeripherals.removeAll()
        peripheralReferences.removeAll()
        if centralManager == nil {
            appendEvent("Requesting Bluetooth access")
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        if centralManager?.state == .poweredOn {
            beginScan()
        }
    }

    func connect(to id: UUID) {
        guard let peripheral = peripheralReferences[id] else {
            lastError = "That peripheral is no longer available."
            return
        }
        selectedPeripheralID = id
        centralManager?.stopScan()
        connectionState = .connecting
        appendEvent("Connecting to \(peripheral.displayName)")
        peripheral.delegate = self
        centralManager?.connect(peripheral)
    }

    func disconnect() {
        reconnectTask?.cancel()
        centralManager?.stopScan()
        if let connectedPeripheral {
            centralManager?.cancelPeripheralConnection(connectedPeripheral)
        }
        finishDisconnected()
    }

    func send(_ command: TreadmillCommand) {
        guard connectionState == .connected, let characteristic = writeCharacteristic else {
            lastError = "Connect to a treadmill before sending commands."
            appendEvent(lastError ?? "")
            return
        }

        do {
            let frame = try TreadmillProtocol(configuration: configuration).frame(for: command)
            let type: CBCharacteristicWriteType = characteristic.properties.contains(.write)
                ? .withResponse
                : .withoutResponse
            connectedPeripheral?.writeValue(frame, for: characteristic, type: type)
            appendLog(direction: .sent, message: frame.hexString)
            updateLocalState(for: command)
            if case .start = command {
                let startupSpeed = targetSpeed > 0 ? targetSpeed : 0.5
                targetSpeed = startupSpeed
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let self else { return }
                    self.send(.speed(startupSpeed))
                }
            }
        } catch {
            lastError = error.localizedDescription
            appendEvent("Command rejected: \(error.localizedDescription)")
        }
    }

    func setSpeed(_ speed: Double) {
        let clampedSpeed = min(max(speed, 0), 20)
        targetSpeed = clampedSpeed
        send(.speed(clampedSpeed))
    }

    func clearLogs() {
        logs.removeAll()
    }

    func resetConfiguration() {
        configuration = .defaults
    }

    func peripheralName(for id: UUID) -> String {
        peripheralReferences[id]?.displayName ?? "Unknown treadmill"
    }

    private func updateLocalState(for command: TreadmillCommand) {
        switch command {
        case .start:
            isRunning = true
            startSessionClock()
        case .pause:
            isRunning = false
            stopSessionClock()
        case .stop:
            isRunning = false
            targetSpeed = 0
            stopSessionClock()
        case .speed:
            break
        }
    }

    private func startSessionClock() {
        guard sessionStartedAt == nil else { return }
        sessionStartedAt = Date().addingTimeInterval(-elapsedTime)
        sessionClockTask?.cancel()
        sessionClockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let sessionStartedAt = self.sessionStartedAt else { return }
                self.elapsedTime = Date().timeIntervalSince(sessionStartedAt)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopSessionClock() {
        sessionClockTask?.cancel()
        sessionClockTask = nil
        sessionStartedAt = nil
    }

    private func finishDisconnected() {
        connectionState = .disconnected
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        discoveredTargetService = false
        activeServiceUUID = nil
        gattServices.removeAll()
    }

    private func beginScan() {
        guard centralManager?.state == .poweredOn else { return }
        appendEvent("Scanning for fitness machines and treadmill advertisements")
        centralManager?.scanForPeripherals(
            // Scan broadly because many proprietary treadmill boards do not
            // advertise their GATT service UUID until after connection.
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func scheduleReconnect() {
        guard selectedPeripheralID != nil else {
            finishDisconnected()
            return
        }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.attemptReconnect()
        }
    }

    private func attemptReconnect() {
        guard let selectedPeripheralID, centralManager?.state == .poweredOn else {
            scan()
            return
        }

        let retrieved = centralManager?.retrievePeripherals(withIdentifiers: [selectedPeripheralID]) ?? []
        if let peripheral = retrieved.first {
            peripheralReferences[peripheral.identifier] = peripheral
            connect(to: peripheral.identifier)
        } else {
            scan()
        }
    }

    private func appendLog(direction: HexLogEntry.Direction, message: String) {
        logs.append(HexLogEntry(date: Date(), direction: direction, message: message))
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }

    private func appendEvent(_ message: String) {
        appendLog(direction: .event, message: message)
    }
}

extension TreadmillManager: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, connectionState == .scanning {
            beginScan()
        } else if central.state != .poweredOn {
            connectionState = .disconnected
            appendEvent("Bluetooth state: \(central.state.description)")
            if central.state == .unauthorized {
                lastError = "Bluetooth access is denied. Allow it in Settings > Privacy & Security > Bluetooth."
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unnamed peripheral"
        guard let match = treadmillAdvertisementMatch(name: name, advertisementData: advertisementData) else {
            return
        }
        peripheralReferences[peripheral.identifier] = peripheral
        let advertisedServices = ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? [])
            .map(\.uuidString)
        let summary = DiscoveredPeripheral(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            isSelected: peripheral.identifier == selectedPeripheralID,
            matchReason: match,
            advertisedServices: advertisedServices
        )
        if let index = nearbyPeripherals.firstIndex(where: { $0.id == summary.id }) {
            nearbyPeripherals[index] = summary
        } else {
            nearbyPeripherals.append(summary)
            nearbyPeripherals.sort { $0.rssi > $1.rssi }
        }
        if connectionState == .scanning, peripheral.identifier == selectedPeripheralID {
            connect(to: peripheral.identifier)
        }
    }

    private func treadmillAdvertisementMatch(name: String, advertisementData: [String: Any]) -> String? {
        let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let normalizedName = name.lowercased()
        let treadmillKeywords = [
            "egofit", "fitshow", "treadmill", "walking pro", "walkingpad",
            "walkpad", "citysports"
        ]
        if let keyword = treadmillKeywords.first(where: { normalizedName.contains($0) }) {
            return "Name match: \(keyword.capitalized)"
        }
        if advertisedServices.contains(configuration.serviceUUIDValue) {
            return "Configured service: \(configuration.serviceUUID.uppercased())"
        }
        if advertisedServices.contains(CBUUID(string: "1826")) {
            return "Fitness Machine Service: 0x1826"
        }
        return nil
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectionState = .connected
        appendEvent("Connected to \(peripheral.displayName)")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        lastError = error?.localizedDescription ?? "Unable to connect."
        appendEvent("Connection failed: \(lastError ?? "")")
        scheduleReconnect()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        appendEvent(error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected")
        finishDisconnected()
        scheduleReconnect()
    }
}

extension TreadmillManager: @MainActor CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lastError = error.localizedDescription
            appendEvent("Service discovery failed: \(error.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        gattServices = services.map { GATTService(id: $0.uuid, characteristics: []) }
        let knownServiceUUIDs = [
            configuration.serviceUUIDValue,
            CBUUID(string: "FFF0"),
            CBUUID(string: "FFE0"),
            CBUUID(string: "AE00")
        ]
        let targetService = knownServiceUUIDs.lazy.compactMap { uuid in
            services.first { $0.uuid == uuid }
        }.first
        discoveredTargetService = targetService != nil
        activeServiceUUID = targetService?.uuid
        if let targetService {
            peripheral.discoverCharacteristics(nil, for: targetService)
        } else {
            let available = services.map(\.uuid.uuidString).joined(separator: ", ")
            appendEvent("Configured service \(configuration.serviceUUID) not found. Available: \(available)")
        }
        for service in services where service.uuid != targetService?.uuid {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            lastError = error.localizedDescription
            appendEvent("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        let characteristics = service.characteristics ?? []
        if let index = gattServices.firstIndex(where: { $0.id == service.uuid }) {
            gattServices[index].characteristics = characteristics.map {
                GATTCharacteristic(id: $0.uuid, properties: $0.properties)
            }
        }
        let fallbackWriteUUIDs = [
            CBUUID(string: "FFF2"),
            CBUUID(string: "FFE1"),
            CBUUID(string: "AE01"),
            CBUUID(string: "FAB1"),
            CBUUID(string: "FAB2")
        ]
        let fallbackNotifyUUIDs = [
            CBUUID(string: "FFF1"),
            CBUUID(string: "FFF3"),
            CBUUID(string: "FFF4"),
            CBUUID(string: "FAB3")
        ]
        for characteristic in characteristics {
            if (characteristic.uuid == configuration.writeCharacteristicUUIDValue ||
                (writeCharacteristic == nil && fallbackWriteUUIDs.contains(characteristic.uuid))),
               characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
            }
            if (characteristic.uuid == configuration.notifyCharacteristicUUIDValue ||
                fallbackNotifyUUIDs.contains(characteristic.uuid)),
               characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        if service.uuid == activeServiceUUID, writeCharacteristic == nil {
            appendEvent("Write characteristic \(configuration.writeCharacteristicUUID) was not found.")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            appendEvent("Notification error: \(error.localizedDescription)")
        } else if let value = characteristic.value {
            appendLog(direction: .received, message: value.hexString)
        }
    }
}

private extension CBPeripheral {
    var displayName: String {
        name ?? identifier.uuidString
    }
}

private extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "powered off"
        case .poweredOn: "powered on"
        @unknown default: "unknown"
        }
    }
}

private extension TreadmillConfiguration {
    var serviceUUIDValue: CBUUID { CBUUID(string: serviceUUID) }
    var writeCharacteristicUUIDValue: CBUUID { CBUUID(string: writeCharacteristicUUID) }
    var notifyCharacteristicUUIDValue: CBUUID { CBUUID(string: notifyCharacteristicUUID) }
}

private struct TreadmillConfigurationStore {
    private let key = "treadmill.configuration"

    func load() -> TreadmillConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              var configuration = try? JSONDecoder().decode(TreadmillConfiguration.self, from: data) else {
            return .defaults
        }
        if configuration.startHex.hasPrefix("AA") || configuration.speedHex.hasPrefix("AA") {
            return .defaults
        }
        let savedPausePrefix = configuration.pauseHex
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        if savedPausePrefix.hasPrefix("025306") {
            configuration.pauseHex = TreadmillConfiguration.defaults.pauseHex
        }
        return configuration
    }

    func save(_ configuration: TreadmillConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
