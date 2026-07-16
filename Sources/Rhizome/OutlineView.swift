import SwiftUI
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

    private var hasChildren: Bool { !(node?.children?.isEmpty ?? true) }
    private var isCollapsed: Bool { node?.collapsed ?? false }
    private var isDone: Bool { node?.done ?? false }

    var body: some View {
        // .top: align the bullet with the first line of a possibly-wrapped row, and let the
        // rich editor (a UITextView) sit right next to it.
        HStack(alignment: .top, spacing: 8) {
            Button {
                if hasChildren { model.toggleCollapse(id) }
            } label: {
                Image(systemName: hasChildren ? (isCollapsed ? "chevron.right" : "chevron.down") : "circle.fill")
                    .font(.system(size: hasChildren ? 11 : 5, weight: .semibold))
                    .foregroundStyle(Color.rzInkFaint)
                    .frame(width: 14, height: 26, alignment: .center)
            }
            .buttonStyle(.plain)
            .disabled(!hasChildren)

            if model.editingID == id {
                // rich inline editor: links/refs/tags render as they do when displayed, long
                // lines wrap, Return makes a new bullet, and [[ / (( autocomplete at the caret
                RichTextEditor(model: model, id: id, source: model.editText)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            } else {
                // An edit-tap layer BEHIND the text, so tapping anywhere starts editing — while
                // links/refs in the text (in front) still take their own taps to navigate. A
                // Text with links otherwise swallows taps, leaving linked bullets uneditable.
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { model.beginEdit(id) }
                    Text(RichText.attributed(node?.text ?? "", doc: model.doc))
                        .font(.rz(16.5))
                        .lineSpacing(3)
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? Color.rzDone : Color.rzInk)
                }
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading) // stay tappable when empty
            }
        }
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

/// Keyboard accessory for the rich editor, hosted as the UITextView's `inputAccessoryView`
/// (a SwiftUI `.toolbar(.keyboard)` does NOT attach to a UIKit first responder, so it would
/// otherwise vanish). While a `[[` / `((` trigger is open it shows the autocomplete chips,
/// otherwise the indent / outdent / done / dismiss controls.
struct KeyboardAccessory: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            if !model.linkSuggestions.isEmpty {
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
                Button { if let id = model.editingID { model.outdent(id) } } label: {
                    Image(systemName: "arrow.left.to.line")
                }
                Button { if let id = model.editingID { model.indent(id) } } label: {
                    Image(systemName: "arrow.right.to.line")
                }
                Button { if let id = model.editingID { model.toggleDone(id) } } label: {
                    Image(systemName: "checkmark.circle")
                }
                Button { Task { await model.insertGeoLink() } } label: {
                    if model.locating {
                        ProgressView().controlSize(.small)   // shows it's working (a fix can take a few seconds)
                    } else {
                        Image(systemName: "location")
                    }
                }
                .disabled(model.locating)
                Spacer()
                Button("Done") { model.endEditing() }.fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(.regularMaterial)
        .tint(.rzAccent)
    }
}
