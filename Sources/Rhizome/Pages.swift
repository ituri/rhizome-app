import SwiftUI
import RhizomeKit

/// The Pages tab: top-level pages (root's children, minus the calendar), each
/// opening into its own outline — mirroring the web app's "All pages".
struct PagesView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false
    @State private var path: [String] = []
    @State private var query = ""
    @State private var pendingDelete: String?   // page awaiting delete confirmation
    @State private var renameTarget: String?    // page being renamed
    @State private var renameText = ""

    private func pageIDs(_ doc: RDoc) -> [String] {
        (doc.nodes[doc.root]?.children ?? []).filter { doc.nodes[$0]?.cal != "root" }
    }

    /// Fuzzy (subsequence) match: every character of the query appears in order in the title.
    private func matches(_ query: String, _ title: String) -> Bool {
        let q = query.lowercased(), t = title.lowercased()
        guard !q.isEmpty else { return true }
        var it = t.makeIterator()
        for ch in q {
            var found = false
            while !found, let c = it.next() { if c == ch { found = true } }
            if !found { return false }
        }
        return true
    }

    private func visiblePages(_ doc: RDoc) -> [String] {
        pageIDs(doc)
            .filter { matches(query, RichText.plain(doc.nodes[$0]?.text ?? "", doc: doc)) }
            // most recently edited first (pages without a known edit time sink to the bottom)
            .sorted { (model.lastModified(of: $0) ?? .distantPast) > (model.lastModified(of: $1) ?? .distantPast) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let doc = model.doc {
                    let pages = visiblePages(doc)
                    if pageIDs(doc).isEmpty {
                        ContentUnavailableView("No pages yet", systemImage: "doc.text")
                    } else if pages.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        List {
                            ForEach(pages, id: \.self) { id in
                                pageRow(id, doc: doc)
                            }
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
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search pages")
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
            .confirmationDialog(
                "Delete this page and everything under it?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete page", role: .destructive) {
                    if let id = pendingDelete { model.delete(id) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            }
            .alert("Rename page", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("Title", text: $renameText)
                Button("Save") {
                    if let id = renameTarget { model.renamePage(id, to: renameText) }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
        }
        .handleNodeLinks(path: $path, model: model)
    }

    @ViewBuilder
    private func pageRow(_ id: String, doc: RDoc) -> some View {
        NavigationLink(value: id) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RichText.attributed(doc.nodes[id]?.text ?? "", doc: doc))
                    .font(.rz(17))
                    .lineLimit(1)
                if let edited = model.lastModified(of: id) {
                    Text("edited \(edited.formatted(.relative(presentation: .named)))")
                        .font(.rz(12))
                        .foregroundStyle(Color.rzInkFaint)
                }
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.rzPaper)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = id } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                renameText = RichText.plain(doc.nodes[id]?.text ?? "", doc: doc)
                renameTarget = id
            } label: { Label("Rename", systemImage: "pencil") }
            .tint(.blue)
        }
    }
}

/// A single page opened from the Pages list: its title + editable outline.
struct PageView: View {
    @Environment(AppModel.self) private var model
    let pageID: String
    @State private var showHistory = false
    @State private var showRename = false
    @State private var renameDraft = ""

    private var pageTitle: String { RichText.plain(model.doc?.nodes[pageID]?.text ?? "Page", doc: model.doc) }

    var body: some View {
        Group {
            if let doc = model.doc, doc.nodes[pageID] != nil {
                ScrollViewReader { proxy in
                    List {
                        if let c = model.pageCoords(pageID) {   // a location page → map under the title
                            GeoMapView(lat: c.lat, lon: c.lon)
                                .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.rzPaper)
                        }
                        Section {
                            ForEach(visibleRows(doc, from: pageID)) { row in
                                OutlineRow(id: row.id, node: doc.nodes[row.id])
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
                    .onChange(of: model.editingID) { _, new in
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
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // tap the page title to rename it
            ToolbarItem(placement: .principal) {
                Button {
                    renameDraft = pageTitle
                    showRename = true
                } label: {
                    Text(pageTitle).font(.headline).lineLimit(1).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page title: \(pageTitle)")
                .accessibilityHint("Tap to rename this page")
            }
            ToolbarItem(placement: .topBarTrailing) { SyncIndicator() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let new = model.insertChild(of: pageID) { model.beginEdit(new) }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showHistory) { PageHistoryView(pageID: model.historyPageOf(pageID) ?? pageID) }
        .safeAreaInset(edge: .bottom, spacing: 0) { KeyboardAccessory(model: model) }
        .alert("Rename page", isPresented: $showRename) {
            TextField("Title", text: $renameDraft)
            Button("Rename") { model.renamePage(pageID, to: renameDraft) }
            Button("Cancel", role: .cancel) {}
        }
        .geoAlert(model)
        .noticeAlert(model)
    }
}
