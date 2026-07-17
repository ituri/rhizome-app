import Foundation

/// Glue that lets the Share Extension reuse the main app's signed-in session. The app mirrors
/// its `rz_session` cookie value + server URL into a shared App Group `UserDefaults`; the
/// extension reads them and POSTs to `/api/capture` with an explicit `Cookie` header — no API
/// token, and no reliance on the (flakier) shared HTTPCookieStorage.
///
/// Requires the `com.apple.security.application-groups` entitlement (a paid Apple Developer
/// team) on both the app and the extension.
public enum AppGroup {
    public static let id = "group.org.syslinx.rhizome"

    /// Small key/value store shared with the extension (server URL, session cookie, prefs).
    public static var defaults: UserDefaults? { UserDefaults(suiteName: id) }

    /// The server the app last signed in to (nil if never signed in on this device).
    public static var serverURL: URL? {
        guard let s = defaults?.string(forKey: "serverURL")?.trimmingCharacters(in: .whitespaces),
              !s.isEmpty, let url = URL(string: s), url.scheme != nil else { return nil }
        return url
    }

    /// The signed-in `rz_session` cookie value shared from the app (nil if not signed in).
    public static var sessionCookie: String? {
        let v = defaults?.string(forKey: "sessionCookie")
        return (v?.isEmpty ?? true) ? nil : v
    }

    /// Whether captures are prefixed with the local time (mirrors the app setting).
    public static var captureTimestamp: Bool {
        defaults?.object(forKey: "captureTimestamp") as? Bool ?? true
    }

    // MARK: - written by the main app

    public static func setServerURL(_ s: String) { defaults?.set(s, forKey: "serverURL") }
    public static func setCaptureTimestamp(_ on: Bool) { defaults?.set(on, forKey: "captureTimestamp") }

    /// Mirror the app's `rz_session` cookie value + server URL so the extension can post as the
    /// signed-in user. Call after a successful sign-in.
    public static func mirrorSession(from url: URL) {
        setServerURL(url.absoluteString)
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        if let c = cookies.first(where: { $0.name == "rz_session" }) {
            defaults?.set(c.value, forKey: "sessionCookie")
        }
    }

    /// Drop the shared session on sign-out so the extension can no longer post.
    public static func clearSession() { defaults?.removeObject(forKey: "sessionCookie") }
}
