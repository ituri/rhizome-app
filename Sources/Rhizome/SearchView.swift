import SwiftUI
import RhizomeKit

/// Full-text search across the active graph (server-side FTS), shown as a search
/// tab. Each hit shows the matched node with a breadcrumb; tapping opens it in
/// context.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [String] = []

    var body: some View {
        NavigationStack {
            List(results, id: \.self) { id in
                NavigationLink(value: id) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(RichText.attributed(model.doc?.nodes[id]?.text ?? "", doc: model.doc))
                            .lineLimit(2)
                        let trail = model.breadcrumb(of: id)
                        if !trail.isEmpty {
                            Text(trail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.rzPaper)
            }
            .outlineList()
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Search your graph", systemImage: "magnifyingglass")
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                PageView(pageID: model.parentOf(id) ?? id)
            }
        }
        .searchable(text: $query, prompt: "Search notes")
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 250_000_000)   // debounce
            guard !Task.isCancelled else { return }
            results = await model.search(query)
        }
    }
}
