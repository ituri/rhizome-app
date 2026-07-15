import SwiftUI
import RhizomeKit

/// Daily notes, most recent day first — the native counterpart to the web app's
/// journal. Each day is a section of its (editable) notes.
struct JournalView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: String?

    var body: some View {
        NavigationStack {
            Group {
                if let doc = model.doc {
                    let days = Journal.days(doc)
                    if days.isEmpty {
                        ContentUnavailableView(
                            "No daily notes yet",
                            systemImage: "calendar",
                            description: Text("Capture something with the share sheet or the `r` command, then pull to refresh.")
                        )
                    } else {
                        List {
                            ForEach(days) { day in
                                Section(day.title) {
                                    ForEach(visibleRows(doc, from: day.id)) { row in
                                        OutlineRow(id: row.id, node: doc.nodes[row.id], focused: $focused)
                                            .listRowInsets(EdgeInsets(
                                                top: 3, leading: CGFloat(row.depth) * 16 + 12, bottom: 3, trailing: 12
                                            ))
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                } else if model.busy {
                    ProgressView()
                } else {
                    ContentUnavailableView("No journal", systemImage: "calendar")
                }
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { GraphSwitcher() }
                ToolbarItem(placement: .topBarTrailing) { AccountMenu() }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        if let today = model.doc.map(Journal.days)?.first,
                           let new = model.insertChild(of: today.id) {
                            model.beginEdit(new); focused = new
                        }
                    } label: {
                        Label("New note", systemImage: "plus.circle.fill")
                    }
                    .disabled(model.doc.map(Journal.days)?.isEmpty ?? true)
                }
                EditingKeyboardBar(focused: $focused)
            }
            .onChange(of: focused) { _, new in if new == nil { model.commitEdit() } }
            .refreshable { await model.loadDoc() }
        }
    }
}
