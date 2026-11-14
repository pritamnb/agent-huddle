import AppKit
import SwiftUI
import Combine

final class HuddlePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = HuddleStore()
    var server: HookServer!
    var panel: HuddlePanel!
    var statusItem: NSStatusItem!
    var hosting: NSHostingView<AnyView>!
    var sizeWatch: AnyCancellable?
    var lastDown: Date?
    var debugClick = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = HuddleConfig.load()
        server = HookServer(port: config.port, token: config.token)
        server.onRequest = { [weak self] request, responder in
            guard let self else { return }
            if request.path == "/hook" { self.store.handle(request, responder) } else { self.debug(request, responder) }
        }
        store.frontmostBundle = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "" }
        store.pointerInside = { [weak self] in self?.panel.frame.contains(NSEvent.mouseLocation) ?? false }
        // Remember real mouse-downs so card buttons can tell a click from anything else.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if event.window === self?.panel { self?.lastDown = Date() }
            return event
        }
        store.clickProblem = { [weak self] request in
            guard let self else { return nil }
            if self.debugClick { return nil }
            let type = NSApp.currentEvent?.type
            guard type == .leftMouseUp else { return "not a mouse click (event \(type.map { String($0.rawValue) } ?? "none"))" }
            guard let down = self.lastDown, Date().timeIntervalSince(down) < 5 else { return "no mouse press on the widget" }
            guard down.timeIntervalSince(request.created) > 0.7 else { return "clicked before the card had been visible for a moment" }
            return nil
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let bundle = app?.bundleIdentifier { self?.store.appActivated(bundle) }
        }
        do { try server.start() } catch {
            store.serverError = "Port \(config.port) is busy"
        }

        panel = HuddlePanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 40),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Clicking the widget never takes keyboard focus from the window you're working in.
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        hosting = NSHostingView(rootView: AnyView(RootView().environmentObject(store)))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.wantsLayer = true
        panel.contentView = hosting

        // Start in the bottom-right of the primary screen, or wherever the user last dragged it.
        let screen = NSScreen.screens.first?.visibleFrame ?? .zero
        var corner = NSPoint(x: screen.maxX - 16, y: screen.minY + 16)
        if let saved = UserDefaults.standard.array(forKey: "corner") as? [Double], saved.count == 2,
           NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(NSPoint(x: saved[0] - 20, y: saved[1] + 20)) }) {
            corner = NSPoint(x: saved[0], y: saved[1])
        }
        panel.setFrame(NSRect(x: corner.x - 160, y: corner.y, width: 160, height: 40), display: false)
        fit()
        panel.orderFrontRegardless()
        // Refit after every state change; the content decides the size.
        sizeWatch = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fit() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let f = self?.panel.frame else { return }
            UserDefaults.standard.set([Double(f.maxX), Double(f.minY)], forKey: "corner")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "person.3.fill", accessibilityDescription: "Agent Huddle")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show widget", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Agent Huddle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// Menu bar "Show widget": bring it back to the corner of the primary screen.
    @objc func showPanel() {
        if let screen = NSScreen.screens.first?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 16, y: screen.minY + 16))
        }
        panel.orderFrontRegardless()
    }

    func fit() {
        hosting.layoutSubtreeIfNeeded()
        resize(to: hosting.fittingSize)
    }

    /// Grow and shrink from the bottom-right corner so the widget stays put.
    func resize(to size: CGSize) {
        let old = panel.frame
        guard size.width > 0, size.height > 0, size != old.size else { return }
        panel.setFrame(NSRect(x: old.maxX - size.width, y: old.minY, width: size.width, height: size.height),
                       display: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
