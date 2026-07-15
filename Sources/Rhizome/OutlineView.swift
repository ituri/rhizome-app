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
        @Bindable var model = model
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
                TextField("", text: $model.editBuffer)
                    .focused($focused, equals: id)
                    .submitLabel(.next)
                    .onSubmit {
                        model.commitEdit()
                        if let next = model.insertSibling(after: id) {
                            model.beginEdit(next)
                            focused = next
                        }
                    }
            } else {
                Text(RichText.attributed(node?.text ?? "", doc: model.doc))
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

/// Keyboard accessory shared by both editing lists: indent / outdent / done / dismiss.
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
            Button("Done") { model.commitEdit(); focused = nil }
        }
    }
}

/// The Outline tab: the whole graph as an indented, editable list.
struct OutlineView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: String?

    var body: some View {
        NavigationStack {
            Group {
                if let doc = model.doc {
                    List(visibleRows(doc)) { row in
                        OutlineRow(id: row.id, node: doc.nodes[row.id], focused: $focused)
                            .listRowInsets(EdgeInsets(
                                top: 3, leading: CGFloat(row.depth) * 16 + 12, bottom: 3, trailing: 12
                            ))
                    }
                    .listStyle(.plain)
                } else if model.busy {
                    ProgressView()
                } else {
                    ContentUnavailableView("No outline", systemImage: "leaf")
                }
            }
            .navigationTitle(model.activeGraph?.name ?? "Rhizome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { GraphSwitcher() }
                ToolbarItem(placement: .topBarTrailing) { AccountMenu() }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        if let doc = model.doc, let new = model.insertChild(of: doc.root) {
                            model.beginEdit(new); focused = new
                        }
                    } label: {
                        Label("New item", systemImage: "plus.circle.fill")
                    }
                }
                EditingKeyboardBar(focused: $focused)
            }
            .onChange(of: focused) { _, new in if new == nil { model.commitEdit() } }
            .refreshable { await model.loadDoc() }
        }
    }
}
