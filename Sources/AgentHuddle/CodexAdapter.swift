import Foundation

/// OpenAI Codex hooks (https://learn.chatgpt.com/docs/hooks), for the Codex CLI and app.
///
/// Codex's hook events and fields follow Claude Code's closely: SessionStart, UserPromptSubmit,
/// PreToolUse, PostToolUse, PermissionRequest, Stop, Interrupt and SessionEnd, keyed by session_id.
/// PermissionRequest fires only when Codex is about to show its own approval prompt and accepts
/// the same decision.behavior reply; empty output means "no decision", so Codex asks as usual.
///
/// Codex's request_user_input questions can't be answered from a hook, so they are shown as
/// "needs you" without answer buttons.
struct CodexAdapter: AgentAdapter {
    func normalize(_ raw: [String: Any]) -> HuddleEvent? {
        guard raw["session_id"] is String, let name = raw["hook_event_name"] as? String else { return nil }
        var e = raw
        let tool = raw["tool_name"] as? String ?? ""

        switch name {
        case "SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd":
            break
        case "PreToolUse":
            if tool == "request_user_input" {
                let questions = (raw["tool_input"] as? [String: Any])?["questions"] as? [[String: Any]] ?? []
                e["hook_event_name"] = "Notification"
                e["notification_type"] = "agent_needs_input"
                e["message"] = "Asked you a question: "
                    + questions.compactMap { $0["question"] as? String }.joined(separator: " / ")
            }
        case "Interrupt":
            e["hook_event_name"] = "Stop"
            e["last_assistant_message"] = "Interrupted"
        default:
            return nil
        }

        // apply_patch sends the whole patch as its "command": show the files it touches instead.
        if tool == "apply_patch", let patch = (raw["tool_input"] as? [String: Any])?["command"] as? String {
            let files = patch.split(separator: "\n").compactMap { line -> String? in
                for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(prefix) {
                    return String(line.dropFirst(prefix.count))
                }
                return nil
            }
            e["tool_name"] = "Edit"
            e["tool_input"] = ["file_path": files.joined(separator: ", ")]
        }
        return e
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
        case .answer, .handBack:
            // Empty output: no decision, Codex shows its normal approval prompt.
            return ""
        }
    }
}
