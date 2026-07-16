import SwiftUI
import RhizomeKit

/// The Assets tab: every file referenced in the graph (In use) plus files no note references
/// anymore (Unused), with thumbnails, backlinks to the notes using them, and delete/cleanup.
struct AssetsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0               // 0 = in use, 1 = unused
    @State private var path: [String] = []
    @State private var confirmDeleteAll = false
    @State private var pickTarget: RAsset?   // unused image awaiting a note to insert into
    @State private var renameTarget: RAsset? // in-use file being renamed
    @State private var renameText = ""

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if tab == 0 { usedList } else { unusedList }
            }
            .navigationTitle("Assets")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { PageView(pageID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { GraphSwitcher() }
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $tab) {
                        Text("In use").tag(0)
                        Text("Unused").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                ToolbarItem(placement: .topBarTrailing) { SyncIndicator() }
            }
            .task { await model.loadAssets() }
            .refreshable { await model.loadAssets() }
            .sheet(item: $pickTarget) { NotePickerSheet(asset: $0) }
            .alert("Rename file", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } }),
                   presenting: renameTarget) { a in
                TextField("Name", text: $renameText)
                Button("Save") {
                    let url = a.url, name = renameText
                    Task { await model.renameAsset(url, to: name) }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
        }
    }

    @ViewBuilder private var usedList: some View {
        if model.assets.isEmpty {
            ContentUnavailableView("No files yet", systemImage: "photo.on.rectangle",
                                   description: Text("Images and files you attach to notes show up here."))
        } else {
            List {
                ForEach(model.assets) { a in
                    AssetRow(asset: a)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await model.deleteAsset(a.url) } } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button { renameText = a.name ?? ""; renameTarget = a } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            }
            .listStyle(.plain)
            .paperBackground()
        }
    }

    @ViewBuilder private var unusedList: some View {
        if model.orphans.isEmpty {
            ContentUnavailableView("No unused files", systemImage: "checkmark.circle",
                                   description: Text("Every uploaded file is referenced by a note."))
        } else {
            List {
                Section {
                    ForEach(model.orphans) { o in
                        AssetRow(asset: o, pickAction: { pickTarget = o })
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if let n = o.name { Task { await model.deleteOrphans([n]) } }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                } footer: {
                    Text("Tap an image to insert it into a note.")
                }
                Section {
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Text("Delete all \(model.orphans.count) unused files")
                    }
                    .listRowBackground(Color.rzPaper)
                }
            }
            .listStyle(.plain)
            .paperBackground()
            .confirmationDialog("Delete all unused files? This can't be undone.",
                                isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete \(model.orphans.count) files", role: .destructive) {
                    Task { await model.deleteOrphans(model.orphans.compactMap(\.name)) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

/// One asset: thumbnail (tap → full screen), name + size/date/usage, backlink chips, share.
struct AssetRow: View {
    @Environment(AppModel.self) private var model
    let asset: RAsset
    var pickAction: (() -> Void)? = nil   // set for unused rows: tapping the image picks a note
    @State private var viewer: ViewerImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                thumb
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name ?? asset.url).font(.rz(15)).lineLimit(1)
                    Text(meta).font(.rz(12)).foregroundStyle(Color.rzInkFaint)
                }
                Spacer()
                if let url = model.fileURL(asset.url) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up").foregroundStyle(Color.rzInkFaint) }
                }
            }
            if let refs = asset.refs, !refs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(refs) { r in
                            NavigationLink(value: r.page ?? r.node) {
                                Text("→ " + (r.pageTitle?.isEmpty == false ? r.pageTitle! : "note"))
                                    .font(.rz(12)).foregroundStyle(Color.rzAccent).lineLimit(1)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.rzAccent.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.rzPaper)
        .fullScreenCover(item: $viewer) { v in ImageViewer(url: v.url) }
    }

    @ViewBuilder private var thumb: some View {
        if asset.isImage, let url = model.fileURL(asset.url) {
            AssetThumb(url: url) {
                if let pickAction { pickAction() } else { viewer = ViewerImage(url: url) }
            }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.rzLineSoft)
                .frame(width: 56, height: 56)
                .overlay { Image(systemName: "paperclip").foregroundStyle(Color.rzInkFaint) }
        }
    }

    private var meta: String {
        var bits: [String] = []
        if let s = asset.size { bits.append(ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file)) }
        if let m = asset.mtime {
            bits.append(Date(timeIntervalSince1970: m / 1000).formatted(date: .abbreviated, time: .omitted))
        }
        if let refs = asset.refs { bits.append("used in \(refs.count)") } else { bits.append("unused") }
        if asset.missing == true { bits.append("missing on disk") }
        return bits.joined(separator: " · ")
    }
}

/// A 56pt cached image thumbnail (loads once via ImageCache), tap opens it full screen.
struct AssetThumb: View {
    let url: URL
    let onTap: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.rzLineSoft.overlay { ProgressView() }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .task(id: url) { image = await ImageCache.load(url) }
    }
}

/// A fuzzy-searchable list of notes (top-level pages + journal days); picking one inserts the
/// asset into it as a new image bullet.
struct NotePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let asset: RAsset
    @State private var query = ""

    private struct NoteTarget: Identifiable { let id: String; let title: String }

    var body: some View {
        NavigationStack {
            List(filtered) { t in
                Button {
                    let id = t.id
                    Task { await model.insertImage(asset, into: id) }
                    dismiss()
                } label: {
                    Label(t.title, systemImage: "doc.text")
                        .lineLimit(1)
                        .foregroundStyle(Color.rzInk)
                }
                .listRowBackground(Color.rzPaper)
            }
            .listStyle(.plain)
            .paperBackground()
            .overlay {
                if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
            .navigationTitle("Insert into…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    /// Top-level pages (children of root, minus the calendar scaffold) plus journal days.
    private var targets: [NoteTarget] {
        guard let doc = model.doc else { return [] }
        var out: [NoteTarget] = []
        for id in doc.nodes[doc.root]?.children ?? [] {
            guard let n = doc.nodes[id], n.cal != "root" else { continue }
            let t = RichText.plain(n.text ?? "", doc: doc).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(NoteTarget(id: id, title: t)) }
        }
        for (id, n) in doc.nodes where n.cal == "day" {
            let t = RichText.plain(n.text ?? "", doc: doc).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(NoteTarget(id: id, title: t)) }
        }
        return out
    }

    private var filtered: [NoteTarget] {
        guard !query.isEmpty else { return targets }
        return targets.filter { fuzzy(query, $0.title) }
    }

    /// Subsequence fuzzy match: every char of the query appears in order in the title.
    private func fuzzy(_ query: String, _ title: String) -> Bool {
        let q = query.lowercased()
        var it = title.lowercased().makeIterator()
        for ch in q {
            var found = false
            while !found, let c = it.next() { if c == ch { found = true } }
            if !found { return false }
        }
        return true
    }
}
