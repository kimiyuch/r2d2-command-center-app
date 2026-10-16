import Foundation

/// An enum-like robot property as reported by the helper: the raw MIoT value plus the
/// `dreame_vacuum` enum name (snake_case, "unknown" if the value isn't known).
struct RobotValue: Codable, Hashable, Sendable {
    let raw: Int
    let name: String

    var label: String { name.humanized }
}

/// The X50 packs mode, self-clean interval and mop humidity into one cleaning mode value.
struct CleaningMode: Codable, Hashable, Sendable {
    let raw: Int
    let name: String
    let selfClean: Int
    let humidity: Int

    var label: String {
        switch name {
        case "sweeping": "Vacuum"
        case "mopping": "Mop"
        case "sweeping_and_mopping": "Vacuum & mop"
        case "mopping_after_sweeping": "Vacuum, then mop"
        default: name.humanized
        }
    }
}

struct RobotStatus: Codable, Hashable, Sendable {
    var state: RobotValue?
    var error: RobotValue?
    var battery: Int?
    var charging: RobotValue?
    var status: RobotValue?
    var suction: RobotValue?
    var task: RobotValue?
    var cleaningMode: CleaningMode?
    /// Robot position on the `RobotMap` image; nil until the map was loaded once.
    var robot: MapPoint?

    var hasError: Bool {
        guard let error else { return false }
        return error.raw != 0
    }

    var isCleaning: Bool {
        guard let name = state?.name else { return false }
        return Self.cleaningStates.contains(name)
    }

    var isPaused: Bool { state?.name == "paused" }

    var isDocked: Bool {
        guard let name = charging?.name else { return false }
        return name == "charging" || name == "charging_completed"
    }

    private static let cleaningStates: Set<String> = [
        "sweeping", "mopping", "sweeping_and_mopping", "spot_cleaning", "second_cleaning",
        "clean_summon", "heading_to_extra_cleaning",
    ]
}

struct RobotDevice: Codable, Hashable, Sendable, Identifiable {
    let did: String
    let name: String
    let model: String
    /// As reported by the Dreame cloud when logging in.
    var online: Bool?

    var id: String { did }
}

enum RobotCommand: String, CaseIterable, Sendable {
    case start, pause, stop, dock, locate

    var title: String {
        switch self {
        case .start: "Start"
        case .pause: "Pause"
        case .stop: "Stop"
        case .dock: "Dock"
        case .locate: "Locate"
        }
    }

    var systemImage: String {
        switch self {
        case .start: "play.fill"
        case .pause: "pause.fill"
        case .stop: "stop.fill"
        case .dock: "house.fill"
        case .locate: "speaker.wave.2.fill"
        }
    }
}

extension String {
    /// "charging_completed" -> "Charging completed"
    var humanized: String {
        let words = split(separator: "_").joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

struct Room: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let type: Int
}
