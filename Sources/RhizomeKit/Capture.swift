import Foundation

/// Posts quick-capture text to Rhizome's `/api/capture` as the signed-in user, using the
/// session shared from the main app via the App Group. The line lands under today's journal
/// in the Inbox, like the `r` shell command.
public enum Capture {
    public struct Failure: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    /// Send one capture line. A leading `HH:mm` timestamp is added if the shared setting is on.
    /// Requires the main app to be signed in (its session is mirrored into the App Group).
    public static func send(_ text: String) async throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw Failure(message: "Nothing to capture") }
        AppGroup.logShare("send: url=\(AppGroup.serverURL?.absoluteString ?? "nil") cookie=\(AppGroup.sessionCookie != nil ? "set(\(AppGroup.sessionCookie!.count))" : "nil")")
        guard let base = AppGroup.serverURL, let cookie = AppGroup.sessionCookie else {
            AppGroup.logShare("blocked: no server URL or cookie in the App Group")
            throw Failure(message: "Open Rhizome and sign in first")
        }

        var request = URLRequest(url: base.appendingPathComponent("api/capture"))
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("rz_session=\(cookie)", forHTTPHeaderField: "Cookie")   // reuse the app's session
        let line = AppGroup.captureTimestamp ? "\(timestamp()) \(body)" : body
        request.httpBody = Data(line.utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            AppGroup.logShare("no HTTP response")
            throw Failure(message: "No response from the server")
        }
        AppGroup.logShare("http \(http.statusCode)")
        if http.statusCode == 401 {
            throw Failure(message: "Session expired — open Rhizome, sign in, then try again")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure(message: "Server returned \(http.statusCode)")
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}
