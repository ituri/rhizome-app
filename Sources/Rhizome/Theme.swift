import SwiftUI
import RhizomeKit

/// The web app's light-theme palette (oklch tokens converted to sRGB).
extension Color {
    static let rzPaper = Color(red: Config.background.red, green: Config.background.green, blue: Config.background.blue)
    static let rzAccent = Color(red: Config.accent.red, green: Config.accent.green, blue: Config.accent.blue)
    static let rzInk = Color(red: 0.1847, green: 0.14, blue: 0.1105)      // --ink
    static let rzInkSoft = Color(red: 0.3926, green: 0.3455, blue: 0.315) // --ink-soft
    static let rzInkFaint = Color(red: 0.5795, green: 0.5415, blue: 0.5124) // --ink-faint
    static let rzLine = Color(red: 0.8741, green: 0.8549, blue: 0.8238)   // --line
    static let rzLineSoft = Color(red: 0.9144, green: 0.9011, blue: 0.8739) // --line-soft
    static let rzMention = Color(red: 0.2177, green: 0.4244, blue: 0.6278) // --mention
    static let rzDone = Color(red: 0.6198, green: 0.5919, blue: 0.5616)   // --done
    static let rzRaised = Color(red: 0.9909, green: 0.9872, blue: 0.9727) // --bg-raised
    static let rzRefPage = Color(red: 0.063, green: 0.42, blue: 0.639)    // web .ref-page (#106ba3)
    static let rzTint = Color(red: 0.953, green: 0.915, blue: 0.884)      // accent ~8% on paper (references bg)
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
