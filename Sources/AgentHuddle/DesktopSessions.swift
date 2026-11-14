import Foundation

/// Finds the Claude desktop app's own id (local_...) for a Claude Code session, so jump can
/// open that exact session even when its hooks never reported the id.
enum DesktopSessions {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")

    /// Matches the hook's session_id against each desktop session's CLI session ids.
    static func localID(forCLISession id: String) -> String? { record(forCLISession: id)?.id }

    /// The desktop app's id and title for a Claude Code session, if it runs in the app.
    static func record(forCLISession id: String) -> (id: String, title: String)? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator
        where url.lastPathComponent.hasPrefix("local_") && url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  json["isArchived"] as? Bool != true else { continue }
            if json["cliSessionId"] as? String == id || json["lastAssistantCliSessionId"] as? String == id {
                return (json["sessionId"] as? String ?? url.deletingPathExtension().lastPathComponent,
                        json["title"] as? String ?? "")
            }
        }
        return nil
    }
}
