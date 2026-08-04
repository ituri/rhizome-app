import SwiftUI
import RhizomeKit

/// Daily notes, most recent day first (future days hidden, like the web app).
/// Each day is a section of its (editable) notes; the + quick-captures into today.
struct JournalView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCapture = false
    @State private var captureText = ""
    @State private var showingSettings = false
    @State private var path: [String] = []

    private var days: [JournalDay] {
        let now = Date()
        return model.journalDays.filter { $0.date <= now }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let doc = model.doc {
                    let days = self.days
                    if days.isEmpty {
                        ContentUnavailableView(
                            "No daily notes yet",
                            systemImage: "calendar",
                            description: Text("Tap + to capture your first note into today.")
                        )
                    } else {
                        List {
                            ForEach(days) { day in
                                Section {
                                    ForEach(visibleRows(doc, from: day.id)) { row in
                                        OutlineRow(id: row.id, node: doc.nodes[row.id])
                                            .listRowInsets(rzRowInsets(depth: row.depth, skin: model.skin))
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.rzPaper)
                                    }
                                    // NB: no Linked/Unlinked References here. `Section`'s builder is
                                    // eager, so rendering them meant two full passes over doc.nodes
                                    // for EVERY day in the stream on every doc mutation — i.e. after
                                    // every debounced keystroke, which is what made typing lag.
                                    // The web shows backlinks only on the zoomed page, so the day's
                                    // own page view (tap the date) is where they belong.
                                } header: {
                                    // tapping the date opens the full-page view of that day
                                    NavigationLink(value: day.id) {
                                        Text(day.title)
                                            .font(.rzTitle(model.fontSize))   // web .day-title
                                            .foregroundStyle(Color.rzInk)
                                            .textCase(nil)
                                            .padding(.top, model.skin.sectionGap)
                                            .padding(.bottom, model.skin.titleGap)
                                    }
                                    .buttonStyle(.plain)
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
            .navigationDestination(for: String.self) { PageView(pageID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { GraphSwitcher() }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingCapture = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) { SyncIndicator() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
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
            .onAppear { model.ensureToday() }   // create today's day when entering the journal
            .refreshable { await model.loadDoc() }
            .safeAreaInset(edge: .bottom, spacing: 0) { KeyboardAccessory(model: model) }
            .geoAlert(model)
        .noticeAlert(model)
        }
        .handleNodeLinks(path: $path, model: model)
    }

}
