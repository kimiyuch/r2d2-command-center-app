import Foundation

/// Clean floor plan of the saved map, as computed by the helper (`floorplan.py`): one outline per room
/// (a rectangle where it fits), in pixel coordinates of the map as rotated in the Dreamehome app. Robot
/// and dock positions use the same coordinates. The home's outline is the union of the rooms.
struct RobotMap: Codable, Hashable, Sendable {
    let mapID: Int
    let width: Int
    let height: Int
    let rooms: [MapRoom]
    let charger: MapPoint?

    /// The room containing a point, if any.
    func roomID(at point: MapPoint) -> Int? {
        rooms.first { $0.contains(point) }?.id
    }
}

struct MapRoom: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    /// Label position: the point deepest inside the room.
    let x: Double
    let y: Double
    /// Floor area in m².
    let area: Double
    let outline: [MapRing]

    /// Even-odd rule over all rings, so holes don't count.
    func contains(_ point: MapPoint) -> Bool {
        outline.reduce(false) { inside, ring in ring.contains(point) != inside }
    }
}

/// A closed polygon, encoded by the helper as a flat [x0, y0, x1, y1, ...] array.
struct MapRing: Codable, Hashable, Sendable {
    let points: [MapPoint]

    init(points: [MapPoint]) {
        self.points = points
    }

    init(from decoder: any Decoder) throws {
        let flat = try decoder.singleValueContainer().decode([Double].self)
        points = stride(from: 0, to: flat.count - 1, by: 2).map { MapPoint(x: flat[$0], y: flat[$0 + 1]) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(points.flatMap { [$0.x, $0.y] })
    }

    /// Ray casting point-in-polygon test.
    func contains(_ point: MapPoint) -> Bool {
        var inside = false
        var j = points.count - 1
        for i in points.indices {
            let a = points[i], b = points[j]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

struct MapPoint: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
}
