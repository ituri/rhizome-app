import Foundation

/// Shared visual configuration. The server URL is entered on the sign-in screen,
/// so there's no hard-coded instance here.
public enum Config {
    /// The app's paper background — the web `--bg` (#f7f5f0).
    public static let background = (red: 0.9712, green: 0.9647, blue: 0.9447)

    /// The accent (links, tags) — the web `--accent` (#bf562f).
    public static let accent = (red: 0.7499, green: 0.3389, blue: 0.1866)
}
