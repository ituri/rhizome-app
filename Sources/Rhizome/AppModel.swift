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
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Toggle a node's collapsed state locally (view-only for now; not yet persisted).
    func toggleCollapse(_ id: String) {
        guard var node = doc?.nodes[id] else { return }
        node.collapsed = !(node.collapsed ?? false)
        doc?.nodes[id] = node
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
