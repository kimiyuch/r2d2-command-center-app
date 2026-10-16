import AppIntents
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loggedOut
        case connecting
        case ready
        /// Logged in, but the robot isn't connected to the Dreame cloud. Rechecked every `offlineRetryInterval`.
        case offline(String)
        case failed(String)
    }

    static let pollInterval: Duration = .seconds(20)
    static let offlineRetryInterval: Duration = .seconds(60)
    static let refreshDelayAfterCommand: Duration = .seconds(2)

    private(set) var phase: Phase = .loggedOut
    private(set) var device: RobotDevice?
    private(set) var status: RobotStatus?
    private(set) var lastUpdated: Date?
    private(set) var commandInFlight: RobotCommand?
    private(set) var rooms: [Room] = []
    private(set) var presets: [Preset]
    private(set) var presetInFlight: Preset.ID?
    /// Last error from a login attempt, refresh or command. Cleared by the next success.
    private(set) var errorMessage: String?

    private let service: any RobotService
    private let secrets: any SecretStore
    private let defaults: UserDefaults
    private let presetStore: PresetStore
    private var started = false
    private var pollTask: Task<Void, Never>?
    private var offlineRetryTask: Task<Void, Never>?

    init(service: any RobotService, secrets: any SecretStore, defaults: UserDefaults = .standard) {
        self.service = service
        self.secrets = secrets
        self.defaults = defaults
        presetStore = PresetStore(defaults: defaults)
        presets = presetStore.load()
    }

    /// The app and its App Intents share one model (and with it one helper process).
    static let shared = live()

    private static func live() -> AppModel {
        guard let helperDirectory = HelperRobotService.bundledHelperDirectory else {
            preconditionFailure("DreameHelperDirectory missing from Info.plist")
        }
        let secrets = KeychainStore()
        let service = HelperRobotService(helperDirectory: helperDirectory) { token in
            // The helper may log in again on its own (e.g. after a restart) and get a new refresh token.
            if let user = UserDefaults.standard.string(forKey: Keys.user) {
                secrets.setRefreshToken(token, for: user)
            }
        }
        let model = AppModel(service: service, secrets: secrets)
        Task { await model.start() }
        return model
    }

    var user: String? { defaults.string(forKey: Keys.user) }
    var country: String { defaults.string(forKey: Keys.country) ?? "eu" }

    /// The main action: pause while cleaning, otherwise start (which also resumes a paused run).
    var isBusy: Bool { commandInFlight != nil || presetInFlight != nil }

    var primaryCommand: RobotCommand {
        status?.isCleaning == true ? .pause : .start
    }

    /// Reconnects with stored credentials, once per launch.
    func start() async {
        guard !started else { return }
        started = true
        guard let user else { return }
        let password = secrets.password(for: user)
        let token = secrets.refreshToken(for: user)
        guard password != nil || token != nil else { return }
        await connect(Credentials(user: user, country: country, password: password, refreshToken: token))
    }

    func logIn(user: String, password: String, country: String) async {
        await connect(Credentials(user: user, country: country, password: password, refreshToken: nil))
    }

    func retry() async {
        started = false
        await start()
    }

    func logOut() {
        pollTask?.cancel()
        offlineRetryTask?.cancel()
        if let user {
            secrets.setPassword(nil, for: user)
            secrets.setRefreshToken(nil, for: user)
        }
        defaults.removeObject(forKey: Keys.user)
        defaults.removeObject(forKey: Keys.deviceID)
        device = nil
        status = nil
        rooms = []
        lastUpdated = nil
        errorMessage = nil
        phase = .loggedOut
    }

    func refresh() async {
        guard phase == .ready else { return }
        do {
            status = try await service.status()
            lastUpdated = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func perform(_ command: RobotCommand) async {
        try? await execute(command)
    }

    /// Sends a command. Throws so App Intents can report failures; the UI shows `errorMessage`.
    func execute(_ command: RobotCommand) async throws {
        try await ensureConnected()
        guard !isBusy else { return }
        commandInFlight = command
        defer { commandInFlight = nil }
        do {
            try await service.perform(command)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
        try? await Task.sleep(for: Self.refreshDelayAfterCommand)
        await refresh()
    }

    /// Runs a preset. Throws so App Intents can report failures; the UI shows `errorMessage`.
    func run(_ preset: Preset) async throws {
        try await ensureConnected()
        guard !isBusy else { return }
        presetInFlight = preset.id
        defer { presetInFlight = nil }
        do {
            try await service.clean(preset)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
        try? await Task.sleep(for: Self.refreshDelayAfterCommand)
        await refresh()
    }

    func loadRooms() async {
        do {
            rooms = try await service.rooms()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func roomNames(for preset: Preset) -> String {
        let names = preset.roomIDs.compactMap { id in rooms.first { $0.id == id }?.name }
        return names.isEmpty ? "No rooms" : names.formatted(.list(type: .and))
    }

    func save(_ preset: Preset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        presetsChanged()
    }

    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        presetsChanged()
    }

    func movePresets(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
        presetsChanged()
    }

    private func presetsChanged() {
        presetStore.save(presets)
        // Lets Siri match the new preset names in "Run <preset> with R2D2 Command Center".
        RobotShortcuts.updateAppShortcutParameters()
    }

    /// An App Intent may launch the app; wait for the automatic reconnect instead of failing right away.
    private func ensureConnected() async throws {
        await start()
        let deadline = ContinuousClock.now + .seconds(60)
        if case .offline = phase { await retry() }
        while phase == .connecting, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }
        switch phase {
        case .ready: return
        case .offline(let message): throw RobotError.robotOffline(message)
        default: throw RobotError.notLoggedIn
        }
    }

    private func connect(_ credentials: Credentials) async {
        pollTask?.cancel()
        offlineRetryTask?.cancel()
        phase = .connecting
        errorMessage = nil
        do {
            let result = try await service.login(credentials)
            defaults.set(credentials.user, forKey: Keys.user)
            defaults.set(credentials.country, forKey: Keys.country)
            if let password = credentials.password {
                secrets.setPassword(password, for: credentials.user)
            }
            if let token = result.refreshToken {
                secrets.setRefreshToken(token, for: credentials.user)
            }

            let savedID = defaults.string(forKey: Keys.deviceID)
            guard let deviceID = result.devices.first(where: { $0.did == savedID })?.did ?? result.devices.first?.did
            else {
                throw RobotError.noDevice
            }
            device = try await service.select(deviceID: deviceID)
            defaults.set(deviceID, forKey: Keys.deviceID)
            phase = .ready
            await refresh()
            await loadRooms()
            startPolling()
        } catch RobotError.robotOffline(let message) {
            phase = .offline(message)
            offlineRetryTask = Task { [weak self] in
                try? await Task.sleep(for: Self.offlineRetryInterval)
                guard !Task.isCancelled else { return }
                await self?.retry()
            }
        } catch RobotError.authFailed {
            // Stored credentials no longer work: back to the login form.
            phase = .loggedOut
            errorMessage = RobotError.authFailed.errorDescription
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    private enum Keys {
        static let user = "user"
        static let country = "country"
        static let deviceID = "deviceID"
    }
}
