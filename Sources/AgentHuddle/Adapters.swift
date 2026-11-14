import Foundation

/// The coding agents Agent Huddle understands. Each one is an adapter that turns the agent's
/// own hook payload into the widget's event shape (modelled on Claude Code's hook events), and
/// turns the widget's decisions back into the reply that agent expects.
enum Agent: String, CaseIterable {
    case claude, codex, cursor

    init(header: String?) { self = Agent(rawValue: (header ?? "").lowercased()) ?? .claude }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    var adapter: AgentAdapter {
        switch self {
        case .claude: return ClaudeAdapter()
        case .codex: return CodexAdapter()
        case .cursor: return CursorAdapter()
        }
    }
}

/// What the user decided about a prompt.
enum Decision {
    case allow
    case deny
    case answer([String: String])
    /// Not decided in the widget: the agent should carry on exactly as if the widget were absent.
    case handBack
}

/// A normalized event, in the shape the store reads.
///
/// Keys: session_id, hook_event_name, cwd, tool_name, tool_input, tool_use_id, prompt, source,
/// session_title, message, notification_type, last_assistant_message.
/// Events the store understands: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse,
/// PostToolUseFailure, PermissionRequest, Notification, Stop, SubagentStop, SessionEnd.
/// PermissionRequest (and PreToolUse for AskUserQuestion) can be held for a decision.
typealias HuddleEvent = [String: Any]

protocol AgentAdapter {
    /// Converts the agent's raw hook payload; nil means "not something the widget shows".
    func normalize(_ raw: [String: Any]) -> HuddleEvent?
    /// The exact stdout the agent's hook must print for this decision.
    /// `raw` is the original payload, `event` the normalized one.
    func reply(_ decision: Decision, raw: [String: Any], event: HuddleEvent) -> String
}

func jsonString(_ object: Any) -> String {
    (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
}

// MARK: Claude Code (https://code.claude.com/docs/en/hooks)

struct ClaudeAdapter: AgentAdapter {
    func normalize(_ raw: [String: Any]) -> HuddleEvent? {
        raw["session_id"] is String && raw["hook_event_name"] is String ? raw : nil
    }

    func reply(_ decision: Decision, raw: [String: Any], event: HuddleEvent) -> String {
        switch decision {
        case .allow:
            return jsonString(["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                                      "decision": ["behavior": "allow"]]])
        case .deny:
            return jsonString(["hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": "deny", "message": "The user denied this from Agent Huddle."]]])
        case .answer(let answers):
            var input = event["tool_input"] as? [String: Any] ?? [:]
            input["answers"] = answers
            return jsonString(["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow",
                                                      "updatedInput": input]])
        case .handBack:
            // Empty output: Claude Code runs its normal permission flow.
            return ""
        }
    }
}
