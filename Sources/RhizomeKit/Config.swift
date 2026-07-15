import Foundation

/// Shared configuration for the app and its extensions. Point this at your own
/// Rhizome instance.
public enum Config {
    /// The Rhizome server. Change this if you self-host elsewhere.
    public static let serverURL = URL(string: "https://rhizome.syslinx.org")!

    /// A write-scoped `rzk_…` API key for the Share Extension's quick-capture
    /// (it POSTs to `/api/capture?token=…`). Lives in `Secrets.swift`, which is
    /// git-ignored so the key never lands in version control.
    public static var captureToken: String { Secrets.captureToken }

    /// The app's paper background — the web `--bg` (#f7f5f0).
    public static let background = (red: 0.9712, green: 0.9647, blue: 0.9447)

    /// The accent (links, tags) — the web `--accent` (#bf562f).
    public static let accent = (red: 0.7499, green: 0.3389, blue: 0.1866)
}
