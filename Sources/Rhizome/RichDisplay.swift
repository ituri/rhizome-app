import SwiftUI
import UIKit
import RhizomeKit

// MARK: - UIKit rendering of RichText pieces

extension NSAttributedString.Key {
    /// Marks a #tag run the display view draws a rounded pill behind (Roam skin).
    static let rzPill = NSAttributedString.Key("rzPill")
}

/// Renders `RichText.pieces` as an `NSAttributedString` for the resting-row display view — the
/// UIKit sibling of `RichText.attributed`. Same fonts and paragraph style as the editor
/// (RichEditor), so a row doesn't shift when editing starts.
@MainActor
enum RichDisplay {
    /// Dynamic colours the SwiftUI palette can't hand to UIKit directly.
    static var bracket: UIColor { uiTone(RZTheme.roamBracket.light, RZTheme.roamBracket.dark) }
    static var done: UIColor { uiTone((0.6198, 0.5919, 0.5616), (0.4305, 0.4075, 0.3773)) }      // --done
    static var inkSoft: UIColor { uiTone((0.3926, 0.3455, 0.315), (0.6772, 0.6543, 0.6172)) }    // --ink-soft
    /// The Roam block-ref underline — web `color-mix(in oklab, var(--ink) 35%, transparent)`.
    static var blockRefLine: UIColor {
        UIColor { trait in
            let (light, dark) = RZTheme.ink
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 0.35)
        }
    }
    /// The tag pill's fill — web `--accent-soft` (accent at 12% light / 16% dark). Reads the
    /// current accent at resolve time so an accent change re-tints on the next render.
    static var pillFill: UIColor {
        UIColor { trait in
            let a = RZTheme.accent
            let isDark = trait.userInterfaceStyle == .dark
            let c = isDark ? a.dark : a.light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: isDark ? 0.16 : 0.12)
        }
    }
    private static func uiTone(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> UIColor {
        UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }

    /// Render `raw` at `size`. `baseColor` is the surrounding ink (done/quote rows tint it),
    /// `baseBold`/`baseCode` carry the block format (headings / codeblock), `strikeAll` the done
    /// state, `scaled` opts into Dynamic Type.
    static func attributed(
        _ raw: String, doc: RDoc?, size: CGFloat, baseColor: UIColor,
        baseBold: Bool = false, baseCode: Bool = false, strikeAll: Bool = false, scaled: Bool = false
    ) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let para = RichEditor.paragraphStyle()
        for p in RichText.pieces(raw, doc: doc) {
            out.append(render(p, size: size, baseColor: baseColor, baseBold: baseBold,
                              baseCode: baseCode, strikeAll: strikeAll, scaled: scaled))
        }
        out.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: out.length))
        return out
    }

    private static func render(
        _ p: RichPiece, size: CGFloat, baseColor: UIColor,
        baseBold: Bool, baseCode: Bool, strikeAll: Bool, scaled: Bool
    ) -> NSAttributedString {
        func face(_ s: CGFloat, _ fmt: String) -> UIFont {
            let f = RichEditor.uiFont(size: s, fmt)
            return scaled ? UIFontMetrics.default.scaledFont(for: f) : f
        }
        if p.bracket {   // Roam's faint [[ ]] — part of the link, so tapping them navigates too
            var attrs: [NSAttributedString.Key: Any] = [
                .font: face(size, baseCode ? "c" : ""), .foregroundColor: bracket
            ]
            if let url = p.link { attrs[.link] = url }
            return NSAttributedString(string: p.text, attributes: attrs)
        }

        let pilled = p.pill && RZTheme.skin == .roam
        var fmt = ""
        if p.code || baseCode { fmt += "c" }
        if p.bold || baseBold { fmt += "b" }
        if p.italic { fmt += "i" }
        // the pill's 0.92em only applies to an unstyled tag, matching the SwiftUI renderer
        let styled = p.bold || p.italic || p.code
        let fontSize = (pilled && !styled) ? size * 0.92 : size
        var attrs: [NSAttributedString.Key: Any] = [.font: face(fontSize, fmt)]

        // colour: explicit text colour > graph-link blue > accent > surrounding ink
        if let tc = p.textColor {
            attrs[.foregroundColor] = tc.uiColor
        } else if p.accent || p.link != nil {
            attrs[.foregroundColor] = RichText.isNodeLink(p.link) ? RichEditor.link : RichEditor.accent
        } else {
            attrs[.foregroundColor] = baseColor
        }
        if p.strike || strikeAll { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if p.underline, p.link == nil { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let url = p.link { attrs[.link] = url }
        // Roam draws a ((block reference)) as ordinary ink with a soft underline (ink at 35%)
        if p.blockRef, RZTheme.skin == .roam, p.textColor == nil {
            attrs[.foregroundColor] = RichEditor.ink
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attrs[.underlineColor] = blockRefLine
        }
        if let h = p.highlight { attrs[.backgroundColor] = h.uiColor }
        if pilled { attrs[.rzPill] = true }   // fill drawn as a rounded rect by the display view

        // the narrow no-break spaces fake the pill's 0.4em side padding inside the drawn rect
        return NSAttributedString(string: pilled ? "\u{202F}\(p.text)\u{202F}" : p.text, attributes: attrs)
    }
}

// MARK: - The display text view (TextKit 2)

/// A non-editable UITextView for resting outline rows. Three jobs SwiftUI `Text` can't do:
/// draws rounded pills behind `#tag` runs (a run background is always a square), honours
/// per-run underline colours, and — via `point(inside:)` — is only touchable over link glyphs,
/// so every other tap falls through to the SwiftUI tap-to-edit layer behind it.
final class PillTextView: UITextView {
    var onLink: ((URL) -> Void)?

    private let pillLayer = CAShapeLayer()
    private var linkRects: [(rect: CGRect, url: URL)] = []

    init() {
        // Build the TextKit 2 stack by hand — `init(usingTextLayoutManager:)` is a convenience
        // initializer a subclass can't delegate to. Segment geometry drives pills and link rects.
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: .zero)
        layoutManager.textContainer = container
        let storage = NSTextContentStorage()
        storage.addTextLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = false                        // pure display; link taps are our recognizer's
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        linkTextAttributes = [:]                    // keep the runs' own colours
        layer.insertSublayer(pillLayer, at: 0)      // pills under the glyphs
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: PillTextView, _) in
            self.refillPills()
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        recomputeDecorations()
    }

    /// Only link glyphs are touchable; everything else falls through to SwiftUI (tap-to-edit,
    /// long-press-to-edit). This replaces three rounds of SwiftUI gesture-arbitration fixes.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        linkRects.contains { $0.rect.contains(point) }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: self)
        if let hit = linkRects.first(where: { $0.rect.contains(p) }) { onLink?(hit.url) }
    }

    /// Recompute pill paths and link hit-rects from the laid-out text.
    private func recomputeDecorations() {
        linkRects = []
        var pills: [CGRect] = []
        guard let ns = attributedText, ns.length > 0 else { pillLayer.path = nil; return }
        textLayoutManager?.ensureLayout(for: textLayoutManager!.documentRange)
        let whole = NSRange(location: 0, length: ns.length)
        ns.enumerateAttribute(.rzPill, in: whole) { value, range, _ in
            guard value != nil else { return }
            // one rect per line the run touches; the outset scales with the tag's font so the
            // pill keeps its proportions at any text size (≈0.25em sideways, ≈0.14em vertically)
            let f = ns.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
            let em = f?.pointSize ?? RichEditor.fontSize
            pills += segmentRects(range).map { $0.insetBy(dx: -em * 0.25, dy: -max(1.5, em * 0.14)) }
        }
        ns.enumerateAttribute(.link, in: whole) { value, range, _ in
            guard let url = value as? URL ?? (value as? String).flatMap(URL.init) else { return }
            linkRects += segmentRects(range).map { ($0.insetBy(dx: -3, dy: -3), url) }
        }
        let path = UIBezierPath()
        for r in pills { path.append(UIBezierPath(roundedRect: r, cornerRadius: min(7, r.height / 2))) }
        pillLayer.path = path.isEmpty ? nil : path.cgPath
        refillPills()
    }

    fileprivate func refillPills() {
        pillLayer.fillColor = RichDisplay.pillFill.resolvedColor(with: traitCollection).cgColor
    }

    /// The on-screen rects of a character range (one per line fragment). Inset and padding are
    /// zero, so text-container coordinates are view coordinates.
    private func segmentRects(_ range: NSRange) -> [CGRect] {
        guard let tlm = textLayoutManager, let tcm = tlm.textContentManager,
              let start = tcm.location(tcm.documentRange.location, offsetBy: range.location),
              let end = tcm.location(start, offsetBy: range.length),
              let tr = NSTextRange(location: start, end: end) else { return [] }
        var rects: [CGRect] = []
        tlm.enumerateTextSegments(in: tr, type: .standard, options: []) { _, frame, _, _ in
            if frame.width > 0.5 { rects.append(frame) }
            return true
        }
        return rects
    }
}

// MARK: - SwiftUI wrapper

/// A resting bullet's rendered text. Internal `rhizome://` links route through the same
/// `openURL` environment the SwiftUI path used (handleNodeLinks), so navigation is unchanged.
struct RichTextDisplay: UIViewRepresentable {
    var raw: String
    var doc: RDoc?
    var size: CGFloat
    var baseColor: UIColor
    var baseBold = false
    var baseCode = false
    var strikeAll = false
    var scaled = false
    var maxLines = 0
    var interactive = true

    // re-render when the user's Dynamic Type size changes (fonts are metrics-scaled when `scaled`)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeUIView(context: Context) -> PillTextView { PillTextView() }

    func updateUIView(_ tv: PillTextView, context: Context) {
        tv.onLink = { url in context.environment.openURL(url) }
        tv.isUserInteractionEnabled = interactive
        tv.textContainer.maximumNumberOfLines = maxLines
        tv.textContainer.lineBreakMode = .byTruncatingTail
        tv.attributedText = RichDisplay.attributed(
            raw, doc: doc, size: size, baseColor: baseColor,
            baseBold: baseBold, baseCode: baseCode, strikeAll: strikeAll, scaled: scaled
        )
        tv.setNeedsLayout()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PillTextView, context: Context) -> CGSize? {
        guard let w = proposal.width, w > 0, w.isFinite else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        // full proposed width: the empty area right of the text stays inside this view, where
        // point(inside:) is false — so taps there reach the SwiftUI edit layer behind
        return CGSize(width: w, height: fit.height)
    }
}
