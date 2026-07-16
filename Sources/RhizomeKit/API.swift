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

/// One outline node. Unknown fields in the server JSON are ignored.
public struct RNode: Codable, Sendable {
    public var text: String?
    public var note: String?
    public var children: [String]?
    public var collapsed: Bool?
    public var done: Bool?
    public var cal: String?   // "root" | "year" | "month" | "day" on calendar nodes

    public init(
        text: String? = nil, note: String? = nil, children: [String]? = nil,
        collapsed: Bool? = nil, done: Bool? = nil, cal: String? = nil
    ) {
        self.text = text; self.note = note; self.children = children
        self.collapsed = collapsed; self.done = done; self.cal = cal
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
    public func capture(_ text: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/capture"))
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(text.utf8)
        _ = try await send(request)
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
