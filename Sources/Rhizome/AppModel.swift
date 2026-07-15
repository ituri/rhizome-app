import Foundation
import Observation
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
    var editBuffer = ""

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
        guard let node = doc?.nodes[id] else { return }
        let next = !(node.done ?? false)
        doc?.nodes[id]?.done = next
        send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["done": .bool(next)])])
    }

    /// Start editing a node (committing any in-flight edit first).
    func beginEdit(_ id: String) {
        commitEdit()
        editingID = id
        editBuffer = doc?.nodes[id]?.text ?? ""
    }

    /// Persist the buffered text of the row being edited, if it changed.
    func commitEdit() {
        guard let id = editingID else { return }
        if editBuffer != (doc?.nodes[id]?.text ?? "") {
            doc?.nodes[id]?.text = editBuffer
            send([Op(kind: "update", node: id, hlc: clock.stamp(), patch: ["text": .string(editBuffer)])])
        }
        editingID = nil
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
        guard let parent = parentMap[id],
              let sibs = doc?.nodes[parent]?.children,
              let idx = sibs.firstIndex(of: id), idx > 0 else { return }
        move(id, to: sibs[idx - 1], ord: doc?.nodes[sibs[idx - 1]]?.children?.count ?? 0)
    }

    /// Shift-Tab: become a sibling of the parent, just after it.
    func outdent(_ id: String) {
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

    /// Fire off a batch of ops; on failure, resync from the server.
    private func send(_ ops: [Op]) {
        guard let api, let graphID = activeGraph?.id else { return }
        let device = clock.device
        Task {
            do {
                version = try await api.postOps(graphID: graphID, ops: ops, device: device)
            } catch {
                await loadDoc()
            }
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
