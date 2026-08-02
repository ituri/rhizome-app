import WidgetKit
import SwiftUI
import RhizomeKit

// Rhizome's palette, hardcoded (the widget shares RhizomeKit for the session, not the theme).
private let rzClay = Color(red: 0.76, green: 0.34, blue: 0.23)   // #c2563a
private let rzPaper = Color(red: 0.957, green: 0.945, blue: 0.918) // #f4f1ea
private let rzInk = Color(red: 0.20, green: 0.19, blue: 0.17)

/// Today's capture bullet + a preview of its items (newest first), from the App Group.
private func loadSnapshot() -> (bullet: String, items: [String], total: Int) {
    (AppGroup.captureBullet, AppGroup.widgetItems, AppGroup.widgetTotal)
}

struct CaptureEntry: TimelineEntry {
    let date: Date
    let bullet: String
    let items: [String]   // newest first, "<depth>\t<text>"
    let total: Int        // total entries under the bullet today
}

struct CaptureProvider: TimelineProvider {
    private func entry() -> CaptureEntry {
        let s = loadSnapshot()
        return CaptureEntry(date: .now, bullet: s.bullet, items: s.items, total: s.total)
    }
    func placeholder(in context: Context) -> CaptureEntry {
        CaptureEntry(date: .now, bullet: "Inbox", items: ["Milch kaufen", "Zahnarzt anrufen"], total: 2)
    }
    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(entry())
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<CaptureEntry>) -> Void) {
        // Each timeline refresh fetches today's items straight from the server (shared session),
        // so the widget stays current WITHOUT the app running — falling back to the App Group
        // snapshot the app last published (offline, signed out, locked keychain after reboot).
        Task {
            let e = await Self.fetchedEntry() ?? entry()
            completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(1800))))
        }
    }

    /// Today's capture-bullet items live from `/api/v1/journal/today?depth=6` — mirrors the
    /// app's refreshWidgetSnapshot() flattening ("<depth>\t<text>", newest entry first, cap 8)
    /// and republishes the snapshot so the next fallback render matches.
    private static func fetchedEntry() async -> CaptureEntry? {
        guard let base = AppGroup.serverURL, let cookie = AppGroup.sessionCookie,
              var comps = URLComponents(url: base.appendingPathComponent("api/v1/journal/today"),
                                        resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [URLQueryItem(name: "depth", value: "6")]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("rz_session=\(cookie)", forHTTPHeaderField: "Cookie")
        struct WNode: Decodable { let plain: String?; let children: [WNode]? }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let day = try? JSONDecoder().decode(WNode.self, from: data) else { return nil }

        let bullet = AppGroup.captureBullet
        let want = bullet.trimmingCharacters(in: .whitespaces).lowercased()
        guard let target = (day.children ?? []).first(where: {
            ($0.plain ?? "").trimmingCharacters(in: .whitespaces).lowercased() == want
        }) else {
            // no capture bullet under today yet → genuinely empty (not an error)
            AppGroup.setWidgetItems([]); AppGroup.setWidgetTotal(0)
            return CaptureEntry(date: .now, bullet: bullet, items: [], total: 0)
        }
        var items: [String] = []
        let entries = target.children ?? []
        let limit = 8
        func collect(_ n: WNode, _ depth: Int) {
            guard items.count < limit else { return }
            let t = (n.plain ?? "").trimmingCharacters(in: .whitespaces)
            let childDepth: Int
            if t.isEmpty { childDepth = depth } else { items.append("\(depth)\t\(t)"); childDepth = depth + 1 }
            for c in n.children ?? [] {
                if items.count >= limit { break }
                collect(c, childDepth)
            }
        }
        for entry in entries.reversed() {   // newest first
            if items.count >= limit { break }
            collect(entry, 0)
        }
        AppGroup.setWidgetItems(items)
        AppGroup.setWidgetTotal(entries.count)
        return CaptureEntry(date: .now, bullet: bullet, items: items, total: entries.count)
    }
}

// snapshot items are encoded "<depth>\t<text>"; fall back to depth 0 for plain strings
private func parseItem(_ raw: String) -> (depth: Int, text: String) {
    if let tab = raw.firstIndex(of: "\t"), let d = Int(raw[..<tab]) {
        return (min(d, 3), String(raw[raw.index(after: tab)...]))
    }
    return (0, raw)
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaptureEntry

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(rzPaper, for: .widget)
        .widgetURL(URL(string: "rhizome://capture"))   // whole widget → quick capture
    }

    // Small: the capture button (unchanged).
    private var small: some View {
        VStack(spacing: 10) {
            brand
            Spacer(minLength: 0)
            captureButton
            Spacer(minLength: 0)
        }
    }

    // the newest few items to render (already newest-first in the snapshot)
    private var shownItems: [String] { Array(entry.items.prefix(4)) }
    // older entries that fell off the bottom, counted at the entry (depth-0) level
    private var olderCount: Int {
        let shownEntries = shownItems.filter { parseItem($0).depth == 0 }.count
        return max(0, entry.total - shownEntries)
    }

    // Medium: today's newest items under the capture bullet, plus a capture affordance.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.system(size: 12)).foregroundStyle(rzClay)
                Text(entry.bullet).font(.system(size: 15, weight: .bold)).foregroundStyle(rzInk)
                Spacer()
                Image(systemName: "square.and.pencil").font(.system(size: 16, weight: .semibold)).foregroundStyle(rzClay)
            }
            if entry.items.isEmpty {
                // no items yet (or the App Group snapshot isn't available) → offer capture
                Spacer(minLength: 0)
                captureButton.frame(maxWidth: 200)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(shownItems.enumerated()), id: \.offset) { _, raw in
                    let item = parseItem(raw)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.depth == 0 ? "•" : "◦").foregroundStyle(rzClay)
                        Text(item.text).lineLimit(1).foregroundStyle(rzInk)
                    }
                    .font(.system(size: 13))
                    .padding(.leading, CGFloat(item.depth) * 12)
                }
                if olderCount > 0 {
                    Text("+\(olderCount) older")
                        .font(.system(size: 11)).foregroundStyle(rzInk.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 5) {
            Image(systemName: "leaf.fill").font(.system(size: 12))
            Text("Rhizome").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(rzClay)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureButton: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.and.pencil").font(.system(size: 26, weight: .semibold))
            Text("Capture").font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(rzClay, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CaptureWidget: Widget {
    let kind = "RhizomeCapture"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureProvider()) { entry in
            CaptureWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Capture")
        .description("Capture into today’s journal — the medium size previews your capture bullet.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct RhizomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaptureWidget()
    }
}
