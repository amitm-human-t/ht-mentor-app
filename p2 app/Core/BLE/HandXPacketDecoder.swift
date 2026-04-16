import Foundation
import simd

enum HandXPacketDecoder {
    static func mergeFastPacket(_ data: Data, onto sample: HandXSample) -> HandXSample {
        guard data.count >= 8 else { return sample }

        var updated = sample
        let roll = Float(readInt16(data, at: 2))
        let pitch = Float(readInt16(data, at: 4))
        let yaw = Float(readInt16(data, at: 6))
        updated.orientation = SIMD3(roll, pitch, yaw)

        var offset = 8
        var joyY: Float = 0
        var joyX: Float = 0
        var direction: Float = 0
        var bend: Float = 0
        if data.count >= offset + 8 {
            joyY = Float(readInt16(data, at: offset))
            joyX = Float(readInt16(data, at: offset + 2))
            direction = Float(readInt16(data, at: offset + 4))
            bend = Float(readInt16(data, at: offset + 6))
            offset += 8
        } else if data.count >= offset + 4 {
            joyY = Float(readInt16(data, at: offset))
            joyX = Float(readInt16(data, at: offset + 2))
            offset += 4
        }

        updated.joystick = normalizeJoystick(x: joyX, y: joyY)
        updated.direction = direction
        updated.bend = bend

        if data.count >= offset + 4 {
            updated.roll = Float(readInt16(data, at: offset))
            updated.grip = Float(readInt16(data, at: offset + 2))
            offset += 4
        }

        if data.count >= offset + 4 {
            updated.state["sys"] = Int(data[offset])
            updated.state["lock"] = Int(data[offset + 1])
            updated.state["coupling"] = Int(data[offset + 2])
            updated.buttons.state = [Int(data[offset + 3])]
        }

        return updated
    }

    static func mergeSlowPacket(_ data: Data, onto sample: HandXSample) -> HandXSample {
        var updated = sample
        if data.count >= 37 {
            updated.orientation = SIMD3(
                Float(readInt16(data, at: 5)),
                Float(readInt16(data, at: 7)),
                Float(readInt16(data, at: 9))
            )
            updated.state["sys"] = Int(data[23])
            updated.state["lock"] = Int(data[24])
            updated.state["coupling"] = Int(data[25])
            updated.state["invert"] = Int(data[26])
            updated.buttons.event = [Int(data[27]), Int(data[28]), Int(data[29])]
            updated.buttons.number = [Int(data[30]), Int(data[31]), Int(data[32])]
            updated.buttons.state = [Int(data[33]), Int(data[34]), Int(data[35])]
            return updated
        }

        guard data.count >= 21 else { return updated }
        updated.state["sys"] = Int(data[7])
        updated.state["lock"] = Int(data[8])
        updated.state["coupling"] = Int(data[9])
        updated.state["invert"] = Int(data[10])
        updated.buttons.event = [Int(data[11]), Int(data[12]), Int(data[13])]
        updated.buttons.number = [Int(data[14]), Int(data[15]), Int(data[16])]
        updated.buttons.state = [Int(data[17]), Int(data[18]), Int(data[19])]
        return updated
    }

    private static func readInt16(_ data: Data, at offset: Int) -> Int16 {
        let range = offset..<(offset + 2)
        return Int16(littleEndian: data[range].withUnsafeBytes { $0.load(as: Int16.self) })
    }

    private static func normalizeJoystick(x: Float, y: Float) -> SIMD2<Float> {
        let normalizedX = max(-1, min(1, (x - 2048) / 2047))
        let normalizedY = max(-1, min(1, (y - 2048) / 2047))
        return SIMD2(normalizedX, normalizedY)
    }
}

struct HandXSample: Sendable {
    var timestamp: TimeInterval
    var connected: Bool
    var joystick: SIMD2<Float>
    var direction: Float
    var bend: Float
    var roll: Float
    var grip: Float
    var orientation: SIMD3<Float>
    var state: [String: Int]
    var buttons: HandXButtons

    static let zero = HandXSample(
        timestamp: 0,
        connected: false,
        joystick: .zero,
        direction: 0,
        bend: 0,
        roll: 0,
        grip: 0,
        orientation: .zero,
        state: [:],
        buttons: .init(event: [], number: [], state: [])
    )

    func markConnected() -> HandXSample {
        var copy = self
        copy.connected = true
        copy.timestamp = Date().timeIntervalSince1970
        return copy
    }

    func markDisconnected() -> HandXSample {
        var copy = self
        copy.connected = false
        copy.timestamp = Date().timeIntervalSince1970
        return copy
    }
}

struct HandXButtons: Sendable {
    var event: [Int]
    var number: [Int]
    var state: [Int]
}
