import SwiftUI
import RhizomeKit

/// A small toolbar sync-status glyph: spinner while saving, cloud when synced,
/// a warning if the last save failed.
struct SyncIndicator: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.isOffline {
            Image(systemName: "icloud.slash")
                .foregroundStyle(Color.rzInkFaint)
        } else {
            switch model.syncState {
            case .syncing:
                ProgressView().controlSize(.mini)
            case .error:
                Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange)
            case .synced:
                Image(systemName: "checkmark.icloud").foregroundStyle(Color.rzInkFaint)
            }
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
                // ---- Account ----
                Section("Account") {
                    LabeledContent("User", value: model.user?.username ?? "—")
                    if model.user?.isAdmin == true {
                        LabeledContent("Role", value: "Admin")
                    }
                    NavigationLink("Change password") { ChangePasswordView() }
                    NavigationLink("Statistics") { StatisticsView() }
                    if let base = URL(string: model.serverURLString.trimmingCharacters(in: .whitespaces)), base.scheme != nil {
                        Link("Privacy policy", destination: base.appendingPathComponent("privacy"))
                    }
                }

                // ---- Connection (server + graph) ----
                Section {
                    TextField("Server URL", text: $model.serverURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if let graph = model.activeGraph {
                        LabeledContent("Graph", value: graph.name)
                    }
                    if model.graphs.count > 1 {
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
                } header: {
                    Text("Connection")
                } footer: {
                    if model.graphs.count > 1 { Text("Tap a graph to switch to it.") }
                }

                // ---- Appearance ----
                Section {
                    Picker("Theme", selection: $model.theme) {
                        ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Accent", selection: $model.accent) {
                        ForEach(AccentChoice.allCases) { a in
                            HStack {
                                Circle().fill(rzAccentColor(a)).frame(width: 14, height: 14)
                                Text(a.label)
                            }.tag(a)
                        }
                    }
                    Stepper(value: $model.fontSize, in: 12...28, step: 0.5) {
                        LabeledContent("Font size", value: String(format: "%.1f pt", model.fontSize))
                    }
                    Stepper(value: $model.lineSpacing, in: 0...14, step: 1) {
                        LabeledContent("Line spacing", value: String(format: "%.0f pt", model.lineSpacing))
                    }
                    Toggle("Scale with system text size", isOn: $model.scaleWithSystem)
                    // live preview of size, spacing and accent (tag + link tones)
                    Text(RichText.attributed("The quick #brown fox jumps over the lazy dog.", doc: nil))
                        .font(model.scaleWithSystem ? .rz(model.fontSize) : .rzFixed(model.fontSize))
                        .lineSpacing(model.lineSpacing)
                        .foregroundStyle(Color.rzInk)
                    Button("Reset to defaults", role: .destructive) { model.resetDesign() }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("With scaling off, text stays a fixed size so the line you're editing matches the rest.")
                }

                // ---- Editing behaviour ----
                Section {
                    Toggle("Add timestamp to notes", isOn: $model.captureTimestamp)
                    Toggle("Haptic feedback", isOn: $model.haptics)
                    Toggle("Resolve location address", isOn: $model.geoResolveAddress)
                    NavigationLink("Editor toolbar") { EditorToolbarView() }
                } header: {
                    Text("Behaviour")
                } footer: {
                    Text("Timestamped notes are prefixed with the time like the r command — this preference is shared with the web app and your other devices. With “Resolve location address” on, a new location tag is reverse-geocoded to its street address; off keeps the raw coordinates. Long-press the location button to do the opposite just once.")
                }

                // ---- Uploads ----
                Section {
                    Stepper(value: $model.imageScalePercent, in: 20...100, step: 10) {
                        LabeledContent("Image size", value: "\(Int(model.imageScalePercent)) %")
                    }
                } header: {
                    Text("Uploads")
                } footer: {
                    Text("Downscale photos before upload to save space (100 % = full size).")
                }

                // ---- Security ----
                Section("Security") {
                    Toggle("Require Face ID / Touch ID", isOn: $model.appLock)
                }

                // ---- This device ----
                Section {
                    TextField("Device name", text: $model.deviceName)
                        .autocorrectionDisabled()
                } header: {
                    Text("This device")
                } footer: {
                    Text("Shown in the web app's page history, so you can tell which device made a change.")
                }

                // ---- Sync & diagnostics ----
                Section("Sync & diagnostics") {
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

                // ---- Sign out ----
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await model.signOut(); dismiss() }
                    }
                    NavigationLink("Delete account") { DeleteAccountView() }
                        .foregroundStyle(.red)
                } footer: {
                    Text("Deleting your account permanently removes it and the graphs you own from the server.")
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

/// Change the signed-in account's password (POST /api/account/password).
struct ChangePasswordView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var next = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var busy = false

    private var valid: Bool { !current.isEmpty && next.count >= 6 && next == confirm }

    var body: some View {
        Form {
            Section {
                SecureField("Current password", text: $current)
                SecureField("New password", text: $next)
                SecureField("Confirm new password", text: $confirm)
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
                else if !next.isEmpty && next.count < 6 { Text("New password must be at least 6 characters.") }
                else if !confirm.isEmpty && next != confirm { Text("Passwords don't match.") }
            }
            Section {
                Button {
                    busy = true; error = nil
                    Task {
                        let e = await model.changePassword(current: current, next: next)
                        busy = false
                        if let e { error = e } else { dismiss() }
                    }
                } label: {
                    if busy { ProgressView() } else { Text("Change password") }
                }
                .disabled(!valid || busy)
            }
        }
        .paperBackground()
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Storage usage + the applicable quota for the signed-in user (GET /api/me/stats).
struct StatisticsView: View {
    @Environment(AppModel.self) private var model
    @State private var stats: RStats?
    @State private var loading = true

    static func fmt(_ n: Int) -> String {
        let d = Double(n)
        if n < 1_000 { return "\(n) B" }
        if n < 1_000_000 { return String(format: "%.1f KB", d / 1e3) }
        if n < 1_000_000_000 { return String(format: "%.1f MB", d / 1e6) }
        return String(format: "%.2f GB", d / 1e9)
    }

    var body: some View {
        Form {
            if let s = stats {
                Section("Usage") {
                    LabeledContent("Pages", value: "\(s.pages)")
                    LabeledContent("Notes", value: Self.fmt(s.noteBytes))
                    LabeledContent("Images & files", value: Self.fmt(s.fileBytes))
                    LabeledContent("Total", value: Self.fmt(s.totalBytes))
                }
                if s.quotaBytes > 0 {
                    Section("Storage quota") { QuotaBar(stats: s) }
                } else {
                    Section { Text("No storage limit set.").foregroundStyle(.secondary) }
                }
            } else if loading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else {
                Section { Text("Could not load statistics.").foregroundStyle(.secondary) }
            }
        }
        .paperBackground()
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .task { stats = await model.fetchStats(); loading = false }
        .refreshable { stats = await model.fetchStats() }
    }
}

private struct QuotaBar: View {
    let stats: RStats
    var body: some View {
        let pct = Double(stats.totalBytes) / Double(max(1, stats.quotaBytes)) * 100
        let hardPct = 100 + Double(stats.tolerancePct)
        let color: Color = pct <= 100 ? .rzAccent : (pct <= hardPct ? .orange : .red)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: pct < 10 ? "%.1f%% used" : "%.0f%% used", pct))
                Spacer()
                Text("\(StatisticsView.fmt(stats.totalBytes)) / \(StatisticsView.fmt(stats.quotaBytes))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(color).frame(width: geo.size.width * min(1, pct / 100))
                }
            }
            .frame(height: 10)
            if pct > hardPct {
                Text("Storage full — new uploads are blocked until you free space.")
                    .font(.caption).foregroundStyle(.red)
            } else if pct > 100 {
                Text("Over your quota — within the \(stats.tolerancePct)% grace. Free space soon.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Permanently delete the signed-in account (DELETE /api/account). Requires the password
/// and an explicit confirmation, since it also removes the graphs the user owns.
struct DeleteAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirming = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Text("This permanently deletes your account and the graphs you own, including all their notes and files. This cannot be undone.")
                    .foregroundStyle(.secondary)
            }
            Section {
                SecureField("Password", text: $password)
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button(role: .destructive) {
                    confirming = true
                } label: {
                    if busy { ProgressView() } else { Text("Delete account") }
                }
                .disabled(password.isEmpty || busy)
            }
        }
        .paperBackground()
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete your account?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                busy = true; error = nil
                Task {
                    let e = await model.deleteAccount(password: password)
                    busy = false
                    if let e { error = e } else { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

/// Add / remove / reorder the editor keyboard toolbar's buttons.
struct EditorToolbarView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section {
                ForEach(model.editorTools) { tool in
                    Label(tool.label, systemImage: tool.icon)
                }
                .onMove { from, to in model.editorTools.move(fromOffsets: from, toOffset: to) }
                .onDelete { model.editorTools.remove(atOffsets: $0) }
            } header: {
                Text("In toolbar")
            } footer: {
                Text("Drag to reorder, swipe to remove. Shown left of Done while you edit a bullet.")
            }
            if !model.availableTools.isEmpty {
                Section("Available") {
                    ForEach(model.availableTools) { tool in
                        Button {
                            model.editorTools.append(tool)
                        } label: {
                            HStack {
                                Label(tool.label, systemImage: tool.icon)
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(Color.rzAccent)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            Section {
                Button("Restore defaults", role: .destructive) {
                    model.editorTools = EditorTool.defaultOrder
                }
            }
        }
        .paperBackground()
        .navigationTitle("Editor toolbar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}
