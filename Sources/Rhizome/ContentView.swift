import SwiftUI

/// Top-level router: resume a session, otherwise sign in, otherwise show the
/// native outline.
struct ContentView: View {
    @Environment(AppModel.self) private var model

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
                Tab("Search", systemImage: "magnifyingglass", role: .search) { SearchView() }
            }
        }
    }
}
