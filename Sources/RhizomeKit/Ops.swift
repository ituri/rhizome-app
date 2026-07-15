import Foundation

/// A JSON scalar we might send in an op's `data`/`patch`.
public enum JSONValue: Encodable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        }
    }
}

/// One mutation op, matching the server's Route-B protocol (`opsdoc.js`). Only the
/// fields relevant to a given `kind` are set; the rest stay nil and are omitted.
public struct Op: Encodable, Sendable {
    public var kind: String
    public var node: String
    public var hlc: String
    public var parent: String?
    public var ord: Int?
    public var data: [String: JSONValue]?
    public var patch: [String: JSONValue]?
    public var unset: [String]?
    public var ts: Int?

    public init(
        kind: String, node: String, hlc: String,
        parent: String? = nil, ord: Int? = nil,
        data: [String: JSONValue]? = nil, patch: [String: JSONValue]? = nil,
        unset: [String]? = nil, ts: Int? = nil
    ) {
        self.kind = kind; self.node = node; self.hlc = hlc
        self.parent = parent; self.ord = ord
        self.data = data; self.patch = patch; self.unset = unset; self.ts = ts
    }
}

/// Generates hybrid-logical-clock stamps + node ids compatible with the web client.
public struct Clock: Sendable {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    public let device: String
    private var counter = 0

    public init() {
        device = String((0..<8).map { _ in Self.alphabet.randomElement()! })
    }

    /// `pad(ms,13):pad(counter,5):device` — sorts after any earlier stamp.
    public mutating func stamp() -> String {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        counter = (counter + 1) % 100_000
        return String(format: "%013d:%05d:%@", ms, counter, device)
    }

    public func newID() -> String {
        String((0..<12).map { _ in Self.alphabet.randomElement()! })
    }
}
