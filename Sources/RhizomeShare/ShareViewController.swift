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
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else { return }
        let urlType = UTType.url.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) else { return }
        provider.loadItem(forTypeIdentifier: urlType, options: nil) { [weak self] value, _ in
            guard let url = value as? URL else { return }
            DispatchQueue.main.async {
                self?.sharedURL = url.absoluteString
                if (self?.contentText ?? "").isEmpty {
                    self?.textView.text = url.absoluteString
                }
            }
        }
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
                    // format the shared page as a clickable, titled link
                    let title = (await LinkFormat.fetchTitle(u)) ?? u.host ?? url
                    let anchor = LinkFormat.anchor(url: url, title: title)
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
