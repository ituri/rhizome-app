import Foundation

/// A JSON scalar we might send in an op's `data`/`patch`.
public enum JSONValue: Codable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
}

/// One mutation op, matching the server's Route-B protocol (`opsdoc.js`). Only the
/// fields relevant to a given `kind` are set; the rest stay nil and are omitted.
public struct Op: Codable, Sendable {
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
    /// Built without `String(format:)`: `%d` is 32-bit and would truncate the
    /// 64-bit millisecond timestamp, producing a too-small stamp that the server
    /// rejects (updates to existing nodes would be silently dropped).
    public mutating func stamp() -> String {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        counter = (counter + 1) % 100_000
        return "\(Self.pad(ms, 13)):\(Self.pad(counter, 5)):\(device)"
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let s = String(value)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    public func newID() -> String {
        String((0..<12).map { _ in Self.alphabet.randomElement()! })
    }
}
