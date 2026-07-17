import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Renders a Rhizome node's stored text — an HTML fragment (`<a href>` links,
/// `<s>` strikethrough, occasionally `<b>/<i>/<code>`) mixed with plain `#tags`
/// and `((block references))` — into a styled `AttributedString`.
public enum RichText {
    #if canImport(SwiftUI)
    /// The accent for tags/links in displayed text — follows the selected accent, and (on UIKit)
    /// the light/dark theme, so it re-resolves when the colour scheme flips.
    public static var accent: Color {
        let a = RZTheme.accent
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? a.dark : a.light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        return Color(red: a.light.0, green: a.light.1, blue: a.light.2)
        #endif
    }
    #endif

    /// Markup stripped to plain text (for titles etc.).
    public static func plain(_ raw: String, doc: RDoc? = nil) -> String {
        String(attributed(raw, doc: doc).characters)
    }

    private struct Style {
        var bold = false, italic = false, strike = false, code = false
        var link: URL?
        var highlight: Highlight?
        var textColor: TextColor?
    }

    private static func classAttr(_ tag: String) -> String? {
        guard let r = tag.range(of: #"class\s*=\s*["']([^"']*)["']"#, options: .regularExpression) else { return nil }
        return String(tag[r])
    }
    private static func hlFrom(tag: String) -> Highlight? { classAttr(tag).flatMap(Highlight.inClass) }
    private static func tcFrom(tag: String) -> TextColor? { classAttr(tag).flatMap(TextColor.inClass) }

    // The base point size for the current render, so bold/italic/code runs can be given an
    // explicit font (Inter ships without an italic face, so the inline-intent italic doesn't
    // slant — we substitute a real italic). 0 = fall back to inline presentation intents.
    nonisolated(unsafe) private static var renderSize: CGFloat = 0

    public static func attributed(_ raw: String, doc: RDoc? = nil, size: CGFloat = 0) -> AttributedString {
        renderSize = size
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
        case "span":
            if let h = hlFrom(tag: tag) { style.highlight = h }   // <span class="hl-…">
            if let c = tcFrom(tag: tag) { style.textColor = c }   // <span class="tc-…">
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
        pattern: #"(https?://[^\s<>()]+)|(\bwww\.[^\s<>()]+)|(\(\([A-Za-z0-9_-]+\)\))|(#\[\[[^\]]+\]\])|(#[\p{L}0-9_\-]+)|(\[\[[^\]]+\]\])"#
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
            if token.hasPrefix("http://") || token.hasPrefix("https://") || token.hasPrefix("www.") {
                if style.link != nil {
                    append(token, style, accent: false, &out)   // already inside an explicit <a href>
                } else {
                    // don't swallow trailing sentence punctuation into the URL
                    var url = token, trailing = ""
                    while let last = url.last, ".,;:!?".contains(last) { trailing = String(last) + trailing; url = String(url.dropLast()) }
                    let target = url.hasPrefix("www.") ? "https://\(url)" : url   // bare www. → https
                    if let u = URL(string: target) {
                        var s = style
                        s.link = u
                        append(url, s, accent: true, &out)
                    } else {
                        append(url, style, accent: false, &out)
                    }
                    if !trailing.isEmpty { append(trailing, style, accent: false, &out) }
                }
            } else if token.hasPrefix("((") {
                let id = String(token.dropFirst(2).dropLast(2))
                let target = doc?.nodes[id]?.text ?? ""
                var s = style
                s.link = URL(string: "rhizome://n/\(id)")   // tapping a block ref jumps to its bullet
                append(plainStrip(target), s, accent: true, &out)
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
        let styled = style.bold || style.italic || style.code
        #if canImport(SwiftUI)
        if styled, renderSize > 0 {
            // give styled runs an explicit font so italic actually slants (Inter has no italic face)
            if style.code {
                piece.font = .system(size: renderSize, design: .monospaced)
            } else if style.italic {
                var f = Font.system(size: renderSize).italic()
                if style.bold { f = f.weight(.bold) }
                piece.font = f
            } else if style.bold {
                piece.font = .custom("Inter", fixedSize: renderSize).weight(.bold)
            }
        } else if styled {
            var intent: InlinePresentationIntent = []
            if style.bold { intent.insert(.stronglyEmphasized) }
            if style.italic { intent.insert(.emphasized) }
            if style.code { intent.insert(.code) }
            piece.inlinePresentationIntent = intent
        }
        #else
        if styled {
            var intent: InlinePresentationIntent = []
            if style.bold { intent.insert(.stronglyEmphasized) }
            if style.italic { intent.insert(.emphasized) }
            if style.code { intent.insert(.code) }
            piece.inlinePresentationIntent = intent
        }
        #endif
        if style.strike { piece.strikethroughStyle = .single }
        #if canImport(SwiftUI)
        if let tc = style.textColor {
            piece.foregroundColor = tc.color               // explicit text colour wins
        } else if isAccent || style.link != nil {
            piece.foregroundColor = accent
        }
        if let url = style.link { piece.link = url; piece.underlineStyle = nil }
        if let h = style.highlight { piece.backgroundColor = h.color }
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
