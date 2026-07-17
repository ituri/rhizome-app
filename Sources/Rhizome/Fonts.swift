import SwiftUI
import CoreText

/// Registers and exposes the bundled Inter typeface (the web app's sans font).
enum Fonts {
    /// Register the bundled Inter faces (upright + italic) so `Font.custom("Inter"…)` and
    /// `Font.custom("Inter-Italic"…)` work.
    static func register() {
        for name in ["Inter", "Inter-Italic", "Inter-BoldItalic"] {
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

extension Font {
    /// Inter at a given size/weight (falls back to the system font if unavailable). Scales with
    /// the system text size (Dynamic Type).
    static func rz(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }

    /// Inter at a fixed size — does NOT scale with Dynamic Type, so it matches the (fixed-size)
    /// UITextView editor exactly.
    static func rzFixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Inter", fixedSize: size).weight(weight)
    }
}
