import Foundation

/// Cursor hooks (https://cursor.com/docs/agent/hooks), for the Cursor editor agent and cursor-agent.
///
/// Observation: sessionStart, beforeSubmitPrompt, postToolUse, postToolUseFailure, afterFileEdit,
/// afterAgentResponse, stop, sessionEnd. These never change what Cursor does.
///
/// Approvals (opt-in): beforeShellExecution and beforeMCPExecution are held until the user decides.
/// Cursor runs these hooks for every command, not only the ones it would ask about, so turning
/// approvals on routes every shell command and MCP call through the widget.
///
/// preToolUse is deliberately not used: its only answers are allow and deny, and there is no
/// neutral reply that leaves Cursor's own approval in charge.
struct CursorAdapter: AgentAdapter {
    func normalize(_ raw: [String: Any]) -> HuddleEvent? {
        guard let name = raw["hook_event_name"] as? String,
              let conversation = (raw["conversation_id"] as? String) ?? (raw["session_id"] as? String) else { return nil }
        let roots = raw["workspace_roots"] as? [String] ?? []
        var e: HuddleEvent = ["session_id": conversation, "cwd": (raw["cwd"] as? String) ?? roots.first ?? ""]

        switch name {
        case "sessionStart":
            e["hook_event_name"] = "SessionStart"
            e["source"] = (raw["composer_mode"] as? String).map { "started (\($0))" } ?? "started"
        case "beforeSubmitPrompt":
            e["hook_event_name"] = "UserPromptSubmit"
            e["prompt"] = raw["prompt"] as? String ?? ""
        case "postToolUse", "postToolUseFailure":
            e["hook_event_name"] = "ToolRan"
            e["tool_name"] = raw["tool_name"] as? String ?? "Tool"
            e["tool_input"] = raw["tool_input"] as? [String: Any] ?? [:]
            e["failed"] = name == "postToolUseFailure"
        case "afterFileEdit":
            e["hook_event_name"] = "ToolRan"
            e["tool_name"] = "Edit"
            e["tool_input"] = ["file_path": raw["file_path"] as? String ?? ""]
        case "afterAgentResponse":
            e["hook_event_name"] = "AgentMessage"
            e["message"] = raw["text"] as? String ?? ""
        case "stop":
            e["hook_event_name"] = "Stop"
            let status = raw["status"] as? String ?? "completed"
            e["last_assistant_message"] = status == "completed" ? "" : "Stopped: \(status)"
        case "sessionEnd":
            e["hook_event_name"] = "SessionEnd"
        case "beforeShellExecution":
            e["hook_event_name"] = "PermissionRequest"
            e["tool_name"] = "Shell"
            e["tool_input"] = ["command": raw["command"] as? String ?? ""]
        case "beforeMCPExecution":
            e["hook_event_name"] = "PermissionRequest"
            let server = raw["mcp_server_name"] as? String ?? "MCP"
            e["tool_name"] = "\(server): \(raw["tool_name"] as? String ?? "tool")"
            e["tool_input"] = raw["tool_input"] as? [String: Any] ?? [:]
        default:
            return nil
        }
        return e
    }

    func reply(_ decision: Decision, raw: [String: Any], event: HuddleEvent) -> String {
        let name = raw["hook_event_name"] as? String ?? ""
        switch name {
        case "beforeShellExecution", "beforeMCPExecution":
            switch decision {
            case .allow:
                return jsonString(["permission": "allow"])
            case .deny:
                return jsonString(["permission": "deny",
                                   "user_message": "Denied from Agent Huddle.",
                                   "agent_message": "The user denied this from Agent Huddle."])
            case .answer, .handBack:
                // "ask" hands the decision to Cursor's own prompt; it never approves anything.
                return jsonString(["permission": "ask"])
            }
        case "beforeSubmitPrompt":
            return jsonString(["continue": true])
        default:
            // Observation hooks: an empty object changes nothing.
            return "{}"
        }
    }
}
