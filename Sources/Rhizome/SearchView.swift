import SwiftUI
import RhizomeKit

/// Full-text search across the active graph (server-side FTS), shown as a search
/// tab. Each hit shows the matched node with a breadcrumb; tapping opens it in
/// context.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [String] = []
    @State private var path: [String] = []

    /// Real pages first (they're the primary hit), then the bullets that mention them —
    /// keeping the server's relevance order within each group.
    private var ordered: [String] {
        results.filter { model.isPage($0) } + results.filter { !model.isPage($0) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(ordered, id: \.self) { id in row(id) }
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
            .navigationDestination(for: String.self) { PageView(pageID: $0) }
        }
        .searchable(text: $query, prompt: "Search notes")
        .handleNodeLinks(path: $path, model: model)
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 250_000_000)   // debounce
            guard !Task.isCancelled else { return }
            results = await model.search(query)
        }
    }

    /// A small type chip — accent for pages, muted grey for mentions.
    private func chip(_ label: String, accent: Bool) -> some View {
        let color = accent ? Color.rzAccent : Color.rzInkFaint
        return Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(accent ? 0.14 : 0.12), in: Capsule())
    }

    /// One result row: a real page is highlighted (semibold, tinted background, an accent
    /// "Page"/"Journal" chip) and opens itself; a mention shows its text + breadcrumb with a
    /// muted "Mention" chip and opens its parent.
    @ViewBuilder
    private func row(_ id: String) -> some View {
        let page = model.isPage(id)
        NavigationLink(value: page ? id : (model.parentOf(id) ?? id)) {
            if page {
                HStack(spacing: 8) {
                    Text(RichText.attributed(model.doc?.nodes[id]?.text ?? "", doc: model.doc))
                        .font(.rz(16.5, .semibold))
                        .foregroundStyle(Color.rzInk)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    chip(model.doc?.nodes[id]?.cal == "day" ? "Journal" : "Page", accent: true)
                }
                .padding(.vertical, 3)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(RichText.attributed(model.doc?.nodes[id]?.text ?? "", doc: model.doc))
                            .font(.rz(16.5))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        chip("Mention", accent: false)
                    }
                    let trail = model.breadcrumb(of: id)
                    if !trail.isEmpty {
                        Text(trail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(page ? Color.rzAccent.opacity(0.07) : Color.rzPaper)
    }
}
