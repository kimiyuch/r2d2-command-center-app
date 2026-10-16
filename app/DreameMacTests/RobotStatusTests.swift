import Foundation
import Testing
@testable import DreameMac

@Suite struct RobotStatusTests {
    @Test func decodesHelperStatus() throws {
        // Recorded from the real robot (X50 Ultra, docked), via dreame_helper.py.
        let json = """
        {"state": {"raw": 13, "name": "charging_completed"}, "error": {"raw": 0, "name": "no_error"}, "battery": 100,
         "charging": {"raw": 1, "name": "charging"}, "status": {"raw": 6, "name": "charging"},
         "suction": {"raw": 2, "name": "strong"}, "task": {"raw": 0, "name": "completed"},
         "cleaningMode": {"raw": 3842, "name": "sweeping", "selfClean": 15, "humidity": 0}}
        """
        let status = try JSONDecoder().decode(RobotStatus.self, from: Data(json.utf8))
        #expect(status.state?.label == "Charging completed")
        #expect(status.cleaningMode?.label == "Vacuum")
        #expect(!status.hasError)
        #expect(!status.isCleaning)
        #expect(status.isDocked)
    }

    @Test func toleratesMissingProperties() throws {
        let status = try JSONDecoder().decode(RobotStatus.self, from: Data(#"{"state": null, "battery": 42}"#.utf8))
        #expect(status.battery == 42)
        #expect(status.state == nil)
    }
}
