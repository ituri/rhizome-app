import Foundation
import Observation
import SwiftUI
import RhizomeKit

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

    init() {
        let saved = UserDefaults.standard.string(forKey: "serverURL")
        serverURLString = saved ?? Config.serverURL.absoluteString
        activeGraphID = UserDefaults.standard.string(forKey: "activeGraphID")
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
        guard let api else { phase = .signedOut; return }
        do {
            let me = try await api.me()
            if let u = me.user {
                await adopt(user: u, graphs: me.graphs ?? [], api: api)
            } else {
                phase = .signedOut
            }
        } catch {
            phase = .signedOut
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
        if let api { try? await api.logout() }
        user = nil; graphs = []; doc = nil; version = 0
        phase = .signedOut
    }

    func selectGraph(_ id: String) async {
        activeGraphID = id
        await loadDoc()
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
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Editing

    private var clock = Clock()
    private(set) var parentMap: [String: String] = [:]
    var editingID: String?
    private var dirty: Set<String> = []
    private var suppressBlur = false

    private var flushTask: Task<Void, Never>?

    /// Live two-way binding to a node's text: edits update the local doc immediately
    /// and stream to the server after a short debounce, so the web app sees changes
    /// as you type (not only on Return).
    func textBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.doc?.nodes[id]?.text ?? "" },
            set: { [weak self] in
                guard let self else { return }
                self.doc?.nodes[id]?.text = $0
                self.dirty.insert(id)
                self.scheduleFlush(id)
            }
        )
    }

    /// Debounced streaming send while typing.
    private func scheduleFlush(_ id: String) {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            self.flush(id)
        }
    }

    /// Send a node's pending text immediately, if it changed since the last flush.
    func flush(_ id: String) {
        flushTask?.cancel()
        guard dirty.remove(id) != nil else { return }
        send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["text": .string(doc?.nodes[id]?.text ?? "")])])
    }

    func beginEdit(_ id: String) {
        if let prev = editingID, prev != id { flush(prev) }
        editingID = id
    }

    /// Return: save the current line, then open a fresh sibling to keep typing.
    @discardableResult
    func returnKey(on id: String) -> String? {
        flush(id)
        guard let new = insertSibling(after: id) else { editingID = nil; return nil }
        suppressBlur = true      // the old field's focus loss is a transition, not a real blur
        editingID = new
        return new
    }

    func focusSettled() { suppressBlur = false }

    /// The edited field lost focus (keyboard dismissed / tapped elsewhere).
    func blurred() {
        if suppressBlur { return }
        if let id = editingID { flush(id) }
        editingID = nil
    }

    func reindex() {
        var map: [String: String] = [:]
        for (id, node) in doc?.nodes ?? [:] {
            for child in node.children ?? [] { map[child] = id }
        }
        parentMap = map
    }

    func parentOf(_ id: String) -> String? { parentMap[id] }

    func toggleCollapse(_ id: String) {
        guard let node = doc?.nodes[id] else { return }
        let next = !(node.collapsed ?? false)
        doc?.nodes[id]?.collapsed = next
        send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["collapsed": .bool(next)])])
    }

    func toggleDone(_ id: String) {
        flush(id)
        guard let node = doc?.nodes[id] else { return }
        let next = !(node.done ?? false)
        doc?.nodes[id]?.done = next
        send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["done": .bool(next)])])
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
        flush(id)
        guard let parent = parentMap[id],
              let sibs = doc?.nodes[parent]?.children,
              let idx = sibs.firstIndex(of: id), idx > 0 else { return }
        move(id, to: sibs[idx - 1], ord: doc?.nodes[sibs[idx - 1]]?.children?.count ?? 0)
    }

    /// Shift-Tab: become a sibling of the parent, just after it.
    func outdent(_ id: String) {
        flush(id)
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
        guard let api, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try await api.capture(text)
            await loadDoc()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    enum SyncState { case synced, syncing, error }
    private(set) var inflight = 0
    private(set) var syncFailed = false
    var syncState: SyncState { syncFailed ? .error : (inflight > 0 ? .syncing : .synced) }

    /// Fire off a batch of ops; on failure, resync from the server.
    private func send(_ ops: [Op]) {
        guard let api, let graphID = activeGraph?.id else { return }
        let device = clock.device
        inflight += 1
        Task {
            do {
                version = try await api.postOps(graphID: graphID, ops: ops, device: device)
                syncFailed = false
            } catch {
                syncFailed = true
                await loadDoc()
            }
            inflight -= 1
        }
    }

    private func adopt(user: RUser, graphs: [RGraph], api: RhizomeAPI) async {
        self.user = user
        self.graphs = graphs
        if activeGraphID == nil || !graphs.contains(where: { $0.id == activeGraphID }) {
            activeGraphID = graphs.first?.id
        }
        phase = .ready
        await loadDoc()
    }
}
