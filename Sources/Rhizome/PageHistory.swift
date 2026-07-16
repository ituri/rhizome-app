import SwiftUI
import RhizomeKit

/// Version history for a page (top-level page or journal day): list of snapshots with time +
/// device, an inline diff against the previous version, and restore.
struct PageHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pageID: String
    @State private var versions: [RHistoryVersion] = []
    @State private var loading = true
    @State private var confirmRestore: RHistoryVersion?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if versions.isEmpty {
                    ContentUnavailableView("No versions yet", systemImage: "clock.arrow.circlepath",
                        description: Text("Snapshots are saved a little after you edit a page."))
                } else {
                    List {
                        ForEach(Array(versions.enumerated()), id: \.element.id) { i, v in
                            VersionRow(pageID: pageID, version: v, previous: i + 1 < versions.count ? versions[i + 1] : nil,
                                       onRestore: { confirmRestore = v })
                        }
                    }
                    .listStyle(.plain)
                    .paperBackground()
                }
            }
            .navigationTitle("Page history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { versions = await model.historyVersions(pageID); loading = false }
            .confirmationDialog(
                "Restore this version? The current content is replaced (a new version is saved, so this is undoable).",
                isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } }),
                titleVisibility: .visible,
                presenting: confirmRestore
            ) { v in
                Button("Restore", role: .destructive) {
                    Task { await model.restorePage(pageID, versionID: v.id); dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

private struct VersionRow: View {
    @Environment(AppModel.self) private var model
    let pageID: String
    let version: RHistoryVersion
    let previous: RHistoryVersion?
    let onRestore: () -> Void
    @State private var showDiff = false
    @State private var lines: [DiffLine]?
    @State private var loadingDiff = false

    private var when: String { Date(timeIntervalSince1970: version.ts / 1000).formatted(date: .abbreviated, time: .shortened) }
    private var device: String { (version.device?.isEmpty == false) ? version.device! : "unknown device" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(when).font(.rz(14)).foregroundStyle(Color.rzInk)
                    Text(device).font(.rz(12)).foregroundStyle(Color.rzInkFaint)
                }
                Spacer()
                Button(showDiff ? "Hide" : "Diff") { toggle() }
                    .font(.rz(13)).buttonStyle(.bordered).tint(.secondary)
                Button("Restore", action: onRestore)
                    .font(.rz(13)).buttonStyle(.borderedProminent)
            }
            if showDiff {
                if loadingDiff {
                    ProgressView().padding(.vertical, 4)
                } else if let lines {
                    DiffLinesView(lines: lines)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.rzPaper)
    }

    private func toggle() {
        showDiff.toggle()
        guard showDiff, lines == nil, !loadingDiff else { return }
        loadingDiff = true
        Task {
            let newDoc = await model.historyDoc(pageID, version.id)
            var oldDoc: RDoc?
            if let prev = previous { oldDoc = await model.historyDoc(pageID, prev.id) }
            lines = HistoryDiff.compute(old: oldDoc, new: newDoc)
            loadingDiff = false
        }
    }
}

struct DiffLine: Identifiable {
    let id = UUID()
    let kind: Kind
    let text: String
    enum Kind { case added, removed, note }
}

/// Diff two page snapshots by node: added / removed / changed bullets, plus structure-only notes.
enum HistoryDiff {
    static func compute(old: RDoc?, new: RDoc?) -> [DiffLine] {
        let oldN = old?.nodes ?? [:], newN = new?.nodes ?? [:]
        var out: [DiffLine] = []
        var notes: [String] = []
        func note(_ s: String) { if !notes.contains(s) { notes.append(s) } }

        for (id, nn) in newN {
            let nt = RichText.plain(nn.text ?? "", doc: new).trimmingCharacters(in: .whitespaces)
            guard let on = oldN[id] else {
                if nt.isEmpty { note("Added an empty bullet") } else { out.append(DiffLine(kind: .added, text: nt)) }
                continue
            }
            let ot = RichText.plain(on.text ?? "", doc: old).trimmingCharacters(in: .whitespaces)
            if ot != nt {
                out.append(DiffLine(kind: .removed, text: ot))
                out.append(DiffLine(kind: .added, text: nt))
            } else {
                if (on.text ?? "") != (nn.text ?? "") { note("Changed text formatting") }
                if (on.done ?? false) != (nn.done ?? false) { note(nn.done ?? false ? "Marked a bullet done" : "Un-marked a bullet") }
                if (on.collapsed ?? false) != (nn.collapsed ?? false) { note(nn.collapsed ?? false ? "Collapsed a bullet" : "Expanded a bullet") }
                if (on.note ?? "") != (nn.note ?? "") { note("Edited a note") }
                if (on.children ?? []) != (nn.children ?? []) { note("Moved / reordered bullets") }
            }
        }
        for (id, on) in oldN where newN[id] == nil {
            let ot = RichText.plain(on.text ?? "", doc: old).trimmingCharacters(in: .whitespaces)
            if ot.isEmpty { note("Removed an empty bullet") } else { out.append(DiffLine(kind: .removed, text: ot)) }
        }
        out.append(contentsOf: notes.map { DiffLine(kind: .note, text: $0) })
        return out
    }
}

private struct DiffLinesView: View {
    let lines: [DiffLine]

    var body: some View {
        if lines.isEmpty {
            Text("No changes in this version.").font(.rz(12)).foregroundStyle(Color.rzInkFaint)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines) { l in
                    Text(prefix(l) + l.text)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(l.kind == .removed ? Color.rzInkFaint : Color.rzInk)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(l), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    private func prefix(_ l: DiffLine) -> String {
        switch l.kind { case .added: "+ "; case .removed: "− "; case .note: "• " }
    }
    private func background(_ l: DiffLine) -> Color {
        switch l.kind {
        case .added: Color.green.opacity(0.15)
        case .removed: Color.red.opacity(0.12)
        case .note: Color.clear
        }
    }
}
