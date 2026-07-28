import SwiftUI
import UIKit
import QuickLook
import PDFKit
import ImageIO
import CryptoKit

/// Two-tier image cache: an in-memory `NSCache` (auto-evicting under pressure) plus an on-disk
/// thumbnail cache in `Caches/`, so downsampled thumbnails survive app relaunches and aren't
/// re-fetched or re-decoded every time. Thumbnails (`maxPixel != nil`) are downsampled with ImageIO
/// — we never decode a multi-MB photo at full resolution just to fill a 56pt cell. Full-resolution
/// loads (`maxPixel == nil`, e.g. the zoomable viewer) stay memory-only.
@MainActor
enum ImageCache {
    private static let mem: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        c.totalCostLimit = 80 * 1024 * 1024   // ~80 MB of decoded pixels
        return c
    }()
    nonisolated private static let diskDir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rz-thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func load(_ url: URL, maxPixel: Int? = nil) async -> UIImage? {
        let mp = maxPixel ?? 0
        let key = "\(mp)|\(url.absoluteString)" as NSString
        if let img = mem.object(forKey: key) { return img }
        // download + downsample + disk I/O all happen off the main thread; only the (now small)
        // final decode + NSCache insert run here on the main actor
        guard let bytes = await fetchBytes(url, mp), let img = UIImage(data: bytes) else { return nil }
        mem.setObject(img, forKey: key, cost: img.cgImage.map { $0.bytesPerRow * $0.height } ?? 1)
        return img
    }

    /// Returns the bytes to decode: a disk-cached thumbnail if present, else the (downsampled, for
    /// thumbnails) network bytes — which are also written to the disk cache. Sendable `Data` crosses
    /// back to the main actor; the heavy work never touches it.
    nonisolated private static func fetchBytes(_ url: URL, _ maxPixel: Int) async -> Data? {
        let disk = diskURL(url, maxPixel)
        if maxPixel > 0, let data = try? Data(contentsOf: disk) { return data }
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard maxPixel > 0 else { return data }                 // full-res: no downsample, no disk
        let thumb = downsample(data, maxPixel: maxPixel) ?? data
        try? thumb.write(to: disk, options: .atomic)
        return thumb
    }

    /// ImageIO downsample → a small JPEG. Reads the source lazily and only materialises the thumbnail,
    /// so a huge photo never gets fully decoded into memory.
    nonisolated private static func downsample(_ data: Data, maxPixel: Int) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)
    }

    nonisolated private static func diskURL(_ url: URL, _ maxPixel: Int) -> URL {
        let digest = SHA256.hash(data: Data("\(maxPixel)|\(url.absoluteString)".utf8))
        return diskDir.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined()).appendingPathExtension("jpg")
    }

    /// Fetch a previously stored / freshly stored thumbnail image by an arbitrary key (used by
    /// PDFThumbCache so rendered first-page thumbnails also survive relaunches).
    nonisolated static func diskImageData(key: String) -> Data? { try? Data(contentsOf: keyedDiskURL(key)) }
    nonisolated static func storeDiskImage(_ data: Data, key: String) { try? data.write(to: keyedDiskURL(key), options: .atomic) }
    nonisolated private static func keyedDiskURL(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        return diskDir.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined()).appendingPathExtension("jpg")
    }
}

/// Downloads a file attachment via the authenticated session (URLSession.shared carries the
/// rz_session cookie) to a temp file, so QuickLook — which needs a LOCAL file url — can preview
/// it. Reusing the original filename lets QuickLook infer the type + show the name.
@MainActor
enum FileCache {
    private static var store: [URL: URL] = [:]
    static func download(_ url: URL, name: String) async -> URL? {
        if let local = store[url], FileManager.default.fileExists(atPath: local.path) { return local }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rz-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name.isEmpty ? "file" : name)
        do { try data.write(to: dest, options: .atomic); store[url] = dest; return dest }
        catch { return nil }
    }
}

/// Renders a PDF's first page to a thumbnail image (once, cached) so PDFs show inline like photos.
/// Reuses FileCache to fetch the bytes through the authenticated session.
@MainActor
enum PDFThumbCache {
    private static var store: [URL: UIImage] = [:]
    static func thumb(_ url: URL, name: String) async -> UIImage? {
        if let img = store[url] { return img }
        let key = "pdf|\(url.absoluteString)"
        // disk cache first → no need to re-download the PDF and re-render on every launch
        if let data = ImageCache.diskImageData(key: key), let img = UIImage(data: data) { store[url] = img; return img }
        guard let local = await FileCache.download(url, name: name.isEmpty ? "file.pdf" : name),
              let doc = PDFDocument(url: local), let page = doc.page(at: 0) else { return nil }
        let img = page.thumbnail(of: CGSize(width: 700, height: 900), for: .cropBox)
        store[url] = img
        if let jpeg = img.jpegData(compressionQuality: 0.8) { ImageCache.storeDiskImage(jpeg, key: key) }
        return img
    }
}

/// A remote file to preview full-screen (drives `.fullScreenCover(item:)`).
struct ViewerFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
}

/// Downloads a non-image attachment (PDF, doc, …) and previews it in QuickLook.
struct FilePreview: View {
    let remoteURL: URL
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var localURL: URL?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if let localURL {
                QuickLookView(url: localURL).ignoresSafeArea()
            } else if failed {
                VStack(spacing: 14) {
                    Image(systemName: "doc.questionmark").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("Couldn't open this file.").foregroundStyle(.secondary)
                    Button("Close") { dismiss() }
                }
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 30))
                    .symbolRenderingMode(.palette).foregroundStyle(.primary, Color(.systemGray5))
            }
            .padding()
        }
        .task { localURL = await FileCache.download(remoteURL, name: name); if localURL == nil { failed = true } }
    }
}

/// SwiftUI wrapper around QLPreviewController (previews PDFs, docs, images, and more).
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

/// A URL that can drive `.fullScreenCover(item:)`.
struct ViewerImage: Identifiable {
    let id = UUID()
    let url: URL
}

/// An image attachment on a bullet: a fixed-aspect thumbnail (stable size regardless of the List's
/// measurement pass), a delete "×" in its corner, and a tap that opens it full-screen.
struct AttachmentImageView: View {
    let url: URL
    let onDelete: () -> Void
    let onTap: () -> Void          // select/edit the bullet (reveals its file-name text)
    let onOpen: () -> Void         // open full-screen (zoomable)
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                // explicit aspect ratio → stable size from the first render (no collapse until the
                // row is re-measured); no max width → it fills the available column width. The delete
                // "×" overlay is applied to the IMAGE (before the width-filling frame) so it hugs the
                // picture's corner instead of floating in the trailing space of a wider frame.
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)                 // tap the picture → edit the bullet
                    .onLongPressGesture(perform: onOpen)         // long-press → full-screen (also below)
                    .overlay(alignment: .topTrailing) {
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(6)
                    }
                    // an explicit, discoverable way to view/zoom without editing — a plain tap on the
                    // picture jumps into the line, this corner button opens the zoomable viewer
                    .overlay(alignment: .bottomTrailing) {
                        Button(action: onOpen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                                .font(.system(size: 24))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(6)
                        .accessibilityLabel("View full screen")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.rzLineSoft)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                    .overlay { failed ? AnyView(Image(systemName: "photo").foregroundStyle(Color.rzInkFaint)) : AnyView(ProgressView()) }
                    .onTapGesture(perform: onTap)
            }
        }
        .task(id: url) {
            failed = false
            if let img = await ImageCache.load(url, maxPixel: 1600) { image = img } else { failed = true }
        }
    }
}

/// A PDF attachment shown inline like a photo: its first-page thumbnail with a filename badge and a
/// delete "×". Matches the image gestures — tap selects/edits the bullet, long-press opens the PDF
/// full-screen in QuickLook.
struct PDFThumbView: View {
    let url: URL
    let name: String
    let onDelete: () -> Void
    let onTap: () -> Void
    let onOpen: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topLeading) { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.rzLine, lineWidth: 1) }
                    .overlay(alignment: .bottomLeading) {
                        Label(name, systemImage: "doc.richtext")
                            .font(.rz(12)).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)                 // tap → edit the bullet
                    .onLongPressGesture(perform: onOpen)         // long-press → open (also the button below)
                    .overlay(alignment: .topTrailing) {
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(6)
                    }
                    // explicit "open" button so viewing doesn't require a long-press / editing the line
                    .overlay(alignment: .bottomTrailing) {
                        Button(action: onOpen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                                .font(.system(size: 24))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(6)
                        .accessibilityLabel("Open full screen")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.rzLineSoft)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                    .overlay { ProgressView() }
            }
        }
        .task(id: url) { image = await PDFThumbCache.thumb(url, name: name) }
    }
}

/// Full-screen, pinch-to-zoom image viewer.
struct ImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale = max(1, $0) }
                            .onEnded { _ in withAnimation(.easeOut) { scale = max(1, min(scale, 5)) } }
                    )
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.25))
            }
            .padding()
        }
        .task { image = await ImageCache.load(url) }
    }
}
