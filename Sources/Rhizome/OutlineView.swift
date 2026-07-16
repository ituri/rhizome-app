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
    @FocusState.Binding var focused: String?

    private var hasChildren: Bool { !(node?.children?.isEmpty ?? true) }
    private var isCollapsed: Bool { node?.collapsed ?? false }
    private var isDone: Bool { node?.done ?? false }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                if hasChildren { model.toggleCollapse(id) }
            } label: {
                Image(systemName: hasChildren ? (isCollapsed ? "chevron.right" : "chevron.down") : "circle.fill")
                    .font(.system(size: hasChildren ? 11 : 5, weight: .semibold))
                    .foregroundStyle(Color.rzInkFaint)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .disabled(!hasChildren)

            if model.editingID == id {
                // axis: .vertical lets a long line WRAP while typing instead of scrolling off
                // the edge. The trade-off is that Return now inserts a newline rather than
                // submitting, so we watch for a newline and turn it into "finish this bullet,
                // start the next" — the same behaviour the single-line field had via onSubmit.
                TextField("", text: model.editBinding, axis: .vertical)
                    .font(.rz(16.5))
                    .autocorrectionDisabled()               // stop iOS silently changing words (Sync → Synck)
                    .textInputAutocapitalization(.sentences)
                    .focused($focused, equals: id)
                    .onChange(of: model.editText) { _, value in
                        guard model.editingID == id, value.contains("\n") else { return }
                        model.editText = value.replacingOccurrences(of: "\n", with: "") // Return, not a literal newline
                        if let next = model.returnKey(on: id) {
                            // let the List render the new row before we focus it
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                focused = next
                                model.focusSettled()
                            }
                        } else {
                            focused = nil
                        }
                    }
            } else {
                Text(RichText.attributed(node?.text ?? "", doc: model.doc))
                    .font(.rz(16.5))
                    .lineSpacing(3)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Color.rzDone : Color.rzInk)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading) // stay tappable when empty
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.beginEdit(id)
                        focused = id
                    }
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

/// Keyboard accessory shared by the editing lists: indent / outdent / done / dismiss.
struct EditingKeyboardBar: ToolbarContent {
    @Environment(AppModel.self) private var model
    @FocusState.Binding var focused: String?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button { if let id = model.editingID { model.outdent(id) } } label: {
                Image(systemName: "arrow.left.to.line")
            }
            Button { if let id = model.editingID { model.indent(id) } } label: {
                Image(systemName: "arrow.right.to.line")
            }
            Button { if let id = model.editingID { model.toggleDone(id) } } label: {
                Image(systemName: "checkmark.circle")
            }
            Spacer()
            Button("Done") { focused = nil }
        }
    }
}

/// The `[[` (page) / `((` (block) autocomplete strip, shown above the keyboard while a
/// trigger is active — the mobile counterpart to the desktop's caret popup. Tapping a
/// chip inserts the link (or creates the page) via `AppModel.acceptLinkSuggestion`.
struct LinkSuggestionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.linkSuggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.linkSuggestions) { s in
                        Button { model.acceptLinkSuggestion(s) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: s.isCreate ? "plus.circle"
                                    : (model.linkSuggestKind == .block ? "text.quote" : "link"))
                                    .font(.system(size: 12))
                                Text(s.isCreate ? "Create “\(s.title)”" : s.title)
                                    .lineLimit(1)
                                    .font(.rz(15))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.rzAccent.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.rzAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
