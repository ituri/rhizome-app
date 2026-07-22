import WidgetKit
import SwiftUI

// Rhizome's palette, hardcoded so the widget target stays self-contained (no RhizomeKit).
private let rzClay = Color(red: 0.76, green: 0.34, blue: 0.23)   // #c2563a
private let rzPaper = Color(red: 0.957, green: 0.945, blue: 0.918) // #f4f1ea
private let rzInk = Color(red: 0.20, green: 0.19, blue: 0.17)

private let appGroupID = "group.org.syslinx.rhizome"

/// Today's capture bullet + a preview of its items, published by the app into the App Group.
private func loadSnapshot() -> (bullet: String, items: [String]) {
    let d = UserDefaults(suiteName: appGroupID)
    let raw = d?.string(forKey: "captureBullet")?.trimmingCharacters(in: .whitespaces) ?? ""
    let bullet = raw.isEmpty ? "Inbox" : raw
    let items = d?.stringArray(forKey: "widgetItems") ?? []
    return (bullet, items)
}

struct CaptureEntry: TimelineEntry {
    let date: Date
    let bullet: String
    let items: [String]
}

struct CaptureProvider: TimelineProvider {
    private func entry() -> CaptureEntry {
        let s = loadSnapshot()
        return CaptureEntry(date: .now, bullet: s.bullet, items: s.items)
    }
    func placeholder(in context: Context) -> CaptureEntry {
        CaptureEntry(date: .now, bullet: "Inbox", items: ["Milch kaufen", "Zahnarzt anrufen"])
    }
    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        // the app reloads us via WidgetCenter on every change; refresh in ~30 min as a fallback
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(1800))))
    }
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

    // Medium: today's items under the capture bullet, plus a capture affordance.
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
                ForEach(entry.items.prefix(4), id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(rzClay)
                        Text(item).lineLimit(1).foregroundStyle(rzInk)
                    }
                    .font(.system(size: 13))
                }
                if entry.items.count > 4 {
                    Text("+\(entry.items.count - 4) more")
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
