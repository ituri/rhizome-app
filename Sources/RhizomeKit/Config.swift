import Foundation

/// Shared configuration for the app and its extensions. Point this at your own
/// Rhizome instance.
public enum Config {
    /// The Rhizome server. Change this if you self-host elsewhere.
    public static let serverURL = URL(string: "https://rhizome.syslinx.org")!

    /// A write-scoped `rzk_…` API key. Required for the Share Extension's native
    /// quick-capture (it POSTs to `/api/capture?token=…`). Leave empty to disable
    /// capture. Create one in the web app under Account → API keys.
    ///
    /// Kept out of version control on purpose — paste yours here locally, or move
    /// this to a gitignored file. (It's the same key the `r` shell command uses.)
    public static let captureToken = ""

    /// The app's paper background, matching the web theme (#f4f1ea).
    public static let background = (red: 0.957, green: 0.945, blue: 0.918)
}
