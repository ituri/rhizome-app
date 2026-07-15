import Foundation

/// Local secrets. The committed copy is intentionally empty; your real values
/// stay out of git via `git update-index --skip-worktree` on this file (see the
/// README). Paste your key below and rebuild.
enum Secrets {
    /// A write-scoped `rzk_…` API key for the Share Extension's quick-capture.
    /// Create one in the web app under Account → API keys. Empty = capture off.
    static let captureToken = ""
}
