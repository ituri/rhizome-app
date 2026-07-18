import SwiftUI
import UIKit
import QuickLook

/// A tiny in-memory cache so an attachment loads once, not on every List re-render.
@MainActor
enum ImageCache {
    private static var store: [URL: UIImage] = [:]
    static func load(_ url: URL) async -> UIImage? {
        if let img = store[url] { return img }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) else { return nil }
        store[url] = img
        return img
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
    let onLongPress: () -> Void    // open full-screen
    @State private var image: UIImage?

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
                    .onTapGesture(perform: onTap)
                    .onLongPressGesture(perform: onLongPress)
                    .overlay(alignment: .topTrailing) {
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.rzLineSoft)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                    .overlay { ProgressView() }
            }
        }
        .task(id: url) { image = await ImageCache.load(url) }
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
