import SwiftUI
import UIKit

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
    let onTap: () -> Void
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
