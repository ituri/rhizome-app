import Foundation

/// App-wide configuration. Point this at your own Rhizome instance.
enum Config {
    /// The Rhizome server the app wraps. Change this if you self-host elsewhere.
    static let serverURL = URL(string: "https://rhizome.syslinx.org")!

    /// The app's own paper background, matching the web theme (#f4f1ea).
    static let background = (red: 0.957, green: 0.945, blue: 0.918)
}
