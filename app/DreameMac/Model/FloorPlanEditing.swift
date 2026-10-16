import Foundation

/// One wall of a room rectangle.
enum RectEdge: CaseIterable, Sendable {
    case left, top, right, bottom

    var isVertical: Bool { self == .left || self == .right }

    func value(of rect: MapRect) -> Double {
        switch self {
        case .left: rect.x0
        case .top: rect.y0
        case .right: rect.x1
        case .bottom: rect.y1
        }
    }

    /// The span of the edge along the other axis.
    func span(of rect: MapRect) -> ClosedRange<Double> {
        isVertical ? rect.y0...rect.y1 : rect.x0...rect.x1
    }

    func setting(_ value: Double, in rect: MapRect) -> MapRect {
        var rect = rect
        switch self {
        case .left: rect.x0 = value
        case .top: rect.y0 = value
        case .right: rect.x1 = value
        case .bottom: rect.y1 = value
        }
        return rect
    }
}

/// Moving room walls in the floor plan editor.
enum FloorPlanEditing {
    /// Rooms can't get smaller than this (in map pixels; 20 cm at 5 cm per pixel).
    static let minimumSize = 4.0

    /// Walls that are flush with the dragged one and should move with it so neighboring rooms stay flush:
    /// on the same line with overlapping spans, transitively (a straight wall across several rooms moves
    /// as one). Includes the dragged wall itself, first.
    static func linkedEdges(of roomID: Int, _ edge: RectEdge, in rects: [Int: MapRect]) -> [(Int, RectEdge)] {
        guard let rect = rects[roomID] else { return [] }
        let line = edge.value(of: rect)
        var linked = [(roomID, edge)]
        var queue = [(roomID, edge)]
        while let (id, current) = queue.popLast() {
            guard let span = rects[id].map(current.span(of:)) else { continue }
            for (otherID, other) in rects {
                for candidate in RectEdge.allCases where candidate.isVertical == edge.isVertical {
                    guard abs(candidate.value(of: other) - line) < 0.01,
                          !linked.contains(where: { $0.0 == otherID && $0.1 == candidate }) else { continue }
                    let otherSpan = candidate.span(of: other)
                    if otherSpan.lowerBound < span.upperBound && span.lowerBound < otherSpan.upperBound {
                        linked.append((otherID, candidate))
                        queue.append((otherID, candidate))
                    }
                }
            }
        }
        return linked
    }

    /// Moves the given walls to `value`, unless that would make any of their rooms too small.
    static func move(_ edges: [(Int, RectEdge)], to value: Double, in rects: [Int: MapRect]) -> [Int: MapRect] {
        var result = rects
        for (id, edge) in edges {
            guard let rect = result[id] else { continue }
            let moved = edge.setting(value, in: rect)
            if moved.width < minimumSize || moved.height < minimumSize { return rects }
            result[id] = moved
        }
        return result
    }

    /// Snaps to the nearest wall of another room within `tolerance`, otherwise to the half-pixel grid
    /// (room edges sit between pixels, at .5 in map coordinates).
    static func snap(_ value: Double, vertical: Bool, excluding moving: [(Int, RectEdge)], in rects: [Int: MapRect], tolerance: Double) -> Double {
        let movingIDs = Set(moving.map(\.0))
        let candidates = rects.filter { !movingIDs.contains($0.key) }.values.flatMap { rect in
            vertical ? [rect.x0, rect.x1] : [rect.y0, rect.y1]
        }
        if let nearest = candidates.min(by: { abs($0 - value) < abs($1 - value) }), abs(nearest - value) <= tolerance {
            return nearest
        }
        return (value - 0.5).rounded() + 0.5
    }
}

/// A stretch of a room wall: either shared with a neighboring room (flush, on the other side) or exterior.
struct WallSegment: Hashable, Sendable {
    let roomID: Int
    let edge: RectEdge
    /// Position of the wall line (x for vertical walls, y for horizontal ones).
    let line: Double
    /// Extent along the wall.
    let range: ClosedRange<Double>
    let isShared: Bool

    var middle: Double { (range.lowerBound + range.upperBound) / 2 }
    var length: Double { range.upperBound - range.lowerBound }

    var endpoints: (MapPoint, MapPoint) {
        edge.isVertical
            ? (MapPoint(x: line, y: range.lowerBound), MapPoint(x: line, y: range.upperBound))
            : (MapPoint(x: range.lowerBound, y: line), MapPoint(x: range.upperBound, y: line))
    }
}

extension FloorPlanEditing {
    /// Splits every room wall into the parts shared with a flush neighbor and the exterior parts.
    static func segments(in rects: [Int: MapRect]) -> [WallSegment] {
        var result: [WallSegment] = []
        for (id, rect) in rects.sorted(by: { $0.key < $1.key }) {
            for edge in RectEdge.allCases {
                let line = edge.value(of: rect)
                let span = edge.span(of: rect)
                var shared: [ClosedRange<Double>] = []
                for (otherID, other) in rects where otherID != id {
                    for candidate in RectEdge.allCases where candidate.isVertical == edge.isVertical && candidate != edge {
                        guard abs(candidate.value(of: other) - line) < 0.01 else { continue }
                        let otherSpan = candidate.span(of: other)
                        let lower = max(span.lowerBound, otherSpan.lowerBound), upper = min(span.upperBound, otherSpan.upperBound)
                        if lower < upper { shared.append(lower...upper) }
                    }
                }
                shared = merged(shared)
                for range in shared {
                    result.append(WallSegment(roomID: id, edge: edge, line: line, range: range, isShared: true))
                }
                // The rest of the wall is exterior.
                var start = span.lowerBound
                for range in shared + [span.upperBound...span.upperBound] {
                    if range.lowerBound - start > 0.01 {
                        result.append(WallSegment(roomID: id, edge: edge, line: line, range: start...range.lowerBound, isShared: false))
                    }
                    start = max(start, range.upperBound)
                }
            }
        }
        return result
    }

    private static func merged(_ ranges: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        ranges.sorted { $0.lowerBound < $1.lowerBound }.reduce(into: []) { result, range in
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
    }
}
