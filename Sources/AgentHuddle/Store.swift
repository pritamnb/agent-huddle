import Foundation
import SwiftUI

enum SessionStatus {
    case working, needsYou, idle, ended

    var label: String {
        switch self {
        case .working: return "Working"
        case .needsYou: return "Needs you"
        case .idle: return "Waiting for you"
        case .ended: return "Ended"
        }
    }
    var color: Color {
        switch self {
        case .working: return .green
        case .needsYou: return .orange
        case .idle: return .blue
        case .ended: return .gray
        }
    }
}

enum StepState { case info, running, done, failed }

struct Step: Identifiable {
    let id = UUID()
    let time = Date()
    var icon: String
    var title: String
    var detail: String = ""
    var state: StepState = .info
    var toolUseID: String?
}

struct Question: Identifiable {
    let id = UUID()
    let question: String
    let header: String
    let options: [(label: String, description: String)]
    let multiSelect: Bool
}

final class PendingRequest: Identifiable {
    let id = UUID()
    let sessionID: String
    let toolName: String
    let summary: String
    let toolInput: [String: Any]
    let questions: [Question]
    let responder: HookResponder
    let agent: Agent
    let raw: [String: Any]
    let event: HuddleEvent
    let created = Date()
    var isQuestion: Bool { !questions.isEmpty }

    init(sessionID: String, toolName: String, summary: String, toolInput: [String: Any],
         questions: [Question], responder: HookResponder, agent: Agent, raw: [String: Any], event: HuddleEvent) {
        self.agent = agent
        self.raw = raw
        self.event = event
        self.sessionID = sessionID
        self.toolName = toolName
        self.summary = summary
        self.toolInput = toolInput
        self.questions = questions
        self.responder = responder
    }
}

struct Session: Identifiable {
    let id: String
    var cwd: String
    var title: String
    var agent: Agent = .claude
    var bundleID = ""
    var term = ""
    var tty = ""
    var status: SessionStatus = .working
    var steps: [Step] = []
    var updatedAt = Date()

    var project = ""
    /// The agent's process id, when known (from Claude Code's session records).
    var pid: Int32 = 0
    /// Whether this session's hooks have reported anything; without hooks there is no timeline.
    var hooked = false
    /// The desktop app's own id for this session (local_...), used for its deep link.
    var hostSession = ""
    var name: String {
        if !title.isEmpty { return title }
        return ((project.isEmpty ? cwd : project) as NSString).lastPathComponent
    }
    /// Bundle id of the app whose window hosts this session.
    var hostBundle: String {
        if !bundleID.isEmpty { return bundleID }
        switch term {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "vscode": return "com.microsoft.VSCode"
        default: return ""
        }
    }
    var activity: String {
        guard let last = steps.last else { return status.label }
        let detail = last.detail.split(separator: "\n").first.map(String.init) ?? ""
        return last.state == .running && !detail.isEmpty ? "\(last.title): \(detail)" : last.title
    }
}

final class HuddleStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var pending: [PendingRequest] = []
    @Published var serverError: String?
    // View state lives here: the Command Line Tools SDK ships without the @State macro plugin.
    @Published var expanded = false
    @Published var selected: String?
    @Published var picks: [UUID: Set<String>] = [:]

    /// A short note shown in the collapsed pill for a few seconds, e.g. "api: allow Bash?".
    @Published var notice: String?
    private var noticeToken = UUID()

    func notify(_ text: String) {
        let token = UUID()
        noticeToken = token
        notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.noticeToken == token { self?.notice = nil }
        }
    }

    /// Sessions in priority order: waiting on you first, then working, waiting for a new
    /// message, ended. Order within a group stays as it was, so rows don't jump around.
    var orderedSessions: [Session] {
        func rank(_ s: Session) -> Int {
            switch status(of: s) {
            case .needsYou: return 0
            case .working: return 1
            case .idle: return 2
            case .ended: return 3
            }
        }
        return sessions.enumerated()
            .sorted { rank($0.element) != rank($1.element) ? rank($0.element) < rank($1.element) : $0.offset < $1.offset }
            .map(\.element)
    }
    /// Bundle id of the frontmost app, so prompts go to the session when the user is already in it.
    var frontmostBundle: () -> String = { "" }
    /// How long a prompt may sit in the widget before it is handed to the session.
    var holdSeconds: TimeInterval = 90
    var pointerInside: () -> Bool = { false }
    /// Returns why a button action must be ignored, or nil when it came from a deliberate click.
    var clickProblem: (PendingRequest) -> String? = { _ in nil }

    /// Buttons on a prompt card act only on a real, deliberate mouse click.
    private func deliberate(_ p: PendingRequest, _ action: String) -> Bool {
        guard pending.contains(where: { $0.id == p.id }) else { return false }
        if let problem = clickProblem(p) {
            record(p, "Ignored \(action): \(problem)")
            return false
        }
        return true
    }
    var recent: [[String: Any]] = []
    private var lookedUp: Set<String> = []

    func session(_ id: String) -> Session? { sessions.first { $0.id == id } }
    func pending(for id: String) -> [PendingRequest] { pending.filter { $0.sessionID == id } }
    func status(of s: Session) -> SessionStatus { pending(for: s.id).isEmpty ? s.status : .needsYou }
    var needsYouCount: Int { sessions.filter { status(of: $0) == .needsYou }.count }

    // MARK: Incoming hook events

    func handle(_ req: HookRequest, _ responder: HookResponder) {
        let agent = Agent(header: req.headers["x-huddle-agent"])
        let raw = req.json
        recent.append(["headers": req.headers.filter { $0.key.hasPrefix("x-huddle-") && $0.key != "x-huddle-token" },
                       "json": raw])
        // Anything the widget can't use gets the agent's "carry on as normal" reply.
        guard let j = agent.adapter.normalize(raw),
              let sid = j["session_id"] as? String, !sid.isEmpty,
              let event = j["hook_event_name"] as? String else {
            responder.send(agent.adapter.reply(.handBack, raw: raw, event: [:]))
            return
        }
        let handBack = agent.adapter.reply(.handBack, raw: raw, event: j)
        let wait = req.headers["x-huddle-wait"] == "1"
        if recent.count > 150 { recent.removeFirst(recent.count - 150) }
        let tool = j["tool_name"] as? String ?? ""
        let input = j["tool_input"] as? [String: Any] ?? [:]

        update(sid) { s in
            s.agent = agent
            s.hooked = true
            // Cursor runs user hooks from ~/.cursor, so fall back to its bundle id for jumping.
            if agent == .cursor, s.bundleID.isEmpty, (req.headers["x-huddle-term"] ?? "").isEmpty {
                s.bundleID = "com.todesktop.230313mzl4w4u92"
            }
            if let cwd = j["cwd"] as? String, !cwd.isEmpty { s.cwd = cwd }
            if let t = j["session_title"] as? String, !t.isEmpty { s.title = t }
            if let b = req.headers["x-huddle-bundle"], !b.isEmpty { s.bundleID = b }
            if let t = req.headers["x-huddle-term"], !t.isEmpty { s.term = t }
            if let p = req.headers["x-huddle-project"], !p.isEmpty { s.project = p }
            // Only the desktop app's own hooks can report its session id; a CLI started from inside
            // a desktop session inherits the variable, so ignore it there.
            if let h = req.headers["x-huddle-host-session"], h.hasPrefix("local_"),
               req.headers["x-huddle-bundle"] == Jumper.desktopApp { s.hostSession = h }
            if let t = req.headers["x-huddle-tty"], !t.isEmpty, !t.contains("?") { s.tty = t }
            s.updatedAt = Date()
        }

        // First sight of a Claude Code session: take its title (and id) from the desktop app's
        // records, so sessions in the same folder don't all show the folder name.
        if agent == .claude, !lookedUp.contains(sid) {
            lookedUp.insert(sid)
            if let record = DesktopSessions.record(forCLISession: sid) {
                update(sid) { s in
                    if s.title.isEmpty { s.title = record.title }
                    if s.hostSession.isEmpty { s.hostSession = record.id }
                }
            }
        }

        // Blocking hooks: keep the connection open until the user decides.
        if wait {
            let isQuestion = tool == "AskUserQuestion"
            // Questions are answered from PreToolUse; everything else from PermissionRequest.
            guard (event == "PreToolUse" && isQuestion) || (event == "PermissionRequest" && !isQuestion) else {
                responder.send(handBack)
                return
            }
            // The user is already looking at the session's app: let it show its own prompt.
            let host = session(sid)?.hostBundle ?? ""
            if !host.isEmpty, host == frontmostBundle() {
                responder.send(handBack)
                update(sid) { s in
                    s.status = .needsYou
                    s.steps.append(Step(icon: isQuestion ? "questionmark.bubble" : "hand.raised",
                                        title: isQuestion ? "Asked you a question" : "Asked permission: \(tool)",
                                        detail: Self.summary(tool, input)))
                }
                return
            }
            let request = PendingRequest(
                sessionID: sid, toolName: tool, summary: Self.summary(tool, input), toolInput: input,
                questions: isQuestion ? Self.questions(input) : [], responder: responder,
                agent: agent, raw: raw, event: j)
            responder.onClose = { [weak self, weak request] in
                guard let self, let request else { return }
                self.pending.removeAll { $0.id == request.id }
                self.record(request, "\(request.agent.displayName) withdrew the prompt (decided in the session or by its own rules)")
            }
            pending.append(request)
            // Never open the widget or take focus: a short note in the pill is enough.
            notify("\(session(sid)?.name ?? "A session"): \(isQuestion ? "has a question" : "allow \(tool)?")")
            scheduleHandOff(request)
            return
        }

        responder.send(handBack)
        var needsNote = false
        update(sid) { s in
            switch event {
            case "SessionStart":
                s.status = .idle
                s.steps.append(Step(icon: "play.circle", title: "Session \(j["source"] as? String ?? "started")"))
            case "UserPromptSubmit":
                s.status = .working
                s.steps.append(Step(icon: "person.fill", title: "You", detail: j["prompt"] as? String ?? ""))
            case "PreToolUse":
                s.status = .working
                var detail = Self.summary(tool, input)
                if !s.cwd.isEmpty, detail.hasPrefix(s.cwd + "/") { detail.removeFirst(s.cwd.count + 1) }
                s.steps.append(Step(icon: Self.icon(tool), title: tool, detail: detail,
                                    state: .running, toolUseID: j["tool_use_id"] as? String))
            case "PostToolUse", "PostToolUseFailure":
                s.status = .working
                let id = j["tool_use_id"] as? String
                if let i = s.steps.lastIndex(where: { $0.state == .running && (id == nil || $0.toolUseID == id) }) {
                    s.steps[i].state = event == "PostToolUse" ? .done : .failed
                }
            case "Notification":
                let type = j["notification_type"] as? String ?? ""
                if type == "permission_prompt" || type == "elicitation_dialog" || type == "agent_needs_input" {
                    s.status = .needsYou
                    needsNote = true
                } else if type == "idle_prompt" {
                    s.status = .idle
                }
                s.steps.append(Step(icon: "bell", title: j["message"] as? String ?? "Notification"))
            case "Stop":
                s.status = .idle
                for i in s.steps.indices where s.steps[i].state == .running { s.steps[i].state = .done }
                s.steps.append(Step(icon: "checkmark.circle", title: "Finished its turn",
                                    detail: j["last_assistant_message"] as? String ?? ""))
            case "ToolRan":
                // Agents that only report finished tools (Cursor): one completed step.
                s.status = .working
                var detail = Self.summary(tool, input)
                if !s.cwd.isEmpty, detail.hasPrefix(s.cwd + "/") { detail.removeFirst(s.cwd.count + 1) }
                s.steps.append(Step(icon: Self.icon(tool), title: tool, detail: detail,
                                    state: (j["failed"] as? Bool ?? false) ? .failed : .done))
            case "AgentMessage":
                if let text = j["message"] as? String, !text.isEmpty {
                    s.steps.append(Step(icon: "text.bubble", title: "Replied", detail: text))
                }
            case "SubagentStop":
                s.steps.append(Step(icon: "person.2", title: "Subagent finished"))
            case "SessionEnd":
                s.status = .ended
                s.steps.append(Step(icon: "stop.circle", title: "Session ended"))
                // Closed sessions clear themselves; live ones stay until crossed off.
                DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
                    if self?.session(sid)?.status == .ended { self?.crossOff(sid) }
                }
            default:
                break
            }
            if s.steps.count > 300 { s.steps.removeFirst(s.steps.count - 300) }
        }
        if needsNote, let s = session(sid) { notify("\(s.name): needs you") }
        // The tool ran or the turn ended, so any prompt for it was answered elsewhere.
        if ["PostToolUse", "PostToolUseFailure", "Stop", "SessionEnd", "UserPromptSubmit"].contains(event) {
            for p in pending(for: sid) {
                p.responder.send(p.agent.adapter.reply(.handBack, raw: p.raw, event: p.event))
                record(p, "Prompt closed: the session moved on (\(event))")
            }
            pending.removeAll { $0.sessionID == sid }
        }
    }

    /// Every way a prompt card leaves the widget is written to the timeline and to huddle.log.
    func record(_ p: PendingRequest, _ cause: String) {
        update(p.sessionID) { $0.steps.append(Step(icon: "info.circle", title: cause)) }
        HuddleConfig.log("\(session(p.sessionID)?.name ?? p.sessionID) \(p.toolName): \(cause)")
    }

    /// Merges Claude Code's own session records: adds running sessions the hooks haven't
    /// reported, keeps statuses current, and ends sessions whose process has gone.
    func applyDiscovered(_ found: [DiscoveredSession]) {
        let live = Set(found.map(\.id))
        for d in found {
            let isNew = session(d.id) == nil
            update(d.id) { s in
                s.pid = d.pid
                if s.cwd.isEmpty { s.cwd = d.cwd }
                if !d.name.isEmpty { s.title = d.name }
                if s.hostSession.isEmpty { s.hostSession = d.hostSession }
                if s.bundleID.isEmpty { s.bundleID = d.bundleID }
                if s.term.isEmpty { s.term = d.term }
                if s.tty.isEmpty { s.tty = d.tty }
                // Claude Code's own busy/idle is the truth for sessions without hooks; with
                // hooks, keep the finer status they give (e.g. waiting on you).
                if !s.hooked || s.status == .ended { s.status = d.status }
                if isNew, !s.hooked {
                    s.steps.append(Step(icon: "eye", title: "Found running",
                                        detail: "Started before Agent Huddle's hooks were installed: restart it to see its steps and answer its prompts here."))
                }
            }
        }
        // Discovered sessions whose process is gone: ended.
        for s in sessions where s.agent == .claude && s.pid != 0 && !live.contains(s.id) && s.status != .ended {
            update(s.id) { $0.status = .ended }
            let id = s.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
                if self?.session(id)?.status == .ended { self?.crossOff(id) }
            }
        }
    }

    private func update(_ id: String, _ change: (inout Session) -> Void) {
        if let i = sessions.firstIndex(where: { $0.id == id }) {
            change(&sessions[i])
        } else {
            var s = Session(id: id, cwd: "", title: "")
            change(&s)
            sessions.append(s)
        }
    }

    // MARK: User actions

    func allow(_ p: PendingRequest) {
        guard deliberate(p, "Allow") else { return }
        finish(p, .allow, note: "You allowed \(p.toolName)")
    }

    func deny(_ p: PendingRequest) {
        guard deliberate(p, "Deny") else { return }
        finish(p, .deny, note: "You denied \(p.toolName)")
    }

    func answer(_ p: PendingRequest, _ answers: [String: String]) {
        guard deliberate(p, "Send answer") else { return }
        finish(p, .answer(answers), note: "You answered: " + answers.values.sorted().joined(separator: "; "))
    }

    /// Hand the prompt back to the agent's own dialog.
    func passThrough(_ p: PendingRequest, cause: String = "You chose to decide in the session") {
        finish(p, .handBack, note: nil)
        record(p, cause)
        update(p.sessionID) { $0.status = .needsYou }
    }

    /// After the hold time an unanswered prompt goes to the session's own dialog, but never
    /// while the pointer is over the widget: nothing may change under the user's cursor.
    private func scheduleHandOff(_ request: PendingRequest) {
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) { [weak self, weak request] in
            guard let self, let request, self.pending.contains(where: { $0.id == request.id }) else { return }
            if self.pointerInside() { self.scheduleHandOff(request) } else { self.passThrough(request, cause: "Handed to the session: no answer in the widget") }
        }
    }

    func decideInSession(_ p: PendingRequest) {
        guard deliberate(p, "Decide in session") else { return }
        passThrough(p)
    }

    /// The user switched to an app: prompts from sessions it hosts move there.
    func appActivated(_ bundle: String) {
        for p in pending where session(p.sessionID)?.hostBundle == bundle { passThrough(p, cause: "Handed to the session: you switched to its app") }
    }

    private func finish(_ p: PendingRequest, _ decision: Decision, note: String?) {
        p.responder.send(p.agent.adapter.reply(decision, raw: p.raw, event: p.event))
        pending.removeAll { $0.id == p.id }
        if let note { record(p, note + " (button click)") }
        if case .handBack = decision { return }
        update(p.sessionID) { $0.status = .working }
    }

    func crossOff(_ id: String) {
        for p in pending(for: id) { p.responder.send(p.agent.adapter.reply(.handBack, raw: p.raw, event: p.event)) }
        pending.removeAll { $0.sessionID == id }
        sessions.removeAll { $0.id == id }
    }

    // MARK: Helpers

    static func json(_ object: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func questions(_ input: [String: Any]) -> [Question] {
        (input["questions"] as? [[String: Any]] ?? []).map { q in
            Question(question: q["question"] as? String ?? "",
                     header: q["header"] as? String ?? "",
                     options: (q["options"] as? [[String: Any]] ?? []).map {
                         ($0["label"] as? String ?? "", $0["description"] as? String ?? "")
                     },
                     multiSelect: q["multiSelect"] as? Bool ?? false)
        }
    }

    static func summary(_ tool: String, _ input: [String: Any]) -> String {
        for key in ["command", "file_path", "pattern", "url", "query", "description", "prompt", "skill"] {
            if let v = input[key] as? String, !v.isEmpty { return v }
        }
        if let qs = input["questions"] as? [[String: Any]] {
            return qs.compactMap { $0["question"] as? String }.joined(separator: "\n")
        }
        return input.isEmpty ? "" : json(input)
    }

    static func icon(_ tool: String) -> String {
        switch tool {
        case "Bash", "Shell", "exec_command", "shell": return "terminal"
        case "Delete": return "trash"
        case "apply_patch": return "pencil"
        case "Read": return "doc.text"
        case "Edit", "Write", "NotebookEdit": return "pencil"
        case "Grep", "Glob": return "magnifyingglass"
        case "WebFetch", "WebSearch": return "globe"
        case "Agent", "Task": return "person.2"
        default: return "wrench.and.screwdriver"
        }
    }
}
