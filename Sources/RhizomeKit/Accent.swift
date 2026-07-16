import Foundation

/// Accent colour — mirrors the web app's Clay / Sage / Indigo / Ink, each with a light + dark tone
/// (oklch tokens converted to sRGB). Shared here so both the display text (RichText) and the app's
/// palette resolve the same accent.
public enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case clay, sage, indigo, ink
    public var id: String { rawValue }
    public var label: String {
        switch self { case .clay: "Clay"; case .sage: "Sage"; case .indigo: "Indigo"; case .ink: "Ink" }
    }
    public var light: (Double, Double, Double) {
        switch self {
        case .clay: (0.7499, 0.3389, 0.1866)
        case .sage: (0.2828, 0.5032, 0.3334)
        case .indigo: (0.3099, 0.3526, 0.6747)
        case .ink: (0.2611, 0.2206, 0.189)
        }
    }
    public var dark: (Double, Double, Double) {
        switch self {
        case .clay: (0.9191, 0.5695, 0.3842)
        case .sage: (0.4846, 0.7405, 0.5381)
        case .indigo: (0.56, 0.6192, 0.939)
        case .ink: (0.8201, 0.8043, 0.7787)
        }
    }
}

/// The currently selected accent, read by the themed colours. AppModel keeps it in sync with the
/// persisted setting; only ever written from the main actor.
public enum RZTheme {
    nonisolated(unsafe) public static var accent: AccentChoice = .clay
}
