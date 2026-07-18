import Foundation

// MARK: - Wire models (subset of the Rhizome JSON we render natively)

public struct RUser: Codable, Sendable, Identifiable {
    public let id: String
    public let username: String
    public let isAdmin: Bool?
}

public struct RGraph: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let role: String?
}

/// Cross-device preferences for the signed-in account (shared web ⇄ iOS).
public struct RPrefs: Codable, Sendable {
    public var captureTimestamp: Bool?
    public init(captureTimestamp: Bool? = nil) { self.captureTimestamp = captureTimestamp }
}

public struct RMe: Codable, Sendable {
    public let user: RUser?
    public let graphs: [RGraph]?
    public let prefs: RPrefs?
    public let authRequired: Bool?
}

/// Usage statistics + the storage quota that applies to the signed-in user (GET /api/me/stats).
public struct RStats: Codable, Sendable {
    public var pages: Int
    public var noteBytes: Int
    public var fileBytes: Int
    public var totalBytes: Int
    public var quotaBytes: Int    // 0 = unlimited
    public var tolerancePct: Int
}

/// Whether a file should render as an image — decided by its NAME extension (authoritative): a
/// broken/edited extension (e.g. "Photo.jp") stops it rendering, and a missing mime type doesn't.
public func looksLikeImage(_ s: String?) -> Bool {
    (s ?? "").range(of: #"\.(png|jpe?g|gif|webp|svg|bmp|heic|heif|avif)$"#, options: [.regularExpression, .caseInsensitive]) != nil
}

/// An uploaded attachment on a node (`/files/<id>` url + mime type).
public struct RFile: Codable, Sendable {
    public var url: String
    public var name: String?
    public var type: String?
    public var size: Double?
    public init(url: String, name: String? = nil, type: String? = nil, size: Double? = nil) {
        self.url = url; self.name = name; self.type = type; self.size = size
    }
    public var isImage: Bool { looksLikeImage(name ?? url) }
    public var isPDF: Bool { (name ?? url).lowercased().hasSuffix(".pdf") || (type ?? "").contains("pdf") }
    /// An SF Symbol representing the file kind (for the non-image attachment chip).
    public var symbol: String {
        let n = (name ?? url).lowercased()
        if isPDF { return "doc.richtext" }
        if n.hasSuffix(".zip") || n.hasSuffix(".tar") || n.hasSuffix(".gz") || n.hasSuffix(".7z") { return "doc.zipper" }
        if n.hasSuffix(".txt") || n.hasSuffix(".md") || n.hasSuffix(".rtf") { return "doc.plaintext" }
        if n.hasSuffix(".mp3") || n.hasSuffix(".m4a") || n.hasSuffix(".wav") { return "waveform" }
        if n.hasSuffix(".mp4") || n.hasSuffix(".mov") || n.hasSuffix(".m4v") { return "film" }
        return "doc"
    }
}

/// One saved version in a page's history.
public struct RHistoryVersion: Codable, Sendable, Identifiable {
    public var id: Int
    public var ts: Double
    public var device: String?
}

/// A note that references an asset (backlink).
public struct RAssetRef: Codable, Sendable, Identifiable {
    public var node: String
    public var page: String?
    public var pageTitle: String?
    public var id: String { node }
}

/// One uploaded file in the asset manager: metadata + which notes use it.
public struct RAsset: Codable, Sendable, Identifiable {
    public var url: String
    public var name: String?
    public var type: String?
    public var size: Double?
    public var mtime: Double?
    public var refs: [RAssetRef]?
    public var missing: Bool?
    public var id: String { url }
    public var isImage: Bool { looksLikeImage(name ?? url) }
}

/// One outline node. Unknown fields in the server JSON are ignored.
public struct RNode: Codable, Sendable {
    public var text: String?
    public var note: String?
    public var children: [String]?
    public var collapsed: Bool?
    public var done: Bool?
    public var cal: String?    // "root" | "year" | "month" | "day" on calendar nodes
    public var format: String? // nil = bullet; "todo" renders a checkbox, plus number/h1/quote/…
    public var files: [RFile]? // image / file attachments
    public var cd: String?     // calendar day, "yyyy-MM-dd" (the day's stable identity)
    public var cm: Int?        // calendar month (0-based) on month nodes
    public var cy: Int?        // calendar year on year nodes
    public var m: Double?      // last-modified, ms since epoch (server-set)
    public var c: Double?      // created, ms since epoch (server-set)

    public init(
        text: String? = nil, note: String? = nil, children: [String]? = nil,
        collapsed: Bool? = nil, done: Bool? = nil, cal: String? = nil,
        format: String? = nil, files: [RFile]? = nil,
        cd: String? = nil, cm: Int? = nil, cy: Int? = nil, m: Double? = nil, c: Double? = nil
    ) {
        self.text = text; self.note = note; self.children = children
        self.collapsed = collapsed; self.done = done; self.cal = cal
        self.format = format; self.files = files
        self.cd = cd; self.cm = cm; self.cy = cy; self.m = m; self.c = c
    }
}

public struct RDoc: Codable, Sendable {
    public var root: String
    public var nodes: [String: RNode]
}

public struct RDocResponse: Codable, Sendable {
    public var version: Int
    public var doc: RDoc
}

// MARK: - API client

/// A minimal async client for the Rhizome HTTP API. Auth is a session cookie
/// (`rz_session`) held by URLSession's shared, persistent cookie storage — log in
/// once and it survives relaunches.
public struct RhizomeAPI: Sendable {
    public struct APIError: Error, CustomStringConvertible, Sendable {
        public let status: Int
        public let message: String
        public var description: String { message }
    }

    public var baseURL: URL
    public init(baseURL: URL) { self.baseURL = baseURL }

    public func login(username: String, password: String) async throws -> RUser {
        struct Body: Encodable { let username: String; let password: String }
        struct Wrapper: Decodable { let user: RUser }
        let data = try await post("api/login", body: Body(username: username, password: password))
        return try JSONDecoder().decode(Wrapper.self, from: data).user
    }

    public func logout() async throws {
        _ = try await post("api/logout", body: [String: String]())
    }

    public func changePassword(current: String, next: String) async throws {
        struct Body: Encodable { let current: String; let next: String }
        _ = try await post("api/account/password", body: Body(current: current, next: next))
    }

    /// Permanently delete the signed-in account (and the graphs it solely owns). Confirmed
    /// by re-entering the password. The server also clears the session cookie.
    public func deleteAccount(password: String) async throws {
        struct Body: Encodable { let password: String }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/account"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(password: password))
        _ = try await send(request)
    }

    /// Reverse-geocode a coordinate to a short address (server-side, same result as the web app).
    public func reverseGeocode(lat: Double, lon: Double) async throws -> String {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/geocode"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "lat", value: String(lat)), URLQueryItem(name: "lon", value: String(lon))]
        let data = try await send(URLRequest(url: comps.url!))
        struct R: Decodable { let address: String? }
        return (try JSONDecoder().decode(R.self, from: data)).address ?? ""
    }

    public func me() async throws -> RMe {
        let data = try await get("api/me")
        return try JSONDecoder().decode(RMe.self, from: data)
    }

    public func stats() async throws -> RStats {
        let data = try await get("api/me/stats")
        return try JSONDecoder().decode(RStats.self, from: data)
    }

    /// Save cross-device preferences (merged server-side with any existing prefs).
    public func putPrefs(_ prefs: RPrefs) async throws {
        struct Body: Encodable { let prefs: RPrefs }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/account/prefs"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(prefs: prefs))
        _ = try await send(request)
    }

    public func doc(graphID: String) async throws -> RDocResponse {
        let data = try await get("api/g/\(graphID)/doc")
        return try JSONDecoder().decode(RDocResponse.self, from: data)
    }

    /// Send a batch of mutation ops; returns the new server version.
    @discardableResult
    public func postOps(graphID: String, ops: [Op], device: String, deviceName: String = "") async throws -> Int {
        struct Body: Encodable { let ops: [Op]; let device: String; let deviceName: String }
        struct Version: Decodable { let version: Int }
        let data = try await post("api/g/\(graphID)/ops", body: Body(ops: ops, device: device, deviceName: deviceName))
        return (try? JSONDecoder().decode(Version.self, from: data).version) ?? 0
    }

    /// Upload a file's bytes (the app is single-authed; uploads aren't graph-scoped on the server).
    /// Returns the stored `/files/<id>` url to attach to a node.
    public func upload(_ data: Data, name: String, contentType: String) async throws -> RFile {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/upload"), resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "name", value: name)]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let out = try await send(request)
        struct Resp: Decodable { let url: String; let name: String?; let size: Double? }
        let r = try JSONDecoder().decode(Resp.self, from: out)
        return RFile(url: r.url, name: r.name, type: contentType, size: r.size)
    }

    // MARK: page history

    public func history(graphID: String, pageID: String) async throws -> [RHistoryVersion] {
        let data = try await get("api/g/\(graphID)/history/\(pageID)")
        struct R: Decodable { let versions: [RHistoryVersion] }
        return (try? JSONDecoder().decode(R.self, from: data).versions) ?? []
    }

    public func historyDoc(graphID: String, pageID: String, versionID: Int) async throws -> RDoc {
        let data = try await get("api/g/\(graphID)/history/\(pageID)/\(versionID)")
        struct R: Decodable { let doc: RDoc }
        return try JSONDecoder().decode(R.self, from: data).doc
    }

    @discardableResult
    public func restore(graphID: String, pageID: String, versionID: Int, device: String, deviceName: String) async throws -> Int {
        struct Body: Encodable { let device: String; let deviceName: String }
        struct V: Decodable { let version: Int }
        let data = try await post("api/g/\(graphID)/history/\(pageID)/\(versionID)/restore", body: Body(device: device, deviceName: deviceName))
        return (try? JSONDecoder().decode(V.self, from: data).version) ?? 0
    }

    // MARK: assets

    public func assets(graphID: String) async throws -> [RAsset] {
        let data = try await get("api/g/\(graphID)/assets")
        struct R: Decodable { let assets: [RAsset] }
        return (try? JSONDecoder().decode(R.self, from: data).assets) ?? []
    }

    public func deleteAsset(graphID: String, url: String) async throws {
        struct Body: Encodable { let url: String }
        _ = try await post("api/g/\(graphID)/assets/delete", body: Body(url: url))
    }

    public func renameAsset(graphID: String, url: String, name: String) async throws {
        struct Body: Encodable { let url: String; let name: String }
        _ = try await post("api/g/\(graphID)/assets/rename", body: Body(url: url, name: name))
    }

    public func orphans(graphID: String) async throws -> [RAsset] {
        let data = try await get("api/g/\(graphID)/assets/orphans")
        struct R: Decodable { let orphans: [RAsset] }
        return (try? JSONDecoder().decode(R.self, from: data).orphans) ?? []
    }

    public func deleteOrphans(graphID: String, names: [String]) async throws {
        struct Body: Encodable { let names: [String] }
        _ = try await post("api/g/\(graphID)/assets/orphans/delete", body: Body(names: names))
    }

    public func renameOrphan(graphID: String, name: String, newName: String) async throws {
        struct Body: Encodable { let name: String; let newName: String }
        _ = try await post("api/g/\(graphID)/assets/orphans/rename", body: Body(name: name, newName: newName))
    }

    /// Full-text search → matching node ids (server-side FTS).
    public func search(graphID: String, query: String) async throws -> [String] {
        // Build the query with URLComponents — appendingPathComponent would percent-
        // encode the "?" and the server would see no query parameter.
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/g/\(graphID)/search"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        let data = try await send(URLRequest(url: comps.url!))
        struct Result: Decodable { let ids: [String] }
        return (try? JSONDecoder().decode(Result.self, from: data).ids) ?? []
    }

    /// Quick-capture a line into today's journal Inbox (the server creates the day
    /// node if needed). Uses the current session.
    public func capture(_ text: String, deviceName: String = "") async throws {
        struct Body: Encodable { let text: String; let deviceName: String }
        _ = try await post("api/capture", body: Body(text: text, deviceName: deviceName))
    }

    // MARK: request plumbing

    private func get(_ path: String) async throws -> Data {
        try await send(URLRequest(url: baseURL.appendingPathComponent(path)))
    }

    private func post(_ path: String, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: -1, message: "No response from the server")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: Self.errorMessage(data, status: http.statusCode))
        }
        return data
    }

    private static func errorMessage(_ data: Data, status: Int) -> String {
        struct E: Decodable { let error: String? }
        if let e = try? JSONDecoder().decode(E.self, from: data), let msg = e.error {
            return msg
        }
        switch status {
        case 401: return "Wrong username or password"
        case 423: return "Account locked — try again later"
        default: return "Server error (\(status))"
        }
    }
}
