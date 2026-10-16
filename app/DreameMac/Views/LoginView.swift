import SwiftUI

struct LoginView: View {
    /// Dreamehome cloud regions. Europe (incl. Switzerland) is `eu`.
    static let regions: [(code: String, name: String)] = [
        ("eu", "Europe"),
        ("us", "North America"),
        ("sg", "Asia Pacific"),
        ("ru", "Russia"),
        ("in", "India"),
        ("kr", "Korea"),
        ("cn", "China"),
    ]

    @Environment(AppModel.self) private var model
    @State private var user = ""
    @State private var password = ""
    @State private var country = "eu"
    @State private var isLoggingIn = false

    var body: some View {
        Form {
            VStack(spacing: 8) {
                RobotArtwork(height: 150)
                Text(AppInfo.name).font(.title.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Section {
                TextField("Email", text: $user)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                Picker("Region", selection: $country) {
                    ForEach(Self.regions, id: \.code) { region in
                        Text(region.name).tag(region.code)
                    }
                }
            } header: {
                Text("Dreamehome Account")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let message = model.errorMessage {
                        Text(message).foregroundStyle(.red)
                    }
                    Text("Dreame locks the account after 5 wrong passwords. Paste it from your password manager.")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                isLoggingIn = true
                Task {
                    await model.logIn(user: user.trimmingCharacters(in: .whitespaces), password: password, country: country)
                    isLoggingIn = false
                }
            } label: {
                if isLoggingIn {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Log In")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(user.isEmpty || password.isEmpty || isLoggingIn)
        }
        .formStyle(.grouped)
        .onAppear {
            user = model.user ?? ""
            country = model.country
        }
    }
}
