import AppKit

/// Brings the window that hosts a session to the front.
enum Jumper {
    static let editors = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
                          "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf"]

    static func jump(to session: Session) {
        var s = session
        // Claude desktop sessions: use the app's own id, looked up from its records if the
        // hooks didn't report it, so the exact session opens.
        if s.agent == .claude, s.hostBundle == desktopApp || s.hostBundle.isEmpty,
           let local = DesktopSessions.localID(forCLISession: s.id) {
            s.hostSession = local
            s.bundleID = desktopApp
        }
        HuddleConfig.log("jump \(s.name) [\(s.id)]: \(method(for: s))")
        perform(s)
    }

    static let desktopApp = "com.anthropic.claudefordesktop"

    /// What the jump button will do, in plain words, for its tooltip.
    static func help(for s: Session) -> String {
        if s.term == "Apple_Terminal", !s.tty.isEmpty { return "Switch to its Terminal tab" }
        if s.term == "iTerm.app", !s.tty.isEmpty { return "Switch to its iTerm tab" }
        if s.agent == .codex, ["com.openai.codex", "com.openai.chat"].contains(s.hostBundle) { return "Open this thread in Codex" }
        if s.agent == .claude, s.hostBundle == desktopApp || s.hostBundle.isEmpty { return "Open this session in Claude" }
        if editors.contains(s.hostBundle) { return "Bring its editor window to the front" }
        if !s.hostBundle.isEmpty {
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: s.hostBundle)
                .map { $0.deletingPathExtension().lastPathComponent } ?? s.hostBundle
            return "Bring \(name) to the front (it can't open a specific session)"
        }
        return "Nothing to jump to: the session didn't say where it runs"
    }

    /// Describes how jump reaches a session, for the log.
    static func method(for s: Session) -> String {
        if s.term == "Apple_Terminal", !s.tty.isEmpty { return "Terminal tab \(s.tty)" }
        if s.term == "iTerm.app", !s.tty.isEmpty { return "iTerm tab \(s.tty)" }
        if s.agent == .codex, ["com.openai.codex", "com.openai.chat"].contains(s.hostBundle) { return "codex://threads/\(s.id)" }
        if s.hostBundle == desktopApp, !s.hostSession.isEmpty { return "claude://code/continue?session=\(s.hostSession)" }
        if editors.contains(s.hostBundle) { return "open -b \(s.hostBundle) \(s.project.isEmpty ? s.cwd : s.project)" }
        if !s.hostBundle.isEmpty { return "activate \(s.hostBundle) only" }
        return "nothing known to open"
    }

    private static func perform(_ s: Session) {
        let tty = s.tty.isEmpty ? "" : "/dev/" + s.tty
        if s.term == "Apple_Terminal", !tty.isEmpty {
            osascript("""
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    activate
                    return
                  end if
                end repeat
              end repeat
              activate
            end tell
            """)
        } else if s.term == "iTerm.app", !tty.isEmpty {
            osascript("""
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with x in sessions of t
                    if tty of x is "\(tty)" then
                      select w
                      select t
                      select x
                      activate
                      return
                    end if
                  end repeat
                end repeat
              end repeat
              activate
            end tell
            """)
        } else if s.agent == .codex, ["com.openai.codex", "com.openai.chat"].contains(s.hostBundle) {
            // The Codex app opens a local thread by its id, which is the hook's session_id.
            run("/usr/bin/open", ["codex://threads/\(s.id)"])
        } else if s.hostBundle == desktopApp, !s.hostSession.isEmpty {
            // The desktop app's own deep link opens this exact session.
            run("/usr/bin/open", ["claude://code/continue?session=\(s.hostSession)"])
        } else if editors.contains(s.hostBundle) {
            // Reopening the folder focuses the editor window that already has it open.
            run("/usr/bin/open", ["-b", s.hostBundle, s.project.isEmpty ? s.cwd : s.project])
        } else if !s.hostBundle.isEmpty {
            run("/usr/bin/open", ["-b", s.hostBundle])
        }
    }

    private static func osascript(_ source: String) { run("/usr/bin/osascript", ["-e", source]) }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }
}
