import Foundation

/// Finds every running Claude Code session, with or without hooks, from the records Claude
/// Code keeps in ~/.claude/sessions/<pid>.json (session id, folder, name, busy/idle status).
/// Sessions started before the hooks were installed show up this way too: with their status
/// and a working jump button, but no step-by-step timeline.
struct DiscoveredSession {
    let id: String
    let pid: Int32
    let cwd: String
    let name: String
    let status: SessionStatus
    let hostSession: String
    let bundleID: String
    let term: String
    let tty: String
}

enum Discovery {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")

    /// Scans the records; runs off the main thread (it calls ps for new sessions).
    static func scan(known: Set<String>) -> [DiscoveredSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var found: [DiscoveredSession] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = j["sessionId"] as? String,
                  let pid = (j["pid"] as? NSNumber)?.int32Value,
                  (j["kind"] as? String ?? "interactive") == "interactive",
                  kill(pid, 0) == 0 || errno == EPERM else { continue }

            let nameSource = j["nameSource"] as? String
            let name = nameSource == "derived" ? "" : (j["name"] as? String ?? "")
            let status: SessionStatus = (j["status"] as? String) == "idle" ? .idle : .working
            let desktop = (j["entrypoint"] as? String) == "claude-desktop"

            // Host app and tab only need working out once per session.
            var bundle = desktop ? "com.anthropic.claudefordesktop" : ""
            var term = "", tty = ""
            if !desktop, !known.contains(id) {
                let env = environment(of: pid)
                bundle = env["__CFBundleIdentifier"] ?? ""
                term = env["TERM_PROGRAM"] ?? ""
                tty = ttyName(of: pid)
            }
            var title = name
            if title.isEmpty, bundle == "dev.herdr.app", let t = herdrTerminal(running: pid)?.title { title = t }
            found.append(DiscoveredSession(
                id: id, pid: pid, cwd: j["cwd"] as? String ?? "", name: title, status: status,
                hostSession: j["hostSessionId"] as? String ?? "", bundleID: bundle, term: term, tty: tty))
        }
        return found
    }

    /// The Herdr terminal whose foreground program is this pid: its address (t3) and title.
    static func herdrTerminal(running pid: Int32) -> (address: String, title: String)? {
        let hc = FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/hc"
        guard FileManager.default.isExecutableFile(atPath: hc) else { return nil }
        let list = (try? JSONSerialization.jsonObject(with: Data(run(hc, ["ls", "--json"]).utf8))) as? [String: Any]
        for t in list?["terminals"] as? [[String: Any]] ?? [] {
            guard let address = t["address"] as? String else { continue }
            let info = (try? JSONSerialization.jsonObject(with: Data(run(hc, ["get", address, "--json"]).utf8))) as? [String: Any]
            let fg = (info?["foreground"] as? [String: Any])?["pid"] as? NSNumber
            if fg?.int32Value == pid {
                let title = (info?["title"] as? String) ?? ""
                let label = ((info?["labels"] as? [String: Any])?["where"] as? String) ?? ""
                return (address, title.isEmpty ? label : title)
            }
        }
        return nil
    }

    /// A process's environment, read with ps (the same values its hooks would report).
    static func environment(of pid: Int32) -> [String: String] {
        let out = run("/bin/ps", ["-E", "-ww", "-p", "\(pid)", "-o", "command="])
        var env: [String: String] = [:]
        for token in out.split(separator: " ") {
            guard let eq = token.firstIndex(of: "="), token.first?.isUppercase == true || token.first == "_" else { continue }
            env[String(token[..<eq])] = String(token[token.index(after: eq)...])
        }
        return env
    }

    static func ttyName(of pid: Int32) -> String {
        let t = run("/bin/ps", ["-o", "tty=", "-p", "\(pid)"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains("?") ? "" : t
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
