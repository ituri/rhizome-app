import Foundation

/// Glue that lets the Share Extension reuse the main app's signed-in session. The app
/// mirrors its `rz_session` cookie and server URL into a shared App Group container; the
/// extension reads them and POSTs to `/api/capture` as the same user — no API token needed.
///
/// Requires the `com.apple.security.application-groups` entitlement (a paid Apple
/// Developer team) on both the app and the extension.
public enum AppGroup {
    public static let id = "group.org.syslinx.rhizome"

    /// Cookie storage shared between the app and the extension (a per-group singleton, so a
    /// computed accessor returns the same instance each call — and sidesteps the Swift 6
    /// non-Sendable static-let concurrency check).
    public static var cookieStorage: HTTPCookieStorage { HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: id) }

    /// Small key/value store shared with the extension (server URL, capture prefs).
    public static var defaults: UserDefaults? { UserDefaults(suiteName: id) }

    /// A URLSession backed by the shared cookie storage (used by the extension).
    public static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = cookieStorage
        config.httpCookieAcceptPolicy = .always
        return URLSession(configuration: config)
    }()

    /// The server the app last signed in to (nil if never signed in on this device).
    public static var serverURL: URL? {
        guard let s = defaults?.string(forKey: "serverURL")?.trimmingCharacters(in: .whitespaces),
              !s.isEmpty, let url = URL(string: s), url.scheme != nil else { return nil }
        return url
    }

    /// Whether captures are prefixed with the local time (mirrors the app setting).
    public static var captureTimestamp: Bool {
        defaults?.object(forKey: "captureTimestamp") as? Bool ?? true
    }

    // MARK: - written by the main app

    public static func setServerURL(_ s: String) { defaults?.set(s, forKey: "serverURL") }
    public static func setCaptureTimestamp(_ on: Bool) { defaults?.set(on, forKey: "captureTimestamp") }

    /// Copy the app's `rz_session` cookie for `url` into the shared storage so the
    /// extension can authenticate as the same user. Call after a successful sign-in.
    public static func mirrorSession(from url: URL) {
        setServerURL(url.absoluteString)
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        for c in cookies where c.name == "rz_session" { cookieStorage.setCookie(c) }
    }

    /// Drop the shared session on sign-out so the extension can no longer post.
    public static func clearSession() {
        for c in cookieStorage.cookies ?? [] where c.name == "rz_session" { cookieStorage.deleteCookie(c) }
    }
}
