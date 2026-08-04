import Foundation

/// A daily-notes day: the calendar day node plus its parsed date, for the Journal view.
public struct JournalDay: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let date: Date
}

public enum Journal {
    /// All calendar day nodes, most recent first (like the web app's daily notes). Identity + label
    /// come from the day's stable `cd` field (not its editable title), so renaming a day's text
    /// doesn't change where it sorts or how it's labelled — matching the web.
    public static func days(_ doc: RDoc) -> [JournalDay] {
        doc.nodes
            .filter { $0.value.cal == "day" }
            .map { id, node in
                if let cd = node.cd, let date = parseCd(cd) {
                    return JournalDay(id: id, title: label(for: date), date: date)
                }
                let title = node.text ?? ""   // fallback for day nodes without a cd field
                return JournalDay(id: id, title: title, date: parseDate(title) ?? .distantPast)
            }
            .sorted { $0.date > $1.date }
    }

    /// A Gregorian calendar in the device's (live) time zone — the parsing/labelling calendar.
    /// Held as a `let` because `days` runs on every Journal re-render: building a `DateFormatter`
    /// per day node was the single most expensive thing in that path.
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = .autoupdatingCurrent
        return c
    }()

    /// English month names — the canonical day title is `en_US_POSIX`, never localized.
    private static let months = ["January", "February", "March", "April", "May", "June",
                                 "July", "August", "September", "October", "November", "December"]

    /// "2026-07-16" → Date. Hand-parsed (no `DateFormatter`): strict about the three numeric
    /// components, so a malformed `cd` still returns nil rather than rolling over.
    static func parseCd(_ cd: String) -> Date? {
        let parts = cd.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return cal.date(from: DateComponents(year: y, month: m, day: d))
    }

    /// Date → "July 16th, 2026" (the canonical journal-day title).
    public static func label(for date: Date) -> String {
        let c = cal.dateComponents([.day, .month, .year], from: date)
        guard let day = c.day, let month = c.month, let year = c.year, (1...12).contains(month) else { return "" }
        let suffix: String
        if (11...13).contains(day % 100) { suffix = "th" }
        else { switch day % 10 { case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"; default: suffix = "th" } }
        return "\(months[month - 1]) \(day)\(suffix), \(year)"
    }

    /// "July 14th, 2026" → a Date (strips the ordinal suffix).
    static func parseDate(_ text: String) -> Date? {
        let stripped: String
        if let re = try? NSRegularExpression(pattern: "(\\d+)(st|nd|rd|th)") {
            let ns = text as NSString
            stripped = re.stringByReplacingMatches(
                in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "$1"
            )
        } else {
            stripped = text
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.date(from: stripped)
    }
}
