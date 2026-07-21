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

// MARK: - Optimistic replay

extension RNode {
    /// Apply an op's `data`/`patch` scalar fields onto this node (mirrors the web client's
    /// `applyRemoteOps`). Unknown keys are ignored; `files` is left to a full reload.
    mutating func applyFields(_ fields: [String: JSONValue]) {
        for (k, v) in fields {
            switch k {
            case "text": if case let .string(s) = v { text = s }
            case "note": if case let .string(s) = v { note = s } else if case .null = v { note = nil }
            case "done": if case let .bool(b) = v { done = b }
            case "collapsed": if case let .bool(b) = v { collapsed = b }
            case "format": if case let .string(s) = v { format = s }
            case "geo": if case let .string(s) = v { geo = s } else if case .null = v { geo = nil }
            case "cal": if case let .string(s) = v { cal = s }
            case "cd": if case let .string(s) = v { cd = s }
            case "cm": if case let .int(i) = v { cm = i }
            case "cy": if case let .int(i) = v { cy = i }
            case "children":
                if case let .array(a) = v { children = a.compactMap { if case let .string(s) = $0 { return s } else { return nil } } }
            case "m": if case let .double(d) = v { m = d } else if case let .int(i) = v { m = Double(i) }
            case "c": if case let .double(d) = v { c = d } else if case let .int(i) = v { c = Double(i) }
            default: break
            }
        }
    }

    mutating func unset(_ key: String) {
        switch key {
        case "format": format = nil
        case "geo": geo = nil
        case "note": note = nil
        case "done": done = nil
        case "collapsed": collapsed = nil
        default: break
        }
    }
}

extension RDoc {
    /// Replay queued (un-acked) ops onto a freshly fetched server doc so the user's pending
    /// offline edits stay visible instead of being clobbered by the reload. Idempotent and
    /// tolerant of missing nodes — the authoritative merge still happens server-side.
    public mutating func apply(_ ops: [Op]) {
        for op in ops {
            switch op.kind {
            case "insert":
                if nodes[op.node] != nil { break }
                var n = RNode()
                if let data = op.data { n.applyFields(data) }
                if n.children == nil { n.children = [] }
                nodes[op.node] = n
                insert(op.node, under: op.parent ?? root, at: op.ord)
            case "update":
                guard nodes[op.node] != nil else { break }
                if let patch = op.patch { nodes[op.node]!.applyFields(patch) }
                if let unset = op.unset { for k in unset { nodes[op.node]!.unset(k) } }
            case "move":
                guard nodes[op.node] != nil, let parent = op.parent, nodes[parent] != nil else { break }
                detach(op.node)
                insert(op.node, under: parent, at: op.ord)
            case "delete":
                for id in subtreeIDs(op.node) { nodes[id] = nil }
                detach(op.node)
            default: break
            }
        }
    }

    private mutating func insert(_ id: String, under parent: String, at ord: Int?) {
        guard nodes[parent] != nil else { return }
        var kids = nodes[parent]!.children ?? []
        kids.removeAll { $0 == id }               // never duplicate an id among siblings
        let idx = max(0, min(ord ?? kids.count, kids.count))
        kids.insert(id, at: idx)
        nodes[parent]!.children = kids
    }

    private mutating func detach(_ id: String) {
        for pid in Array(nodes.keys) where nodes[pid]?.children?.contains(id) == true {
            nodes[pid]!.children!.removeAll { $0 == id }
        }
    }

    private func subtreeIDs(_ id: String) -> [String] {
        var out = [id], i = 0
        while i < out.count {
            if let kids = nodes[out[i]]?.children { out.append(contentsOf: kids) }
            i += 1
        }
        return out
    }
}
