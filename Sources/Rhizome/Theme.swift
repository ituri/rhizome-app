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
///
/// Both skins share it. The web's Roam skin is *not* a palette swap: its CSS re-tints only the
/// light-mode `--ink`, and leaves `--bg`, the rules, `--mention`, `--done` and `--accent` warm. The
/// handful of tones it really does change are the `skin == .roam` branches below.
extension Color {
    static let rzPaper = rzDynamic((0.9712, 0.9647, 0.9447), (0.1165, 0.0957, 0.0725))   // --bg
    static let rzRaised = rzDynamic((0.9909, 0.9872, 0.9727), (0.1553, 0.132, 0.1061))   // --bg-raised
    static var rzInk: Color { rzDynamic(RZTheme.ink.light, RZTheme.ink.dark) }           // --ink (#202b33 light under Roam)
    static let rzInkSoft = rzDynamic((0.3926, 0.3455, 0.315), (0.6772, 0.6543, 0.6172))  // --ink-soft
    static let rzInkFaint = rzDynamic((0.5795, 0.5415, 0.5124), (0.4775, 0.4525, 0.4194)) // --ink-faint
    static let rzLine = rzDynamic((0.8741, 0.8549, 0.8238), (0.2294, 0.2046, 0.1771))    // --line
    static let rzLineSoft = rzDynamic((0.9144, 0.9011, 0.8739), (0.1881, 0.1656, 0.1408)) // --line-soft
    static let rzMention = rzDynamic((0.2177, 0.4244, 0.6278), (0.4763, 0.6944, 0.8791)) // --mention
    static let rzDone = rzDynamic((0.6198, 0.5919, 0.5616), (0.4305, 0.4075, 0.3773))    // --done
    static let rzRefPage = rzDynamic((0.063, 0.42, 0.639), (0.38, 0.647, 0.82))          // .ref-page #106ba3 / #61a5d1
    /// The "Linked References" label — Roam's flat `#8a9ba8` (web `.backlinks h3`), else warm faint ink.
    static var rzRefHead: Color { RZTheme.skin == .roam ? Color(rzTriple: RZTheme.roamGrey) : rzInkFaint }
    /// The accent stays the user's choice in both skins — the Roam CSS never touches `--accent`.
    static var rzAccent: Color { rzAccentColor(RZTheme.accent) }
    /// The reference row's accent wash — web `.ref-row` mixes the accent at 5% under Roam.
    static var rzTint: Color { rzAccent.opacity(RZTheme.skin == .roam ? 0.05 : 0.08) }
    /// The bullet dot — web `.bullet .dot`; Roam lightens it to `#a7b6c2`, but only in light mode.
    static var rzDot: Color {
        RZTheme.skin == .roam ? rzDynamic(RZTheme.roamDot, (0.6772, 0.6543, 0.6172)) : rzInkFaint
    }

    /// A flat sRGB triple (used for the tones the web CSS hard-codes across both themes).
    init(rzTriple t: (Double, Double, Double)) { self.init(red: t.0, green: t.1, blue: t.2) }
}

/// List-row insets for an outline row at `depth` — the active skin's per-level indent (web
/// `--indent`) and its vertical block rhythm.
func rzRowInsets(depth: Int, skin: RZSkin) -> EdgeInsets {
    EdgeInsets(top: skin.rowPadding, leading: CGFloat(depth) * skin.indent + 14,
               bottom: skin.rowPadding, trailing: 14)
}

extension View {
    /// Replace the default grouped/system background with the paper colour.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.rzPaper.ignoresSafeArea())
    }

    /// A paper-backed plain list for outline rows with comfortable, even spacing. The minimum row
    /// height follows the text — a fixed one would leave the Roam skin's 14 pt rows floating.
    @MainActor
    func outlineList() -> some View {
        listStyle(.plain)
            .environment(\.defaultMinListRowHeight, RichEditor.rowLineHeight() + 2 * RZTheme.skin.rowPadding)
            .paperBackground()
    }
}
