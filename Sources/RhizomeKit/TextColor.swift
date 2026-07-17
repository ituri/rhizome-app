import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
#endif

/// A text (foreground) colour, matching the web app's `tc-<name>` spans. The stored class is
/// authoritative for cross-platform round-tripping; the iOS shades are close approximations.
public enum TextColor: String, CaseIterable, Sendable, Identifiable {
    case red, orange, yellow, green, blue, purple, pink
    public var id: String { rawValue }
    public var cssClass: String { "tc-\(rawValue)" }

    /// (light sRGB, dark sRGB) — dark mode uses a lighter shade so it reads on the dark paper.
    public var srgb: (light: (Double, Double, Double), dark: (Double, Double, Double)) {
        switch self {
        case .red:    ((0.72, 0.20, 0.16), (0.90, 0.45, 0.42))
        case .orange: ((0.78, 0.42, 0.10), (0.92, 0.62, 0.35))
        case .yellow: ((0.62, 0.50, 0.10), (0.88, 0.78, 0.30))
        case .green:  ((0.24, 0.52, 0.30), (0.55, 0.80, 0.60))
        case .blue:   ((0.16, 0.42, 0.72), (0.50, 0.70, 0.92))
        case .purple: ((0.44, 0.30, 0.70), (0.72, 0.60, 0.92))
        case .pink:   ((0.78, 0.28, 0.52), (0.92, 0.55, 0.72))
        }
    }

    /// The colour named by a `class="… tc-x …"` attribute value, if any.
    public static func inClass(_ cls: String) -> TextColor? {
        allCases.first { cls.contains("tc-\($0.rawValue)") }
    }

    #if canImport(UIKit)
    public var uiColor: UIColor {
        let s = srgb
        return UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? s.dark : s.light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }
    #endif
    #if canImport(SwiftUI)
    public var color: Color {
        #if canImport(UIKit)
        Color(uiColor: uiColor)   // follows light/dark
        #else
        let c = srgb.light; return Color(.sRGB, red: c.0, green: c.1, blue: c.2)
        #endif
    }
    #endif
}
