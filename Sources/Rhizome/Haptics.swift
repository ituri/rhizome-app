import UIKit

/// Light haptic feedback, gated by the user's setting (AppModel mirrors `enabled`).
@MainActor
enum Haptics {
    nonisolated(unsafe) static var enabled = true

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
