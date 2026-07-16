import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
#endif

/// A text highlight colour, matching the web app's `hl-<name>` spans (oklch → sRGB, with alpha).
public enum Highlight: String, CaseIterable, Sendable, Identifiable {
    case red, orange, yellow, green, blue, purple, pink, gray
    public var id: String { rawValue }
    public var cssClass: String { "hl-\(rawValue)" }

    /// Semi-transparent background (r, g, b, alpha).
    public var rgba: (Double, Double, Double, Double) {
        switch self {
        case .red: (0.869, 0.306, 0.295, 0.22)
        case .orange: (0.894, 0.508, 0.201, 0.26)
        case .yellow: (0.893, 0.776, 0.308, 0.4)
        case .green: (0.331, 0.715, 0.432, 0.25)
        case .blue: (0.319, 0.579, 0.836, 0.22)
        case .purple: (0.584, 0.431, 0.824, 0.2)
        case .pink: (0.927, 0.464, 0.7, 0.22)
        case .gray: (0.518, 0.499, 0.478, 0.18)
        }
    }

    /// The highlight named by a `class="… hl-x …"` attribute value, if any.
    public static func inClass(_ cls: String) -> Highlight? {
        allCases.first { cls.contains("hl-\($0.rawValue)") }
    }

    #if canImport(SwiftUI)
    public var color: Color { let c = rgba; return Color(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: c.3) }
    #endif
    #if canImport(UIKit)
    public var uiColor: UIColor { let c = rgba; return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3) }
    #endif
}
