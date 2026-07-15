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

    /// The app's paper background, matching the web theme (#f4f1ea).
    public static let background = (red: 0.957, green: 0.945, blue: 0.918)

    /// The accent (links, tags, bullets) — the web theme's #c2563a.
    public static let accent = (red: 0.760, green: 0.337, blue: 0.227)
}
