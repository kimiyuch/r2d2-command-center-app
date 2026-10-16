import Foundation

/// `RobotService` backed by the Python helper (vendored `dreame_vacuum` cloud protocol).
actor HelperRobotService: RobotService {
    private let helper: HelperProcess
    private let refreshTokenChanged: @Sendable (String) -> Void
    private var credentials: Credentials?
    private var deviceID: String?

    init(helperDirectory: URL, refreshTokenChanged: @escaping @Sendable (String) -> Void) {
        helper = HelperProcess(
            pythonURL: helperDirectory.appending(path: ".venv/bin/python"),
            scriptURL: helperDirectory.appending(path: "dreame_helper.py")
        )
        self.refreshTokenChanged = refreshTokenChanged
    }

    /// The helper directory comes from Info.plist (`DreameHelperDirectory`, set at build time).
    static var bundledHelperDirectory: URL? {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "DreameHelperDirectory") as? String else {
            return nil
        }
        return URL(filePath: path).standardizedFileURL
    }

    func login(_ credentials: Credentials) async throws -> LoginResult {
        let result = try await helper.call("login", params: LoginParams(credentials), as: LoginPayload.self)
        var credentials = credentials
        if let token = result.refreshToken, token != credentials.refreshToken {
            credentials.refreshToken = token
            refreshTokenChanged(token)
        }
        self.credentials = credentials
        deviceID = nil
        return LoginResult(refreshToken: result.refreshToken, devices: result.devices)
    }

    func select(deviceID: String) async throws -> RobotDevice {
        let device = try await helper.call("select", params: ["did": deviceID], as: RobotDevice.self)
        self.deviceID = deviceID
        return device
    }

    func status() async throws -> RobotStatus {
        try await withSession {
            try await helper.call("status", params: NoParams(), as: RobotStatus.self)
        }
    }

    func perform(_ command: RobotCommand) async throws {
        try await withSession {
            _ = try await helper.call("action", params: ["name": command.rawValue], as: NoParams.self)
        }
    }

    func rooms() async throws -> [Room] {
        try await withSession {
            try await helper.call("rooms", params: NoParams(), as: [Room].self)
        }
    }

    func clean(_ preset: Preset) async throws {
        try await withSession {
            _ = try await helper.call("cleanRooms", params: CleanRoomsParams(preset), as: NoParams.self)
        }
    }

    /// The helper keeps its session in memory. If it restarted, log in and select the robot again, then retry once.
    private func withSession<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as RobotError {
            guard error == .notLoggedIn || error == .noDevice, let credentials, let deviceID else { throw error }
            _ = try await login(credentials)
            _ = try await select(deviceID: deviceID)
            return try await operation()
        }
    }
}

private struct LoginParams: Encodable, Sendable {
    let user: String
    let country: String
    let password: String?
    let refreshToken: String?

    init(_ credentials: Credentials) {
        user = credentials.user
        country = credentials.country
        password = credentials.password
        refreshToken = credentials.refreshToken
    }
}

private struct CleanRoomsParams: Encodable, Sendable {
    let rooms: [Int]
    let mode: String?
    let suction: String?
    let repeats: Int

    init(_ preset: Preset) {
        rooms = preset.roomIDs
        mode = preset.mode?.rawValue
        suction = preset.suction?.rawValue
        repeats = preset.repeats
    }
}

private struct LoginPayload: Decodable {
    let refreshToken: String?
    let devices: [RobotDevice]
}
