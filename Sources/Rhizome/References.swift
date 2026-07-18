import SwiftUI
import RhizomeKit

/// References grouped by their containing page.
struct RefGroup: Identifiable {
    let pageID: String
    var id: String { pageID }
    let pageName: String
    let refs: [String]
}

/// A backlink row — only the quote sits in a barely-there warm tint box (web
/// `.ref-row`: accent 5%, rounded, indented). Tapping opens it in context.
struct ReferenceRow: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        NavigationLink(value: model.parentOf(id) ?? id) {
            Text(RichText.attributed(model.doc?.nodes[id]?.text ?? "", doc: model.doc))
                .font(.rz(15))
                .foregroundStyle(Color.rzInk)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.rzTint, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.rzPaper)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 22, bottom: 4, trailing: 14))
    }
}

/// The muted section label ("Linked / Unlinked References") — web h3 (#8a9ba8).
struct ReferenceHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.rz(13, .bold))
            .foregroundStyle(Color.rzRefHead)
            .textCase(nil)
    }
}

/// A blue page-name heading grouping references (web `.ref-page`, #106ba3).
struct RefPageName: View {
    let name: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.rz(9))
                .foregroundStyle(Color.rzInkFaint)
            Text(name.isEmpty ? "Untitled" : name)
                .font(.rz(15, .semibold))
                .foregroundStyle(Color.rzRefPage)
        }
    }
}

/// Renders the grouped Linked / Unlinked reference rows for a page, as list rows.
@MainActor @ViewBuilder
func referenceListContent(pageID: String, model: AppModel) -> some View {
    let linked = model.linkedRefGroups(to: pageID)
    let unlinked = model.unlinkedRefGroups(to: pageID)

    if !linked.isEmpty {
        ReferenceHeader(title: "Linked References").refLabelRow(top: 18)
        ForEach(linked) { group in
            RefPageName(name: group.pageName).refLabelRow(top: 8)
            ForEach(group.refs, id: \.self) { ReferenceRow(id: $0) }
        }
    }
    if !unlinked.isEmpty {
        ReferenceHeader(title: "Unlinked References").refLabelRow(top: 18)
        ForEach(unlinked) { group in
            RefPageName(name: group.pageName).refLabelRow(top: 8)
            ForEach(group.refs, id: \.self) { ReferenceRow(id: $0) }
        }
    }
}

private extension View {
    /// Reference labels sit on plain paper (only the quote boxes are tinted).
    func refLabelRow(top: CGFloat) -> some View {
        self.listRowSeparator(.hidden)
            .listRowBackground(Color.rzPaper)
            .listRowInsets(EdgeInsets(top: top, leading: 14, bottom: 2, trailing: 14))
    }
}
