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

    /// Fetch a URL and return its `<title>` (nil if missing, blocked, or a bot-check interstitial)
    /// plus the final URL after redirects — so a callers can derive a title from the resolved
    /// URL's slug even when the page body is a "please wait / verify you are human" wall.
    public static func resolve(_ url: URL, timeout: TimeInterval = 6) async -> (title: String?, finalURL: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return (nil, url) }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        // a realistic browser UA gets the real page from many sites that block obvious bots
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return (nil, url) }
        let finalURL = http.url ?? url
        guard (200..<400).contains(http.statusCode) else { return (nil, finalURL) }
        let html = String(decoding: data.prefix(256 * 1024), as: UTF8.self)   // the <head> is near the top
        return (extractTitle(html), finalURL)
    }

    /// A readable title from a URL's slug, e.g. Reddit `/r/x/comments/<id>/<slug>/` → "The slug".
    /// Used when the page can't be scraped (bot walls) but the URL still carries the title.
    public static func titleFromURL(_ url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if let i = parts.firstIndex(of: "comments"), i + 2 < parts.count {   // reddit post slug
            return humanizeSlug(parts[i + 2])
        }
        return nil
    }

    private static func humanizeSlug(_ slug: String) -> String? {
        let s = slug.removingPercentEncoding ?? slug
        let words = s.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard words.count > 2 else { return nil }
        return words.prefix(1).uppercased() + String(words.dropFirst())
    }

    static func extractTitle(_ html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        let raw = ns.substring(with: m.range(at: 1))
        let decoded = decodeEntities(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (decoded.isEmpty || isInterstitial(decoded)) ? nil : String(decoded.prefix(300))
    }

    /// True for bot-check / verification interstitial titles (Reddit, Cloudflare, …) so we don't
    /// store "Please wait for verification" as the link title.
    static func isInterstitial(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["just a moment", "please wait", "attention required", "verify you are human",
                "are you a robot", "are you human", "checking your browser", "enable javascript",
                "javascript is disabled", "verification", "access denied", "captcha",
                "request blocked", "one moment"].contains { t.contains($0) }
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
