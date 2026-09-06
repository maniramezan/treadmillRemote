import CoreBluetooth
import Foundation

enum ConnectionState: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning"
    case connecting = "Connecting"
    case connected = "Connected"
}

enum ChecksumMode: String, CaseIterable, Identifiable, Codable {
    case xor = "XOR"
    case addition = "Addition"

    var id: String { rawValue }
}

struct TreadmillConfiguration: Codable, Equatable {
    var serviceUUID = "FFF0"
    var writeCharacteristicUUID = "FFF2"
    var notifyCharacteristicUUID = "FFF1"
    var startHex = "02 53 01 00 00 00 00 00 00 00 00 {{CHECKSUM}} 03"
    var pauseHex = "02 53 0A {{CHECKSUM}} 03"
    var stopHex = "02 53 03 {{CHECKSUM}} 03"
    var speedHex = "02 53 02 {{SPEED}} 00 {{CHECKSUM}} 03"
    var checksumMode: ChecksumMode = .xor
    var speedScale: Double = 10

    static let defaults = TreadmillConfiguration()

    private var serviceUUIDValue: CBUUID {
        CBUUID(string: serviceUUID)
    }
}

struct DiscoveredPeripheral: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var isSelected: Bool
    var matchReason: String
    var advertisedServices: [String]

    static func == (lhs: DiscoveredPeripheral, rhs: DiscoveredPeripheral) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.rssi == rhs.rssi && lhs.isSelected == rhs.isSelected
    }
}

struct GATTCharacteristic: Identifiable {
    let id: CBUUID
    let properties: CBCharacteristicProperties

    var propertyDescription: String {
        var values: [String] = []
        if properties.contains(.read) { values.append("read") }
        if properties.contains(.write) { values.append("write") }
        if properties.contains(.writeWithoutResponse) { values.append("write-no-response") }
        if properties.contains(.notify) { values.append("notify") }
        if properties.contains(.indicate) { values.append("indicate") }
        return values.isEmpty ? "none" : values.joined(separator: ", ")
    }
}

struct GATTService: Identifiable {
    let id: CBUUID
    var characteristics: [GATTCharacteristic]
}

struct HexLogEntry: Identifiable, Equatable {
    enum Direction: String {
        case sent = "OUT"
        case received = "IN"
        case event = "EVENT"
    }

    let id = UUID()
    let date: Date
    let direction: Direction
    let message: String

    var timestamp: String {
        date.formatted(date: .omitted, time: .standard)
    }
}

enum TreadmillCommand {
    case start
    case pause
    case stop
    case speed(Double)
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
