import SwiftUI
import UIKit
import RhizomeKit

extension NSAttributedString.Key {
    /// A link run's href (`#/n/ID` internal or `https://…` external). The run's TEXT stays editable
    /// (an alias): serialization emits `<a href="…">currentText</a>`, so editing the text keeps the
    /// link. Opened via long-press, not tap.
    static let rzHref = NSAttributedString.Key("rzHref")
    /// A block reference's target id → serialized as `((id))`; its text is the live block content.
    static let rzRef = NSAttributedString.Key("rzRef")
    /// An unresolved `[[Name]]` wiki link → serialized as `[[currentText]]` (text = page name).
    static let rzWiki = NSAttributedString.Key("rzWiki")
    /// Inline format flags on a plain run — a sorted subset of "bisc" (bold/italic/strike/code).
    static let rzFormat = NSAttributedString.Key("rzFormat")
    /// A highlight colour name (e.g. "yellow") on a run → serialized as `<span class="hl-…">`.
    static let rzHighlight = NSAttributedString.Key("rzHighlight")
    /// A text colour name (e.g. "red") on a run → serialized as `<span class="tc-…">`.
    static let rzColor = NSAttributedString.Key("rzColor")
}

/// Bridges a Rhizome node's stored HTML source ⇄ an editable `NSAttributedString`. Raw-on-focus:
/// while you edit a bullet, everything shows its MARKDOWN SOURCE as ordinary editable text — links
/// `[[Name]]` / `[text](url)` / `((id))` and formatting `**bold**` / `*italic*` / `` `code` `` /
/// `~~strike~~` — so you can change any of it freely. On blur, `AppModel.resolveEditorMarkdown`
/// turns it all back into stored HTML (`<a href>`, `<b>`, `<i>`, `<code>`, `<s>`, `((id))`).
/// Highlight/text colour are not markdown, so they stay rendered (spans → `.rzHighlight`/`.rzColor`).
@MainActor
enum RichEditor {
    // configurable from Settings (AppModel mirrors the persisted values into these)
    static var fontSize: CGFloat = 15.5
    static var lineSpacing: CGFloat = 1
    // dynamic so the editor's text follows the selected theme (light/dark) and accent
    static var ink: UIColor {
        UIColor { trait in
            let c: (Double, Double, Double) = trait.userInterfaceStyle == .dark
                ? (0.8975, 0.8815, 0.849) : (0.1847, 0.14, 0.1105)
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }
    static var accent: UIColor { rzAccentUIColor(RZTheme.accent) }

    /// The paragraph style carrying the configured line spacing, applied across the whole editor.
    static func paragraphStyle() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        return p
    }

    static func font(_ fmt: String = "") -> UIFont {
        // Italic uses the bundled Inter italic faces (Inter ships them as separate files);
        // fall back to the system italic if they're somehow unavailable. Bold/code stay Inter/Menlo.
        if fmt.contains("i") {
            let name = fmt.contains("b") ? "Inter-BoldItalic" : "Inter-Italic"
            if let f = UIFont(name: name, size: fontSize) { return f }
            var traits: UIFontDescriptor.SymbolicTraits = .traitItalic
            if fmt.contains("b") { traits.insert(.traitBold) }
            let base = UIFont.systemFont(ofSize: fontSize)
            if let d = base.fontDescriptor.withSymbolicTraits(traits) { return UIFont(descriptor: d, size: fontSize) }
            return base
        }
        let name = fmt.contains("c") ? "Menlo" : "Inter"
        var f = UIFont(name: name, size: fontSize) ?? UIFont(name: "\(name)-Regular", size: fontSize) ?? .systemFont(ofSize: fontSize)
        if fmt.contains("b"), let d = f.fontDescriptor.withSymbolicTraits(.traitBold) { f = UIFont(descriptor: d, size: fontSize) }
        return f
    }

    // ((id)) | #[[multi word]] | #tag | [[wiki link]]  — same shapes RichText recognises.
    private static let tokenRE = try? NSRegularExpression(
        pattern: #"(\(\([A-Za-z0-9_-]+\)\))|(#\[\[[^\]]+\]\])|(#[\p{L}0-9_\-]+)|(\[\[[^\]]+\]\])"#
    )
    // #tag / #[[multi word]] — for live re-colouring of typed text.
    private static let tagRE = try? NSRegularExpression(pattern: #"#\[\[[^\]]+\]\]|#[\p{L}0-9_\-]+"#)

    /// Ranges of `#tag` / `#[[multi]]` within a plain string (for the editor's live restyle).
    static func tagRanges(in text: String) -> [NSRange] {
        guard let re = tagRE else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
    }

    // MARK: - source HTML → attributed

    static func render(_ raw: String, doc: RDoc?) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let chars = Array(raw)
        var i = 0
        let fmt = ""   // raw-on-focus: formatting is shown as literal markdown markers, not styled runs
        var hl = ""   // current highlight colour name (from <span class="hl-…">)
        var tc = ""   // current text colour name (from <span class="tc-…">)
        while i < chars.count {
            if chars[i] == "<", let close = nextIndex(">", chars, i) {
                let tag = String(chars[(i + 1)..<close]).trimmingCharacters(in: .whitespaces).lowercased()
                let closing = tag.hasPrefix("/")
                let base = (closing ? String(tag.dropFirst()) : tag).split(whereSeparator: { $0 == " " }).first.map(String.init) ?? ""
                if base == "a", !closing, let end = closeTagRange("a", chars, close + 1) {
                    let inner = String(chars[(close + 1)..<end.open])
                    let href = hrefIn(String(chars[(i + 1)..<close]))   // raw tag → case-preserving href
                    let display = plainStrip(inner)
                    // raw-on-focus: show the markdown source in the editor, editable. [[Name]] for
                    // internal links, [text](url) for external; resolved back to <a href> on blur.
                    let raw = href.isEmpty ? display : (href.hasPrefix("#/n/") ? "[[\(display)]]" : "[\(display)](\(href))")
                    out.append(styled(raw, fmt, hl: hl, tc: tc))
                    i = end.after
                    continue
                }
                switch base {
                // raw-on-focus: emit the markdown marker (same for open/close) as editable text
                case "b", "strong": out.append(styled("**", fmt, hl: hl, tc: tc))
                case "i", "em": out.append(styled("*", fmt, hl: hl, tc: tc))
                case "s", "strike", "del": out.append(styled("~~", fmt, hl: hl, tc: tc))
                case "code": out.append(styled("`", fmt, hl: hl, tc: tc))
                case "span":
                    if closing { hl = ""; tc = "" }
                    else { hl = Highlight.inClass(tag)?.rawValue ?? hl; tc = TextColor.inClass(tag)?.rawValue ?? tc }
                default: break
                }
                i = close + 1
            } else if chars[i] == "<" {
                appendPlain(out, String(chars[i...]), fmt, hl, tc, doc); break
            } else {
                var j = i
                while j < chars.count, chars[j] != "<" { j += 1 }
                appendPlain(out, String(chars[i..<j]), fmt, hl, tc, doc)
                i = j
            }
        }
        if out.length > 0 {
            out.addAttribute(.paragraphStyle, value: paragraphStyle(), range: NSRange(location: 0, length: out.length))
        }
        return out
    }

    private static func appendPlain(_ out: NSMutableAttributedString, _ text: String, _ fmt: String, _ hl: String, _ tc: String, _ doc: RDoc?) {
        let decoded = decodeEntities(text)
        guard let re = tokenRE else { out.append(styled(decoded, fmt, hl: hl, tc: tc)); return }
        let ns = decoded as NSString
        var last = 0
        for m in re.matches(in: decoded, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last {
                out.append(styled(ns.substring(with: NSRange(location: last, length: m.range.location - last)), fmt, hl: hl, tc: tc))
            }
            let tok = ns.substring(with: m.range)
            if tok.hasPrefix("((") || tok.hasPrefix("[[") {
                // raw-on-focus: show ((id)) / [[Name]] as editable accented source
                out.append(styled(tok, fmt, hl: hl, tc: tc))
            } else {
                out.append(styled(tok, fmt, hl: hl, tc: tc)) // #tag: accented but editable (no source)
            }
            last = m.range.location + m.range.length
        }
        if last < ns.length { out.append(styled(ns.substring(from: last), fmt, hl: hl, tc: tc)) }
    }

    private static func styled(_ s: String, _ fmt: String, hl: String = "", tc: String = "", accented: Bool = false) -> NSAttributedString {
        guard !s.isEmpty else { return NSAttributedString() }
        let fg: UIColor = TextColor(rawValue: tc)?.uiColor ?? (accented ? accent : ink)
        var attrs: [NSAttributedString.Key: Any] = [.font: font(fmt), .foregroundColor: fg]
        if !fmt.isEmpty { attrs[.rzFormat] = fmt }
        if fmt.contains("s") { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let h = Highlight(rawValue: hl) { attrs[.rzHighlight] = hl; attrs[.backgroundColor] = h.uiColor }
        if TextColor(rawValue: tc) != nil { attrs[.rzColor] = tc }
        return NSAttributedString(string: s, attributes: attrs)
    }

    static func tokenAttributes() -> [NSAttributedString.Key: Any] {
        [.font: font(), .foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue]
    }

    /// A plain, editable run (accent-free) — used for inserting raw link syntax like `[[Name]]`.
    static func plainRun(_ s: String) -> NSAttributedString { styled(s, "") }

    /// The href value from a raw (case-preserving) `<a …>` tag string.
    static func hrefIn(_ tag: String) -> String {
        guard let r = tag.range(of: #"href\s*=\s*["']([^"']*)["']"#, options: .regularExpression) else { return "" }
        let match = String(tag[r])
        guard let q = match.range(of: #"["']([^"']*)["']"#, options: .regularExpression) else { return "" }
        return String(match[q]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    // MARK: - attributed → source HTML

    static func serialize(_ attr: NSAttributedString) -> String {
        var out = ""
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            let text = (attr.string as NSString).substring(with: range)
            var piece: String
            if let href = attrs[.rzHref] as? String {
                piece = "<a href=\"\(escapeHTML(href))\">\(wrap(escapeHTML(text), attrs[.rzFormat] as? String ?? ""))</a>"
            } else if let ref = attrs[.rzRef] as? String {
                piece = "((\(ref)))"
            } else if attrs[.rzWiki] != nil {
                piece = "[[\(text)]]"
            } else {
                piece = wrap(escapeHTML(text), attrs[.rzFormat] as? String ?? "")
            }
            var classes: [String] = []
            if let tc = attrs[.rzColor] as? String, TextColor(rawValue: tc) != nil { classes.append("tc-\(tc)") }
            if let hl = attrs[.rzHighlight] as? String, Highlight(rawValue: hl) != nil { classes.append("hl-\(hl)") }
            if !classes.isEmpty { piece = "<span class=\"\(classes.joined(separator: " "))\">\(piece)</span>" }
            out += piece
        }
        return out
    }

    private static func wrap(_ text: String, _ fmt: String) -> String {
        guard !fmt.isEmpty, !text.isEmpty else { return text }
        let map: [(Character, String, String)] = [("c", "<code>", "</code>"), ("b", "<b>", "</b>"), ("i", "<i>", "</i>"), ("s", "<s>", "</s>")]
        var open = "", close = ""
        for (ch, o, c) in map where fmt.contains(ch) { open += o; close = c + close }
        return open + text + close
    }

    // MARK: - helpers

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func nextIndex(_ ch: Character, _ chars: [Character], _ from: Int) -> Int? {
        var i = from + 1
        while i < chars.count { if chars[i] == ch { return i }; i += 1 }
        return nil
    }

    /// Locate `</name>`; returns the index of its `<` and the index just past its `>`.
    private static func closeTagRange(_ name: String, _ chars: [Character], _ from: Int) -> (open: Int, after: Int)? {
        let needle = "</\(name)>"
        let n = needle.count
        var i = from
        while i + n <= chars.count {
            if String(chars[i..<(i + n)]).lowercased() == needle { return (i, i + n) }
            i += 1
        }
        return nil
    }

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
}

/// A `UITextView` that edits one bullet as rendered rich text (links/refs/tags shown inline),
/// syncing its HTML source back into `AppModel`. Handles Return → new bullet, atomic token
/// deletion, `[[`/`((` autocomplete at the real caret, and auto-grows to fit its content.
struct RichTextEditor: UIViewRepresentable {
    let model: AppModel
    let id: String
    /// The current source — not used for rendering (the UITextView owns its text), but reading
    /// it in the parent makes the row re-layout as the text grows so `sizeThatFits` is re-queried.
    let source: String

    func makeCoordinator() -> Coordinator { Coordinator(model: model, id: id) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.font = RichEditor.font()
        tv.textColor = RichEditor.ink
        tv.tintColor = RichEditor.accent
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.spellCheckingType = .yes
        tv.attributedText = RichEditor.render(model.editText, doc: model.doc)
        tv.selectedRange = NSRange(location: tv.attributedText.length, length: 0)   // caret at end on focus
        tv.typingAttributes = [
            .font: RichEditor.font(), .foregroundColor: RichEditor.ink,
            .paragraphStyle: RichEditor.paragraphStyle(),
        ]
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        context.coordinator.textView = tv
        model.registerEditor { [weak coord = context.coordinator] s in coord?.insertSuggestion(s) }
        model.registerEditorReload { [weak coord = context.coordinator] in coord?.reloadFromModel() }
        model.registerEditorResign { [weak tv] in _ = tv?.resignFirstResponder() }
        model.registerEditorHighlight { [weak coord = context.coordinator] name in coord?.applyHighlight(name) }
        model.registerEditorDeleteSlash { [weak coord = context.coordinator] in coord?.deleteSlashQuery() }
        model.registerEditorInline { [weak coord = context.coordinator] ch in coord?.applyInline(ch) }
        model.registerEditorTextColor { [weak coord = context.coordinator] name in coord?.applyTextColor(name) }
        model.registerEditorLink { [weak coord = context.coordinator] url in coord?.insertLink(url) }
        return tv
        // NB: the keyboard bar lives as a SwiftUI .safeAreaInset(KeyboardAccessory) in the views
        // now — a UIHostingController hosted as inputAccessoryView didn't receive button taps.
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.syncExternal(uiView)
        // this row is the one being edited → take the keyboard (idiomatic representable focus).
        // On Return the new row's view may not be in a window yet, so becomeFirstResponder fails;
        // retry next runloop via the coordinator so focus (and the keyboard) carries over.
        if model.editingID == id, !uiView.isFirstResponder, !uiView.becomeFirstResponder() {
            Task { @MainActor [weak coord = context.coordinator] in _ = coord?.textView?.becomeFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let h = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: max(h, RichEditor.font().lineHeight))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let model: AppModel
        let id: String
        weak var textView: UITextView?
        private var lastSource: String

        init(model: AppModel, id: String) { self.model = model; self.id = id; self.lastSource = model.editText }

        /// Adopt a source change made elsewhere (e.g. a remote edit) — but never while the user
        /// is actively typing here, which would fight the cursor.
        func syncExternal(_ tv: UITextView) {
            guard !tv.isFirstResponder, model.editText != lastSource else { return }
            lastSource = model.editText
            tv.attributedText = RichEditor.render(model.editText, doc: model.doc)
        }

        func textViewDidChange(_ tv: UITextView) {
            guard model.editingID == id else { return }
            if handleMarkdown(tv) { return }   // # heading / [text](url) link converted this change
            let source = RichEditor.serialize(tv.attributedText)
            lastSource = source
            model.onEditorText(source)
            tv.invalidateIntrinsicContentSize()
            updateSuggestions(tv)
            restyleTags(tv)
        }

        /// Live markdown while typing: `# `/`## `/`### ` at the very start of a bullet becomes a
        /// heading; a full `[label](url)` becomes an inline link token (on the closing ')').
        /// Returns true when it consumed the change (mirrors the web editorInputHook).
        private func handleMarkdown(_ tv: UITextView) -> Bool {
            guard tv.markedTextRange == nil else { return false }   // don't disturb IME composition
            let ns = tv.attributedText.string as NSString
            let caret = min(tv.selectedRange.location, ns.length)

            // block markers — the whole text so far is exactly a marker + a trailing space:
            // "# "/"## "/"### " → heading, "> " → quote, "1. "/"1) " → numbered
            if caret == ns.length {
                var blockFmt: String?
                if ns.range(of: "^#{1,3} $", options: .regularExpression).location == 0, ns.length >= 2, ns.length <= 4 {
                    blockFmt = "h\(ns.length - 1)"
                } else if ns.isEqual(to: "> ") {
                    blockFmt = "quote"
                } else if ns.range(of: "^[0-9]+[.)] $", options: .regularExpression).location == 0 {
                    blockFmt = "number"
                }
                if let fmt = blockFmt {
                    let mut = NSMutableAttributedString(attributedString: tv.attributedText)
                    mut.deleteCharacters(in: NSRange(location: 0, length: ns.length))
                    tv.attributedText = mut
                    tv.selectedRange = NSRange(location: 0, length: 0)
                    model.onEditorText(RichEditor.serialize(tv.attributedText))
                    model.setFormat(id, fmt)
                    return true
                }
            }

            // raw-on-focus: inline markdown (**bold** / *italic* / `code` / ~~strike~~) and
            // [text](url) are left as raw editable syntax, resolved to HTML on blur.
            return false
        }

        /// Re-colour typed `#tags` live (accent), in place, without touching link/ref tokens or
        /// the caret — the desktop's "re-decorate as you type", for tags.
        private func restyleTags(_ tv: UITextView) {
            guard tv.markedTextRange == nil else { return }   // don't disturb IME composition
            let storage = tv.textStorage
            let whole = storage.string as NSString
            var plain: [NSRange] = []
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, _ in
                // a run is "plain" (tags may be re-accented in it) unless it's a link/ref/wiki run
                if attrs[.rzHref] == nil, attrs[.rzRef] == nil, attrs[.rzWiki] == nil { plain.append(range) }
            }
            let sel = tv.selectedRange
            storage.beginEditing()
            for range in plain {
                storage.addAttribute(.foregroundColor, value: RichEditor.ink, range: range)
                for m in RichEditor.tagRanges(in: whole.substring(with: range)) {
                    storage.addAttribute(.foregroundColor, value: RichEditor.accent,
                                         range: NSRange(location: range.location + m.location, length: m.length))
                }
            }
            storage.endEditing()
            tv.selectedRange = sel
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" || text == "\r" { model.returnFromEditor(); return false } // Return → finish this bullet, start the next
            if text.isEmpty { // deletion
                // backspace at the very start of an empty bullet → delete it and move up
                if range.location == 0, range.length == 0, tv.attributedText.length == 0,
                   model.backspaceDelete(id) != nil { return false }
                // links/refs are ordinary editable runs now — normal char-by-char deletion applies
            }
            return true
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            guard model.editingID == id else { return }
            updateSuggestions(tv)
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if model.suppressBlur { return }            // a modal (link prompt) stole focus — keep editing
            // raw-on-focus: resolve THIS bullet's raw markdown ([[Name]] / [text](url)) back to stored
            // links and persist it by id — even when another row already took over (editingID moved on),
            // so leaving a bullet by tapping another one still saves the resolved link.
            model.persistText(id, model.resolveEditorMarkdown(RichEditor.serialize(tv.attributedText)))
            guard model.editingID == id else { return } // another row took over → transition, not a blur
            model.blurred()
        }

        private func updateSuggestions(_ tv: UITextView) {
            let ns = tv.attributedText.string as NSString
            let caret = min(tv.selectedRange.location, ns.length)
            model.updateSuggestions(before: ns.substring(to: caret))
        }

        /// Replace the open `[[query` / `((query` at the caret with the raw markdown source
        /// (`[[Name]]` / `((id))`), editable — resolved to a real link on blur.
        func insertSuggestion(_ s: LinkSuggestion) {
            guard let tv = textView, let kind = model.linkSuggestKind else { return }
            let ns = tv.attributedText.string as NSString
            let caret = min(tv.selectedRange.location, ns.length)
            let open = kind == .page ? "[[" : "(("
            let before = ns.substring(to: caret) as NSString
            let r = before.range(of: open, options: .backwards)
            guard r.location != NSNotFound else { model.clearLinkSuggestions(); return }
            let raw = kind == .page ? "[[\(s.title)]]" : "((\(s.id)))"
            let token = NSMutableAttributedString(attributedString: RichEditor.plainRun(raw))
            token.append(NSAttributedString(string: " ", attributes: [.font: RichEditor.font(), .foregroundColor: RichEditor.ink]))
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            m.replaceCharacters(in: NSRange(location: r.location, length: caret - r.location), with: token)
            tv.attributedText = m
            tv.selectedRange = NSRange(location: r.location + token.length, length: 0)
            tv.typingAttributes = [.font: RichEditor.font(), .foregroundColor: RichEditor.ink] // keep typing plain after the token
            textViewDidChange(tv)
        }

        /// Delete the open `/query` at the caret (before running a slash command).
        func deleteSlashQuery() {
            guard let tv = textView else { return }
            let ns = tv.attributedText.string as NSString
            let caret = min(tv.selectedRange.location, ns.length)
            let before = ns.substring(to: caret) as NSString
            let r = before.range(of: "/", options: .backwards)
            guard r.location != NSNotFound else { return }
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            m.deleteCharacters(in: NSRange(location: r.location, length: caret - r.location))
            tv.attributedText = m
            tv.selectedRange = NSRange(location: r.location, length: 0)
            tv.typingAttributes = [.font: RichEditor.font(), .foregroundColor: RichEditor.ink]
            textViewDidChange(tv)
        }

        /// Re-render from the model's source after it changed out-of-band (geo append), caret at end.
        func reloadFromModel() {
            guard let tv = textView else { return }
            tv.attributedText = RichEditor.render(model.editText, doc: model.doc)
            lastSource = model.editText
            tv.selectedRange = NSRange(location: tv.attributedText.length, length: 0)
            tv.typingAttributes = [.font: RichEditor.font(), .foregroundColor: RichEditor.ink]
        }

        /// Apply (or, for "", remove) a highlight colour on the current selection.
        func applyHighlight(_ name: String) {
            guard let tv = textView, tv.selectedRange.length > 0 else { return }
            let sel = tv.selectedRange
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            if let h = Highlight(rawValue: name) {
                m.addAttribute(.rzHighlight, value: name, range: sel)
                m.addAttribute(.backgroundColor, value: h.uiColor, range: sel)
            } else {
                m.removeAttribute(.rzHighlight, range: sel)
                m.removeAttribute(.backgroundColor, range: sel)
            }
            tv.attributedText = m
            tv.selectedRange = sel
            textViewDidChange(tv)   // re-serialize + sync
        }

        /// Toggle an inline format ("b"/"i"/"s"/"c") over the current selection.
        /// raw-on-focus: wrap the selection in the markdown marker (**bold**, *italic*, `code`,
        /// ~~strike~~) as editable text; it's resolved to <b>/<i>/… on blur. The selected content
        /// keeps its own attributes (highlight/colour) — only the markers are inserted around it.
        func applyInline(_ ch: String) {
            guard let tv = textView, tv.selectedRange.length > 0 else { return }
            let marker: String
            switch ch {
            case "b": marker = "**"
            case "i": marker = "*"
            case "s": marker = "~~"
            case "c": marker = "`"
            default: return
            }
            let sel = tv.selectedRange
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            m.insert(RichEditor.plainRun(marker), at: sel.location + sel.length)   // closing first
            m.insert(RichEditor.plainRun(marker), at: sel.location)                // then opening
            tv.attributedText = m
            tv.selectedRange = NSRange(location: sel.location + marker.count, length: sel.length)  // keep inner selected
            tv.typingAttributes = [.font: RichEditor.font(), .foregroundColor: RichEditor.ink]
            textViewDidChange(tv)
        }

        /// Apply (or, for "", clear) a text colour on the current selection.
        func applyTextColor(_ name: String) {
            guard let tv = textView, tv.selectedRange.length > 0 else { return }
            let sel = tv.selectedRange
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            if let c = TextColor(rawValue: name) {
                m.addAttribute(.rzColor, value: name, range: sel)
                m.addAttribute(.foregroundColor, value: c.uiColor, range: sel)
            } else {
                var edits: [(NSRange, Bool)] = []
                m.enumerateAttributes(in: sel, options: []) { attrs, range, _ in
                    let isLink = attrs[.rzHref] != nil || attrs[.rzRef] != nil || attrs[.rzWiki] != nil
                    edits.append((range, isLink))
                }
                for (range, isLink) in edits {
                    m.removeAttribute(.rzColor, range: range)
                    m.addAttribute(.foregroundColor, value: isLink ? RichEditor.accent : RichEditor.ink, range: range)
                }
            }
            tv.attributedText = m
            tv.selectedRange = sel
            textViewDidChange(tv)   // restyleTags re-accents #tags afterwards
        }

        /// Wrap the current selection in a link to `url` (a page hash or a web URL).
        func insertLink(_ url: String) {
            guard let tv = textView, tv.selectedRange.length > 0 else { return }
            let sel = tv.selectedRange
            let display = (tv.attributedText.string as NSString).substring(with: sel)
            let trimmed = url.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let href = (trimmed.contains("://") || trimmed.hasPrefix("#") || trimmed.hasPrefix("mailto:")) ? trimmed : "https://\(trimmed)"
            let raw = href.hasPrefix("#/n/") ? "[[\(display)]]" : "[\(display)](\(href))"   // raw markdown, resolved on blur
            let token = RichEditor.plainRun(raw)
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            m.replaceCharacters(in: sel, with: token)
            tv.attributedText = m
            tv.selectedRange = NSRange(location: sel.location + token.length, length: 0)
            tv.typingAttributes = [.font: RichEditor.font(), .foregroundColor: RichEditor.ink]
            textViewDidChange(tv)
        }
    }
}
