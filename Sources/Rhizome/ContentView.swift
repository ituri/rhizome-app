import SwiftUI

/// Top-level router: resume a session, otherwise sign in, otherwise show the
/// native outline.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showCapture = false
    @State private var captureText = ""

    var body: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .tint(.secondary)
        case .signedOut:
            SignInView()
        case .ready:
            TabView {
                Tab("Journal", systemImage: "calendar") { JournalView() }
                Tab("Pages", systemImage: "doc.text") { PagesView() }
                Tab("Assets", systemImage: "photo.on.rectangle") { AssetsView() }
                Tab("Search", systemImage: "magnifyingglass", role: .search) { SearchView() }
            }
            .overlay { if model.appLock && model.locked { LockView() } }
            // widget deep link (rhizome://capture) → the same quick-capture sheet as the + button,
            // available whichever tab is showing. onAppear covers a cold launch by the widget.
            .alert("Capture to today", isPresented: $showCapture) {
                TextField("Note", text: $captureText)
                Button("Add") {
                    let text = captureText; captureText = ""
                    Task { await model.captureToday(text) }
                }
                Button("Cancel", role: .cancel) { captureText = "" }
            }
            .onChange(of: model.pendingCapture) { _, want in if want { consumeCapture() } }
            .onAppear { if model.pendingCapture { consumeCapture() } }
        }
    }

    private func consumeCapture() {
        model.pendingCapture = false
        showCapture = true
    }
}

/// Covers the app until the user passes Face ID / Touch ID (or the device passcode).
struct LockView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.rzPaper.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Color.rzInkFaint)
                Text("Rhizome is locked").font(.rz(18, .semibold)).foregroundStyle(Color.rzInk)
                Button("Unlock") { Task { await model.unlock() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .task { await model.unlock() }
    }
}
