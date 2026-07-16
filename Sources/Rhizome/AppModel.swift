import Foundation
import Observation
import SwiftUI
import UIKit
import Network
import CoreLocation
import RhizomeKit

/// What a `[[` / `((` autocomplete is currently linking to.
enum LinkKind { case page, block }

/// One suggestion in the `[[` (page) / `((` (block) autocomplete list.
struct LinkSuggestion: Identifiable, Hashable {
    let id: String       // target node id, or "__create__" for a new page
    let title: String
    let isCreate: Bool
}

/// Observable app state: server URL, the signed-in user, their graphs, and the
/// currently loaded outline. The session lives in URLSession's cookie storage, so
/// `bootstrap()` can silently resume a previous login.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading        // checking for an existing session
        case signedOut
        case ready
    }

    var phase: Phase = .loading
    var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: "serverURL") }
    }
    var user: RUser?
    var graphs: [RGraph] = []
    var activeGraphID: String? {
        didSet { UserDefaults.standard.set(activeGraphID, forKey: "activeGraphID") }
    }
    var doc: RDoc?
    var version = 0
    var errorMessage: String?
    var busy = false
    var isOffline = false

    /// Prepend an `HH:mm` timestamp to captured notes, like the `r` command.
    var captureTimestamp: Bool {
        didSet { UserDefaults.standard.set(captureTimestamp, forKey: "captureTimestamp") }
    }

    /// Human-readable name sent with edits, shown in the web app's page history.
    var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: "deviceName") }
    }

    /// Outline text size (pt). Mirrored into RichEditor so display + editor stay in sync.
    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize"); RichEditor.fontSize = CGFloat(fontSize) }
    }

    /// Extra spacing between wrapped lines (pt).
    var lineSpacing: Double {
        didSet { UserDefaults.standard.set(lineSpacing, forKey: "lineSpacing"); RichEditor.lineSpacing = CGFloat(lineSpacing) }
    }

    /// Colour scheme: Light / Auto / Dark (mirrors the web app).
    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }

    /// Accent colour: Clay / Sage / Indigo / Ink (mirrors the web app).
    var accent: AccentChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent"); RZTheme.accent = accent }
    }

    // Design defaults, shared with the Settings "reset" action.
    static let defaultFontSize = 15.5
    static let defaultLineSpacing = 1.0
    static let defaultTheme = AppTheme.auto
    static let defaultAccent = AccentChoice.clay

    /// Restore the design settings (text size, spacing, theme, accent) to their defaults.
    func resetDesign() {
        fontSize = Self.defaultFontSize
        lineSpacing = Self.defaultLineSpacing
        theme = Self.defaultTheme
        accent = Self.defaultAccent
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "serverURL")
        serverURLString = saved ?? Config.serverURL.absoluteString
        activeGraphID = UserDefaults.standard.string(forKey: "activeGraphID")
        captureTimestamp = UserDefaults.standard.object(forKey: "captureTimestamp") as? Bool ?? true
        deviceName = UserDefaults.standard.string(forKey: "deviceName") ?? UIDevice.current.name
        fontSize = UserDefaults.standard.object(forKey: "fontSize") as? Double ?? Self.defaultFontSize
        lineSpacing = UserDefaults.standard.object(forKey: "lineSpacing") as? Double ?? Self.defaultLineSpacing
        theme = UserDefaults.standard.string(forKey: "theme").flatMap(AppTheme.init) ?? Self.defaultTheme
        accent = UserDefaults.standard.string(forKey: "accent").flatMap(AccentChoice.init) ?? Self.defaultAccent
        RichEditor.fontSize = CGFloat(fontSize)
        RichEditor.lineSpacing = CGFloat(lineSpacing)
        RZTheme.accent = accent
    }

    var api: RhizomeAPI? {
        guard let url = URL(string: serverURLString.trimmingCharacters(in: .whitespaces)),
              url.scheme != nil else { return nil }
        return RhizomeAPI(baseURL: url)
    }

    var activeGraph: RGraph? {
        graphs.first { $0.id == activeGraphID } ?? graphs.first
    }

    /// On launch: if a session cookie is still valid, resume straight into the outline.
    func bootstrap() async {
        startNetworkMonitor()
        guard let api else { phase = .signedOut; return }
        do {
            let me = try await api.me()
            LocalStore.save(me, "me.json")
            isOffline = false
            if let u = me.user {
                await adopt(user: u, graphs: me.graphs ?? [], api: api)
            } else {
                phase = .signedOut
            }
        } catch {
            // offline: resume from the last cached session + doc
            if let me = LocalStore.load(RMe.self, "me.json"), let u = me.user {
                isOffline = true
                await adopt(user: u, graphs: me.graphs ?? [], api: api)
            } else {
                phase = .signedOut
            }
        }
    }

    func signIn(username: String, password: String) async {
        guard let api else { errorMessage = "Enter a valid server URL"; return }
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            let user = try await api.login(username: username, password: password)
            let me = try await api.me()
            await adopt(user: user, graphs: me.graphs ?? [], api: api)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func signOut() async {
        stopEvents()
        if let api { try? await api.logout() }
        user = nil; graphs = []; doc = nil; version = 0
        phase = .signedOut
    }

    func selectGraph(_ id: String) async {
        persistOutbox()        // save the current graph's pending edits (under its id)
        activeGraphID = id
        loadOutbox()           // load the new graph's queue
        doc = nil              // force a fresh load (or cached) for the new graph
        await loadDoc()
        startEvents()
    }

    func loadDoc() async {
        guard let api, let graphID = activeGraph?.id else { return }
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            let response = try await api.doc(graphID: graphID)
            doc = response.doc
            version = response.version
            reindex()
            LocalStore.save(response, "doc-\(graphID).json")
            isOffline = false
            ensureToday()   // create today's journal day if the server doesn't have it yet
            drain()   // network is up — flush any edits queued while offline
        } catch {
            isOffline = true
            // cold offline boot: fall back to the cached doc (don't clobber a doc
            // we already have loaded with unsynced local edits)
            if doc == nil, let cached = LocalStore.load(RDocResponse.self, "doc-\(graphID).json") {
                doc = cached.doc
                version = cached.version
                reindex()
                ensureToday()   // offline cold boot on a new day: queue today's day for later sync
            }
        }
    }

    // MARK: - Editing

    private var clock = Clock()
    private(set) var parentMap: [String: String] = [:]
    var editingID: String?
    var editText = ""                 // live buffer for the row being edited
    var linkSuggestions: [LinkSuggestion] = []   // active [[ / (( autocomplete matches
    var linkSuggestKind: LinkKind?
    var locating = false                          // geo button is waiting for a fix
    var geoMessage: String?                       // transient status/diagnostic shown after a geo tap
    @ObservationIgnored private let locationProvider = LocationProvider()
    private var flushTask: Task<Void, Never>?

    // The UITextView editor registers a callback so the keyboard bar's suggestion chips can
    // insert a link at the real caret. It also streams the serialized source back via onEditorText.
    @ObservationIgnored var editorInsert: (@MainActor (LinkSuggestion) -> Void)?
    func registerEditor(_ insert: @MainActor @escaping (LinkSuggestion) -> Void) { editorInsert = insert }

    // Re-render the active editor from `editText` (after the model changed it out-of-band,
    // e.g. the geo button appending a link). Puts the caret at the end.
    @ObservationIgnored var editorReload: (@MainActor () -> Void)?
    func registerEditorReload(_ reload: @MainActor @escaping () -> Void) { editorReload = reload }

    // Resign the editor's first responder — used by the keyboard bar's Done button (removing
    // the SwiftUI view alone doesn't reliably dismiss the UIKit keyboard).
    @ObservationIgnored var editorResign: (@MainActor () -> Void)?
    func registerEditorResign(_ resign: @MainActor @escaping () -> Void) { editorResign = resign }

    /// The editor produced a new source string for the current row → buffer + debounce-sync.
    func onEditorText(_ source: String) {
        editText = source
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            self.flushCurrent()
        }
    }

    /// Commit the buffer into the doc + send it, if it changed.
    func flushCurrent() {
        flushTask?.cancel()
        guard let id = editingID, editText != (doc?.nodes[id]?.text ?? "") else { return }
        doc?.nodes[id]?.text = editText
        send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["text": .string(editText)])])
    }

    func beginEdit(_ id: String) {
        if editingID != id { flushCurrent() }
        editingID = id
        editText = doc?.nodes[id]?.text ?? ""
        clearLinkSuggestions()
        locationProvider.start()   // warm up location so the geo button is ready/instant
    }

    /// Return pressed in the rich editor: save this bullet, open a fresh sibling and make it the
    /// editing row — its editor auto-focuses. The old editor's end-editing is ignored because
    /// `editingID` has already moved on (see the guard in the editor delegate).
    func returnFromEditor() {
        guard let id = editingID else { return }
        flushCurrent()
        guard let new = insertSibling(after: id) else { editingID = nil; return }
        editingID = new
        editText = ""
        clearLinkSuggestions()
    }

    /// Backspace at the very start of an EMPTY leaf bullet → delete it and move editing to the
    /// bullet visually above (previous sibling's last descendant, else the parent). Returns the
    /// id now being edited, or nil if it shouldn't be handled (non-empty, has children, or it's
    /// the first bullet of a page/day with nothing above).
    @discardableResult
    func backspaceDelete(_ id: String) -> String? {
        guard let node = doc?.nodes[id], (node.text ?? "").isEmpty, (node.children ?? []).isEmpty else { return nil }
        guard let parent = parentMap[id], let sibs = doc?.nodes[parent]?.children,
              let idx = sibs.firstIndex(of: id) else { return nil }
        let target: String
        if idx > 0 {
            target = lastDescendant(of: sibs[idx - 1])
        } else if parent != doc?.root, doc?.nodes[parent]?.cal != "day" {
            target = parent                        // first child → fold up into the parent
        } else {
            return nil                             // first bullet of a page/day → nothing above
        }
        delete(id)
        editingID = target
        editText = doc?.nodes[target]?.text ?? ""
        clearLinkSuggestions()
        return target
    }

    /// The deepest last (visible) descendant of `id` — the node right above its next sibling.
    private func lastDescendant(of id: String) -> String {
        var cur = id
        while !(doc?.nodes[cur]?.collapsed ?? false), let last = doc?.nodes[cur]?.children?.last {
            cur = last
        }
        return cur
    }

    /// Dismiss the keyboard from the Done button. Resigning the text view triggers
    /// textViewDidEndEditing → blurred(), which commits and clears editingID. Fall back to
    /// dropping the row directly if no editor registered.
    func endEditing() {
        if let editorResign {
            editorResign()
        } else {
            flushCurrent()
            editingID = nil
            clearLinkSuggestions()
        }
    }

    /// The edited field lost focus (keyboard dismissed / tapped elsewhere).
    func blurred() {
        flushCurrent()
        editingID = nil
        clearLinkSuggestions()
        locationProvider.stop()
        if pendingRemoteRefresh {
            pendingRemoteRefresh = false
            Task { await loadDoc() }   // catch up on remote changes deferred during editing
        }
    }

    // MARK: - [[ page / (( block autocomplete (like the desktop's caret popup)

    func clearLinkSuggestions() {
        if !linkSuggestions.isEmpty { linkSuggestions = [] }
        linkSuggestKind = nil
    }

    /// Recompute the autocomplete list from the plain text before the real caret (the editor
    /// passes it in). Looks for the last unclosed `[[` (pages) or `((` (blocks); the text after
    /// it is the live query.
    func updateSuggestions(before: String) {
        guard editingID != nil else { clearLinkSuggestions(); return }
        if let q = tailQuery(before, open: "[[", closeChar: "]") {
            linkSuggestKind = .page
            linkSuggestions = pageSuggestions(q)
        } else if let q = tailQuery(before, open: "((", closeChar: ")") {
            linkSuggestKind = .block
            linkSuggestions = blockSuggestions(q)
        } else {
            clearLinkSuggestions()
        }
    }

    /// The query after the last `open` marker, or nil if that marker is already closed
    /// (its close bracket appears after it) or spans a newline.
    private func tailQuery(_ text: String, open: String, closeChar: Character) -> String? {
        guard let r = text.range(of: open, options: .backwards) else { return nil }
        let tail = text[r.upperBound...]
        if tail.contains(closeChar) || tail.contains("\n") { return nil }
        return String(tail)
    }

    private func pageSuggestions(_ query: String) -> [LinkSuggestion] {
        guard let doc else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var out: [LinkSuggestion] = []
        // top-level pages (skip the calendar root)
        for id in doc.nodes[doc.root]?.children ?? [] where doc.nodes[id]?.cal == nil {
            let title = RichText.plain(doc.nodes[id]?.text ?? "", doc: doc).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            if q.isEmpty || title.lowercased().contains(q) { out.append(LinkSuggestion(id: id, title: title, isCreate: false)) }
        }
        // journal day pages, like the desktop's page picker (only when narrowing)
        if !q.isEmpty {
            for (id, node) in doc.nodes where node.cal == "day" {
                let title = (node.text ?? "").trimmingCharacters(in: .whitespaces)
                if title.lowercased().contains(q) { out.append(LinkSuggestion(id: id, title: title, isCreate: false)) }
            }
        }
        var result = Array(out.prefix(8))
        if !q.isEmpty, !out.contains(where: { $0.title.lowercased() == q }) {
            result.append(LinkSuggestion(id: "__create__", title: query.trimmingCharacters(in: .whitespaces), isCreate: true))
        }
        return result
    }

    private func blockSuggestions(_ query: String) -> [LinkSuggestion] {
        guard let doc else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }   // a bare (( would match everything — wait for a query
        var out: [LinkSuggestion] = []
        for (id, node) in doc.nodes where id != editingID && node.cal == nil {
            let hay = plainCache[id] ?? RichText.plain(node.text ?? "", doc: doc).lowercased()
            guard hay.contains(q) else { continue }
            let title = RichText.plain(node.text ?? "", doc: doc).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { out.append(LinkSuggestion(id: id, title: title, isCreate: false)) }
        }
        return Array(out.prefix(8))
    }

    /// A keyboard-bar chip was tapped → let the active editor splice the token in at the real
    /// caret (it renders inline and serializes back to source).
    func acceptLinkSuggestion(_ s: LinkSuggestion) {
        editorInsert?(s)
    }

    /// The rendered display text + the verbatim source to store for a chosen suggestion:
    /// a real `<a href="#/n/…">` page link (creating the page if needed), or a live `((id))`
    /// block reference. Matches what the desktop stores.
    func tokenSource(for s: LinkSuggestion, kind: LinkKind) -> (display: String, source: String) {
        switch kind {
        case .page:
            let pageID = s.isCreate ? createPage(title: s.title) : s.id
            guard !pageID.isEmpty else { return ("", "") }
            return (s.title, "<a href=\"#/n/\(pageID)\" rel=\"noopener\">\(Self.escapeHTML(s.title))</a>")
        case .block:
            guard doc?.nodes[s.id] != nil else { return ("", "") }
            let display = RichText.plain(doc?.nodes[s.id]?.text ?? "", doc: doc).trimmingCharacters(in: .whitespaces)
            return (display.isEmpty ? "ref" : display, "((\(s.id)))")
        }
    }

    /// Create a new top-level page with `title`; returns its id.
    private func createPage(title: String) -> String {
        guard let root = doc?.root else { return "" }
        let id = clock.newID()
        doc?.nodes[id] = RNode(text: title, children: [])
        if doc?.nodes[root]?.children == nil { doc?.nodes[root]?.children = [] }
        let ord = doc?.nodes[root]?.children?.count ?? 0
        doc?.nodes[root]?.children?.append(id)
        parentMap[id] = root
        send([Op(kind: "insert", node: id, hlc: clock.stamp(), parent: root, ord: ord, data: ["text": .string(title)])])
        return id
    }

    /// Existing top-level page whose title matches `title`, else a freshly created one.
    private func findOrCreatePage(title: String) -> String {
        if let doc, let existing = (doc.nodes[doc.root]?.children ?? []).first(where: {
            doc.nodes[$0]?.cal == nil &&
            RichText.plain(doc.nodes[$0]?.text ?? "", doc: doc).trimmingCharacters(in: .whitespaces) == title
        }) { return existing }
        return createPage(title: title)
    }

    /// Geo button: fetch the current position and append it as a `[[coords]]` page link to the
    /// bullet you started from (find-or-create the coordinates page). Appending — rather than a
    /// caret splice — means it works whether or not the editor kept focus during the fetch.
    func insertGeoLink() async {
        guard !locating, let id = editingID else { return }
        locationProvider.start()
        // use the warm fix if we have one; otherwise poll briefly (bounded — never hangs)
        if locationProvider.current == nil {
            locating = true
            defer { locating = false }
            for _ in 0..<30 where locationProvider.current == nil {
                try? await Task.sleep(nanoseconds: 300_000_000)   // ~9s max
            }
        }
        guard let coord = locationProvider.current else {
            geoMessage = "Standort nicht verfügbar — kurz warten, dann erneut 📍"
            return
        }
        let title = String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
        let pageID = findOrCreatePage(title: title)
        guard !pageID.isEmpty else { return }
        appendGeo(to: id, source: "<a href=\"#/n/\(pageID)\" rel=\"noopener\">\(Self.escapeHTML(title))</a>")
    }

    /// Append a source fragment to a bullet (separated by a space) and sync. If that bullet is
    /// being edited, base off the live buffer (not the possibly-stale doc) and re-render the
    /// editor so the link shows immediately without dropping unsynced typing.
    private func appendGeo(to id: String, source: String) {
        let editing = (editingID == id)
        let base = editing ? editText : (doc?.nodes[id]?.text ?? "")
        let next = base + (base.isEmpty || base.hasSuffix(" ") ? "" : " ") + source
        doc?.nodes[id]?.text = next
        if editing { editText = next; editorReload?() }
        send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["text": .string(next)])])
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private var plainCache: [String: String] = [:]

    func reindex() {
        var map: [String: String] = [:]
        var plain: [String: String] = [:]
        for (id, node) in doc?.nodes ?? [:] {
            for child in node.children ?? [] { map[child] = id }
            plain[id] = RichText.plain(node.text ?? "", doc: doc).lowercased()
        }
        parentMap = map
        plainCache = plain
    }

    func parentOf(_ id: String) -> String? { parentMap[id] }

    /// Full-text search in the active graph → matching node ids.
    func search(_ query: String) async -> [String] {
        guard let api, let graphID = activeGraph?.id,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return (try? await api.search(graphID: graphID, query: query)) ?? []
    }

    /// Node ids whose text links to `pageID` (Roam-style backlinks). Links are
    /// stored as `<a href="#/n/<id>">…</a>`.
    func linkedReferences(to pageID: String) -> [String] {
        guard let doc else { return [] }
        let needle = "#/n/\(pageID)"
        return doc.nodes.compactMap { id, node in
            (id != pageID && (node.text?.contains(needle) ?? false)) ? id : nil
        }.sorted()
    }

    /// Node ids whose plain text mentions the page's name but don't link to it.
    func unlinkedReferences(to pageID: String) -> [String] {
        guard let doc else { return [] }
        let name = (plainCache[pageID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 3 else { return [] }
        let linkNeedle = "#/n/\(pageID)"
        return doc.nodes.compactMap { id, node -> String? in
            guard id != pageID, let t = node.text, !t.contains(linkNeedle) else { return nil }
            return (plainCache[id] ?? "").contains(name) ? id : nil
        }.sorted()
    }

    /// The page (top-level node, or the journal day) that contains `id`.
    func pageOf(_ id: String) -> String {
        var cur = id
        var guardN = 0
        while let p = parentMap[cur], guardN < 50 {
            if p == doc?.root { return cur }
            if doc?.nodes[p]?.cal == "day" { return p }
            cur = p; guardN += 1
        }
        return cur
    }

    func linkedRefGroups(to pageID: String) -> [RefGroup] { groupRefs(linkedReferences(to: pageID)) }
    func unlinkedRefGroups(to pageID: String) -> [RefGroup] { groupRefs(unlinkedReferences(to: pageID)) }

    private func groupRefs(_ ids: [String]) -> [RefGroup] {
        var byPage: [String: [String]] = [:]
        var order: [String] = []
        for id in ids {
            let page = pageOf(id)
            if byPage[page] == nil { order.append(page) }
            byPage[page, default: []].append(id)
        }
        return order.map { page in
            RefGroup(pageID: page,
                     pageName: RichText.plain(doc?.nodes[page]?.text ?? "", doc: doc),
                     refs: byPage[page] ?? [])
        }
    }

    /// A " › "-joined trail of ancestor texts, for search-result context.
    func breadcrumb(of id: String) -> String {
        var trail: [String] = []
        var cur = parentMap[id]
        var guardCount = 0
        while let node = cur, node != doc?.root, guardCount < 20 {
            let text = RichText.plain(doc?.nodes[node]?.text ?? "", doc: doc)
            if !text.isEmpty { trail.append(text) }
            cur = parentMap[node]
            guardCount += 1
        }
        return trail.reversed().joined(separator: " › ")
    }

    func toggleCollapse(_ id: String) {
        guard let node = doc?.nodes[id] else { return }
        let next = !(node.collapsed ?? false)
        doc?.nodes[id]?.collapsed = next
        send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["collapsed": .bool(next)])])
    }

    func toggleDone(_ id: String) {
        flushCurrent()
        guard let node = doc?.nodes[id] else { return }
        let next = !(node.done ?? false)
        doc?.nodes[id]?.done = next
        send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["done": .bool(next)])])
    }

    /// Turn a bullet into a checkable to-do item and back (web `opSetFormat(id,'todo')`).
    func toggleTodo(_ id: String) {
        guard let node = doc?.nodes[id] else { return }
        if node.format == "todo" {
            doc?.nodes[id]?.format = nil
            send([Op(kind: "update", node: id, hlc: clock.stamp(), unset: ["format"])])
        } else {
            doc?.nodes[id]?.format = "todo"
            send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["format": .string("todo")])])
        }
    }

    /// Absolute URL of an uploaded `/files/…` attachment (loaded with the shared session cookie).
    func fileURL(_ path: String) -> URL? {
        guard let base = api?.baseURL else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    /// Remove one attachment from a node, syncing the shortened (or cleared) `files` list.
    func removeFile(_ url: String, from id: String) {
        guard var files = doc?.nodes[id]?.files else { return }
        files.removeAll { $0.url == url }
        doc?.nodes[id]?.files = files.isEmpty ? nil : files
        if files.isEmpty {
            send([Op(kind: "update", node: id, hlc: clock.stamp(), unset: ["files"])])
        } else {
            let arr = JSONValue.array(files.map { f in
                .object(["url": .string(f.url), "name": .string(f.name ?? ""), "type": .string(f.type ?? "")])
            })
            send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["files": arr])])
        }
    }

    /// Upload image/file bytes and attach them to a node, syncing the new `files` list.
    func attachFile(_ data: Data, name: String, contentType: String, to id: String) async {
        guard let api, doc?.nodes[id] != nil else { return }
        do {
            let file = try await api.upload(data, name: name, contentType: contentType)
            var files = doc?.nodes[id]?.files ?? []
            files.append(file)
            doc?.nodes[id]?.files = files
            let arr = JSONValue.array(files.map { f in
                .object(["url": .string(f.url), "name": .string(f.name ?? ""), "type": .string(f.type ?? "")])
            })
            send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["files": arr])])
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Insert a new empty sibling after `id`; returns its id (to focus it).
    @discardableResult
    func insertSibling(after id: String) -> String? {
        guard let parent = parentMap[id] else { return nil }
        let index = ((doc?.nodes[parent]?.children?.firstIndex(of: id)) ?? -1) + 1
        return insert(parent: parent, ord: index)
    }

    @discardableResult
    func insertChild(of parent: String) -> String? {
        guard doc?.nodes[parent] != nil else { return nil }
        return insert(parent: parent, ord: doc?.nodes[parent]?.children?.count ?? 0)
    }

    private func insert(parent: String, ord: Int) -> String {
        let id = clock.newID()
        doc?.nodes[id] = RNode(text: "", children: [])
        if doc?.nodes[parent]?.children == nil { doc?.nodes[parent]?.children = [] }
        let clamped = min(ord, doc?.nodes[parent]?.children?.count ?? 0)
        doc?.nodes[parent]?.children?.insert(id, at: clamped)
        parentMap[id] = parent
        send([Op(kind: "insert", node: id, hlc: clock.stamp(), parent: parent, ord: ord, data: ["text": .string("")])])
        return id
    }

    /// The most recent modified time across a page and its whole subtree (server-set `m`, ms).
    func lastModified(of id: String) -> Date? {
        guard let doc else { return nil }
        var best: Double = 0
        var stack = [id]
        while let cur = stack.popLast() {
            if let m = doc.nodes[cur]?.m, m > best { best = m }
            stack.append(contentsOf: doc.nodes[cur]?.children ?? [])
        }
        return best > 0 ? Date(timeIntervalSince1970: best / 1000) : nil
    }

    func delete(_ id: String) {
        guard let doc else { return }
        var toRemove: Set<String> = []
        var stack = [id]
        while let cur = stack.popLast() {
            toRemove.insert(cur)
            stack.append(contentsOf: doc.nodes[cur]?.children ?? [])
        }
        if let parent = parentMap[id] { self.doc?.nodes[parent]?.children?.removeAll { $0 == id } }
        for node in toRemove { self.doc?.nodes.removeValue(forKey: node); parentMap.removeValue(forKey: node) }
        if editingID == id { editingID = nil }
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        send([Op(kind: "delete", node: id, hlc: clock.stamp(), ts: ts)])
    }

    /// Tab: become the last child of the previous sibling.
    func indent(_ id: String) {
        flushCurrent()
        guard let parent = parentMap[id],
              let sibs = doc?.nodes[parent]?.children,
              let idx = sibs.firstIndex(of: id), idx > 0 else { return }
        move(id, to: sibs[idx - 1], ord: doc?.nodes[sibs[idx - 1]]?.children?.count ?? 0)
    }

    /// Shift-Tab: become a sibling of the parent, just after it.
    func outdent(_ id: String) {
        flushCurrent()
        guard let parent = parentMap[id], let grand = parentMap[parent] else { return }
        let index = ((doc?.nodes[grand]?.children?.firstIndex(of: parent)) ?? -1) + 1
        move(id, to: grand, ord: index)
    }

    private func move(_ id: String, to newParent: String, ord: Int) {
        guard parentMap[id] != nil, doc?.nodes[newParent] != nil else { return }
        if let old = parentMap[id] { doc?.nodes[old]?.children?.removeAll { $0 == id } }
        if doc?.nodes[newParent]?.children == nil { doc?.nodes[newParent]?.children = [] }
        let clamped = min(ord, doc?.nodes[newParent]?.children?.count ?? 0)
        doc?.nodes[newParent]?.children?.insert(id, at: clamped)
        parentMap[id] = newParent
        send([Op(kind: "move", node: id, hlc: clock.stamp(), parent: newParent, ord: ord)])
    }

    /// Quick-capture into today's journal Inbox (server creates today if needed).
    func captureToday(_ text: String) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, !body.isEmpty else { return }
        let line: String
        if captureTimestamp {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm"
            line = "\(f.string(from: Date())) \(body)"
        } else {
            line = body
        }
        do {
            try await api.capture(line, deviceName: deviceName)
            await loadDoc()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Journal: ensure today exists

    private var ensuredDay: String?   // cd we've already created/confirmed this session

    /// Make sure today's journal day exists so it shows up (and is writable) the moment
    /// the day rolls over — the native equivalent of the web app auto-creating today when
    /// you open the daily view. Builds the calendar root → year → month → day chain as
    /// needed (find-or-create by title), plus one empty bullet to type into. Idempotent.
    func ensureToday() {
        guard let doc else { return }
        let root = doc.root
        let cal = Calendar.current
        let now = Date()
        let parts = cal.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        let cd = String(format: "%04d-%02d-%02d", year, month, day)
        if ensuredDay == cd { return }

        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "en_US_POSIX")
        monthFmt.dateFormat = "MMMM"
        let monthName = monthFmt.string(from: now)
        let title = "\(monthName) \(day)\(Self.ordinalSuffix(day)), \(year)"   // "July 16th, 2026"

        if doc.nodes.values.contains(where: { $0.cal == "day" && $0.text == title }) {
            ensuredDay = cd
            return
        }
        let calRootID = doc.nodes.first(where: { $0.value.cal == "root" })?.key
            ?? insertCalNode(parent: root, cal: "root", text: "📅 Calendar")
        let yearID = childCalNode(of: calRootID, cal: "year", text: "\(year)")
            ?? insertCalNode(parent: calRootID, cal: "year", text: "\(year)", extra: ["cy": .int(year)])
        let monthID = childCalNode(of: yearID, cal: "month", text: monthName)
            ?? insertCalNode(parent: yearID, cal: "month", text: monthName, extra: ["cm": .int(month - 1), "cy": .int(year)])
        let dayID = insertCalNode(parent: monthID, cal: "day", text: title, extra: ["cd": .string(cd)])
        _ = insertChild(of: dayID)   // an empty bullet so the day is immediately writable
        ensuredDay = cd
    }

    private func childCalNode(of parent: String, cal: String, text: String) -> String? {
        doc?.nodes[parent]?.children?.first { doc?.nodes[$0]?.cal == cal && doc?.nodes[$0]?.text == text }
    }

    /// Append a calendar node (root/year/month/day) under `parent`, mirroring it into the
    /// insert op's data (incl. cd/cm/cy) so the server stores a proper calendar node.
    @discardableResult
    private func insertCalNode(parent: String, cal: String, text: String, extra: [String: JSONValue] = [:]) -> String {
        let id = clock.newID()
        doc?.nodes[id] = RNode(text: text, children: [], cal: cal)
        if doc?.nodes[parent]?.children == nil { doc?.nodes[parent]?.children = [] }
        let ord = doc?.nodes[parent]?.children?.count ?? 0
        doc?.nodes[parent]?.children?.append(id)
        parentMap[id] = parent
        var data: [String: JSONValue] = ["text": .string(text), "cal": .string(cal)]
        for (k, v) in extra { data[k] = v }
        send([Op(kind: "insert", node: id, hlc: clock.stamp(), parent: parent, ord: ord, data: data)])
        return id
    }

    private static func ordinalSuffix(_ n: Int) -> String {
        if (11...13).contains(n % 100) { return "th" }
        switch n % 10 { case 1: return "st"; case 2: return "nd"; case 3: return "rd"; default: return "th" }
    }

    enum SyncState { case synced, syncing, error }
    private var outbox: [Op] = []
    private var sending = false
    private(set) var syncFailed = false
    var syncState: SyncState { syncFailed ? .error : ((sending || !outbox.isEmpty) ? .syncing : .synced) }

    // Diagnostics (shown in Settings)
    var lastSync = "—"
    var selfTestResult = "not run"

    /// End-to-end check of the op path through the app's own networking:
    /// insert → update → read back → delete. Tells us whether sends actually work.
    func syncSelfTest() async {
        guard let api, let graphID = activeGraph?.id, let root = doc?.root else {
            selfTestResult = "no active graph"; return
        }
        let id = clock.newID()
        do {
            let v1 = try await api.postOps(graphID: graphID, ops: [
                Op(kind: "insert", node: id, hlc: clock.stamp(), parent: root, ord: 0, data: ["text": .string("selftest")])
            ], device: clock.device)
            let v2 = try await api.postOps(graphID: graphID, ops: [
                Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["text": .string("selftest-ok")])
            ], device: clock.device)
            let readback = try await api.doc(graphID: graphID).doc.nodes[id]?.text ?? "∅"
            _ = try await api.postOps(graphID: graphID, ops: [
                Op(kind: "delete", node: id, hlc: clock.stamp(), ts: Int(Date().timeIntervalSince1970 * 1000))
            ], device: clock.device)
            selfTestResult = "insert v\(v1) · update v\(v2) · readback=\(readback)"
        } catch {
            selfTestResult = "✗ \(error)"
        }
    }

    /// Queue ops and drain the outbox in strict FIFO order — one request at a time —
    /// so an `insert` is always acked before the `update` that fills its text.
    /// (Sent concurrently, a text update can reach the server before the node exists
    /// and get dropped, which is why structure synced but text didn't.)
    private func send(_ ops: [Op]) {
        outbox.append(contentsOf: ops)
        persistOutbox()
        drain()
    }

    private func drain() {
        guard !sending, !outbox.isEmpty, let api, let graphID = activeGraph?.id else { return }
        sending = true
        let batch = outbox                       // keep it queued until it's acked
        let device = clock.device
        let dname = deviceName
        let kinds = batch.map(\.kind).joined(separator: ",")
        Task {
            do {
                version = try await api.postOps(graphID: graphID, ops: batch, device: device, deviceName: dname)
                outbox.removeFirst(batch.count)  // drop only the acked prefix (edits during await stay)
                persistOutbox()
                lastSync = "\(kinds) → v\(version)"
                syncFailed = false
                isOffline = false
                sending = false
                drain()                          // flush anything queued during the await
            } catch {
                // offline / transient: keep the batch queued and retry later
                lastSync = "queued offline: \(kinds)"
                syncFailed = true
                isOffline = true
                sending = false
            }
        }
    }

    // MARK: - Live sync (SSE)

    private var eventTask: Task<Void, Never>?
    private var pendingRemoteRefresh = false

    private static let eventSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.httpCookieStorage = .shared
        return URLSession(configuration: config)
    }()

    /// Subscribe to the active graph's server-sent events; refetch when a change
    /// with a newer version arrives (from another device). Reconnects on drop.
    func startEvents() {
        eventTask?.cancel()
        guard let api, let graphID = activeGraph?.id else { return }
        let base = api.baseURL
        eventTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.consumeEvents(base: base, graphID: graphID)
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 2_000_000_000)  // reconnect backoff
            }
        }
    }

    func stopEvents() { eventTask?.cancel(); eventTask = nil }

    private func consumeEvents(base: URL, graphID: String) async {
        var request = URLRequest(url: base.appendingPathComponent("api/g/\(graphID)/events"))
        request.timeoutInterval = 3600
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await Self.eventSession.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            for try await line in bytes.lines {
                if Task.isCancelled { return }
                guard line.hasPrefix("data:") else { continue }  // ignore :hb heartbeats
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let data = payload.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let remoteVersion = obj["version"] as? Int, remoteVersion > version else { continue }
                if editingID == nil {
                    await loadDoc()
                } else {
                    pendingRemoteRefresh = true   // don't disturb the caret; catch up on blur
                }
            }
        } catch { /* dropped → the loop reconnects */ }
    }

    private func adopt(user: RUser, graphs: [RGraph], api: RhizomeAPI) async {
        self.user = user
        self.graphs = graphs
        if activeGraphID == nil || !graphs.contains(where: { $0.id == activeGraphID }) {
            activeGraphID = graphs.first?.id
        }
        phase = .ready
        loadOutbox()          // restore edits queued offline in a previous run
        await loadDoc()       // online → fetch + cache + drain; offline → cached doc
        startEvents()
    }

    // MARK: - Offline op queue (persisted per graph)

    private func outboxKey(_ graphID: String) -> String { "outbox-\(graphID).json" }

    private func persistOutbox() {
        guard let graphID = activeGraph?.id else { return }
        LocalStore.save(outbox, outboxKey(graphID))
    }

    private func loadOutbox() {
        guard let graphID = activeGraph?.id else { outbox = []; return }
        outbox = LocalStore.load([Op].self, outboxKey(graphID)) ?? []
    }

    /// Retry pending sends + refresh when the app returns to the foreground.
    func onForeground() {
        guard user != nil else { return }
        startEvents()
        Task { await loadDoc() }   // loadDoc ensures today's day (catches a day rollover)
    }

    // MARK: - Network monitor (instant reconnect)

    private var netMonitor: NWPathMonitor?

    func startNetworkMonitor() {
        guard netMonitor == nil else { return }
        let monitor = NWPathMonitor()
        netMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self, self.user != nil else { return }
                if path.status == .satisfied, self.isOffline {
                    self.startEvents()          // resubscribe
                    await self.loadDoc()        // refresh + drain the offline queue
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "rhizome.net"))
    }
}
