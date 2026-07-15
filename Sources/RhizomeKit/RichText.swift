import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Renders a Rhizome node's stored text — an HTML fragment (`<a href>` links,
/// `<s>` strikethrough, occasionally `<b>/<i>/<code>`) mixed with plain `#tags`
/// and `((block references))` — into a styled `AttributedString`.
public enum RichText {
    #if canImport(SwiftUI)
    public static let accent = Color(
        red: Config.accent.red, green: Config.accent.green, blue: Config.accent.blue
    )
    #endif

    /// Markup stripped to plain text (for titles etc.).
    public static func plain(_ raw: String, doc: RDoc? = nil) -> String {
        String(attributed(raw, doc: doc).characters)
    }

    private struct Style {
        var bold = false, italic = false, strike = false, code = false
        var link: URL?
    }

    public static func attributed(_ raw: String, doc: RDoc? = nil) -> AttributedString {
        var out = AttributedString()
        var stack = [Style()]
        let chars = Array(raw)
        var i = 0

        func emit(_ text: String) { appendStyled(decodeEntities(text), stack.last!, &out, doc) }

        while i < chars.count {
            if chars[i] == "<", let close = nextIndex(of: ">", in: chars, from: i) {
                let tag = String(chars[(i + 1)..<close])
                apply(tag: tag, to: &stack)
                i = close + 1
            } else if chars[i] == "<" {
                emit(String(chars[i...])); break            // stray '<' with no '>'
            } else {
                var j = i
                while j < chars.count, chars[j] != "<" { j += 1 }
                emit(String(chars[i..<j]))
                i = j
            }
        }
        return out
    }

    // MARK: tag handling

    private static func apply(tag: String, to stack: inout [Style]) {
        if tag.hasPrefix("/") {
            if stack.count > 1 { stack.removeLast() }
            return
        }
        let name = tag.split(whereSeparator: { $0 == " " || $0 == ">" }).first.map(String.init)?.lowercased() ?? ""
        var style = stack.last!
        switch name {
        case "a":
            if let h = href(in: tag) {
                // internal links (#/n/<id>) → a custom scheme the app intercepts to navigate
                if h.hasPrefix("#/n/") {
                    style.link = URL(string: "rhizome://n/\(h.dropFirst(4))")
                } else {
                    style.link = URL(string: h)
                }
            }
        case "b", "strong": style.bold = true
        case "i", "em": style.italic = true
        case "s", "strike", "del": style.strike = true
        case "code": style.code = true
        case "br", "hr": return       // void: no push (kept simple; newlines are rare inline)
        default: break                // unknown open tag → push a copy so its close balances
        }
        stack.append(style)
    }

    private static func href(in tag: String) -> String? {
        guard let r = tag.range(of: #"href\s*=\s*["']([^"']*)["']"#, options: .regularExpression) else { return nil }
        let match = String(tag[r])
        guard let q = match.range(of: #"["']([^"']*)["']"#, options: .regularExpression) else { return nil }
        return String(match[q]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    // MARK: styled text emission ( #tags / [[links]] / ((refs)) inside a text run )

    private static let tokenRE = try? NSRegularExpression(
        pattern: #"(\(\([A-Za-z0-9_-]+\)\))|(#\[\[[^\]]+\]\])|(#[\p{L}0-9_\-]+)|(\[\[[^\]]+\]\])"#
    )

    private static func appendStyled(_ text: String, _ style: Style, _ out: inout AttributedString, _ doc: RDoc?) {
        guard let re = tokenRE else { return append(text, style, accent: false, &out) }
        let ns = text as NSString
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last {
                append(ns.substring(with: NSRange(location: last, length: m.range.location - last)), style, accent: false, &out)
            }
            let token = ns.substring(with: m.range)
            if token.hasPrefix("((") {
                let id = String(token.dropFirst(2).dropLast(2))
                let target = doc?.nodes[id]?.text ?? ""
                append(plainStrip(target), style, accent: true, &out)
            } else if token.hasPrefix("[[") {
                append(String(token.dropFirst(2).dropLast(2)), style, accent: true, &out)
            } else {
                append(token, style, accent: true, &out)   // #tag
            }
            last = m.range.location + m.range.length
        }
        if last < ns.length {
            append(ns.substring(from: last), style, accent: false, &out)
        }
    }

    private static func append(_ string: String, _ style: Style, accent isAccent: Bool, _ out: inout AttributedString) {
        guard !string.isEmpty else { return }
        var piece = AttributedString(string)
        var intent: InlinePresentationIntent = []
        if style.bold { intent.insert(.stronglyEmphasized) }
        if style.italic { intent.insert(.emphasized) }
        if style.code { intent.insert(.code) }
        if !intent.isEmpty { piece.inlinePresentationIntent = intent }
        if style.strike { piece.strikethroughStyle = .single }
        #if canImport(SwiftUI)
        if isAccent || style.link != nil {
            piece.foregroundColor = accent
            if let url = style.link { piece.link = url; piece.underlineStyle = nil }
        }
        #endif
        out.append(piece)
    }

    /// The node id from an internal `rhizome://n/<id>` link, else nil.
    public static func nodeID(from url: URL) -> String? {
        guard url.scheme == "rhizome", url.host == "n" else { return nil }
        let id = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return id.isEmpty ? nil : id
    }

    // MARK: helpers

    private static func plainStrip(_ html: String) -> String {
        decodeEntities(html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
    }

    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var r = s
        for (e, c) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            r = r.replacingOccurrences(of: e, with: c)
        }
        return r
    }

    private static func nextIndex(of char: Character, in chars: [Character], from: Int) -> Int? {
        var i = from + 1
        while i < chars.count { if chars[i] == char { return i }; i += 1 }
        return nil
    }
}
