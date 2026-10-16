import Foundation

struct Credentials: Sendable, Equatable {
    var user: String
    var country: String
    var password: String?
    var refreshToken: String?
}

struct LoginResult: Sendable {
    let refreshToken: String?
    let devices: [RobotDevice]
}

enum RobotError: LocalizedError, Equatable {
    /// Wrong password or expired session. The user has to log in again.
    case authFailed
    case notLoggedIn
    case noDevice
    /// The robot has no connection to the Dreame cloud (off, flat battery, Wi-Fi).
    case robotOffline(String)
    case requestFailed(String)
    case helperUnavailable(String)
    case timeout
    case other(code: String, message: String)

    init(code: String, message: String) {
        switch code {
        case "auth_failed": self = .authFailed
        case "not_logged_in": self = .notLoggedIn
        case "no_device": self = .noDevice
        case "robot_offline": self = .robotOffline(message)
        case "request_failed", "login_failed": self = .requestFailed(message)
        default: self = .other(code: code, message: message)
        }
    }

    var errorDescription: String? {
        switch self {
        case .authFailed: "Login failed. Check email, password and region."
        case .notLoggedIn: "Not logged in."
        case .noDevice: "No robot found on this account."
        case .robotOffline(let message): message
        case .requestFailed(let message): "Dreame cloud request failed: \(message)"
        case .helperUnavailable(let message): "The helper couldn't be started: \(message)"
        case .timeout: "The Dreame cloud didn't respond in time."
        case .other(_, let message): message
        }
    }
}

/// What the UI needs from the robot. Implemented by the Python helper bridge and by a mock for previews/tests.
protocol RobotService: Sendable {
    func login(_ credentials: Credentials) async throws -> LoginResult
    func select(deviceID: String) async throws -> RobotDevice
    func status() async throws -> RobotStatus
    func perform(_ command: RobotCommand) async throws
    func rooms() async throws -> [Room]
    func clean(_ preset: Preset) async throws
}
