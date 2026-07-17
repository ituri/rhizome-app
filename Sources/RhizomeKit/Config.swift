import Foundation

/// Shared configuration. The app's server URL is entered on the sign-in screen (no
/// hard-coded instance). The Share Extension is separate — it can't see the app's
/// session, so it captures with its own compiled-in server URL + write-scoped API key,
/// both kept in `Secrets.swift` (git-skipped).
public enum Config {
    /// The app's paper background — the web `--bg` (#f7f5f0).
    public static let background = (red: 0.9712, green: 0.9647, blue: 0.9447)

    /// The accent (links, tags) — the web `--accent` (#bf562f).
    public static let accent = (red: 0.7499, green: 0.3389, blue: 0.1866)

    /// A write-scoped `rzk_…` API key for the Share Extension's quick-capture.
    public static var captureToken: String { Secrets.captureToken }

    /// The Rhizome server the Share Extension captures into (POSTs to `/api/capture`).
    public static var captureServerURL: URL? {
        let s = Secrets.captureServerURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: s), url.scheme != nil else { return nil }
        return url
    }
}
