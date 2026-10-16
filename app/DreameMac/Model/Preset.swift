import Foundation

/// A saved cleaning job, e.g. "Kitchen after dinner: kitchen, vacuum only".
/// Every shortcut surface (window, menu bar, keyboard, Shortcuts/Siri) runs presets.
struct Preset: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var roomIDs: [Int]
    /// nil keeps the robot's current setting.
    var mode: CleaningModeOption?
    var suction: SuctionOption?
    var repeats = 1
}

enum CleaningModeOption: String, Codable, CaseIterable, Sendable {
    case vacuum
    case mop
    case vacuumAndMop = "vacuum_and_mop"
    case mopAfterVacuum = "mop_after_vacuum"

    var title: String {
        switch self {
        case .vacuum: "Vacuum only"
        case .mop: "Mop only"
        case .vacuumAndMop: "Vacuum & mop"
        case .mopAfterVacuum: "Vacuum, then mop"
        }
    }
}

enum SuctionOption: String, Codable, CaseIterable, Sendable {
    case quiet, standard, strong, turbo

    var title: String { rawValue.capitalized }
}
