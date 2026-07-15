import Foundation

/// Posts quick-capture text to Rhizome's `/api/capture`, exactly like the `r`
/// shell command: the line lands under today's journal in the Inbox, prefixed
/// with the local time.
public enum Capture {
    public struct Failure: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    /// Send one capture line (a leading `HH:mm` timestamp is added for you).
    public static func send(_ text: String) async throws {
        let body = trimmed(text)
        guard !body.isEmpty else { throw Failure(message: "Nothing to capture") }
        guard !Config.captureToken.isEmpty else {
            throw Failure(message: "No capture token configured (set Config.captureToken)")
        }

        var components = URLComponents(
            url: Config.serverURL.appendingPathComponent("api/capture"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "token", value: Config.captureToken)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("\(timestamp()) \(body)".utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure(message: "No response from the server")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure(message: "Server returned \(http.statusCode)")
        }
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}
