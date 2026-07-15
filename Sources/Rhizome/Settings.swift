import SwiftUI
import RhizomeKit

/// A small toolbar sync-status glyph: spinner while saving, cloud when synced,
/// a warning if the last save failed.
struct SyncIndicator: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        switch model.syncState {
        case .syncing:
            ProgressView().controlSize(.mini)
        case .error:
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.orange)
        case .synced:
            Image(systemName: "checkmark.icloud")
                .foregroundStyle(.secondary)
        }
    }
}

/// The Settings screen (presented as a sheet): account, server, graph, sync, sign-out.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("User", value: model.user?.username ?? "—")
                    if model.user?.isAdmin == true {
                        LabeledContent("Role", value: "Admin")
                    }
                }

                Section("Server") {
                    TextField("Server URL", text: $model.serverURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if let graph = model.activeGraph {
                        LabeledContent("Graph", value: graph.name)
                    }
                }

                Section {
                    Toggle("Add timestamp to notes", isOn: $model.captureTimestamp)
                } header: {
                    Text("Capture")
                } footer: {
                    Text("New notes added with + are prefixed with the time, like the r command.")
                }

                if model.graphs.count > 1 {
                    Section("Switch graph") {
                        ForEach(model.graphs) { graph in
                            Button {
                                Task { await model.selectGraph(graph.id); dismiss() }
                            } label: {
                                HStack {
                                    Text(graph.name)
                                    Spacer()
                                    if graph.id == model.activeGraphID {
                                        Image(systemName: "checkmark").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }

                Section("Sync") {
                    LabeledContent("Status") {
                        switch model.syncState {
                        case .syncing: Text("Saving…").foregroundStyle(.secondary)
                        case .error: Text("Last save failed").foregroundStyle(.orange)
                        case .synced: Text("Up to date").foregroundStyle(.secondary)
                        }
                    }
                    Button("Reload from server") {
                        Task { await model.loadDoc(); dismiss() }
                    }
                }

                Section("Diagnostics") {
                    LabeledContent("Last sync") {
                        Text(model.lastSync).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Run sync self-test") {
                        Task { await model.syncSelfTest() }
                    }
                    Text(model.selfTestResult)
                        .font(.caption)
                        .foregroundStyle(model.selfTestResult.hasPrefix("✗") ? .orange : .secondary)
                        .textSelection(.enabled)
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await model.signOut(); dismiss() }
                    }
                }
            }
            .paperBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
