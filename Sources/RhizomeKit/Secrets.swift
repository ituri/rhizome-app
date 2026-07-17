import Foundation

/// Local, git-skipped configuration for the Share Extension's quick-capture.
///
/// The extension runs in its own process and can't see the app's signed-in session, so
/// it authenticates with a **write-scoped `rzk_…` API key** and posts to a fixed server.
/// Create the key in the web app under *Account → API keys*, then fill both fields in.
///
/// This file is committed empty; keep your values out of git with:
///
///     git update-index --skip-worktree Sources/RhizomeKit/Secrets.swift
///
/// (undo with `--no-skip-worktree`). Until both are set, the share sheet stays disabled.
public enum Secrets {
    /// A write-scoped `rzk_…` API key. Empty = share-sheet capture off.
    public static let captureToken = ""

    /// The Rhizome instance to capture into, e.g. "https://rhizome.example.org".
    public static let captureServerURL = ""
}
