import SwiftUI
import RhizomeKit

/// Roam's `{{table}}`, web parity: a bullet whose text contains `{{table}}` renders its
/// children as a table beneath the row. Children are rows, nesting levels are columns; a
/// branching parent visually spans its children ("rowspan") because the layout mirrors the
/// tree — a cell sits beside the stack of its children. Wide tables scroll horizontally,
/// like the web's `overflow-x: auto`. The source bullets stay in the outline below
/// (collapse the bullet to see just the table).
struct TableBlockView: View {
    let rootID: String
    @Environment(AppModel.self) private var model

    static let colWidth: CGFloat = 150

    var body: some View {
        let kids = model.doc?.nodes[rootID]?.children ?? []
        if kids.isEmpty {
            Text("Add child bullets: each child is a row, each nesting level a column.")
                .font(.rz(13))
                .foregroundStyle(Color.rzInkFaint)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(kids, id: \.self) { TableNodeView(id: $0) }
                }
                .border(Color.rzLine, width: 0.5)   // outer frame closes the hairline grid
            }
            .padding(.vertical, 4)
        }
    }
}

/// One tree node as `[cell | stack of child rows]` — the recursive shape IS the rowspan.
private struct TableNodeView: View {
    let id: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let node = model.doc?.nodes[id]
        let kids = node?.children ?? []
        HStack(alignment: .top, spacing: 0) {
            Text(RichText.attributed(node?.text ?? "", doc: model.doc, size: model.fontSize))
                .font(.rzFixed(model.fontSize))
                .foregroundStyle(Color.rzInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(width: TableBlockView.colWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)   // span the child rows
                .border(Color.rzLine, width: 0.5)
            if !kids.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(kids, id: \.self) { TableNodeView(id: $0) }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
