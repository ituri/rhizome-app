import Foundation

/// A daily-notes day: the calendar day node plus its parsed date, for the Journal view.
public struct JournalDay: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let date: Date
}

public enum Journal {
    /// All calendar day nodes, most recent first (like the web app's daily notes).
    public static func days(_ doc: RDoc) -> [JournalDay] {
        doc.nodes
            .filter { $0.value.cal == "day" }
            .map { id, node in
                let title = node.text ?? ""
                return JournalDay(id: id, title: title, date: parseDate(title) ?? .distantPast)
            }
            .sorted { $0.date > $1.date }
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
