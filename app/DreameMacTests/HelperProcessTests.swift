import Foundation
import Testing
@testable import DreameMac

@Suite struct HelperProcessTests {
    private func makeHelper(timeout: Duration = .seconds(10)) -> HelperProcess {
        let testsDirectory = URL(filePath: #filePath).deletingLastPathComponent()
        return HelperProcess(
            pythonURL: testsDirectory.appending(path: "../../helper/.venv/bin/python").standardizedFileURL,
            scriptURL: testsDirectory.appending(path: "fake_helper.py"),
            timeout: timeout
        )
    }

    @Test func decodesResult() async throws {
        let helper = makeHelper()
        let status = try await helper.call("status", params: NoParams(), as: RobotStatus.self)
        #expect(status == .docked.with(status: RobotValue(raw: 6, name: "charging")))
        await helper.stop()
    }

    @Test func mapsHelperErrors() async throws {
        let helper = makeHelper()
        await #expect(throws: RobotError.authFailed) {
            try await helper.call("login", params: NoParams(), as: NoParams.self)
        }
        await helper.stop()
    }

    @Test func restartsAfterExit() async throws {
        let helper = makeHelper()
        await #expect(throws: RobotError.helperUnavailable("The helper exited.")) {
            try await helper.call("exit", params: NoParams(), as: NoParams.self)
        }
        let status = try await helper.call("status", params: NoParams(), as: RobotStatus.self)
        #expect(status.battery == 100)
        await helper.stop()
    }

    @Test func timesOut() async throws {
        let helper = makeHelper(timeout: .milliseconds(300))
        await #expect(throws: RobotError.timeout) {
            try await helper.call("hang", params: NoParams(), as: NoParams.self)
        }
        await helper.stop()
    }
}

extension RobotStatus {
    func with(status: RobotValue) -> RobotStatus {
        var copy = self
        copy.status = status
        return copy
    }
}
