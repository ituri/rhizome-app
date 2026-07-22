import Foundation

/// HTML-escaping for building safe inline markup (the server sanitizes, but escape here too so
/// a title/URL can't break out of the anchor).
public enum HTMLEscape {
    public static func text(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
    public static func attr(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Fetch a web page's `<title>` and build a Rhizome link, for the share sheet / clipper flows.
public enum LinkFormat {
    /// `<a href="url" rel="noopener">title</a>` with both parts escaped.
    public static func anchor(url: String, title: String) -> String {
        "<a href=\"\(HTMLEscape.attr(url))\" rel=\"noopener\">\(HTMLEscape.text(title))</a>"
    }

    /// Best-effort page title from a URL's HTML `<title>`. Returns nil on non-HTTP(S), failure or
    /// timeout — callers should fall back to the host/URL.
    public static func fetchTitle(_ url: URL, timeout: TimeInterval = 6) async -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("Mozilla/5.0 (compatible; Rhizome)", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return nil }
        let html = String(decoding: data.prefix(256 * 1024), as: UTF8.self)   // the <head> is near the top
        return extractTitle(html)
    }

    static func extractTitle(_ html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        let raw = ns.substring(with: m.range(at: 1))
        let decoded = decodeEntities(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : String(decoded.prefix(300))
    }

    static func decodeEntities(_ s: String) -> String {
        var r = s
        for (e, c) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                       ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            r = r.replacingOccurrences(of: e, with: c)
        }
        guard let re = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") else { return r }
        let ns = r as NSString
        var out = "", last = 0
        for m in re.matches(in: r, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let tok = ns.substring(with: m.range(at: 1))
            let code = tok.hasPrefix("x") ? Int(tok.dropFirst(), radix: 16) : Int(tok)
            if let code, let scalar = Unicode.Scalar(code) { out.unicodeScalars.append(scalar) }
            else { out += ns.substring(with: m.range) }
            last = m.range.location + m.range.length
        }
        out += ns.substring(with: NSRange(location: last, length: ns.length - last))
        return out
    }
}
