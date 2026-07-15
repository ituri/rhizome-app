import SwiftUI
import CoreText

/// Registers and exposes the bundled Inter typeface (the web app's sans font).
enum Fonts {
    /// Register the bundled font with the process so `Font.custom("Inter", …)` works.
    static func register() {
        guard let url = Bundle.module.url(forResource: "Inter", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    /// Inter at a given size/weight (falls back to the system font if unavailable).
    static func rz(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }
}
