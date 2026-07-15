import SwiftUI
import RhizomeKit

/// The web app's palette: a warm paper background, dark ink, terracotta accent.
extension Color {
    static let rzPaper = Color(red: Config.background.red, green: Config.background.green, blue: Config.background.blue)
    static let rzAccent = Color(red: Config.accent.red, green: Config.accent.green, blue: Config.accent.blue)
    static let rzInk = Color(red: 0.17, green: 0.16, blue: 0.14)
}

extension View {
    /// Replace the default grouped/system background with the paper colour.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.rzPaper.ignoresSafeArea())
    }
}
