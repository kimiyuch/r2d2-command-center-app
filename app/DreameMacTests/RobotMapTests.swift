import Foundation
import Testing
@testable import DreameMac

@Suite struct RobotMapTests {
    @Test func decodesHelperMap() throws {
        // 3×2 map: outside, room 7 floor, room 7 edge / floor without room, room 1, wall.
        let pixels = Data([0, 7, 107, 254, 1, 255]).base64EncodedString()
        let json = """
        {"mapID": 1, "width": 3, "height": 2, "pixels": "\(pixels)",
         "rooms": [{"id": 7, "name": "Kitchen/Dining Room", "x": 1.0, "y": 0.0}, {"id": 1, "name": "Miyu"}],
         "charger": {"x": 2.5, "y": 1.0}}
        """
        let map = try JSONDecoder().decode(RobotMap.self, from: Data(json.utf8))

        #expect(map.roomID(x: 0, y: 0) == nil)
        #expect(map.roomID(x: 1, y: 0) == 7)
        #expect(map.roomID(x: 2, y: 0) == 7)  // edge pixels belong to their room
        #expect(map.roomID(x: 0, y: 1) == nil)
        #expect(map.roomID(x: 1, y: 1) == 1)
        #expect(map.roomID(x: 2, y: 1) == nil)
        #expect(map.roomID(x: 3, y: 0) == nil)  // outside the image
        #expect(map.rooms[1].x == nil)
        #expect(map.charger == MapPoint(x: 2.5, y: 1))
    }

    @Test func rendersOnePixelPerMapPixel() {
        let image = MapRenderer.image(for: .mock, selected: [6], hovered: 1)
        #expect(image.width == RobotMap.mock.width)
        #expect(image.height == RobotMap.mock.height)
    }
}
