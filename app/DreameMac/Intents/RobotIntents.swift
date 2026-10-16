import AppIntents

// Presets and robot commands for Shortcuts, Siri and Spotlight. Intents run inside the app
// (launching it in the background if needed) and share `AppModel.shared`.

struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Cleaning Preset"
    static let defaultQuery = PresetQuery()

    let id: UUID
    let name: String

    init(_ preset: Preset) {
        id = preset.id
        name = preset.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PresetQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PresetEntity] {
        PresetStore().load().filter { identifiers.contains($0.id) }.map(PresetEntity.init)
    }

    func entities(matching string: String) async throws -> [PresetEntity] {
        PresetStore().load().filter { $0.name.localizedStandardContains(string) }.map(PresetEntity.init)
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        PresetStore().load().map(PresetEntity.init)
    }
}

struct RunPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Cleaning Preset"
    static let description = IntentDescription("Cleans the rooms of a saved preset.")

    @Parameter(title: "Preset")
    var preset: PresetEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let saved = model.presets.first(where: { $0.id == preset.id }) else {
            throw RobotError.other(code: "unknown_preset", message: "This preset no longer exists.")
        }
        try await model.run(saved)
        return .result(dialog: "Started \(saved.name).")
    }
}

struct StartCleaningIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Cleaning"
    static let description = IntentDescription("Starts or resumes cleaning.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppModel.shared.execute(.start)
        return .result(dialog: "Started cleaning.")
    }
}

struct PauseCleaningIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Cleaning"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppModel.shared.execute(.pause)
        return .result(dialog: "Paused.")
    }
}

struct SendHomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Robot Home"
    static let description = IntentDescription("Sends the robot back to its dock.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppModel.shared.execute(.dock)
        return .result(dialog: "Heading home.")
    }
}

struct LocateRobotIntent: AppIntent {
    static let title: LocalizedStringResource = "Locate Robot"

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AppModel.shared.execute(.locate)
        return .result()
    }
}

struct RobotStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Robot Status"

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = AppModel.shared
        if model.phase != .ready { await model.start() }
        await model.refresh()
        guard let status = model.status else { throw RobotError.notLoggedIn }
        var text = status.state?.label ?? "Unknown"
        if let battery = status.battery { text += ", battery \(battery)%" }
        if status.hasError, let error = status.error { text += ", error: \(error.label)" }
        return .result(value: text, dialog: "\(text)")
    }
}

struct RobotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunPresetIntent(),
            phrases: ["Run \(\.$preset) with \(.applicationName)", "Start \(\.$preset) in \(.applicationName)"],
            shortTitle: "Run Preset",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: SendHomeIntent(),
            phrases: ["Send the robot home with \(.applicationName)"],
            shortTitle: "Send Home",
            systemImageName: "house"
        )
        AppShortcut(
            intent: StartCleaningIntent(),
            phrases: ["Start cleaning with \(.applicationName)"],
            shortTitle: "Start Cleaning",
            systemImageName: "play"
        )
        AppShortcut(
            intent: PauseCleaningIntent(),
            phrases: ["Pause cleaning with \(.applicationName)"],
            shortTitle: "Pause",
            systemImageName: "pause"
        )
        AppShortcut(
            intent: RobotStatusIntent(),
            phrases: ["What is the robot doing in \(.applicationName)"],
            shortTitle: "Status",
            systemImageName: "robotic.vacuum"
        )
    }
}
