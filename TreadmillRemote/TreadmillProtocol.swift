import Foundation

enum HexFrameError: LocalizedError {
    case invalidByte(String)
    case invalidPlaceholder

    var errorDescription: String? {
        switch self {
        case .invalidByte(let value):
            "Invalid hex byte: \(value)"
        case .invalidPlaceholder:
            "Speed frames must use {{SPEED_LO}} and {{SPEED_HI}} together."
        }
    }
}

struct TreadmillProtocol {
    let configuration: TreadmillConfiguration

    func frame(for command: TreadmillCommand) throws -> Data {
        let template: String
        switch command {
        case .start:
            template = configuration.startHex
        case .pause:
            template = configuration.pauseHex
        case .stop:
            template = configuration.stopHex
        case .speed(let speed):
            template = speedTemplate(for: speed)
        }

        return try parse(template)
    }

    private func speedTemplate(for speed: Double) -> String {
        let scaledSpeed = max(0, Int((speed * configuration.speedScale).rounded()))
        let speedByte = String(format: "%02X", min(scaledSpeed, 255))
        return configuration.speedHex
            .replacingOccurrences(of: "{{SPEED}}", with: speedByte)
            .replacingOccurrences(of: "{{SPEED_LO}}", with: speedByte)
            .replacingOccurrences(of: "{{SPEED_HI}}", with: "00")
    }

    private func parse(_ template: String) throws -> Data {
        let normalized = template
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !normalized.isEmpty else {
            throw HexFrameError.invalidByte("empty frame")
        }

        if normalized.contains("{{SPEED}}") ||
            normalized.contains("{{SPEED_LO}}") ||
            normalized.contains("{{SPEED_HI}}") {
            throw HexFrameError.invalidPlaceholder
        }

        let checksumToken = "{{CHECKSUM}}"
        let checksumIndex = normalized.firstIndex(of: checksumToken)
        let checksumCount = normalized.filter { $0 == checksumToken }.count
        guard checksumCount <= 1 else {
            throw HexFrameError.invalidPlaceholder
        }
        if let checksumIndex {
            let isLast = checksumIndex == normalized.index(before: normalized.endIndex)
            let isBeforeFooter = normalized.last == "03" &&
                checksumIndex == normalized.index(normalized.endIndex, offsetBy: -2)
            guard isLast || isBeforeFooter else {
                throw HexFrameError.invalidPlaceholder
            }
        }

        let frameTokens = normalized.filter { $0 != checksumToken }
        var values = try frameTokens.map { token -> UInt8 in
            guard token.count <= 2, let value = UInt8(token, radix: 16) else {
                throw HexFrameError.invalidByte(token)
            }
            return value
        }

        if checksumCount == 1 {
            let checksumInput: ArraySlice<UInt8>
            if values.first == 0x02, values.last == 0x03, let checksumIndex {
                let payloadEnd = min(checksumIndex, normalized.count)
                let payloadTokens = normalized[1..<payloadEnd]
                let payloadValues = try payloadTokens.map { token -> UInt8 in
                    guard token.count <= 2, let value = UInt8(token, radix: 16) else {
                        throw HexFrameError.invalidByte(token)
                    }
                    return value
                }
                checksumInput = ArraySlice(payloadValues)
            } else {
                checksumInput = values[...]
            }
            let checksum: UInt8
            switch configuration.checksumMode {
            case .xor:
                checksum = checksumInput.reduce(0, ^)
            case .addition:
                checksum = checksumInput.reduce(0) { $0 &+ $1 }
            }
            if values.first == 0x02, values.last == 0x03 {
                values.insert(checksum, at: values.count - 1)
            } else {
                values.append(checksum)
            }
        }

        return Data(values)
    }
}
