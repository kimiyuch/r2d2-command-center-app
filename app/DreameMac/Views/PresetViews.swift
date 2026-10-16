import SwiftUI

/// Preset buttons plus add/edit, shown in the main window.
struct PresetsSection: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Preset?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Presets").font(.headline)
                Spacer()
                Button("New Preset", systemImage: "plus") {
                    editing = Preset(name: "", roomIDs: [], mode: .vacuum)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(model.rooms.isEmpty)
                .help(model.rooms.isEmpty ? "Waiting for the room list…" : "New Preset")
            }

            if model.presets.isEmpty {
                Text("Save a cleaning job, like “Kitchen after dinner, vacuum only”, to run it with one click, a keyboard shortcut or Siri.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.presets.enumerated()), id: \.element.id) { index, preset in
                    PresetRow(preset: preset, shortcutNumber: index < 9 ? index + 1 : nil) {
                        editing = preset
                    }
                }
            }
        }
        .sheet(item: $editing) { preset in
            PresetEditor(preset: preset, isNew: !model.presets.contains { $0.id == preset.id })
        }
    }
}

struct PresetRow: View {
    @Environment(AppModel.self) private var model
    let preset: Preset
    let shortcutNumber: Int?
    let edit: () -> Void

    var body: some View {
        HStack {
            Button {
                Task { try? await model.run(preset) }
            } label: {
                HStack {
                    if model.presetInFlight == preset.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.circle.fill").foregroundStyle(.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                        Text(preset.summary(rooms: model.roomNames(for: preset)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let shortcutNumber {
                        Text("⌘\(shortcutNumber)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(model.phase != .ready || model.isBusy)

            Button("Edit", systemImage: "pencil", action: edit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Delete", role: .destructive) { model.delete(preset) }
        }
    }
}

struct PresetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var preset: Preset
    let isNew: Bool

    var body: some View {
        Form {
            TextField("Name", text: $preset.name, prompt: Text("Kitchen after dinner"))

            Section("Rooms") {
                ForEach(model.rooms) { room in
                    Toggle(room.name, isOn: binding(for: room))
                }
            }

            Section("Cleaning") {
                Picker("Mode", selection: $preset.mode) {
                    Text("Robot's current setting").tag(CleaningModeOption?.none)
                    ForEach(CleaningModeOption.allCases, id: \.self) { mode in
                        Text(mode.title).tag(Optional(mode))
                    }
                }
                Picker("Suction", selection: $preset.suction) {
                    Text("Robot's current setting").tag(SuctionOption?.none)
                    ForEach(SuctionOption.allCases, id: \.self) { suction in
                        Text(suction.title).tag(Optional(suction))
                    }
                }
                Stepper("Passes: \(preset.repeats)", value: $preset.repeats, in: 1...3)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 520)
        // Picks up rooms renamed or split in the Dreamehome app since the app connected.
        .task { await model.loadRooms() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") {
                    preset.name = preset.name.trimmingCharacters(in: .whitespaces)
                    model.save(preset)
                    dismiss()
                }
                .disabled(preset.name.trimmingCharacters(in: .whitespaces).isEmpty || preset.roomIDs.isEmpty)
            }
            if !isNew {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        model.delete(preset)
                        dismiss()
                    }
                }
            }
        }
    }

    /// Keeps room order as on the map, so the robot cleans in a predictable order.
    private func binding(for room: Room) -> Binding<Bool> {
        Binding {
            preset.roomIDs.contains(room.id)
        } set: { isOn in
            var ids = Set(preset.roomIDs)
            if isOn { ids.insert(room.id) } else { ids.remove(room.id) }
            preset.roomIDs = model.rooms.map(\.id).filter(ids.contains)
        }
    }
}

extension Preset {
    func summary(rooms: String) -> String {
        var parts = [rooms]
        if let mode { parts.append(mode.title) }
        if let suction { parts.append(suction.title) }
        if repeats > 1 { parts.append("\(repeats)×") }
        return parts.joined(separator: " · ")
    }
}
