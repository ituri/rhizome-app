import SwiftUI
import RhizomeKit

/// One flattened, visible outline row (a node plus its indentation depth).
struct OutlineRowItem: Identifiable {
    let id: String
    let depth: Int
}

/// Depth-first flatten of the visible tree (respecting collapsed nodes).
func visibleRows(_ doc: RDoc) -> [OutlineRowItem] {
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
    addChildren(of: doc.root, depth: 0)
    return rows
}

/// The native outline: a flat List of indented rows, rebuilt from the tree.
struct OutlineView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let doc = model.doc {
                    List(visibleRows(doc)) { row in
                        OutlineRow(id: row.id, node: doc.nodes[row.id])
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
            .toolbar { toolbar }
            .refreshable { await model.loadDoc() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.graphs.count > 1 {
                Menu {
                    ForEach(model.graphs) { graph in
                        Button {
                            Task { await model.selectGraph(graph.id) }
                        } label: {
                            Label(graph.name, systemImage: graph.id == model.activeGraphID ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "square.stack.3d.up")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let user = model.user {
                    Text("Signed in as \(user.username)")
                }
                Button("Reload", systemImage: "arrow.clockwise") {
                    Task { await model.loadDoc() }
                }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await model.signOut() }
                }
            } label: {
                Image(systemName: "person.crop.circle")
            }
        }
    }
}

/// A single outline row: collapse control / bullet + the node's text.
private struct OutlineRow: View {
    @Environment(AppModel.self) private var model
    let id: String
    let node: RNode?

    private var hasChildren: Bool { !(node?.children?.isEmpty ?? true) }
    private var isCollapsed: Bool { node?.collapsed ?? false }
    private var isDone: Bool { node?.done ?? false }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                if hasChildren { model.toggleCollapse(id) }
            } label: {
                if hasChildren {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                } else {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                }
            }
            .buttonStyle(.plain)
            .disabled(!hasChildren)

            Text(node?.text ?? "")
                .strikethrough(isDone)
                .foregroundStyle(isDone ? .secondary : .primary)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
