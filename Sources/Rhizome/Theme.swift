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

/// A palette token that differs between the warm **Paper** skin and the BlueprintJS **Roam** skin.
/// The active skin is read at evaluation time, so flipping skins re-resolves every token on the
/// next render.
func rzSkinned(paper pl: (Double, Double, Double), _ pd: (Double, Double, Double),
               roam rl: (Double, Double, Double), _ rd: (Double, Double, Double)) -> Color {
    RZTheme.skin == .roam ? rzDynamic(rl, rd) : rzDynamic(pl, pd)
}

/// The palette, light + dark tones per token. Paper is the web app's base tokens (oklch → sRGB).
/// Roam mirrors what Phil's web instance ACTUALLY applies: the injected `rhizome/css` graph page —
/// a full BlueprintJS variable swap (#ffffff / #182026 / #8a9ba8 / #e1e8ed, `--accent: #106ba3`
/// pinned for links, tags and buttons) — layered over the style.css Roam block. That page is
/// light-only ("best in Light mode"); the dark tones here are derived Blueprint darks.
extension Color {
    static var rzPaper: Color { rzSkinned(paper: (0.9712, 0.9647, 0.9447), (0.1165, 0.0957, 0.0725), roam: (1, 1, 1), (0.1098, 0.1294, 0.1529)) }              // --bg  #ffffff
    static var rzRaised: Color { rzSkinned(paper: (0.9909, 0.9872, 0.9727), (0.1553, 0.132, 0.1061), roam: (1, 1, 1), (0.1451, 0.1647, 0.1922)) }              // --bg-raised
    static var rzInk: Color { rzDynamic(RZTheme.ink.light, RZTheme.ink.dark) }                                                                                 // --ink  #182026 (Roam)
    static var rzInkSoft: Color { rzSkinned(paper: (0.3926, 0.3455, 0.315), (0.6772, 0.6543, 0.6172), roam: (0.2235, 0.2941, 0.3490), (0.6549, 0.7137, 0.7608)) } // --ink-soft  #394b59
    static var rzInkFaint: Color { rzSkinned(paper: (0.5795, 0.5415, 0.5124), (0.4775, 0.4525, 0.4194), roam: (0.5412, 0.6078, 0.6588), (0.4510, 0.5255, 0.5804)) } // --ink-faint  #8a9ba8
    static var rzLine: Color { rzSkinned(paper: (0.8741, 0.8549, 0.8238), (0.2294, 0.2046, 0.1771), roam: (0.8824, 0.9098, 0.9294), (0.2000, 0.2314, 0.2667)) }  // --line  #e1e8ed
    static var rzLineSoft: Color { rzSkinned(paper: (0.9144, 0.9011, 0.8739), (0.1881, 0.1656, 0.1408), roam: (0.9216, 0.9451, 0.9608), (0.1647, 0.1922, 0.2275)) } // --line-soft  #ebf1f5
    static var rzMention: Color { rzSkinned(paper: (0.2177, 0.4244, 0.6278), (0.4763, 0.6944, 0.8791), roam: (0.3608, 0.4392, 0.5020), (0.5412, 0.6078, 0.6588)) } // --mention  #5c7080
    static var rzDone: Color { rzSkinned(paper: (0.6198, 0.5919, 0.5616), (0.4305, 0.4075, 0.3773), roam: (0.6549, 0.7137, 0.7608), (0.3608, 0.4392, 0.5020)) }  // --done  #a7b6c2
    static var rzRefPage: Color { rzDynamic((0.063, 0.42, 0.639), (0.38, 0.647, 0.82)) }          // .ref-page #106ba3 / #61a5d1
    static var rzRefHead: Color { rzInkFaint }
    /// Roam pins the accent to Blueprint blue (`--accent: #106ba3` — "page links, tags, buttons");
    /// Paper follows the chosen accent.
    static var rzAccent: Color {
        RZTheme.skin == .roam ? rzDynamic(RZTheme.roamBlue.light, RZTheme.roamBlue.dark) : rzAccentColor(RZTheme.accent)
    }
    /// The reference row's accent wash — web `.ref-row` mixes the accent at 5% under Roam.
    static var rzTint: Color { rzAccent.opacity(RZTheme.skin == .roam ? 0.05 : 0.08) }
    /// The bullet dot — web `.bullet .dot`; Roam lightens it to Blueprint's `#a7b6c2` (= --done).
    static var rzDot: Color { RZTheme.skin == .roam ? rzDone : rzInkFaint }
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
