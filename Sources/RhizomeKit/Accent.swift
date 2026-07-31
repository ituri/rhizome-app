import Foundation

/// Accent colour — mirrors the web app's Clay / Sage / Indigo / Ink, each with a light + dark tone
/// (oklch tokens converted to sRGB). Shared here so both the display text (RichText) and the app's
/// palette resolve the same accent.
public enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case clay, sage, indigo, ink
    public var id: String { rawValue }
    public var label: String {
        switch self { case .clay: "Clay"; case .sage: "Sage"; case .indigo: "Indigo"; case .ink: "Ink" }
    }
    public var light: (Double, Double, Double) {
        switch self {
        case .clay: (0.7499, 0.3389, 0.1866)
        case .sage: (0.2828, 0.5032, 0.3334)
        case .indigo: (0.3099, 0.3526, 0.6747)
        case .ink: (0.2611, 0.2206, 0.189)
        }
    }
    public var dark: (Double, Double, Double) {
        switch self {
        case .clay: (0.9191, 0.5695, 0.3842)
        case .sage: (0.4846, 0.7405, 0.5381)
        case .indigo: (0.56, 0.6192, 0.939)
        case .ink: (0.8201, 0.8043, 0.7787)
        }
    }
}

/// Visual skin — the plain "Paper" default, or "Roam", the look of Phil's web instance.
///
/// The web look is TWO layers: the checked-in Roam block at the end of style.css (type scale,
/// titles, blue [[bracketed]] links, pills, ref styling) PLUS the injected `rhizome/css` graph
/// page — a full BlueprintJS palette swap that pins `--accent: #106ba3` for links, tags and
/// buttons. Roam here mirrors both. Sits on top of the Light/Auto/Dark colour scheme; the web
/// page is light-only, so the dark tones are derived Blueprint darks.
public enum RZSkin: String, CaseIterable, Identifiable, Sendable {
    case paper, roam
    public var id: String { rawValue }
    public var label: String { self == .paper ? "Paper" : "Roam" }

    /// The skin's type scale, applied to the size + spacing settings when you pick a skin (both stay
    /// adjustable afterwards). Roam's is the web CSS's own `14px / 1.5`; Paper keeps the app's
    /// defaults — 15.5 pt at the ratio that reproduces its 1 pt of extra leading.
    public var bodySize: Double { self == .roam ? 14 : 15.5 }
    public var lineHeight: Double { self == .roam ? 1.5 : 1.275 }

    /// Page/day titles: web `.zoom-title` is 36px at a 14px body (2.57×) in Inter **500** for Roam;
    /// Paper keeps its 1.74× bold heading. Capped so a large body size can't produce a title that
    /// no longer fits a phone.
    public var titleScale: Double { self == .roam ? 2.57 : 1.74 }
    public var titleCap: Double { self == .roam ? 40 : 34 }
    /// Per-level outline indent — the web's `--indent: 26px` (`.children` 9px margin + 17px
    /// padding); Paper keeps the app's tighter 18.
    public var indent: Double { self == .roam ? 26 : 18 }
    /// Bullet dot diameter, drawn as an exact circle — web `.bullet .dot` is 7px; Paper keeps the
    /// app's smaller dot.
    public var dotSize: Double { self == .roam ? 7 : 4 }
    /// Vertical padding around an outline row — web `.content { padding: 3px 0 }`; Paper keeps the
    /// app's roomier rows, since its line height carries less of the rhythm.
    public var rowPadding: Double { self == .roam ? 3 : 5 }
    /// Space under a page/day title — web `.day-title { margin: 0 0 12px }`.
    public var titleGap: Double { self == .roam ? 12 : 2 }
    /// Space above a day title in the journal. Roam separates days generously (web
    /// `.day-section + .day-section { padding-top: 32px }`, on top of a 46px margin); a List section
    /// already inserts some of that, so this is the remainder rather than the raw CSS number.
    public var sectionGap: Double { self == .roam ? 24 : 8 }
}

/// Which typeface the outline text uses — mirrors the web app's `[data-font]` options (Inter,
/// the Newsreader serif, the platform UI font, and a monospace).
public enum RZFontChoice: String, CaseIterable, Identifiable, Sendable {
    case inter, serif, system, mono
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .inter: "Inter"
        case .serif: "Newsreader"
        case .system: "System"
        case .mono: "Mono"
        }
    }
    /// Name of the bundled upright face, or nil for a system face (`system` / `mono`). Newsreader
    /// goes by its PostScript name — its family ("Newsreader 16pt") carries the optical size.
    public var regularName: String? {
        switch self { case .inter: "Inter"; case .serif: "Newsreader16pt-Regular"; default: nil }
    }
    /// Name of the bundled italic face (Inter and Newsreader ship italics as separate files).
    public var italicName: String? {
        switch self { case .inter: "Inter-Italic"; case .serif: "Newsreader16pt-Italic"; default: nil }
    }
    /// Name of the bundled bold-italic face — Newsreader's italic is variable, so its bold comes
    /// from a weight applied to the same face.
    public var boldItalicName: String? {
        switch self { case .inter: "Inter-BoldItalic"; case .serif: "Newsreader16pt-Italic"; default: nil }
    }
    /// Newsreader's optical sizing runs a little large; nudge it back onto Inter's x-height.
    public var sizeFactor: Double { self == .serif ? 0.97 : 1 }
}

/// The currently selected accent, skin + typeface, read by the themed colours and fonts. AppModel
/// keeps them in sync with the persisted settings; only ever written from the main actor.
public enum RZTheme {
    nonisolated(unsafe) public static var accent: AccentChoice = .clay
    nonisolated(unsafe) public static var skin: RZSkin = .paper
    nonisolated(unsafe) public static var font: RZFontChoice = .inter

    /// Body-text ink for the active skin, light + dark — Paper's warm brown-black, or Roam's
    /// Blueprint `#182026` (the injected web CSS's `--ink`) / `#e1e8ed`. Read by the palette, the
    /// editor and RichText so all three stay in step.
    public static var ink: (light: (Double, Double, Double), dark: (Double, Double, Double)) {
        skin == .roam
            ? ((0.0941, 0.1255, 0.1490), (0.8824, 0.9098, 0.9294))
            : ((0.1847, 0.14, 0.1105), (0.8975, 0.8815, 0.849))
    }

    /// Blueprint blue (`#106ba3` / `#61a5d1`) — Roam's pinned accent: links, tags and buttons
    /// (the injected web CSS's `--accent`).
    public static let roamBlue: (light: (Double, Double, Double), dark: (Double, Double, Double)) =
        ((0.0627, 0.4196, 0.6392), (0.3804, 0.6471, 0.8196))
    /// The faint `[[` `]]` brackets Roam draws around an internal link (`#ced9e0` / `#44545f`).
    public static let roamBracket: (light: (Double, Double, Double), dark: (Double, Double, Double)) =
        ((0.8078, 0.8510, 0.8784), (0.2667, 0.3294, 0.3725))
}
