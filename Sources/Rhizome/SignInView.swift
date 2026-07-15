import SwiftUI

/// Native sign-in: server URL + username/password → a Rhizome session.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("https://rhizome.syslinx.org", text: $model.serverURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Sign in") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button(action: submit) {
                    HStack {
                        if model.busy { ProgressView() }
                        Text("Sign in")
                    }
                }
                .disabled(model.busy || username.isEmpty || password.isEmpty)
            }
            .paperBackground()
            .navigationTitle("Rhizome")
        }
    }

    private func submit() {
        Task { await model.signIn(username: username, password: password) }
    }
}
