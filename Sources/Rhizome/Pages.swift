import SwiftUI
import RhizomeKit

/// The Pages tab: top-level pages (root's children, minus the calendar), each
/// opening into its own outline — mirroring the web app's "All pages".
struct PagesView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false
    @State private var path: [String] = []

    private func pageIDs(_ doc: RDoc) -> [String] {
        (doc.nodes[doc.root]?.children ?? []).filter { doc.nodes[$0]?.cal != "root" }
    }

    var body: some View {
        NavigationStack(path: $path) {
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
        .handleNodeLinks(path: $path, model: model)
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
                ScrollViewReader { proxy in
                    List {
                        Section {
                            ForEach(visibleRows(doc, from: pageID)) { row in
                                OutlineRow(id: row.id, node: doc.nodes[row.id], focused: $focused)
                                    .listRowInsets(EdgeInsets(
                                        top: 5, leading: CGFloat(row.depth) * 18 + 14, bottom: 5, trailing: 14
                                    ))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.rzPaper)
                                    .id(row.id)
                            }
                        }
                        referenceListContent(pageID: pageID, model: model)
                        // While editing, add a screenful of scroll room below the last row so
                        // ANY line — even the last — can be scrolled up to the middle of the
                        // screen, clear of the keyboard + indent toolbar. Collapses when idle.
                        Color.clear
                            .frame(height: model.editingID != nil ? 360 : 24)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.rzPaper)
                    }
                    .outlineList()
                    // center the line being edited on screen so the keyboard never covers it —
                    // once the keyboard has settled (and the spacer above has opened up the room)
                    .onChange(of: focused) { _, new in
                        guard let new else { return }
                        // two passes: the first catches the common case, the second (a no-op if
                        // already centered) covers a slow keyboard / late layout settle
                        for delay in [0.4, 0.7] {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(new, anchor: .center) }
                            }
                        }
                    }
                }
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
        .safeAreaInset(edge: .bottom, spacing: 0) { LinkSuggestionBar() }
    }
}
