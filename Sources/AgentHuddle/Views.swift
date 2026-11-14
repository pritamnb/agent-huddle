import AppKit
import SwiftUI

struct Blur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct RootView: View {
    @EnvironmentObject var store: HuddleStore

    var body: some View {
        Group {
            if !store.expanded {
                pill
            } else if let id = store.selected, let session = store.session(id) {
                DetailView(session: session, back: { store.selected = nil })
            } else {
                list
            }
        }
        .frame(width: store.expanded ? 340 : nil)
        .background(Blur())
        .clipShape(RoundedRectangle(cornerRadius: store.expanded ? 14 : 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: store.expanded ? 14 : 20, style: .continuous)
            .strokeBorder(.white.opacity(0.15)))
        .fixedSize()
        .preferredColorScheme(.dark)
    }

    var pill: some View {
        HStack(spacing: 0) {
          Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(.tertiary)
            .frame(width: 22, height: 33).help("Drag to move")
          Button { store.expanded = true } label: {
            HStack(spacing: 6) {
                if store.sessions.isEmpty {
                    Circle().fill(.gray).frame(width: 8, height: 8)
                } else {
                    ForEach(store.orderedSessions.prefix(6)) { s in
                        Circle().fill(store.status(of: s).color).frame(width: 8, height: 8)
                    }
                }
                Text(store.notice ?? pillText).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(store.notice == nil ? Color.primary : Color.orange)
                    .lineLimit(1).frame(maxWidth: 260, alignment: .leading).fixedSize()
            }
            .padding(.trailing, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
    }

    var pillText: String {
        if let error = store.serverError { return error }
        if store.needsYouCount > 0 { return "\(store.needsYouCount) need\(store.needsYouCount == 1 ? "s" : "") you" }
        let n = store.sessions.count
        return n == 0 ? "No agents" : "\(n) agent\(n == 1 ? "" : "s")"
    }

    var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent Huddle").font(.system(size: 13, weight: .semibold))
                Spacer()
                IconButton("chevron.down", help: "Collapse") { store.expanded = false }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider()
            if store.sessions.isEmpty {
                Text("No agents yet. Sessions appear here on their next step.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.orderedSessions) { s in
                            SessionRow(session: s, open: { store.selected = s.id })
                        }
                    }
                }
                .frame(height: min(CGFloat(store.sessions.count) * 52, 364))
            }
        }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    init(_ symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.help = help; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).help(help)
    }
}

struct SessionRow: View {
    @EnvironmentObject var store: HuddleStore
    let session: Session
    let open: () -> Void

    /// What the row is waiting on, when it's waiting on you; otherwise its latest step.
    func subtitle(_ status: SessionStatus) -> String {
        if let p = store.pending(for: session.id).first {
            let what = p.isQuestion ? "Question: \(p.summary)" : "Allow \(p.toolName)? \(p.summary)"
            return what.replacingOccurrences(of: "\n", with: " ")
        }
        return status == .needsYou ? "Needs you: \(session.activity)" : session.activity
    }

    var body: some View {
        let status = store.status(of: session)
        HStack(spacing: 10) {
            // A real button, so a click is never mistaken for dragging the window.
            Button(action: open) {
                HStack(spacing: 10) {
                    Circle().fill(status.color).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(session.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            AgentTag(agent: session.agent)
                        }
                        Text(subtitle(status))
                            .font(.system(size: 11)).foregroundStyle(status == .needsYou ? .orange : .secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .frame(maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            IconButton("arrow.up.forward.app", help: Jumper.help(for: session)) { Jumper.jump(to: session) }
            IconButton("checkmark", help: "Cross off") { store.crossOff(session.id) }
        }
        .padding(.horizontal, 12).frame(height: 52)
    }
}

struct DetailView: View {
    @EnvironmentObject var store: HuddleStore
    let session: Session
    let back: () -> Void
    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                IconButton("chevron.left", help: "All agents", action: back)
                Circle().fill(store.status(of: session).color).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(session.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        AgentTag(agent: session.agent)
                    }
                    Text(session.cwd).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 4)
                IconButton("arrow.up.forward.app", help: Jumper.help(for: session)) { Jumper.jump(to: session) }
                IconButton("checkmark", help: "Cross off") { store.crossOff(session.id); back() }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            Divider()
            ForEach(store.pending(for: session.id)) { p in
                PendingCard(request: p)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(session.steps) { step in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: step.icon).font(.system(size: 11))
                                    .foregroundStyle(color(step.state)).frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(step.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                        Spacer(minLength: 4)
                                        if step.state == .running { ProgressView().controlSize(.mini) }
                                        Text(Self.clock.string(from: step.time))
                                            .font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
                                    }
                                    if !step.detail.isEmpty {
                                        Text(step.detail).font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary).lineLimit(4)
                                    }
                                }
                            }
                            .id(step.id)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 300)
                .onAppear { proxy.scrollTo(session.steps.last?.id, anchor: .bottom) }
                .onChange(of: session.steps.count) { _ in
                    proxy.scrollTo(session.steps.last?.id, anchor: .bottom)
                }
            }
        }
    }

    func color(_ state: StepState) -> Color {
        switch state {
        case .info: return .secondary
        case .running: return .green
        case .done: return .secondary
        case .failed: return .red
        }
    }
}

struct PendingCard: View {
    @EnvironmentObject var store: HuddleStore
    let request: PendingRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if request.isQuestion {
                ForEach(request.questions) { q in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(q.question).font(.system(size: 12, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(q.options, id: \.label) { option in
                            let on = store.picks[q.id, default: []].contains(option.label)
                            Button { toggle(q, option.label) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.label).font(.system(size: 12, weight: .medium))
                                    if !option.description.isEmpty {
                                        Text(option.description).font(.system(size: 10))
                                            .foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(on ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.08)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Button("Send answer") { store.answer(request, answers) }
                        .buttonStyle(.borderedProminent)
                        .disabled(request.questions.contains { store.picks[$0.id, default: []].isEmpty })
                    Button("Answer in session") { store.decideInSession(request) }
                }
                .controlSize(.small)
            } else {
                Text("Allow \(request.toolName)?").font(.system(size: 12, weight: .semibold))
                if !request.summary.isEmpty {
                    Text(request.summary).font(.system(size: 11, design: .monospaced))
                        .lineLimit(6).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.3)))
                }
                HStack {
                    Button("Allow") { store.allow(request) }.buttonStyle(.borderedProminent)
                    Button("Deny") { store.deny(request) }
                    Button("Decide in session") { store.decideInSession(request) }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }

    var answers: [String: String] {
        var out: [String: String] = [:]
        for q in request.questions {
            let chosen = store.picks[q.id, default: []]
            out[q.question] = q.options.map(\.label).filter(chosen.contains).joined(separator: ", ")
        }
        return out
    }

    func toggle(_ q: Question, _ label: String) {
        var set = store.picks[q.id, default: []]
        if q.multiSelect {
            if set.contains(label) { set.remove(label) } else { set.insert(label) }
        } else {
            set = [label]
        }
        store.picks[q.id] = set
    }
}

/// Small label naming the tool a session runs in.
struct AgentTag: View {
    let agent: Agent
    var body: some View {
        Text(agent.displayName)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.25)))
            .foregroundStyle(color)
            .fixedSize()
    }
    var color: Color {
        switch agent {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.55, green: 0.75, blue: 1.0)
        case .cursor: return Color(white: 0.85)
        }
    }
}
