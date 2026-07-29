import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Renders a Rhizome node's stored text — an HTML fragment (`<a href>` links,
/// `<s>` strikethrough, occasionally `<b>/<i>/<code>`) mixed with plain `#tags`
/// and `((block references))` — into a styled `AttributedString`.
public enum RichText {
    #if canImport(SwiftUI)
    /// The accent for tags in displayed text — follows the selected accent, and (on UIKit) the
    /// light/dark theme, so it re-resolves when the colour scheme flips. Both skins use it: the web's
    /// Roam CSS keeps `a.tag { color: var(--accent) }`.
    public static var accent: Color { tone(RZTheme.accent.light, RZTheme.accent.dark) }

    /// An internal `[[page]]` link — the one place the Roam skin overrides the accent, with
    /// Blueprint blue (web `a[href^="#/n/"]`).
    static var link: Color {
        RZTheme.skin == .roam ? tone(RZTheme.roamBlue.light, RZTheme.roamBlue.dark) : accent
    }

    /// The tag pill's fill — web `--accent-soft`, the accent at 12% (light) / 16% (dark).
    static var tagFill: Color {
        let a = RZTheme.accent
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let c = isDark ? a.dark : a.light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: isDark ? 0.16 : 0.12)
        })
        #else
        return Color(red: a.light.0, green: a.light.1, blue: a.light.2).opacity(0.12)
        #endif
    }

    /// The faint `[[` `]]` the Roam skin draws around an internal link (web `::before`/`::after`).
    static var bracket: Color { tone(RZTheme.roamBracket.light, RZTheme.roamBracket.dark) }

    /// Body ink — used for the Roam skin's block references, which read as plain underlined text.
    static var ink: Color { tone(RZTheme.ink.light, RZTheme.ink.dark) }

    /// A colour that re-resolves for the active light/dark scheme (on UIKit).
    private static func tone(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        return Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
    #endif

    /// Markup stripped to plain text (for titles etc.).
    public static func plain(_ raw: String, doc: RDoc? = nil) -> String {
        String(attributed(raw, doc: doc).characters)
    }

    private struct Style {
        var bold = false, italic = false, strike = false, code = false, underline = false
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
        case "u", "ins": style.underline = true
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
        // An `<a href="#/n/…">` link (a resolved [[page]]) gets Roam's faint brackets around it;
        // block refs and #tags don't (web: `a.tag::before/::after { content: none }`).
        guard RZTheme.skin == .roam, isNodeLink(style.link) else {
            return appendTokens(text, style, &out, doc)
        }
        appendBrackets("[[", style, &out)
        appendTokens(text, style, &out, doc)
        appendBrackets("]]", style, &out)
    }

    /// Whether a link points into the graph (`rhizome://n/<id>`) — the web's `a[href^="#/n/"]`.
    private static func isNodeLink(_ url: URL?) -> Bool {
        url?.scheme == "rhizome" && url?.host == "n"
    }

    /// The `[[` / `]]` around an internal link — faint grey, and part of the link so tapping the
    /// brackets navigates too.
    private static func appendBrackets(_ text: String, _ style: Style, _ out: inout AttributedString) {
        var piece = AttributedString(text)
        #if canImport(SwiftUI)
        piece.foregroundColor = bracket
        if let url = style.link { piece.link = url; piece.underlineStyle = nil }
        if renderSize > 0 { piece.font = .rzFace(renderSize) }
        #endif
        out.append(piece)
    }

    private static func appendTokens(_ text: String, _ style: Style, _ out: inout AttributedString, _ doc: RDoc?) {
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
                append(plainStrip(target), s, accent: true, &out, blockRef: true)
            } else if token.hasPrefix("[[") {
                // a raw [[Name]] (unresolved wiki link) → link to the page with that title, if one exists
                let name = String(token.dropFirst(2).dropLast(2))
                var s = style
                if let pid = pageID(named: name, doc: doc) { s.link = URL(string: "rhizome://n/\(pid)") }
                if RZTheme.skin == .roam { appendBrackets("[[", s, &out) }
                append(name, s, accent: true, &out)
                if RZTheme.skin == .roam { appendBrackets("]]", s, &out) }
            } else {
                // #tag or #[[Multi word]] → tapping navigates to the page with that name
                // (create-on-tap, like the web's openTag). Keep the visible text as the raw token.
                var name = String(token.dropFirst())            // drop the leading '#'
                if name.hasPrefix("[[") && name.hasSuffix("]]") { name = String(name.dropFirst(2).dropLast(2)) }
                var s = style
                if let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                    s.link = URL(string: "rhizome://tag/\(enc)")
                }
                append(token, s, accent: true, &out, pill: true)   // #tag
            }
            last = m.range.location + m.range.length
        }
        if last < ns.length {
            append(ns.substring(from: last), style, accent: false, &out)
        }
    }

    private static func append(
        _ string: String, _ style: Style, accent isAccent: Bool, _ out: inout AttributedString,
        pill: Bool = false, blockRef: Bool = false
    ) {
        guard !string.isEmpty else { return }
        // The Roam skin renders a #tag as the web's pill: accent-soft background, 0.92em, with the
        // CSS's 0.4em side padding faked by a narrow no-break space inside the tinted run.
        let pilled = pill && RZTheme.skin == .roam
        var piece = AttributedString(pilled ? "\u{202F}\(string)\u{202F}" : string)
        let styled = style.bold || style.italic || style.code
        #if canImport(SwiftUI)
        if styled, renderSize > 0 {
            // give styled runs an explicit font so italic actually slants (the upright faces carry
            // no italic), in whichever typeface is selected
            if style.code {
                piece.font = .system(size: renderSize, design: .monospaced)
            } else {
                piece.font = .rzFace(renderSize, weight: style.bold ? .bold : .regular, italic: style.italic)
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
        if style.underline { piece.underlineStyle = .single }
        #if canImport(SwiftUI)
        if let tc = style.textColor {
            piece.foregroundColor = tc.color               // explicit text colour wins
        } else if isAccent || style.link != nil {
            // a link into the graph takes the skin's link colour (Roam's blue); tags, web links and
            // the rest stay on the accent
            piece.foregroundColor = isNodeLink(style.link) ? link : accent
        }
        if let url = style.link { piece.link = url; piece.underlineStyle = nil }
        // Roam draws a ((block reference)) as ordinary underlined text, not a coloured link
        if blockRef, RZTheme.skin == .roam, style.textColor == nil {
            piece.foregroundColor = ink
            piece.underlineStyle = .single
        }
        if let h = style.highlight { piece.backgroundColor = h.color }
        if pilled {
            piece.backgroundColor = tagFill               // web --accent-soft
            if !styled, renderSize > 0 { piece.font = .rzFace(renderSize * 0.92) }
        }
        #endif
        out.append(piece)
    }

    /// The id of the page whose title matches `name` (case-insensitive), else nil. Matches both
    /// top-level pages (by their text) and daily notes (by their canonical date label, e.g.
    /// "July 16th, 2026", derived from `cd` — daily notes live under the calendar, not at top level).
    public static func pageID(named name: String, doc: RDoc?) -> String? {
        guard let doc else { return nil }
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        for id in doc.nodes[doc.root]?.children ?? [] where doc.nodes[id]?.cal != "root" {
            if plainStrip(doc.nodes[id]?.text ?? "").trimmingCharacters(in: .whitespaces).lowercased() == q { return id }
        }
        for (id, node) in doc.nodes where node.cal == "day" {
            let label = node.cd.flatMap(Journal.parseCd).map(Journal.label(for:)) ?? (node.text ?? "")
            if label.trimmingCharacters(in: .whitespaces).lowercased() == q { return id }
        }
        return nil
    }

    /// The node id from an internal `rhizome://n/<id>` link, else nil.
    public static func nodeID(from url: URL) -> String? {
        guard url.scheme == "rhizome", url.host == "n" else { return nil }
        let id = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return id.isEmpty ? nil : id
    }

    /// The tag/page name from an internal `rhizome://tag/<name>` link (percent-decoded), else nil.
    public static func tagName(from url: URL) -> String? {
        guard url.scheme == "rhizome", url.host == "tag" else { return nil }
        let raw = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let name = raw.removingPercentEncoding ?? raw
        return name.isEmpty ? nil : name
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
