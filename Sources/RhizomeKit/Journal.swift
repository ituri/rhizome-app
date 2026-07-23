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

    /// "2026-07-16" → Date.
    static func parseCd(_ cd: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: cd)
    }

    /// Date → "July 16th, 2026" (the canonical journal-day title).
    public static func label(for date: Date) -> String {
        let cal = Calendar.current
        let day = cal.component(.day, from: date)
        let year = cal.component(.year, from: date)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM"
        let suffix: String
        if (11...13).contains(day % 100) { suffix = "th" }
        else { switch day % 10 { case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"; default: suffix = "th" } }
        return "\(f.string(from: date)) \(day)\(suffix), \(year)"
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
