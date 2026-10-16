import Foundation

/// In-memory robot for SwiftUI previews and tests.
actor MockRobotService: RobotService {
    static let device = RobotDevice(did: "1", name: "R2D2", model: "dreame.vacuum.r5048h")

    static let rooms = [
        Room(id: 1, name: "Primary Bedroom", type: 2),
        Room(id: 6, name: "Living Room", type: 1),
        Room(id: 7, name: "Dining Hall", type: 5),
    ]

    private(set) var commands: [RobotCommand] = []
    private(set) var cleanedPresets: [Preset] = []
    private var current: RobotStatus
    private var online: Bool

    init(status: RobotStatus = .docked, online: Bool = true) {
        current = status
        self.online = online
    }

    func setOnline(_ online: Bool) {
        self.online = online
    }

    func login(_ credentials: Credentials) async throws -> LoginResult {
        LoginResult(refreshToken: "mock-token", devices: [Self.device])
    }

    func select(deviceID: String) async throws -> RobotDevice {
        guard online else { throw RobotError.robotOffline("R2D2 is offline") }
        return Self.device
    }

    func status() async throws -> RobotStatus {
        current
    }

    func perform(_ command: RobotCommand) async throws {
        commands.append(command)
        switch command {
        case .start: current.state = RobotValue(raw: 1, name: "sweeping")
        case .pause: current.state = RobotValue(raw: 3, name: "paused")
        case .stop: current.state = RobotValue(raw: 2, name: "idle")
        case .dock: current.state = RobotValue(raw: 5, name: "returning")
        case .locate: break
        }
    }

    func rooms() async throws -> [Room] {
        Self.rooms
    }

    func map() async throws -> RobotMap {
        .mock
    }

    func clean(_ preset: Preset) async throws {
        cleanedPresets.append(preset)
        current.state = RobotValue(raw: 1, name: "sweeping")
    }
}

extension RobotStatus {
    static let docked = RobotStatus(
        state: RobotValue(raw: 13, name: "charging_completed"),
        error: RobotValue(raw: 0, name: "no_error"),
        battery: 100,
        charging: RobotValue(raw: 1, name: "charging"),
        status: RobotValue(raw: 14, name: "sleeping"),
        suction: RobotValue(raw: 2, name: "strong"),
        task: RobotValue(raw: 0, name: "completed"),
        cleaningMode: CleaningMode(raw: 3842, name: "sweeping", selfClean: 15, humidity: 0)
    )
}

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]

    func string(for account: String) -> String? {
        lock.withLock { items[account] }
    }

    func set(_ value: String?, for account: String) {
        lock.withLock { items[account] = value }
    }
}

extension RobotMap {
    /// Three rooms side by side (ids 1, 6, 7 like `MockRobotService.rooms`) in a 30×10 home.
    static let mock: RobotMap = {
        func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> MapRing {
            MapRing(points: [MapPoint(x: x0, y: y0), MapPoint(x: x1, y: y0), MapPoint(x: x1, y: y1), MapPoint(x: x0, y: y1)])
        }
        return RobotMap(
            mapID: 1, width: 30, height: 10,
            rooms: [
                MapRoom(id: 1, name: "Primary Bedroom", x: 5, y: 5, area: 4, outline: [rect(0, 0, 10, 10)]),
                MapRoom(id: 6, name: "Living Room", x: 15, y: 5, area: 4, outline: [rect(10, 0, 20, 10)]),
                MapRoom(id: 7, name: "Dining Hall", x: 25, y: 5, area: 4, outline: [rect(20, 0, 30, 10)]),
            ],
            charger: MapPoint(x: 3, y: 7)
        )
    }()
}
