import SwiftUI
import RhizomeKit

/// A backlink row, styled like the web `.ref-row`: a left accent line, muted text,
/// a breadcrumb; tapping opens it in context.
struct ReferenceRow: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        NavigationLink(value: model.parentOf(id) ?? id) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.rzLine)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(RichText.attributed(model.doc?.nodes[id]?.text ?? "", doc: model.doc))
                        .font(.rz(15))
                        .foregroundStyle(Color.rzInkSoft)
                        .lineLimit(3)
                    let trail = model.breadcrumb(of: id)
                    if !trail.isEmpty {
                        Text(trail)
                            .font(.rz(11.5))
                            .foregroundStyle(Color.rzInkFaint)
                            .lineLimit(1)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Color.rzPaper)
    }
}

/// Section header for the reference groups (web `.ref-page`: accent, semibold).
struct ReferenceHeader: View {
    let title: String
    let count: Int
    var body: some View {
        Text("\(title) · \(count)")
            .font(.rz(13.5, .semibold))
            .foregroundStyle(Color.rzAccent)
            .textCase(nil)
    }
}
