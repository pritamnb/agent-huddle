import AppKit

/// Token-guarded inspection endpoints so the widget can be checked without screen access:
/// /debug/state, /debug/events, /debug/shot?path=, /debug/click?x=&y= (top-left origin), /debug/open?id=.
extension AppDelegate {
    func debug(_ req: HookRequest, _ responder: HookResponder) {
        switch req.path {
        case "/debug/state":
            let f = panel.frame
            let screen = panel.screen?.visibleFrame ?? .zero
            responder.send(HuddleStore.json([
                "frame": [f.minX, f.minY, f.width, f.height],
                "screenVisible": [screen.minX, screen.minY, screen.width, screen.height],
                "visible": panel.isVisible,
                "key": panel.isKeyWindow,
                "notice": store.notice ?? "",
                "order": store.orderedSessions.map(\.name),
                "expanded": store.expanded,
                "selected": store.selected ?? "",
                "frontmost": store.frontmostBundle(),
                "sessions": store.sessions.map { s in
                    ["id": s.id, "agent": s.agent.rawValue, "name": s.name, "cwd": s.cwd, "project": s.project, "hostSession": s.hostSession, "host": s.hostBundle,
                     "term": s.term, "tty": s.tty, "status": store.status(of: s).label,
                     "steps": s.steps.map { "\($0.state) | \($0.title) | \($0.detail.prefix(80))" }]
                },
                "pending": store.pending.map { ["session": $0.sessionID, "tool": $0.toolName, "summary": $0.summary] },
            ]))
        case "/debug/open":
            // Opens a session's view, as a click on its row would (for scripted tests).
            store.expanded = true
            store.selected = req.query["id"]
            responder.send("{\"opened\":true}")
        case "/debug/events":
            responder.send(HuddleStore.json(["events": store.recent]))
        case "/debug/shot":
            guard let view = panel.contentView, let layer = view.layer else { responder.send("{}"); return }
            let size = view.bounds.size
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor(white: 0.16, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            if let ctx = NSGraphicsContext.current?.cgContext {
                if view.isFlipped { ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1) }
                layer.render(in: ctx)
            }
            image.unlockFocus()
            let path = req.query["path"] ?? NSTemporaryDirectory() + "huddle-shot.png"
            if let tiff = image.tiffRepresentation, let out = NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]) {
                try? out.write(to: URL(fileURLWithPath: path))
            }
            responder.send(HuddleStore.json(["path": path]))
        case "/debug/click":
            let x = Double(req.query["x"] ?? "") ?? 0, y = Double(req.query["y"] ?? "") ?? 0
            let point = NSPoint(x: x, y: Double(panel.frame.height) - y)
            debugClick = true
            defer { debugClick = false }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: panel.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 1, pressure: 1) {
                    panel.sendEvent(e)
                }
            }
            responder.send("{\"clicked\":true}")
        default:
            responder.send("", status: "404 Not Found")
        }
    }
}
