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
    /// - Parameter html: when true, `text` is already-formatted inline HTML (e.g. a titled
    ///   `<a href>` link) — the server sanitizes it instead of escaping it to plain text.
    public static func send(_ text: String, html: Bool = false) async throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw Failure(message: "Nothing to capture") }
        guard let base = AppGroup.serverURL, let cookie = AppGroup.sessionCookie else {
            throw Failure(message: "Open Rhizome and sign in first")
        }

        var request = URLRequest(url: base.appendingPathComponent("api/capture"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("rz_session=\(cookie)", forHTTPHeaderField: "Cookie")   // reuse the app's session
        let line = AppGroup.captureTimestamp ? "\(timestamp()) \(body)" : body
        struct Body: Encodable { let text: String; let bullet: String; let html: Bool }
        request.httpBody = try JSONEncoder().encode(Body(text: line, bullet: AppGroup.captureBullet, html: html))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure(message: "No response from the server")
        }
        if http.statusCode == 401 {
            throw Failure(message: "Session expired — open Rhizome, sign in, then try again")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure(message: "Server returned \(http.statusCode)")
        }
    }

    /// Upload a file's bytes to `/api/upload` as the signed-in user (App Group session), returning
    /// the stored `/files/<id>` attachment. Mirrors `RhizomeAPI.upload` but sets the `Cookie`
    /// header explicitly — the extension can't rely on the app's HTTPCookieStorage.
    public static func upload(_ data: Data, name: String, contentType: String) async throws -> RFile {
        guard !data.isEmpty else { throw Failure(message: "Nothing to upload") }
        guard let base = AppGroup.serverURL, let cookie = AppGroup.sessionCookie else {
            throw Failure(message: "Open Rhizome and sign in first")
        }
        var comps = URLComponents(url: base.appendingPathComponent("api/upload"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "name", value: name)]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("rz_session=\(cookie)", forHTTPHeaderField: "Cookie")
        request.httpBody = data
        let (out, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure(message: "No response from the server") }
        if http.statusCode == 401 { throw Failure(message: "Session expired — open Rhizome, sign in, then try again") }
        if http.statusCode == 413 { throw Failure(message: "Too large — storage quota exceeded") }
        guard (200..<300).contains(http.statusCode) else { throw Failure(message: "Upload failed (\(http.statusCode))") }
        struct Resp: Decodable { let url: String; let name: String?; let size: Double? }
        let r = try JSONDecoder().decode(Resp.self, from: out)
        return RFile(url: r.url, name: r.name, type: contentType, size: r.size)
    }

    /// Capture one node that carries file attachments, with an optional caption and inline-HTML
    /// child bullets (e.g. a `Quelle: <a href>` source line under a shared web image). Lands under
    /// today's capture bullet like `send`. `caption` is plain text (escaped server-side).
    public static func sendFiles(_ files: [RFile], caption: String = "", children: [String] = []) async throws {
        guard !files.isEmpty else { throw Failure(message: "Nothing to capture") }
        guard let base = AppGroup.serverURL, let cookie = AppGroup.sessionCookie else {
            throw Failure(message: "Open Rhizome and sign in first")
        }
        var request = URLRequest(url: base.appendingPathComponent("api/capture"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("rz_session=\(cookie)", forHTTPHeaderField: "Cookie")
        let cap = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (AppGroup.captureTimestamp && !cap.isEmpty) ? "\(timestamp()) \(cap)" : cap
        struct FileBody: Encodable { let url: String; let name: String?; let type: String?; let size: Double? }
        struct Body: Encodable { let text: String; let bullet: String; let files: [FileBody]; let children: [String] }
        let body = Body(text: text, bullet: AppGroup.captureBullet,
                        files: files.map { FileBody(url: $0.url, name: $0.name, type: $0.type, size: $0.size) },
                        children: children)
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure(message: "No response from the server") }
        if http.statusCode == 401 { throw Failure(message: "Session expired — open Rhizome, sign in, then try again") }
        guard (200..<300).contains(http.statusCode) else { throw Failure(message: "Server returned \(http.statusCode)") }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}
