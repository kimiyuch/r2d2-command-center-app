import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Email", value: model.user ?? "–")
                LabeledContent("Region", value: model.country)
                if let device = model.device {
                    LabeledContent("Robot", value: "\(device.name) (\(device.model))")
                }
                Button("Log Out", role: .destructive) { model.logOut() }
                    .disabled(model.user == nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}
