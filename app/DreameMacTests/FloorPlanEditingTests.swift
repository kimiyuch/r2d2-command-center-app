import Foundation
import Testing
@testable import DreameMac

@Suite struct FloorPlanEditingTests {
    // Kitchen and living room share the wall at x = 10; the bedroom sits below the kitchen only.
    let rects: [Int: MapRect] = [
        7: MapRect(x0: 0, y0: 0, x1: 10, y1: 10),
        6: MapRect(x0: 10, y0: 0, x1: 30, y1: 10),
        9: MapRect(x0: 0, y0: 10, x1: 8, y1: 20),
    ]

    @Test func sharedWallMovesBothRooms() {
        let walls = FloorPlanEditing.linkedEdges(of: 7, .right, in: rects)
        #expect(Set(walls.map { "\($0.0)-\($0.1)" }) == ["7-right", "6-left"])

        let moved = FloorPlanEditing.move(walls, to: 12, in: rects)
        #expect(moved[7]?.x1 == 12)
        #expect(moved[6]?.x0 == 12)
        #expect(moved[9] == rects[9])
    }

    @Test func wallsOnTheSameLineButApartAreNotLinked() {
        // The bedroom's top (y = 10) is on the kitchen's bottom line, but the living room's bottom too:
        // only overlapping spans are linked.
        let walls = FloorPlanEditing.linkedEdges(of: 9, .top, in: rects)
        #expect(Set(walls.map { "\($0.0)-\($0.1)" }) == ["9-top", "7-bottom"])
    }

    @Test func straightWallAcrossSeveralRoomsMovesAsOne() {
        // Bathroom | corridor on top, a wide living room below: dragging the bathroom's bottom also moves
        // the corridor's bottom, via the living room's top that touches both.
        let rects: [Int: MapRect] = [
            3: MapRect(x0: 0, y0: 0, x1: 10, y1: 10),
            2: MapRect(x0: 10, y0: 0, x1: 20, y1: 10),
            6: MapRect(x0: 5, y0: 10, x1: 30, y1: 20),
        ]
        let walls = FloorPlanEditing.linkedEdges(of: 3, .bottom, in: rects)
        #expect(Set(walls.map { "\($0.0)-\($0.1)" }) == ["3-bottom", "6-top", "2-bottom"])
    }

    @Test func refusesToMakeARoomTooSmall() {
        let walls = FloorPlanEditing.linkedEdges(of: 7, .right, in: rects)
        #expect(FloorPlanEditing.move(walls, to: 2, in: rects) == rects)
    }

    @Test func snapsToOtherRoomsWallsThenToTheGrid() {
        let walls = FloorPlanEditing.linkedEdges(of: 9, .right, in: rects)
        // Close to the kitchen/living wall at x = 10 -> snaps onto it.
        #expect(FloorPlanEditing.snap(9.3, vertical: true, excluding: walls, in: rects, tolerance: 1) == 10)
        // Nothing near -> nearest half-pixel line.
        #expect(FloorPlanEditing.snap(5.2, vertical: true, excluding: walls, in: rects, tolerance: 1) == 5.5)
    }

    @Test func applyingEditsUpdatesOutlineLabelAndArea() {
        let edited = RobotMap.mock.applying([7: MapRect(x0: 20, y0: 0, x1: 30, y1: 12)])
        let room = edited.rooms.first { $0.id == 7 }
        #expect(room?.rect == MapRect(x0: 20, y0: 0, x1: 30, y1: 12))
        #expect(room?.x == 25)
        #expect(room?.y == 6)
        #expect(abs((room?.area ?? 0) - 10 * 12 * 0.0025) < 0.0001)
        #expect(edited.rooms.first { $0.id == 1 } == RobotMap.mock.rooms.first { $0.id == 1 })
    }
}
