import Foundation
import Network

struct HookRequest {
    var method = "POST"
    var path = "/hook"
    var query: [String: String] = [:]
    let headers: [String: String]
    let json: [String: Any]
}

/// Holds one open hook connection until the widget has an answer for it.
final class HookResponder {
    private let connection: NWConnection
    private var finished = false
    var onClose: (() -> Void)?

    init(connection: NWConnection) { self.connection = connection }

    func send(_ body: String, status: String = "200 OK") {
        guard !finished else { return }
        finished = true
        onClose = nil
        let data = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + data, completion: .contentProcessed { [connection] _ in
            connection.cancel()
        })
    }

    /// The hook went away (timed out, or the prompt was answered elsewhere).
    func closedByPeer() {
        guard !finished else { return }
        finished = true
        connection.cancel()
        onClose?()
    }
}

final class HookServer {
    let port: UInt16
    let token: String
    var onRequest: ((HookRequest, HookResponder) -> Void)?
    private var listener: NWListener?

    init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            self?.read(conn, buffer: Data())
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func read(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = self.parse(buffer) {
                let responder = HookResponder(connection: conn)
                guard request.headers["x-huddle-token"] == self.token else {
                    responder.send("", status: "403 Forbidden")
                    return
                }
                self.watchForClose(conn, responder)
                self.onRequest?(request, responder)
            } else if isComplete || error != nil || buffer.count > 8 << 20 {
                conn.cancel()
            } else {
                self.read(conn, buffer: buffer)
            }
        }
    }

    private func watchForClose(_ conn: NWConnection, _ responder: HookResponder) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil {
                responder.closedByPeer()
            } else {
                self?.watchForClose(conn, responder)
            }
        }
    }

    /// Returns nil until a whole HTTP request (headers + body) has arrived.
    private func parse(_ buffer: Data) -> HookRequest? {
        guard let split = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: buffer[buffer.startIndex..<split.lowerBound], encoding: .utf8) else { return nil }
        var headers: [String: String] = [:]
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = buffer[split.upperBound...]
        guard body.count >= length else { return nil }
        let json = (try? JSONSerialization.jsonObject(with: body.prefix(length))) as? [String: Any] ?? [:]
        var request = HookRequest(headers: headers, json: json)
        let parts = head.components(separatedBy: "\r\n")[0].components(separatedBy: " ")
        if parts.count >= 2, let url = URLComponents(string: parts[1]) {
            request.method = parts[0]
            request.path = url.path
            for item in url.queryItems ?? [] { request.query[item.name] = item.value ?? "" }
        }
        return request
    }
}

/// Port + shared secret, written where the hook script can read them.
enum HuddleConfig {
    /// Appends a line to ~/.agent-huddle/huddle.log.
    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = dir.appendingPathComponent("huddle.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-huddle")

    static func load() -> (port: UInt16, token: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let portFile = dir.appendingPathComponent("port")
        let headerFile = dir.appendingPathComponent("headers")
        let port = (try? String(contentsOf: portFile, encoding: .utf8))
            .flatMap { UInt16($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 47821
        let prefix = "X-Huddle-Token: "
        var token = (try? String(contentsOf: headerFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        token = token.hasPrefix(prefix) ? String(token.dropFirst(prefix.count)) : ""
        if token.isEmpty {
            token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
            fm.createFile(atPath: headerFile.path, contents: Data((prefix + token + "\n").utf8),
                          attributes: [.posixPermissions: 0o600])
        }
        try? "\(port)\n".write(to: portFile, atomically: true, encoding: .utf8)
        return (port, token)
    }
}
