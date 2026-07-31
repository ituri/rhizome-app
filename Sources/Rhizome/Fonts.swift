import SwiftUI
import CoreText
import RhizomeKit

/// Registers and exposes the bundled typefaces — Inter (the web app's sans) and Newsreader (its
/// serif). Both are the variable faces the web self-hosts, so weights come off the wght axis.
enum Fonts {
    /// Register the bundled faces (upright + italic) so `Font.custom("Inter"…)`,
    /// `Font.custom("Newsreader 16pt"…)` and friends resolve. Process scope, so RhizomeKit's
    /// display text finds them too.
    static func register() {
        for name in ["Inter", "Inter-Italic", "Inter-BoldItalic", "Newsreader", "Newsreader-Italic"] {
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

extension Font {
    /// The selected typeface at a given size/weight (falls back to the system font if unavailable).
    /// Scales with the system text size (Dynamic Type).
    static func rz(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .rzFace(size, weight: weight, fixed: false)
    }

    /// The selected typeface at a fixed size — does NOT scale with Dynamic Type, so it matches the
    /// (fixed-size) UITextView editor exactly.
    static func rzFixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .rzFace(size, weight: weight, fixed: true)
    }

    /// A page/day title at the active skin's scale, always Inter under Roam (web
    /// `.zoom-title { font-family: var(--sans) }`, which `[data-font]` doesn't reach). Roam day
    /// titles are Inter **500** (the style.css block); a page title is **800** — the injected
    /// `rhizome/css` page's `.zoom-title { font-weight: 800 }` wins over the block's 500 but
    /// doesn't reach `.day-title`. Paper keeps its bold heading.
    static func rzTitle(_ body: Double, page: Bool = false) -> Font {
        let skin = RZTheme.skin
        let roam = skin == .roam
        return .rzFace(
            min(body * skin.titleScale, skin.titleCap),
            weight: roam ? (page ? .heavy : .medium) : .bold,
            choice: roam ? .inter : RZTheme.font
        )
    }
}
