import Foundation

/// Clean floor plan of the saved map, as computed by the helper (`floorplan.py`): one outline per room
/// (a rectangle where it fits), in pixel coordinates of the map as rotated in the Dreamehome app. Robot
/// and dock positions use the same coordinates. The home's outline is the union of the rooms.
struct RobotMap: Codable, Hashable, Sendable {
    let mapID: Int
    let width: Int
    let height: Int
    /// Meters per pixel (5 cm on the X50).
    var resolution: Double = 0.05
    var rooms: [MapRoom]
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
    var x: Double
    var y: Double
    /// Floor area in m².
    var area: Double
    var outline: [MapRing]

    /// The room as a rectangle, if its outline is one (the helper fits rooms as rectangles where it can).
    var rect: MapRect? {
        guard outline.count == 1, let ring = outline.first, ring.points.count == 4 else { return nil }
        let xs = Set(ring.points.map(\.x)), ys = Set(ring.points.map(\.y))
        guard xs.count == 2, ys.count == 2 else { return nil }
        return MapRect(x0: xs.min()!, y0: ys.min()!, x1: xs.max()!, y1: ys.max()!)
    }

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

extension RobotMap {
    /// The map with the user's corrections (room rectangles) applied.
    func applying(_ edits: [Int: MapRect]) -> RobotMap {
        var map = self
        for index in map.rooms.indices {
            guard let rect = edits[map.rooms[index].id] else { continue }
            map.rooms[index].outline = [rect.ring]
            map.rooms[index].x = (rect.x0 + rect.x1) / 2
            map.rooms[index].y = (rect.y0 + rect.y1) / 2
            map.rooms[index].area = rect.width * rect.height * resolution * resolution
        }
        return map
    }
}

/// Axis-aligned rectangle in map coordinates.
struct MapRect: Codable, Hashable, Sendable {
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double

    var width: Double { x1 - x0 }
    var height: Double { y1 - y0 }

    var ring: MapRing {
        MapRing(points: [
            MapPoint(x: x0, y: y0), MapPoint(x: x1, y: y0), MapPoint(x: x1, y: y1), MapPoint(x: x0, y: y1),
        ])
    }
}

struct MapPoint: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
}
