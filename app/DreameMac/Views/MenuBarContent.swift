import SwiftUI

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.phase == .ready {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.device?.name ?? "Robot").font(.headline)
                        Text(model.status?.state?.label ?? "…").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let battery = model.status?.battery {
                        BatteryLabel(level: battery, charging: model.status?.isDocked == true)
                    }
                }
                if model.status?.hasError == true, let error = model.status?.error {
                    Label(error.label, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                CommandBar(size: .regular)
                    .labelStyle(.iconOnly)
                if !model.presets.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.presets) { preset in
                            Button {
                                Task { try? await model.run(preset) }
                            } label: {
                                Label(preset.name, systemImage: model.presetInFlight == preset.id ? "hourglass" : "play.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.isBusy)
                        }
                    }
                }
                if let message = model.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            } else {
                Text(phaseDescription)
                    .foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button("Open \(AppInfo.name)") {
                    openWindow(id: MainView.windowID)
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 280)
    }

    private var phaseDescription: String {
        switch model.phase {
        case .connecting: "Connecting…"
        case .offline(let message): message
        default: "Not connected"
        }
    }
}
