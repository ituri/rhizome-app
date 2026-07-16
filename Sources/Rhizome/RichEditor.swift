import SwiftUI
import UIKit
import RhizomeKit

extension NSAttributedString.Key {
    /// A token run's exact source (e.g. `<a href="#/n/ID">Label</a>` or `((id))`). Present →
    /// the run is an atomic, non-editable token; serialization emits this verbatim.
    static let rzSource = NSAttributedString.Key("rzSource")
    /// Inline format flags on a plain run — a sorted subset of "bisc" (bold/italic/strike/code).
    static let rzFormat = NSAttributedString.Key("rzFormat")
}

/// Bridges a Rhizome node's stored HTML source ⇄ an editable `NSAttributedString`, so links,
/// block references and tags render inline (as pills / accented text) *while* you edit — the
/// thing a plain `TextField` can't do. Tokens carry their verbatim source in `.rzSource` and
/// are treated atomically; plain text is HTML-escaped and re-wrapped in `<b>/<i>/<s>/<code>`.
@MainActor
enum RichEditor {
    // configurable from Settings (AppModel mirrors the persisted values into these)
    static var fontSize: CGFloat = 16.5
    static var lineSpacing: CGFloat = 3
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
        let name = fmt.contains("c") ? "Menlo" : "Inter"
        var f = UIFont(name: name, size: fontSize) ?? UIFont(name: "\(name)-Regular", size: fontSize) ?? .systemFont(ofSize: fontSize)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if fmt.contains("b") { traits.insert(.traitBold) }
        if fmt.contains("i") { traits.insert(.traitItalic) }
        if !traits.isEmpty, let d = f.fontDescriptor.withSymbolicTraits(traits) { f = UIFont(descriptor: d, size: fontSize) }
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
        var fmt = ""
        func setFmt(_ c: Character, _ on: Bool) {
            var set = Set(fmt); if on { set.insert(c) } else { set.remove(c) }; fmt = String(set.sorted())
        }
        while i < chars.count {
            if chars[i] == "<", let close = nextIndex(">", chars, i) {
                let tag = String(chars[(i + 1)..<close]).trimmingCharacters(in: .whitespaces).lowercased()
                let closing = tag.hasPrefix("/")
                let base = (closing ? String(tag.dropFirst()) : tag).split(whereSeparator: { $0 == " " }).first.map(String.init) ?? ""
                if base == "a", !closing, let end = closeTagRange("a", chars, close + 1) {
                    let inner = String(chars[(close + 1)..<end.open])
                    appendToken(out, display: plainStrip(inner), source: String(chars[i..<end.after]), fallback: "link")
                    i = end.after
                    continue
                }
                switch base {
                case "b", "strong": setFmt("b", !closing)
                case "i", "em": setFmt("i", !closing)
                case "s", "strike", "del": setFmt("s", !closing)
                case "code": setFmt("c", !closing)
                default: break
                }
                i = close + 1
            } else if chars[i] == "<" {
                appendPlain(out, String(chars[i...]), fmt, doc); break
            } else {
                var j = i
                while j < chars.count, chars[j] != "<" { j += 1 }
                appendPlain(out, String(chars[i..<j]), fmt, doc)
                i = j
            }
        }
        if out.length > 0 {
            out.addAttribute(.paragraphStyle, value: paragraphStyle(), range: NSRange(location: 0, length: out.length))
        }
        return out
    }

    private static func appendPlain(_ out: NSMutableAttributedString, _ text: String, _ fmt: String, _ doc: RDoc?) {
        let decoded = decodeEntities(text)
        guard let re = tokenRE else { out.append(styled(decoded, fmt)); return }
        let ns = decoded as NSString
        var last = 0
        for m in re.matches(in: decoded, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last {
                out.append(styled(ns.substring(with: NSRange(location: last, length: m.range.location - last)), fmt))
            }
            let tok = ns.substring(with: m.range)
            if tok.hasPrefix("((") {
                let id = String(tok.dropFirst(2).dropLast(2))
                appendToken(out, display: plainStrip(doc?.nodes[id]?.text ?? ""), source: tok, fallback: "ref")
            } else if tok.hasPrefix("[[") {
                let inner = String(tok.dropFirst(2).dropLast(2))
                let label = inner.contains("|") ? String(inner.split(separator: "|").last ?? "") : inner
                appendToken(out, display: label, source: tok, fallback: "link")
            } else {
                out.append(styled(tok, fmt, accented: true)) // #tag: accented but editable (no source)
            }
            last = m.range.location + m.range.length
        }
        if last < ns.length { out.append(styled(ns.substring(from: last), fmt)) }
    }

    private static func styled(_ s: String, _ fmt: String, accented: Bool = false) -> NSAttributedString {
        guard !s.isEmpty else { return NSAttributedString() }
        var attrs: [NSAttributedString.Key: Any] = [.font: font(fmt), .foregroundColor: accented ? accent : ink]
        if !fmt.isEmpty { attrs[.rzFormat] = fmt }
        if fmt.contains("s") { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return NSAttributedString(string: s, attributes: attrs)
    }

    static func tokenAttributes() -> [NSAttributedString.Key: Any] {
        [.font: font(), .foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue]
    }

    private static func appendToken(_ out: NSMutableAttributedString, display: String, source: String, fallback: String) {
        var attrs = tokenAttributes()
        attrs[.rzSource] = source
        out.append(NSAttributedString(string: display.isEmpty ? fallback : display, attributes: attrs))
    }

    // MARK: - attributed → source HTML

    static func serialize(_ attr: NSAttributedString) -> String {
        var out = ""
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            if let src = attrs[.rzSource] as? String {
                out += src
            } else {
                let text = (attr.string as NSString).substring(with: range)
                out += wrap(escapeHTML(text), attrs[.rzFormat] as? String ?? "")
            }
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
            let source = RichEditor.serialize(tv.attributedText)
            lastSource = source
            model.onEditorText(source)
            tv.invalidateIntrinsicContentSize()
            updateSuggestions(tv)
            restyleTags(tv)
        }

        /// Re-colour typed `#tags` live (accent), in place, without touching link/ref tokens or
        /// the caret — the desktop's "re-decorate as you type", for tags.
        private func restyleTags(_ tv: UITextView) {
            guard tv.markedTextRange == nil else { return }   // don't disturb IME composition
            let storage = tv.textStorage
            let whole = storage.string as NSString
            var plain: [NSRange] = []
            storage.enumerateAttribute(.rzSource, in: NSRange(location: 0, length: storage.length)) { src, range, _ in
                if src == nil { plain.append(range) }   // collect first, mutate after
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
                // otherwise: remove a touched token whole rather than one char of it
                var del = range
                if range.length == 0, range.location > 0 { del = NSRange(location: range.location - 1, length: 1) }
                if let tok = tokenRange(intersecting: del, in: tv.attributedText) {
                    let m = NSMutableAttributedString(attributedString: tv.attributedText)
                    m.deleteCharacters(in: tok)
                    tv.attributedText = m
                    tv.selectedRange = NSRange(location: tok.location, length: 0)
                    textViewDidChange(tv)
                    return false
                }
            }
            return true
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            guard model.editingID == id else { return }
            updateSuggestions(tv)
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            guard model.editingID == id else { return } // another row took over → this is a transition, not a blur
            model.onEditorText(RichEditor.serialize(tv.attributedText))
            model.blurred()
        }

        private func tokenRange(intersecting r: NSRange, in attr: NSAttributedString) -> NSRange? {
            guard r.location >= 0, r.location < attr.length else { return nil }
            var found: NSRange?
            attr.enumerateAttribute(.rzSource, in: NSRange(location: 0, length: attr.length)) { val, range, stop in
                if val != nil, NSIntersectionRange(range, r).length > 0 { found = range; stop.pointee = true }
            }
            return found
        }

        private func updateSuggestions(_ tv: UITextView) {
            let ns = tv.attributedText.string as NSString
            let caret = min(tv.selectedRange.location, ns.length)
            model.updateSuggestions(before: ns.substring(to: caret))
        }

        /// Replace the open `[[query` / `((query` at the caret with an atomic link/ref token.
        func insertSuggestion(_ s: LinkSuggestion) {
            guard let tv = textView, let kind = model.linkSuggestKind else { return }
            let ns = tv.attributedText.string as NSString
            let caret = min(tv.selectedRange.location, ns.length)
            let open = kind == .page ? "[[" : "(("
            let before = ns.substring(to: caret) as NSString
            let r = before.range(of: open, options: .backwards)
            guard r.location != NSNotFound else { model.clearLinkSuggestions(); return }
            let (display, source) = model.tokenSource(for: s, kind: kind)
            guard !source.isEmpty else { model.clearLinkSuggestions(); return }
            var attrs = RichEditor.tokenAttributes()
            attrs[.rzSource] = source
            let token = NSMutableAttributedString(string: display, attributes: attrs)
            token.append(NSAttributedString(string: " ", attributes: [.font: RichEditor.font(), .foregroundColor: RichEditor.ink]))
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            m.replaceCharacters(in: NSRange(location: r.location, length: caret - r.location), with: token)
            tv.attributedText = m
            tv.selectedRange = NSRange(location: r.location + token.length, length: 0)
            tv.typingAttributes = [.font: RichEditor.font(), .foregroundColor: RichEditor.ink] // keep typing plain after the token
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
    }
}
