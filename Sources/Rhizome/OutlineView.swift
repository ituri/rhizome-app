import SwiftUI
import PhotosUI
import UIKit
import RhizomeKit

/// One flattened, visible outline row (a node plus its indentation depth).
struct OutlineRowItem: Identifiable {
    let id: String
    let depth: Int
}

/// Depth-first flatten of the visible tree under `parent` (respecting collapsed
/// nodes). Defaults to the document root.
func visibleRows(_ doc: RDoc, from parent: String? = nil) -> [OutlineRowItem] {
    var rows: [OutlineRowItem] = []
    func addChildren(of parent: String, depth: Int) {
        for child in doc.nodes[parent]?.children ?? [] {
            rows.append(OutlineRowItem(id: child, depth: depth))
            let node = doc.nodes[child]
            let hasChildren = !(node?.children?.isEmpty ?? true)
            if hasChildren, !(node?.collapsed ?? false) {
                addChildren(of: child, depth: depth + 1)
            }
        }
    }
    addChildren(of: parent ?? doc.root, depth: 0)
    return rows
}

/// A single outline row: bullet / collapse control + text (display or inline edit).
struct OutlineRow: View {
    @Environment(AppModel.self) private var model
    let id: String
    let node: RNode?

    @State private var viewer: ViewerImage?   // the attachment shown full-screen

    private var hasChildren: Bool { !(node?.children?.isEmpty ?? true) }
    private var isCollapsed: Bool { node?.collapsed ?? false }
    private var isDone: Bool { node?.done ?? false }
    private var isTodo: Bool { node?.format == "todo" }
    private var isNumbered: Bool { node?.format == "number" }
    private var hasFiles: Bool { !(node?.files?.isEmpty ?? true) }

    /// Image / file attachments rendered below the bullet's text.
    @ViewBuilder
    private var attachments: some View {
        if let files = node?.files, !files.isEmpty {
            ForEach(files, id: \.url) { f in
                if f.isImage, let url = model.fileURL(f.url) {
                    AttachmentImageView(
                        url: url,
                        onDelete: { model.removeFile(f.url, from: id) },
                        onTap: { model.beginEdit(id) },
                        onLongPress: { viewer = ViewerImage(url: url) }
                    )
                } else if let url = model.fileURL(f.url) {
                    Link(destination: url) {
                        Label(f.name ?? "file", systemImage: "paperclip").font(.rz(14))
                    }
                }
            }
        }
    }

    /// The bullet's text — a tap-to-edit layer behind the rendered text (links stay tappable),
    /// styled by the node's block format (headings / quote / code; divider draws a rule).
    @ViewBuilder
    private func textDisplay(_ raw: String, _ lineH: CGFloat) -> some View {
        let fmt = node?.format
        if fmt == "divider" {
            Rectangle().fill(Color.rzLine)
                .frame(maxWidth: .infinity, maxHeight: 1)
                .frame(minHeight: lineH, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture { model.beginEdit(id) }
        } else {
            let hasLinks = raw.contains("[[") || raw.contains("((") || raw.contains("href")
                || raw.contains("http://") || raw.contains("https://") || raw.contains("www.")   // bare URLs are tappable too
            let size: Double = fmt == "h1" ? model.fontSize * 1.55
                : fmt == "h2" ? model.fontSize * 1.3
                : fmt == "h3" ? model.fontSize * 1.12
                : model.fontSize
            let isQuote = fmt == "quote", isCode = fmt == "codeblock"
            let isHeading = fmt == "h1" || fmt == "h2" || fmt == "h3"
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.beginEdit(id) }
                HStack(spacing: 8) {
                    if isQuote {
                        Rectangle().fill(Color.rzAccent.opacity(0.4)).frame(width: 3)
                            .allowsHitTesting(false)
                    }
                    Text(RichText.attributed(raw, doc: model.doc))
                        // fixed size (matching the editor) unless the user opts into Dynamic Type
                        .font(isCode ? .system(size: model.fontSize, design: .monospaced)
                              : (model.scaleWithSystem ? .rz(size) : .rzFixed(size)))
                        .fontWeight(isHeading ? .bold : .regular)
                        .italic(isQuote)
                        .lineSpacing(model.lineSpacing)
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? Color.rzDone : (isQuote ? Color.rzInkSoft : Color.rzInk))
                        .allowsHitTesting(hasLinks)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(isCode ? 6 : 0)
                        .background(isCode ? Color.rzInkFaint.opacity(0.1) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity, minHeight: lineH, alignment: .leading)   // stay tappable when empty
        }
    }

    var body: some View {
        _ = model.accent   // re-render this row live when the accent changes
        // The bullet must stay vertically centred on the first text line at ANY font size, so it
        // shares the line's height (the text box's height) and is centred within it — a fixed
        // height drifts off-centre as the font grows/shrinks.
        let lineH = RichEditor.font().lineHeight
        // .top: align the bullet with the first line of a possibly-wrapped row, and let the
        // rich editor (a UITextView) sit right next to it.
        return HStack(alignment: .top, spacing: 8) {
            if isTodo {
                // a to-do renders a checkbox in place of the bullet; tapping it completes the item
                Button { model.toggleDone(id) } label: {
                    Image(systemName: isDone ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isDone ? Color.rzAccent : Color.rzInkFaint)
                        .frame(width: 14, height: lineH, alignment: .center)
                }
                .buttonStyle(.plain)
            } else if isNumbered {
                Button {
                    if hasChildren { model.toggleCollapse(id) }
                } label: {
                    Text("\(model.numberedIndex(of: id) ?? 1).")
                        .font(.rzFixed(model.fontSize))
                        .foregroundStyle(Color.rzInkFaint)
                        .frame(minWidth: 16, minHeight: lineH, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .disabled(!hasChildren)
            } else {
                Button {
                    if hasChildren { model.toggleCollapse(id) }
                } label: {
                    Image(systemName: hasChildren ? (isCollapsed ? "chevron.right" : "chevron.down") : "circle.fill")
                        .font(.system(size: hasChildren ? 11 : 5, weight: .semibold))
                        .foregroundStyle(Color.rzInkFaint)
                        .frame(width: 14, height: lineH, alignment: .center)
                }
                .buttonStyle(.plain)
                .disabled(!hasChildren)
            }

            VStack(alignment: .leading, spacing: 6) {
                let raw = node?.text ?? ""
                if model.editingID == id {
                    // editing shows the text (the image's file name) INSTEAD of the picture, so you
                    // can rename it, place the cursor, and press Return for a new line beneath it
                    RichTextEditor(model: model, id: id, source: model.editText)
                        .frame(maxWidth: .infinity, minHeight: lineH, alignment: .leading)
                } else if hasFiles {
                    attachments   // tap → edit (reveals the file name); long-press → full screen
                } else {
                    textDisplay(raw, lineH)
                }
                if model.uploadingNodes.contains(id) {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Uploading…").font(.rz(13)).foregroundStyle(Color.rzInkFaint)
                    }
                    .frame(maxWidth: .infinity, minHeight: lineH, alignment: .leading)
                }
                if let c = model.linkedCoords(in: node?.text ?? "") {
                    GeoMapView(lat: c.lat, lon: c.lon)   // mini-map under a bullet referencing a place
                }
            }
        }
        .fullScreenCover(item: $viewer) { v in ImageViewer(url: v.url) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { model.toggleDone(id) } label: {
                Label("Done", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { model.delete(id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Keyboard accessory for the rich editor, added as a SwiftUI `.safeAreaInset(.bottom)` so it
/// floats above the keyboard and — unlike a UIHostingController hosted as inputAccessoryView —
/// its buttons actually receive taps. Only present while editing. While a `[[` / `((` trigger
/// is open it shows the autocomplete chips, otherwise the indent / done / geo controls.
struct KeyboardAccessory: View {
    let model: AppModel
    @State private var showSourceDialog = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showAssetPicker = false
    @State private var attachTarget: String?   // node to attach to, captured before the picker steals focus
    @State private var showLinkAlert = false
    @State private var linkText = ""

    // The picker/dialog modifiers live here (always in the tree), NOT on `bar` — presenting a
    // picker resigns the editor, which can clear editingID and remove `bar`; if the presenters
    // hung off `bar` they'd be torn down mid-present.
    var body: some View {
        Group {
            if model.editingID != nil { bar }
        }
        .confirmationDialog("Add image", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            Button("Choose from Library") { showLibrary = true }
            Button("From uploaded files") { showAssetPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAssetPicker) {
            AssetPickerSheet { asset in if let id = attachTarget { model.attachAsset(asset, to: id) } }
        }
        .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            let target = attachTarget
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    attach(img, to: target)
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in attach(image, to: attachTarget) }
                .ignoresSafeArea()
        }
        .alert("Add link", isPresented: $showLinkAlert) {
            TextField("https://…", text: $linkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Link") { model.editorLink?(linkText); model.suppressBlur = false }
            Button("Cancel", role: .cancel) { model.suppressBlur = false }
        } message: {
            Text("Link the selected text to a URL.")
        }
    }

    private var editingFormat: String? { model.editingID.flatMap { model.doc?.nodes[$0]?.format } }

    private func attach(_ image: UIImage, to id: String?) {
        guard let id else { return }
        let scaled = scaledDown(image, percent: model.imageScalePercent)
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Photo \(f.string(from: Date())).jpg"
        Task { await model.attachFile(data, name: name, contentType: "image/jpeg", to: id) }
    }

    private func scaledDown(_ image: UIImage, percent: Double) -> UIImage {
        let s = percent / 100
        guard s > 0, s < 1 else { return image }
        let size = CGSize(width: image.size.width * s, height: image.size.height * s)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// A filled circle in the highlight's colour (composited over white → its on-paper pastel),
    /// as an original-rendering image so the menu shows it in colour.
    private func hlSwatch(_ h: Highlight) -> Image {
        let c = h.rgba, a = c.3
        let color = UIColor(red: c.0 * a + (1 - a), green: c.1 * a + (1 - a), blue: c.2 * a + (1 - a), alpha: 1)
        let img = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 16, height: 16)).fill()
        }
        return Image(uiImage: img.withRenderingMode(.alwaysOriginal))
    }

    private var bar: some View {
        HStack(spacing: 14) {
            if !model.slashCommands.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.slashCommands) { c in
                            Button { model.runSlashCommand(c) } label: {
                                Label(c.label, systemImage: c.icon)
                                    .lineLimit(1)
                                    .font(.rz(15))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.rzAccent.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.rzAccent)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else if !model.linkSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.linkSuggestions) { s in
                            Button { model.acceptLinkSuggestion(s) } label: {
                                Label(
                                    s.isCreate ? "Create “\(s.title)”" : s.title,
                                    systemImage: s.isCreate ? "plus.circle"
                                        : (model.linkSuggestKind == .block ? "text.quote" : "link")
                                )
                                .lineLimit(1)
                                .font(.rz(15))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.rzAccent.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.rzAccent)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(model.editorTools) { tool in toolButton(tool) }
                    }
                }
                Spacer(minLength: 8)
                Button("Done") { model.endEditing() }.fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(.regularMaterial)
        .tint(.rzAccent)
    }

    /// One editor-toolbar control; menus for the colour pickers, an alert for the link URL,
    /// the image source dialog, everything else a direct action.
    @ViewBuilder
    private func toolButton(_ tool: EditorTool) -> some View {
        switch tool {
        case .highlight:
            Menu {
                ForEach(Highlight.allCases) { h in
                    Button { model.editorHighlight?(h.rawValue) } label: { Label { Text(h.rawValue.capitalized) } icon: { hlSwatch(h) } }
                }
                Button("None", role: .destructive) { model.editorHighlight?("") }
            } label: { Image(systemName: tool.icon) }
        case .textColor:
            Menu {
                ForEach(TextColor.allCases) { c in
                    Button { model.editorTextColor?(c.rawValue) } label: { Label { Text(c.rawValue.capitalized) } icon: { tcSwatch(c) } }
                }
                Button("None", role: .destructive) { model.editorTextColor?("") }
            } label: { Image(systemName: tool.icon) }
        case .image:
            Button { attachTarget = model.editingID; showSourceDialog = true } label: { Image(systemName: tool.icon) }
        case .link:
            Button { model.suppressBlur = true; linkText = ""; showLinkAlert = true } label: { Image(systemName: tool.icon) }
        case .geo:
            Button { Task { await model.insertGeoLink() } } label: {
                Image(systemName: model.locating ? "location.fill" : "location").foregroundStyle(Color.rzAccent)
            }
        case .todo:
            Button { runTool(tool) } label: {
                Image(systemName: editingFormat == "todo" ? "checkmark.circle.fill" : "checkmark.circle")
            }
        default:
            Button { runTool(tool) } label: { Image(systemName: tool.icon) }
        }
    }

    private func runTool(_ tool: EditorTool) {
        guard let id = model.editingID else { return }
        switch tool {
        case .outdent: model.outdent(id)
        case .indent: model.indent(id)
        case .moveUp: model.moveUp(id)
        case .moveDown: model.moveDown(id)
        case .bold: model.editorInline?("b")
        case .italic: model.editorInline?("i")
        case .strikethrough: model.editorInline?("s")
        case .code: model.editorInline?("c")
        case .todo: model.toggleTodo(id)
        case .numbered: model.setFormat(id, "number")
        case .bulletReset: model.setFormat(id, nil)
        default: break
        }
    }

    /// A filled dot in a text colour, for the colour menu.
    private func tcSwatch(_ c: TextColor) -> Image {
        let s = c.srgb.light
        let color = UIColor(red: s.0, green: s.1, blue: s.2, alpha: 1)
        let img = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 16, height: 16)).fill()
        }
        return Image(uiImage: img.withRenderingMode(.alwaysOriginal))
    }
}

/// A thin wrapper around `UIImagePickerController` for taking a photo with the camera
/// (SwiftUI has no native camera capture).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
