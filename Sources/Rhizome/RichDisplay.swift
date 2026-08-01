import SwiftUI
import UIKit
import RhizomeKit

// MARK: - UIKit rendering of RichText pieces

extension NSAttributedString.Key {
    /// Marks a #tag run the display view draws a rounded pill behind (Roam skin).
    static let rzPill = NSAttributedString.Key("rzPill")
    /// Marks a ((block ref)) run the display view draws Roam's grey box behind
    /// (the injected web CSS's `a.block-ref { background: #f0f3f5; border-radius: 4px }`).
    static let rzRefBox = NSAttributedString.Key("rzRefBox")
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
    /// effective accent at resolve time — Blueprint blue under Roam — so a change re-tints on
    /// the next render.
    static var pillFill: UIColor {
        UIColor { trait in
            let a: (light: (Double, Double, Double), dark: (Double, Double, Double)) =
                RZTheme.skin == .roam ? RZTheme.roamBlue : (RZTheme.accent.light, RZTheme.accent.dark)
            let isDark = trait.userInterfaceStyle == .dark
            let c = isDark ? a.dark : a.light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: isDark ? 0.16 : 0.12)
        }
    }
    /// The block-ref box — the injected web CSS's `#f0f3f5`, with a derived Blueprint dark.
    static var refBoxFill: UIColor { uiTone((0.9412, 0.9529, 0.9608), (0.1647, 0.1922, 0.2275)) }
    private static func uiTone(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> UIColor {
        UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }

    /// Render `raw` at `size`. `baseColor` is the surrounding ink (done/quote rows tint it),
    /// `baseBold`/`baseCode` carry the block format (headings / codeblock), `strikeAll` the done
    /// state. Fonts come from RichEditor.uiFont, which applies Dynamic Type itself when the
    /// setting is on — so display, editor and row heights scale identically.
    static func attributed(
        _ raw: String, doc: RDoc?, size: CGFloat, baseColor: UIColor,
        baseBold: Bool = false, baseCode: Bool = false, strikeAll: Bool = false
    ) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let para = RichEditor.paragraphStyle()
        for p in RichText.pieces(raw, doc: doc) {
            out.append(render(p, size: size, baseColor: baseColor, baseBold: baseBold,
                              baseCode: baseCode, strikeAll: strikeAll))
        }
        out.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: out.length))
        return out
    }

    private static func render(
        _ p: RichPiece, size: CGFloat, baseColor: UIColor,
        baseBold: Bool, baseCode: Bool, strikeAll: Bool
    ) -> NSAttributedString {
        func face(_ s: CGFloat, _ fmt: String) -> UIFont { RichEditor.uiFont(size: s, fmt) }
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
        // a tag renders at full body size (Roam's .rm-page-ref--tag has no downscale); an
        // unstyled tag gets weight 500 (the injected web CSS's `.tag { font-weight: 500 }`)
        let styled = p.bold || p.italic || p.code
        let fontSize = size
        var font = face(fontSize, fmt)
        if pilled, !styled {
            let d = font.fontDescriptor.addingAttributes(
                [.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium]]
            )
            font = UIFont(descriptor: d, size: 0)   // size 0: keep the (possibly scaled) point size
        }
        var attrs: [NSAttributedString.Key: Any] = [.font: font]

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
        // in a light grey box (drawn rounded by the display view)
        if p.blockRef, RZTheme.skin == .roam, p.textColor == nil {
            attrs[.foregroundColor] = RichEditor.ink
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attrs[.underlineColor] = blockRefLine
            attrs[.rzRefBox] = true
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
    private let refBoxLayer = CAShapeLayer()
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
        layer.insertSublayer(refBoxLayer, at: 0)    // block-ref boxes under those
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
        var refBoxes: [CGRect] = []
        guard let ns = attributedText, ns.length > 0 else {
            pillLayer.path = nil; refBoxLayer.path = nil; return
        }
        textLayoutManager?.ensureLayout(for: textLayoutManager!.documentRange)
        let whole = NSRange(location: 0, length: ns.length)
        ns.enumerateAttribute(.rzPill, in: whole) { value, range, _ in
            guard value != nil,
                  let f = ns.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
            else { return }
            let em = f.pointSize
            let padV = max(1.5, em * 0.14)
            // One rect per line the run touches. Horizontally the segment frame is right
            // (≈0.25em outset); vertically it spans the whole line box INCLUDING the additive
            // lineSpacing below it, which made the pill hang low. Anchor the pill to the
            // baseline and size it from the tag font's own metrics instead, so the glyphs sit
            // centred; keep the frame as a sanity bound in case baseline semantics ever shift.
            pills += segments(range).map { seg in
                var r = seg.frame.insetBy(dx: -em * 0.25, dy: 0)
                let baseline = seg.frame.minY + seg.baseline
                let top = baseline - f.ascender - padV
                let bottom = baseline - f.descender + padV   // descender is negative
                if top > seg.frame.minY - padV - 2, bottom < seg.frame.maxY + padV + 2, bottom > top {
                    r.origin.y = top
                    r.size.height = bottom - top
                } else {
                    r = r.insetBy(dx: 0, dy: -padV)          // fallback: outset the line box
                }
                return r
            }
        }
        ns.enumerateAttribute(.rzRefBox, in: whole) { value, range, _ in
            guard value != nil else { return }
            // web `a.block-ref { padding: 0 3px }` — a slim box hugging the line
            refBoxes += segments(range).map { $0.frame.insetBy(dx: -3, dy: -0.5) }
        }
        ns.enumerateAttribute(.link, in: whole) { value, range, _ in
            guard let url = value as? URL ?? (value as? String).flatMap(URL.init) else { return }
            linkRects += segments(range).map { ($0.frame.insetBy(dx: -3, dy: -3), url) }
        }
        let path = UIBezierPath()
        for r in pills { path.append(UIBezierPath(roundedRect: r, cornerRadius: r.height / 2)) }   // full capsule
        pillLayer.path = path.isEmpty ? nil : path.cgPath
        let refPath = UIBezierPath()
        for r in refBoxes { refPath.append(UIBezierPath(roundedRect: r, cornerRadius: 4)) }   // web 4px
        refBoxLayer.path = refPath.isEmpty ? nil : refPath.cgPath
        refillPills()
    }

    fileprivate func refillPills() {
        pillLayer.fillColor = RichDisplay.pillFill.resolvedColor(with: traitCollection).cgColor
        refBoxLayer.fillColor = RichDisplay.refBoxFill.resolvedColor(with: traitCollection).cgColor
    }

    /// The on-screen rects of a character range (one per line fragment) with the baseline offset
    /// from the rect's top. Inset and padding are zero, so text-container coordinates are view
    /// coordinates.
    private func segments(_ range: NSRange) -> [(frame: CGRect, baseline: CGFloat)] {
        guard let tlm = textLayoutManager, let tcm = tlm.textContentManager,
              let start = tcm.location(tcm.documentRange.location, offsetBy: range.location),
              let end = tcm.location(start, offsetBy: range.length),
              let tr = NSTextRange(location: start, end: end) else { return [] }
        var out: [(CGRect, CGFloat)] = []
        tlm.enumerateTextSegments(in: tr, type: .standard, options: []) { _, frame, baseline, _ in
            if frame.width > 0.5 { out.append((frame, baseline)) }
            return true
        }
        return out
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
            baseBold: baseBold, baseCode: baseCode, strikeAll: strikeAll
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
