import Foundation

/// Presets as JSON in UserDefaults. Shared by the app and its App Intents (same process).
struct PresetStore {
    private static let key = "presets"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Preset] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
    }

    func save(_ presets: [Preset]) {
        defaults.set(try? JSONEncoder().encode(presets), forKey: Self.key)
    }
}
