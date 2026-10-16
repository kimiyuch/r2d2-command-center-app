import Foundation

/// The user's floor plan corrections (room rectangles), per map, as JSON in UserDefaults.
struct FloorPlanStore {
    private static let key = "floorPlanEdits"
    let defaults: UserDefaults

    func edits(forMap mapID: Int) -> [Int: MapRect] {
        all()[String(mapID)].map { Dictionary(uniqueKeysWithValues: $0.compactMap { key, rect in Int(key).map { ($0, rect) } }) } ?? [:]
    }

    func save(_ edits: [Int: MapRect], forMap mapID: Int) {
        var all = all()
        all[String(mapID)] = edits.isEmpty ? nil : Dictionary(uniqueKeysWithValues: edits.map { (String($0.key), $0.value) })
        defaults.set(try? JSONEncoder().encode(all), forKey: Self.key)
    }

    private func all() -> [String: [String: MapRect]] {
        guard let data = defaults.data(forKey: Self.key) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: MapRect]].self, from: data)) ?? [:]
    }
}
