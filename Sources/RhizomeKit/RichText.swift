import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Renders a Rhizome node's raw text into a styled `AttributedString`: Markdown
/// (**bold**, *italic*, `code`, [links](url)) plus Rhizome's own `[[page links]]`,
/// `#tags` and `((block references))`. Block refs are resolved to the target's
/// text using the loaded doc.
public enum RichText {
    #if canImport(SwiftUI)
    public static let accent = Color(
        red: Config.accent.red, green: Config.accent.green, blue: Config.accent.blue
    )
    #endif

    /// Plain display text with the markup stripped — for places that can't show
    /// an AttributedString (e.g. a navigation title).
    public static func plain(_ raw: String, doc: RDoc? = nil) -> String {
        String(attributed(raw, doc: doc).characters)
    }

    public static func attributed(_ raw: String, doc: RDoc? = nil) -> AttributedString {
        var text = raw

        // ((block-ref)) → the target node's text (one level; strip nested refs)
        if text.contains("((") {
            text = replace(text, #"\(\(([A-Za-z0-9_-]+)\)\)"#) { id in
                let target = doc?.nodes[id]?.text ?? ""
                return target.replacingOccurrences(of: "((", with: "").replacingOccurrences(of: "))", with: "")
            }
        }
        // #[[multi word tag]] and #tag → markdown links (styled below)
        text = replace(text, #"#\[\[([^\]]+)\]\]"#) { "[#\($0)](rhizome://t/\(esc($0)))" }
        text = replace(text, #"(?<![\w/])#([\p{L}0-9_\-]+)"#) { "[#\($0)](rhizome://t/\(esc($0)))" }
        // [[Page Link]] → markdown link
        text = replace(text, #"\[\[([^\]]+)\]\]"#) { "[\($0)](rhizome://p/\(esc($0)))" }

        let parsed: AttributedString
        do {
            parsed = try AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            return AttributedString(raw)
        }

        #if canImport(SwiftUI)
        var result = parsed
        // Style our internal links (pages/tags) with the accent; keep external
        // links tappable. Collect ranges first so we don't mutate mid-iteration.
        let ranges = result.runs.compactMap { run -> (Range<AttributedString.Index>, URL)? in
            guard let url = run.link else { return nil }
            return (run.range, url)
        }
        for (range, url) in ranges {
            result[range].foregroundColor = accent
            if url.scheme == "rhizome" {
                result[range].link = nil          // not navigable yet
                result[range].underlineStyle = nil
            }
        }
        return result
        #else
        return parsed
        #endif
    }

    private static func esc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    /// Replace every match of `pattern` (capture group 1 passed to `transform`).
    private static func replace(_ s: String, _ pattern: String, _ transform: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let group = m.numberOfRanges > 1 ? m.range(at: 1) : m.range
            out += transform(ns.substring(with: group))
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
