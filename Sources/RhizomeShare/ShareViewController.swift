#if os(iOS)
import UIKit
import Social
import UniformTypeIdentifiers
import RhizomeKit

/// Native quick-capture: the iOS share sheet → Rhizome's Inbox. Shows the standard compose sheet
/// pre-filled with the shared text/URL; posting sends it to `/api/capture` as the user signed into
/// the main app (via the shared App Group session).
///
/// Three kinds of share are handled:
///  • a link / selected text → one capture line (a titled `<a href>` for URLs);
///  • a shared **image** → upload the image + attach it, with the original image URL noted as a
///    `Source: <link>` sub-bullet. Long-pressing a web image usually delivers only its URL
///    (`public.url`, not `public.image` bytes), so an image-looking URL is downloaded and uploaded too;
///  • a shared **file** (e.g. a PDF open in Safari) → upload it + attach it to the capture line.
@objc(ShareViewController)
final class ShareViewController: SLComposeServiceViewController {
    /// A loaded attachment (image or file) ready to upload once the user posts.
    private struct SharedFile: Sendable {
        let data: Data
        let name: String
        let mime: String
        let isImage: Bool
    }

    private var sharedURL: String?
    private var sharedImageURL: String?    // an image shared by its URL only (e.g. long-pressed web image)
    private var sharedFile: SharedFile?
    private var sharedSourceURL: String?   // an image's original web URL, for the "Source" sub-bullet

    override func presentationAnimationDidFinish() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?.flatMap { $0.attachments ?? [] } ?? []

        // 1) a shared image → upload + attach, noting its source link (if the app shared one too)
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            loadSourceURL(from: providers)
            Self.loadFile(from: provider, kind: .image) { [weak self] file in
                DispatchQueue.main.async {
                    guard let self, let file else { return }
                    self.sharedFile = file
                    self.validateContent()
                }
            }
            return
        }

        // 2) a shared file (PDF / doc / …) → upload + attach it to the capture line
        if let provider = providers.first(where: { p in p.registeredTypeIdentifiers.contains(where: Self.isFileType) }) {
            Self.loadFile(from: provider, kind: .file) { [weak self] file in
                DispatchQueue.main.async {
                    guard let self, let file else { return }
                    self.sharedFile = file
                    self.validateContent()
                }
            }
            return
        }

        // 3) a shared link / text. Safari gives a clean public.url item, but many apps (e.g. Reddit)
        // share the link only as plain text, or deliver the URL as a String/Data rather than a URL
        // object — so accept all of those. A URL that points at an image (a long-pressed web image
        // shared as its URL) is routed to the image path instead: download + upload + Source link.
        let types = [UTType.url.identifier, UTType.plainText.identifier, UTType.text.identifier]
        for type in types {
            guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type) }) else { continue }
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
                guard let url = Self.coerceURL(value) else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if Self.isImageURL(url) {
                        self.sharedImageURL = url
                    } else {
                        self.sharedURL = url
                        if self.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.textView.text = url
                        }
                    }
                    self.validateContent()   // re-enable the Post button now that we have a URL
                }
            }
            return
        }
    }

    // MARK: attachment loading

    private enum Kind { case image, file }

    /// True for a concrete file payload we should upload as an attachment: data-backed, but not a
    /// bare URL/text (those become a link) and not an image (handled by the image branch above).
    nonisolated private static func isFileType(_ id: String) -> Bool {
        guard let t = UTType(id) else { return false }
        return t.conforms(to: .data) && !t.conforms(to: .url) && !t.conforms(to: .text) && !t.conforms(to: .image)
    }

    /// Load a provider's bytes for the best concrete type it offers, deriving a filename + mime type.
    nonisolated private static func loadFile(from provider: NSItemProvider, kind: Kind, completion: @escaping @Sendable (SharedFile?) -> Void) {
        let typeID: String
        switch kind {
        case .image:
            typeID = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
                ?? UTType.image.identifier
        case .file:
            typeID = provider.registeredTypeIdentifiers.first(where: isFileType) ?? UTType.data.identifier
        }
        let uti = UTType(typeID)
        let mime = uti?.preferredMIMEType ?? (kind == .image ? "image/jpeg" : "application/octet-stream")
        let fallback = kind == .image ? "image" : "file"
        let base = provider.suggestedName?.isEmpty == false ? provider.suggestedName! : fallback
        let ext = uti?.preferredFilenameExtension
        let name = (ext != nil && !base.lowercased().hasSuffix("." + ext!.lowercased())) ? base + "." + ext! : base
        let isImage = kind == .image
        provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
            guard let data, !data.isEmpty else { completion(nil); return }
            completion(SharedFile(data: data, name: name, mime: mime, isImage: isImage))
        }
    }

    /// True if the URL's path ends in a known image extension — a web image shared as its URL.
    nonisolated private static func isImageURL(_ s: String) -> Bool {
        guard let u = URL(string: s) else { return false }
        let ext = u.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "svg", "avif"].contains(ext)
    }

    /// Download an image's bytes from its URL, deriving a filename + mime type for the upload.
    nonisolated private static func download(imageURL s: String) async throws -> SharedFile {
        guard let u = URL(string: s) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: u)
        guard !data.isEmpty else { throw URLError(.zeroByteResource) }
        let mime = response.mimeType ?? "image/jpeg"
        var name = u.lastPathComponent
        if name.isEmpty || !name.contains(".") {
            let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "jpg"
            name = "image." + ext
        }
        return SharedFile(data: data, name: name, mime: mime, isImage: true)
    }

    /// Best-effort: find a URL among the shared items and remember it as an image's source link.
    private func loadSourceURL(from providers: [NSItemProvider]) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) else { return }
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
            guard let url = Self.coerceURL(value) else { return }
            DispatchQueue.main.async { [weak self] in self?.sharedSourceURL = url }
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
        return hasText || sharedURL != nil || sharedImageURL != nil || sharedFile != nil
    }

    override func didSelectPost() {
        let comment = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = extensionContext

        // shared image / file → upload the bytes, then capture a line carrying the attachment.
        // A web image shared only as its URL is downloaded first; its URL doubles as the source link.
        if sharedFile != nil || sharedImageURL != nil {
            let existing = sharedFile
            let imageURL = sharedImageURL
            let source = sharedSourceURL ?? sharedImageURL
            Task {
                do {
                    let file: SharedFile
                    if let existing {
                        file = existing
                    } else if let imageURL {
                        file = try await Self.download(imageURL: imageURL)
                    } else {
                        throw URLError(.unknown)
                    }
                    let uploaded = try await Capture.upload(file.data, name: file.name, contentType: file.mime)
                    var children: [String] = []
                    if file.isImage, let source, let u = URL(string: source) {
                        let title = u.host ?? source
                        children.append("Source: \(LinkFormat.anchor(url: u.absoluteString, title: title))")
                    }
                    try await Capture.sendFiles([uploaded], caption: comment, children: children)
                    context?.completeRequest(returningItems: [], completionHandler: nil)
                } catch {
                    context?.cancelRequest(withError: error)
                }
            }
            return
        }

        let url = sharedURL
        Task {
            do {
                if let url, let u = URL(string: url) {
                    // format the shared page as a clickable, titled link. If the page can't be
                    // scraped (bot walls like Reddit's), fall back to the URL slug, then the host.
                    let r = await LinkFormat.resolve(u)
                    let canonical = r.finalURL.absoluteString
                    let title = r.title ?? LinkFormat.titleFromURL(r.finalURL) ?? LinkFormat.titleFromURL(u) ?? r.finalURL.host ?? url
                    let anchor = LinkFormat.anchor(url: canonical, title: title)
                    let noComment = comment.isEmpty || comment == url || comment.caseInsensitiveCompare(title) == .orderedSame
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
