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
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .disabled(!hasChildren)

            if model.editingID == id {
                TextField("", text: model.editBinding)
                    .focused($focused, equals: id)
                    .submitLabel(.next)
                    .onSubmit {
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
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading) // stay tappable when empty
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
