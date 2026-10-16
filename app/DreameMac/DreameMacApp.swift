import SwiftUI

@main
struct DreameMacApp: App {
    @State private var model = AppModel.shared

    init() {
        // Writing to the helper's stdin after it exited must fail with an error, not kill the app.
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        Window(AppInfo.name, id: MainView.windowID) {
            MainView()
                .environment(model)
        }
        .defaultSize(width: 440, height: 640)
        .commands {
            RobotCommands(model: model)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(systemName: model.status?.isCleaning == true ? "robotic.vacuum.fill" : "robotic.vacuum")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct RobotCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Robot") {
            Button(model.primaryCommand.title) { Task { await model.perform(model.primaryCommand) } }
                .keyboardShortcut(.return, modifiers: .command)
            Button(RobotCommand.dock.title) { Task { await model.perform(.dock) } }
                .keyboardShortcut("d", modifiers: .command)
            Button(RobotCommand.stop.title) { Task { await model.perform(.stop) } }
                .keyboardShortcut(".", modifiers: .command)
            Button(RobotCommand.locate.title) { Task { await model.perform(.locate) } }
                .keyboardShortcut("l", modifiers: .command)
            if !model.presets.isEmpty {
                Divider()
                ForEach(Array(model.presets.prefix(9).enumerated()), id: \.element.id) { index, preset in
                    Button(preset.name) { Task { try? await model.run(preset) } }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            Divider()
            Button("Refresh Status") { Task { await model.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}

enum AppInfo {
    /// The user-visible app name, from Info.plist (CFBundleDisplayName).
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "R2D2 Command Center"
}
