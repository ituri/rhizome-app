import SwiftUI
import RhizomeKit

/// Daily notes, most recent day first (future days hidden, like the web app).
/// Each day is a section of its (editable) notes; the + quick-captures into today.
struct JournalView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: String?
    @State private var showingCapture = false
    @State private var captureText = ""
    @State private var showingSettings = false

    private func days(_ doc: RDoc) -> [JournalDay] {
        let now = Date()
        return Journal.days(doc).filter { $0.date <= now }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let doc = model.doc {
                    let days = days(doc)
                    if days.isEmpty {
                        ContentUnavailableView(
                            "No daily notes yet",
                            systemImage: "calendar",
                            description: Text("Tap + to capture your first note into today.")
                        )
                    } else {
                        List {
                            ForEach(days) { day in
                                Section(day.title) {
                                    ForEach(visibleRows(doc, from: day.id)) { row in
                                        OutlineRow(id: row.id, node: doc.nodes[row.id], focused: $focused)
                                            .listRowInsets(EdgeInsets(
                                                top: 2, leading: CGFloat(row.depth) * 16 + 12, bottom: 2, trailing: 12
                                            ))
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.rzPaper)
                                    }
                                }
                            }
                        }
                        .outlineList()
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingCapture = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) { SyncIndicator() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
                EditingKeyboardBar(focused: $focused)
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .alert("Capture to today", isPresented: $showingCapture) {
                TextField("Note", text: $captureText)
                Button("Add") {
                    let text = captureText; captureText = ""
                    Task { await model.captureToday(text) }
                }
                Button("Cancel", role: .cancel) { captureText = "" }
            }
            .onChange(of: focused) { _, new in if new == nil { model.blurred() } }
            .refreshable { await model.loadDoc() }
        }
    }
}
