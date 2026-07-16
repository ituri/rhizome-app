import SwiftUI
import UIKit
import RhizomeKit

/// Which colour scheme to use — mirrors the web app's Light / Auto / Dark.
enum AppTheme: String, CaseIterable, Identifiable {
    case light, auto, dark
    var id: String { rawValue }
    var label: String {
        switch self { case .light: "Light"; case .auto: "Auto"; case .dark: "Dark" }
    }
    /// nil = follow the system (Auto).
    var colorScheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
}

// AccentChoice + the current-accent holder (RZTheme) live in RhizomeKit so the display text
// (RichText) and this palette resolve the same accent.

/// A colour that resolves to `light` or `dark` sRGB depending on the active interface style —
/// so forcing `.preferredColorScheme` flips the whole palette (the web app's [data-theme]).
func rzDynamic(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
    Color(uiColor: UIColor { trait in
        let c = trait.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
    })
}

func rzAccentColor(_ a: AccentChoice) -> Color { Color(uiColor: rzAccentUIColor(a)) }
func rzAccentUIColor(_ a: AccentChoice) -> UIColor {
    UIColor { trait in
        let c = trait.userInterfaceStyle == .dark ? a.dark : a.light
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
    }
}

/// The web app's palette (oklch tokens converted to sRGB), light + dark tones per token.
extension Color {
    static let rzPaper = rzDynamic((0.9712, 0.9647, 0.9447), (0.1165, 0.0957, 0.0725))   // --bg
    static let rzRaised = rzDynamic((0.9909, 0.9872, 0.9727), (0.1553, 0.132, 0.1061))   // --bg-raised
    static let rzInk = rzDynamic((0.1847, 0.14, 0.1105), (0.8975, 0.8815, 0.849))        // --ink
    static let rzInkSoft = rzDynamic((0.3926, 0.3455, 0.315), (0.6772, 0.6543, 0.6172))  // --ink-soft
    static let rzInkFaint = rzDynamic((0.5795, 0.5415, 0.5124), (0.4775, 0.4525, 0.4194)) // --ink-faint
    static let rzLine = rzDynamic((0.8741, 0.8549, 0.8238), (0.2294, 0.2046, 0.1771))    // --line
    static let rzLineSoft = rzDynamic((0.9144, 0.9011, 0.8739), (0.1881, 0.1656, 0.1408)) // --line-soft
    static let rzMention = rzDynamic((0.2177, 0.4244, 0.6278), (0.4763, 0.6944, 0.8791)) // --mention
    static let rzDone = rzDynamic((0.6198, 0.5919, 0.5616), (0.4305, 0.4075, 0.3773))    // --done
    static let rzRefPage = rzDynamic((0.063, 0.42, 0.639), (0.38, 0.647, 0.82))          // #106ba3 / #61a5d1
    static var rzRefHead: Color { rzInkFaint }
    static var rzAccent: Color { rzAccentColor(RZTheme.accent) }
    static var rzTint: Color { rzAccent.opacity(0.08) }   // accent wash on paper (ref-row box)
}

extension View {
    /// Replace the default grouped/system background with the paper colour.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.rzPaper.ignoresSafeArea())
    }

    /// A paper-backed plain list for outline rows with comfortable, even spacing.
    func outlineList() -> some View {
        listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 30)
            .paperBackground()
    }
}
