import SwiftUI
import RhizomeKit

/// References grouped by their containing page.
struct RefGroup: Identifiable {
    let pageID: String
    var id: String { pageID }
    let pageName: String
    let refs: [String]
}

/// A backlink row: the referencing text + a breadcrumb, flat on the references'
/// light-orange background (no border) — tapping opens it in context.
struct ReferenceRow: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        NavigationLink(value: model.parentOf(id) ?? id) {
            VStack(alignment: .leading, spacing: 3) {
                Text(RichText.attributed(model.doc?.nodes[id]?.text ?? "", doc: model.doc))
                    .font(.rz(15))
                    .foregroundStyle(Color.rzInk)
                    .lineLimit(4)
                let trail = model.breadcrumb(of: id)
                if !trail.isEmpty {
                    Text(trail)
                        .font(.rz(11.5))
                        .foregroundStyle(Color.rzInkFaint)
                        .lineLimit(1)
                }
            }
        }
        .listRowBackground(Color.rzTint)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 14))
    }
}

/// The section label ("Linked / Unlinked References") — accent, small caps-ish.
struct ReferenceHeader: View {
    let title: String
    let count: Int
    var body: some View {
        Text("\(title) · \(count)")
            .font(.rz(12.5, .semibold))
            .foregroundStyle(Color.rzAccent)
            .textCase(.uppercase)
            .kerning(0.5)
    }
}

/// A blue page-name heading grouping references (web `.ref-page`, #106ba3).
struct RefPageName: View {
    let name: String
    var body: some View {
        Text(name.isEmpty ? "Untitled" : name)
            .font(.rz(15, .semibold))
            .foregroundStyle(Color.rzRefPage)
    }
}

/// Renders the grouped Linked / Unlinked reference rows for a page, as list rows.
@MainActor @ViewBuilder
func referenceListContent(pageID: String, model: AppModel) -> some View {
    let linked = model.linkedRefGroups(to: pageID)
    let unlinked = model.unlinkedRefGroups(to: pageID)

    if !linked.isEmpty {
        ReferenceHeader(title: "Linked References", count: linked.reduce(0) { $0 + $1.refs.count })
            .refLabelRow(top: 16)
        ForEach(linked) { group in
            RefPageName(name: group.pageName).refLabelRow(top: 6)
            ForEach(group.refs, id: \.self) { ReferenceRow(id: $0) }
        }
    }
    if !unlinked.isEmpty {
        ReferenceHeader(title: "Unlinked References", count: unlinked.reduce(0) { $0 + $1.refs.count })
            .refLabelRow(top: 16)
        ForEach(unlinked) { group in
            RefPageName(name: group.pageName).refLabelRow(top: 6)
            ForEach(group.refs, id: \.self) { ReferenceRow(id: $0) }
        }
    }
}

private extension View {
    /// Common list-row styling for the reference labels.
    func refLabelRow(top: CGFloat) -> some View {
        self.listRowSeparator(.hidden)
            .listRowBackground(Color.rzTint)
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: 2, trailing: 14))
    }
}
