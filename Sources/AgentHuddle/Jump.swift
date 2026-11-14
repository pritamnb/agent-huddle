import AppKit

/// Brings the window that hosts a session to the front.
enum Jumper {
    static let editors = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
                          "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf"]

    static func jump(to s: Session) {
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
        } else if s.hostBundle == "com.anthropic.claudefordesktop", !s.hostSession.isEmpty {
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
