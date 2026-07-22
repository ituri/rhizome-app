import Foundation

/// Glue that lets the Share Extension reuse the main app's signed-in session. The server URL and
/// prefs live in a shared App Group `UserDefaults`; the (secret) `rz_session` cookie value lives
/// in the shared Keychain access group. The extension reads them and POSTs to `/api/capture`
/// with an explicit `Cookie` header — no API token, no reliance on the flakier HTTPCookieStorage.
///
/// Requires the `com.apple.security.application-groups` and `keychain-access-groups` entitlements
/// (a paid Apple Developer team) on both the app and the extension.
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

    /// The signed-in `rz_session` cookie value, from the shared Keychain (nil if not signed in).
    public static var sessionCookie: String? {
        let v = Keychain.get("rz_session")
        return (v?.isEmpty ?? true) ? nil : v
    }

    /// Whether captures are prefixed with the local time (mirrors the app setting).
    public static var captureTimestamp: Bool {
        defaults?.object(forKey: "captureTimestamp") as? Bool ?? true
    }

    /// The journal bullet quick-capture files under (mirrors the app setting; default "Inbox").
    public static var captureBullet: String {
        let s = defaults?.string(forKey: "captureBullet")?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? "Inbox" : s
    }

    /// A snapshot of today's capture-bullet items (newest first), for the medium widget to render.
    public static var widgetItems: [String] { defaults?.stringArray(forKey: "widgetItems") ?? [] }

    /// Total number of entries under the capture bullet today (for the widget's "+N more" hint).
    public static var widgetTotal: Int { defaults?.integer(forKey: "widgetTotal") ?? 0 }

    // MARK: - written by the main app

    public static func setServerURL(_ s: String) { defaults?.set(s, forKey: "serverURL") }
    public static func setCaptureTimestamp(_ on: Bool) { defaults?.set(on, forKey: "captureTimestamp") }
    public static func setCaptureBullet(_ s: String) { defaults?.set(s, forKey: "captureBullet") }
    public static func setWidgetItems(_ items: [String]) { defaults?.set(items, forKey: "widgetItems") }
    public static func setWidgetTotal(_ n: Int) { defaults?.set(n, forKey: "widgetTotal") }

    /// Mirror the app's `rz_session` cookie value + server URL so the extension can post as the
    /// signed-in user. Call after a successful sign-in.
    public static func mirrorSession(from url: URL) {
        setServerURL(url.absoluteString)
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        if let c = cookies.first(where: { $0.name == "rz_session" }) {
            Keychain.set(c.value, for: "rz_session")
        }
        defaults?.removeObject(forKey: "sessionCookie") // scrub the old plaintext mirror on upgrade
    }

    /// Drop the shared session on sign-out so the extension can no longer post.
    public static func clearSession() {
        Keychain.set(nil, for: "rz_session")
        defaults?.removeObject(forKey: "sessionCookie")
    }
}
