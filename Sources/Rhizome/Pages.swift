import SwiftUI
import RhizomeKit

/// The Pages tab: top-level pages (root's children, minus the calendar), each
/// opening into its own outline — mirroring the web app's "All pages".
struct PagesView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false

    private func pageIDs(_ doc: RDoc) -> [String] {
        (doc.nodes[doc.root]?.children ?? []).filter { doc.nodes[$0]?.cal != "root" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let doc = model.doc {
                    let pages = pageIDs(doc)
                    if pages.isEmpty {
                        ContentUnavailableView("No pages yet", systemImage: "doc.text")
                    } else {
                        List(pages, id: \.self) { id in
                            NavigationLink(value: id) {
                                Text(RichText.attributed(doc.nodes[id]?.text ?? "", doc: doc))
                                    .font(.rz(17))
                                    .lineLimit(1)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.rzPaper)
                        }
                        .listStyle(.plain)
                        .paperBackground()
                        .navigationDestination(for: String.self) { PageView(pageID: $0) }
                    }
                } else if model.busy {
                    ProgressView()
                } else {
                    ContentUnavailableView("No pages", systemImage: "doc.text")
                }
            }
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { GraphSwitcher() }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let doc = model.doc {
                            _ = model.insertChild(of: doc.root)
                            Task { await model.loadDoc() }
                        }
                    } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) { SyncIndicator() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .refreshable { await model.loadDoc() }
        }
    }
}

/// A single page opened from the Pages list: its title + editable outline.
struct PageView: View {
    @Environment(AppModel.self) private var model
    let pageID: String
    @FocusState private var focused: String?

    var body: some View {
        Group {
            if let doc = model.doc, doc.nodes[pageID] != nil {
                let linked = model.linkedReferences(to: pageID)
                let unlinked = model.unlinkedReferences(to: pageID)
                List {
                    Section {
                        ForEach(visibleRows(doc, from: pageID)) { row in
                            OutlineRow(id: row.id, node: doc.nodes[row.id], focused: $focused)
                                .listRowInsets(EdgeInsets(
                                    top: 5, leading: CGFloat(row.depth) * 18 + 14, bottom: 5, trailing: 14
                                ))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.rzPaper)
                        }
                    }
                    if !linked.isEmpty {
                        Section {
                            ForEach(linked, id: \.self) { ReferenceRow(id: $0) }
                        } header: { ReferenceHeader(title: "Linked References", count: linked.count) }
                    }
                    if !unlinked.isEmpty {
                        Section {
                            ForEach(unlinked, id: \.self) { ReferenceRow(id: $0) }
                        } header: { ReferenceHeader(title: "Unlinked References", count: unlinked.count) }
                    }
                }
                .outlineList()
            } else {
                ContentUnavailableView("Page not found", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(RichText.plain(model.doc?.nodes[pageID]?.text ?? "Page", doc: model.doc))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SyncIndicator() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let new = model.insertChild(of: pageID) {
                        model.beginEdit(new); focused = new
                    }
                } label: { Image(systemName: "plus") }
            }
            EditingKeyboardBar(focused: $focused)
        }
        .onChange(of: focused) { _, new in if new == nil { model.blurred() } }
    }
}
