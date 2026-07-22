import WidgetKit
import SwiftUI

// Rhizome's palette, hardcoded so the widget target stays self-contained (no RhizomeKit).
private let rzClay = Color(red: 0.76, green: 0.34, blue: 0.23)   // #c2563a
private let rzPaper = Color(red: 0.957, green: 0.945, blue: 0.918) // #f4f1ea

/// A single static entry — the widget's only job is to deep-link into the app's quick capture.
struct CaptureEntry: TimelineEntry {
    let date: Date
}

struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry { CaptureEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        completion(Timeline(entries: [CaptureEntry(date: .now)], policy: .never))
    }
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        // the whole widget is one tap target → opens rhizome://capture
        Group {
            if family == .systemMedium {
                HStack(spacing: 14) {
                    brand
                    Spacer()
                    button
                    Spacer()
                }
                .padding(.horizontal, 4)
            } else {
                VStack(spacing: 10) {
                    brand
                    Spacer(minLength: 0)
                    button
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(rzPaper, for: .widget)
        .widgetURL(URL(string: "rhizome://capture"))
    }

    private var brand: some View {
        HStack(spacing: 5) {
            Image(systemName: "leaf.fill").font(.system(size: 12))
            Text("Rhizome").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(rzClay)
        .frame(maxWidth: family == .systemMedium ? nil : .infinity, alignment: .leading)
    }

    private var button: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.and.pencil").font(.system(size: 26, weight: .semibold))
            Text("Capture").font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: family == .systemMedium ? 150 : .infinity)
        .padding(.vertical, 14)
        .background(rzClay, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CaptureWidget: Widget {
    let kind = "RhizomeCapture"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureProvider()) { _ in
            CaptureWidgetView()
        }
        .configurationDisplayName("Quick Capture")
        .description("Jot a note straight into today’s journal.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct RhizomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaptureWidget()
    }
}
