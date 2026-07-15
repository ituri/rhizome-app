#if os(iOS)
import UIKit
import Social
import UniformTypeIdentifiers
import RhizomeKit

/// Native quick-capture: the iOS share sheet → Rhizome's Inbox. Shows the standard
/// compose sheet pre-filled with the shared text/URL; posting sends it to
/// `/api/capture` (the native equivalent of the `r` shell command).
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
        guard !Config.captureToken.isEmpty else { return false }
        let hasText = !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || sharedURL != nil
    }

    override func didSelectPost() {
        var line = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = sharedURL, !line.contains(url) {
            line = line.isEmpty ? url : "\(line) \(url)"
        }
        let context = extensionContext
        Task {
            do {
                try await Capture.send(line)
                context?.completeRequest(returningItems: [], completionHandler: nil)
            } catch {
                context?.cancelRequest(withError: error)
            }
        }
    }
}
#endif
