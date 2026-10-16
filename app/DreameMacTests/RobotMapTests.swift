import Foundation
import Testing
@testable import DreameMac

@Suite struct RobotMapTests {
    @Test func decodesHelperFloorPlan() throws {
        let json = """
        {"mapID": 1, "width": 20, "height": 10,
         "rooms": [{"id": 7, "name": "Kitchen/Dining Room", "x": 5, "y": 5, "area": 20.5,
                    "outline": [[0, 0, 10, 0, 10, 10, 0, 10], [3, 3, 6, 3, 6, 6, 3, 6]]},
                   {"id": 1, "name": "Miyu", "x": 15, "y": 5, "area": 12.4, "outline": [[10, 0, 20, 0, 20, 10, 10, 10]]}],
         "charger": {"x": 2.5, "y": 1.0}}
        """
        let map = try JSONDecoder().decode(RobotMap.self, from: Data(json.utf8))

        #expect(map.rooms[0].outline[0].points.count == 4)
        #expect(map.roomID(at: MapPoint(x: 1, y: 1)) == 7)
        #expect(map.roomID(at: MapPoint(x: 4.5, y: 4.5)) == nil)  // inside the hole (furniture)
        #expect(map.roomID(at: MapPoint(x: 15, y: 5)) == 1)
        #expect(map.roomID(at: MapPoint(x: 25, y: 5)) == nil)
        #expect(map.charger == MapPoint(x: 2.5, y: 1))
    }

    @Test func ringRoundTripsAsFlatArray() throws {
        let ring = MapRing(points: [MapPoint(x: 1, y: 2), MapPoint(x: 3, y: 4), MapPoint(x: 5, y: 6)])
        let data = try JSONEncoder().encode(ring)
        #expect(String(decoding: data, as: UTF8.self) == "[1,2,3,4,5,6]")
        #expect(try JSONDecoder().decode(MapRing.self, from: data) == ring)
    }
}
