import Foundation

/// The saved map as sent by the helper: one byte per pixel, rows from the top-left, already rotated
/// like in the Dreamehome app. Coordinates of rooms, dock and robot are in the same pixel space.
struct RobotMap: Codable, Hashable, Sendable {
    let mapID: Int
    let width: Int
    let height: Int
    /// 0 outside, 1–63 floor of that room, 101–163 that room's edge, other values floor without a room.
    let pixels: Data
    let rooms: [MapRoom]
    let charger: MapPoint?

    func pixel(x: Int, y: Int) -> UInt8? {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
        return pixels[pixels.startIndex + y * width + x]
    }

    func roomID(x: Int, y: Int) -> Int? {
        guard let value = pixel(x: x, y: y) else { return nil }
        switch value {
        case 1...63: return Int(value)
        case 101...163: return Int(value) - 100
        default: return nil
        }
    }
}

struct MapRoom: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    /// Label position; missing if the robot didn't report a room center.
    var x: Double?
    var y: Double?
}

struct MapPoint: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
}
