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

public struct RMe: Codable, Sendable {
    public let user: RUser?
    public let graphs: [RGraph]?
    public let authRequired: Bool?
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
    public var isImage: Bool {
        if let t = type, t.hasPrefix("image/") { return true }
        return (name ?? url).range(of: #"\.(png|jpe?g|gif|webp|svg|bmp|heic|heif)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
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
    public var m: Double?      // last-modified, ms since epoch (server-set)
    public var c: Double?      // created, ms since epoch (server-set)

    public init(
        text: String? = nil, note: String? = nil, children: [String]? = nil,
        collapsed: Bool? = nil, done: Bool? = nil, cal: String? = nil,
        format: String? = nil, files: [RFile]? = nil, m: Double? = nil, c: Double? = nil
    ) {
        self.text = text; self.note = note; self.children = children
        self.collapsed = collapsed; self.done = done; self.cal = cal
        self.format = format; self.files = files; self.m = m; self.c = c
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

    public func me() async throws -> RMe {
        let data = try await get("api/me")
        return try JSONDecoder().decode(RMe.self, from: data)
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

    public func orphans(graphID: String) async throws -> [RAsset] {
        let data = try await get("api/g/\(graphID)/assets/orphans")
        struct R: Decodable { let orphans: [RAsset] }
        return (try? JSONDecoder().decode(R.self, from: data).orphans) ?? []
    }

    public func deleteOrphans(graphID: String, names: [String]) async throws {
        struct Body: Encodable { let names: [String] }
        _ = try await post("api/g/\(graphID)/assets/orphans/delete", body: Body(names: names))
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
