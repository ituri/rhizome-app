import SwiftUI
import RhizomeKit

/// A backlink row: the referencing node's text + a breadcrumb, tapping opens it
/// in context.
struct ReferenceRow: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        NavigationLink(value: model.parentOf(id) ?? id) {
            VStack(alignment: .leading, spacing: 3) {
                Text(RichText.attributed(model.doc?.nodes[id]?.text ?? "", doc: model.doc))
                    .font(.rz(16))
                    .lineLimit(3)
                let trail = model.breadcrumb(of: id)
                if !trail.isEmpty {
                    Text(trail)
                        .font(.rz(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Color.rzPaper)
    }
}

/// Section header for the reference groups.
struct ReferenceHeader: View {
    let title: String
    let count: Int
    var body: some View {
        Text("\(title) · \(count)")
            .font(.rz(14, .semibold))
            .foregroundStyle(Color.rzInk)
            .textCase(nil)
    }
}
