import Foundation
import Testing
@testable import DreameMac

@MainActor
@Suite struct AppModelTests {
    let secrets = InMemorySecretStore()
    let defaults = UserDefaults(suiteName: "AppModelTests-\(UUID().uuidString)")!

    @Test func loginStoresCredentialsAndLoadsStatus() async {
        let model = AppModel(service: MockRobotService(), secrets: secrets, defaults: defaults)
        await model.logIn(user: "me@example.com", password: "secret", country: "eu")

        #expect(model.phase == .ready)
        #expect(model.device?.name == "R2D2")
        #expect(model.status?.battery == 100)
        #expect(secrets.password(for: "me@example.com") == "secret")
        #expect(secrets.refreshToken(for: "me@example.com") == "mock-token")
    }

    @Test func reconnectsWithStoredCredentials() async {
        defaults.set("me@example.com", forKey: "user")
        secrets.setRefreshToken("token", for: "me@example.com")
        let model = AppModel(service: MockRobotService(), secrets: secrets, defaults: defaults)
        await model.start()
        #expect(model.phase == .ready)
    }

    @Test func staysLoggedOutWithoutCredentials() async {
        let model = AppModel(service: MockRobotService(), secrets: secrets, defaults: defaults)
        await model.start()
        #expect(model.phase == .loggedOut)
    }

    @Test func primaryCommandFollowsCleaningState() async {
        let service = MockRobotService()
        let model = AppModel(service: service, secrets: secrets, defaults: defaults)
        await model.logIn(user: "me@example.com", password: "secret", country: "eu")
        #expect(model.primaryCommand == .start)

        await model.perform(.start)
        #expect(await service.commands == [.start])
        #expect(model.primaryCommand == .pause)
    }

    @Test func logOutClearsSecrets() async {
        let model = AppModel(service: MockRobotService(), secrets: secrets, defaults: defaults)
        await model.logIn(user: "me@example.com", password: "secret", country: "eu")
        model.logOut()

        #expect(model.phase == .loggedOut)
        #expect(secrets.password(for: "me@example.com") == nil)
        #expect(secrets.refreshToken(for: "me@example.com") == nil)
    }

    @Test func loadsRoomsAfterLogin() async {
        let model = AppModel(service: MockRobotService(), secrets: secrets, defaults: defaults)
        await model.logIn(user: "me@example.com", password: "secret", country: "eu")
        #expect(model.rooms == MockRobotService.rooms)
    }

    @Test func presetsPersistAcrossLaunches() async {
        let model = AppModel(service: MockRobotService(), secrets: secrets, defaults: defaults)
        let preset = Preset(name: "Kitchen after dinner", roomIDs: [7], mode: .vacuum)
        model.save(preset)
        var edited = preset
        edited.suction = .turbo
        model.save(edited)

        let relaunched = AppModel(service: MockRobotService(), secrets: secrets, defaults: defaults)
        #expect(relaunched.presets == [edited])

        relaunched.delete(edited)
        #expect(AppModel(service: MockRobotService(), secrets: secrets, defaults: defaults).presets.isEmpty)
    }

    @Test func runningPresetSendsItToTheRobot() async throws {
        let service = MockRobotService()
        let model = AppModel(service: service, secrets: secrets, defaults: defaults)
        await model.logIn(user: "me@example.com", password: "secret", country: "eu")
        let preset = Preset(name: "Kitchen after dinner", roomIDs: [7], mode: .vacuum)

        try await model.run(preset)
        #expect(await service.cleanedPresets == [preset])
        #expect(model.status?.isCleaning == true)
        #expect(model.roomNames(for: preset) == "Dining Hall")
    }

    @Test func runningPresetWhileLoggedOutFails() async {
        let model = AppModel(service: MockRobotService(), secrets: secrets, defaults: defaults)
        await #expect(throws: RobotError.notLoggedIn) {
            try await model.run(Preset(name: "Kitchen", roomIDs: [7]))
        }
    }

    @Test func offlineRobotShowsOfflineAndRecovers() async throws {
        let service = MockRobotService(online: false)
        let model = AppModel(service: service, secrets: secrets, defaults: defaults)
        await model.logIn(user: "me@example.com", password: "secret", country: "eu")
        #expect(model.phase == .offline("R2D2 is offline"))
        await #expect(throws: RobotError.robotOffline("R2D2 is offline")) {
            try await model.run(Preset(name: "Kitchen", roomIDs: [7]))
        }

        await service.setOnline(true)
        await model.retry()
        #expect(model.phase == .ready)
    }
}
