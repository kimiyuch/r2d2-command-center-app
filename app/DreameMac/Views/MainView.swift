import SwiftUI

struct MainView: View {
    static let windowID = "main"

    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loggedOut:
                LoginView()
            case .connecting:
                VStack(spacing: 16) {
                    RobotArtwork(height: 140)
                    ProgressView("Connecting to Dreame…")
                }
            case .offline(let message):
                ContentUnavailableView {
                    VStack(spacing: 12) {
                        RobotArtwork(height: 120).opacity(0.5)
                        Text(message)
                    }
                } description: {
                    Text("Make sure it's switched on or in its dock, and connected to 2.4 GHz Wi-Fi. Checking again every minute.")
                } actions: {
                    Button("Check Now") { Task { await model.retry() } }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Can't reach the robot", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.retry() } }
                    Button("Log Out") { model.logOut() }
                }
            case .ready:
                RobotView()
            }
        }
        .frame(minWidth: 400, minHeight: 520)
    }
}

struct RobotView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if let status = model.status {
                if status.hasError, let error = status.error {
                    Label(error.label, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red, in: .rect(cornerRadius: 8))
                }
                details(status)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            Divider()
            ScrollView {
                PresetsSection()
            }
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 0)
            CommandBar(size: .large)
            footer
        }
        .padding(24)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            RobotArtwork(height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.device?.name ?? "Robot")
                    .font(.largeTitle.bold())
                Text(model.status?.state?.label ?? " ")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = model.status?.battery {
                BatteryLabel(level: battery, charging: model.status?.isDocked == true)
                    .font(.title3)
            }
        }
    }

    private func details(_ status: RobotStatus) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            row("Mode", status.cleaningMode?.label)
            row("Suction", status.suction?.label)
            row("Task", status.task?.label)
            row("Dock", status.charging?.label)
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(title).foregroundStyle(.secondary)
                Text(value)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let updated = model.lastUpdated {
                Text("Updated \(updated, format: .relative(presentation: .named))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
    }
}

/// The app's robot mascot (same artwork as the app icon).
struct RobotArtwork: View {
    let height: CGFloat

    var body: some View {
        Image("Robot")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

struct BatteryLabel: View {
    let level: Int
    let charging: Bool

    var body: some View {
        Label("\(level)%", systemImage: charging ? "battery.100percent.bolt" : symbol)
            .monospacedDigit()
    }

    private var symbol: String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// Start/Pause, Dock, Locate (and Stop while a run is active). Used in the window and the menu bar.
struct CommandBar: View {
    enum Size { case regular, large }

    @Environment(AppModel.self) private var model
    let size: Size

    var body: some View {
        HStack {
            button(model.primaryCommand, prominent: true)
            if model.status?.isCleaning == true || model.status?.isPaused == true {
                button(.stop)
            }
            button(.dock)
            button(.locate)
        }
        .controlSize(size == .large ? .large : .regular)
        .disabled(model.phase != .ready || model.isBusy)
    }

    @ViewBuilder
    private func button(_ command: RobotCommand, prominent: Bool = false) -> some View {
        let button = Button {
            Task { await model.perform(command) }
        } label: {
            if model.commandInFlight == command {
                ProgressView().controlSize(.small)
            } else {
                Label(command.title, systemImage: command.systemImage)
            }
        }
        .help(command.title)
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

#Preview {
    let model = AppModel(service: MockRobotService(), secrets: InMemorySecretStore())
    MainView()
        .environment(model)
        .task { await model.logIn(user: "preview@example.com", password: "x", country: "eu") }
}
