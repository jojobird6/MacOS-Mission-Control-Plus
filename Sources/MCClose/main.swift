import Cocoa

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = MissionControlMonitor()
    private let overlay = Overlay()
    private let hotkeys = Hotkeys()
    private var statusItem: NSStatusItem!
    private var trackTimer: Timer?
    private var windows: [ScreenWindow] = []
    /// Windows we've asked to close; ignored until Mission Control re-lays out.
    private var closing: Set<CGWindowID> = []
    private var hotkeysStarted = false

    private var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        overlay.onClose = { [weak self] window in self?.perform(.close, on: window) }
        hotkeys.isActive = { [weak self] in self?.isTracking ?? false }
        hotkeys.handler = { [weak self] command in self?.handleHotkey(command) ?? false }
        monitor.onChange = { [weak self] active in self?.missionControlChanged(active) }
        ensurePermissionThenStart()
    }

    private var isTracking: Bool { trackTimer != nil }

    // MARK: Permission

    private func ensurePermissionThenStart() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            start()
            return
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.start()
        }
    }

    private func start() {
        hotkeysStarted = hotkeys.start()
        if !hotkeysStarted { NSLog("MCClose: failed to create key event tap") }
        monitor.start()
    }

    // MARK: Tracking

    private func missionControlChanged(_ active: Bool) {
        if active && enabled {
            closing.removeAll()
            trackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.track() }
            RunLoop.main.add(trackTimer!, forMode: .common)
            track()
        } else {
            trackTimer?.invalidate()
            trackTimer = nil
            overlay.hide()
            windows = []
        }
    }

    private func track() {
        windows = WindowScanner.visibleWindows().filter { !closing.contains($0.id) }
        let mouse = NSEvent.mouseLocation
        let current = overlay.target.flatMap { t in windows.first { $0.id == t.id } }
        if let current, overlay.contains(mouse) {
            overlay.show(for: current)
        } else if let hovered = WindowScanner.window(at: mouse, in: windows) {
            overlay.show(for: hovered)
        } else {
            overlay.hide()
        }
    }

    private var hoveredWindow: ScreenWindow? {
        overlay.target ?? WindowScanner.window(at: NSEvent.mouseLocation, in: windows)
    }

    // MARK: Actions

    private func handleHotkey(_ command: Hotkeys.Command) -> Bool {
        guard let window = hoveredWindow else {
            return false
        }
        DispatchQueue.main.async { self.perform(command, on: window) }
        return true
    }

    private func perform(_ command: Hotkeys.Command, on window: ScreenWindow) {
        switch command {
        case .close:
            closing.insert(window.id)
            Actions.closeWindow(window)
        case .closeAll:
            windows.filter { $0.pid == window.pid }.forEach { closing.insert($0.id) }
            Actions.closeAllWindows(of: window.pid)
        case .minimize:
            Actions.minimize(window)
        case .minimizeAll:
            Actions.minimizeAll(of: window.pid)
        case .hide:
            Actions.hide(pid: window.pid)
        case .hideOthers:
            Actions.hideOthers(except: window.pid)
        case .quit:
            windows.filter { $0.pid == window.pid }.forEach { closing.insert($0.id) }
            Actions.quit(pid: window.pid)
        case .open:
            overlay.hide()
            Actions.open(window)
        }
        overlay.hide()
        track()
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "xmark.rectangle", accessibilityDescription: "MCClose")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "MCClose — close from Mission Control", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)

        if !AXIsProcessTrusted() {
            let perm = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(openAccessibility), keyEquivalent: "")
            perm.target = self
            menu.addItem(perm)
        } else if !hotkeysStarted {
            let item = NSMenuItem(title: "Keyboard shortcuts unavailable", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let title = NSMenuItem(title: "In Mission Control, hover a window and press:", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        for (keys, desc) in Hotkeys.reference {
            let item = NSMenuItem(title: "\(keys)\t\(desc)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MCClose", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        if !enabled { missionControlChanged(false) }
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
