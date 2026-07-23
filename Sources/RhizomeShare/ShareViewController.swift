#if os(iOS)
import UIKit
import Social
import UniformTypeIdentifiers
import RhizomeKit

/// Native quick-capture: the iOS share sheet → Rhizome's Inbox. Shows the standard
/// compose sheet pre-filled with the shared text/URL; posting sends it to `/api/capture`
/// as the user signed into the main app (via the shared App Group session).
@objc(ShareViewController)
final class ShareViewController: SLComposeServiceViewController {
    private var sharedURL: String?

    override func presentationAnimationDidFinish() {
        // Extract a URL from whatever the sharing app handed us. Safari gives a clean public.url
        // item, but many apps (e.g. Reddit) share the link only as plain text, or deliver the URL
        // value as a String/Data rather than a URL object — so accept all of those.
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?.flatMap { $0.attachments ?? [] } ?? []
        let types = [UTType.url.identifier, UTType.plainText.identifier, UTType.text.identifier]
        for type in types {
            guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type) }) else { continue }
            // no `self` capture here → the background completion stays nonisolated; only the
            // resolved URL string (Sendable) hops to the main actor.
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
                guard let url = Self.coerceURL(value) else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.sharedURL = url
                    if self.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.textView.text = url
                    }
                    self.validateContent()   // re-enable the Post button now that we have a URL
                }
            }
            return
        }
    }

    /// Coerce a loaded share item (URL / NSURL / String / Data) into an http(s) URL string, else nil.
    nonisolated private static func coerceURL(_ value: Any?) -> String? {
        let s: String?
        switch value {
        case let u as URL: s = u.absoluteString
        case let n as NSURL: s = n.absoluteString
        case let str as String: s = str
        case let data as Data: s = String(data: data, encoding: .utf8)
        default: s = nil
        }
        guard let s, !s.isEmpty else { return nil }
        // pull the first http(s) URL out of the string (handles "some text https://…" shares)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = s as NSString
            if let m = detector.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
               let u = m.url, (u.scheme == "http" || u.scheme == "https") {
                return u.absoluteString
            }
        }
        return (s.hasPrefix("http://") || s.hasPrefix("https://")) ? s : nil
    }

    override func isContentValid() -> Bool {
        // needs the main app to have signed in (its session is mirrored to the App Group)
        guard AppGroup.serverURL != nil, AppGroup.sessionCookie != nil else { return false }
        let hasText = !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || sharedURL != nil
    }

    override func didSelectPost() {
        let comment = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = sharedURL
        let context = extensionContext
        Task {
            do {
                if let url, let u = URL(string: url) {
                    // format the shared page as a clickable, titled link. If the page can't be
                    // scraped (bot walls like Reddit's), fall back to the URL slug, then the host.
                    let r = await LinkFormat.resolve(u)
                    let canonical = r.finalURL.absoluteString
                    let title = r.title ?? LinkFormat.titleFromURL(r.finalURL) ?? LinkFormat.titleFromURL(u) ?? r.finalURL.host ?? url
                    let anchor = LinkFormat.anchor(url: canonical, title: title)
                    let noComment = comment.isEmpty || comment == url
                    let body = noComment ? anchor : "\(HTMLEscape.text(comment)) \(anchor)"
                    try await Capture.send(body, html: true)
                } else {
                    try await Capture.send(comment)
                }
                context?.completeRequest(returningItems: [], completionHandler: nil)
            } catch {
                context?.cancelRequest(withError: error)
            }
        }
    }
}
#endif
