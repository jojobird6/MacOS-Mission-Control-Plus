import Cocoa
import MCCloseCore

/// An action whose effect is held back until Mission Control may rearrange, and what it hides meanwhile.
private struct PendingCommand {
    let command: Hotkeys.Command
    let target: HoverTarget
    let hiddenWindows: Set<CGWindowID>
    let hidesDockIcon: Bool
}

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = MissionControlMonitor()
    private let overlay = Overlay()
    private let hotkeys = Hotkeys()
    private let covers = Covers()
    private var statusItem: NSStatusItem!
    private var trackTimer: Timer?
    /// Every window thumbnail on screen, including covered ones.
    private var allWindows: [ScreenWindow] = []
    /// Thumbnails that can be hovered.
    private var windows: [ScreenWindow] = []
    /// Every running app in the Dock, including covered ones.
    private var allDockApps: [DockApp] = []
    /// Dock icons that can be hovered.
    private var dockApps: [DockApp] = []
    private var dockScannedAt = Date.distantPast
    /// Windows we've asked to close; ignored until Mission Control re-lays out.
    private var closing: Set<CGWindowID> = []
    /// Apps we've asked to quit; their Dock icons are ignored for the rest of this Mission Control session.
    private var quitting: Set<pid_t> = []
    private var hotkeysStarted = false

    private var pending = PendingQueue<PendingCommand>()
    /// Mission Control's backdrop, used to paint over thumbnails whose action is pending.
    private var backgrounds: [CapturedBackground] = []
    private var captureTask: Task<Void, Never>?
    /// Covers kept after their action ran, until the window or icon is gone, so it never flashes back into view.
    private var committedCovers: [Covers.Key: Date] = [:]
    private static let committedCoverTimeout: TimeInterval = 2
    /// Lets Mission Control finish sliding in the Spaces bar and Dock before capturing its backdrop.
    private static let captureDelay: Duration = .milliseconds(400)

    private var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    /// When off, actions take effect immediately and Screen Recording is never needed or requested.
    private var keepWindowsInPlace: Bool {
        get { UserDefaults.standard.object(forKey: "keepWindowsInPlace") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "keepWindowsInPlace") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        overlay.onClose = { [weak self] target in
            switch target {
            case .window: self?.request(.close, on: target)
            case .dockApp: self?.request(.quit, on: target)
            }
        }
        hotkeys.isActive = { [weak self] in self?.isTracking ?? false }
        hotkeys.handler = { [weak self] command in self?.handleHotkey(command) ?? false }
        monitor.onChange = { [weak self] active in self?.missionControlChanged(active) }
        ensurePermissionThenStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        commit(pending.commitAll())
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
        // Screen Recording is what lets a closed window look gone while the rest of Mission Control holds still.
        // Without it, actions take effect immediately.
        if #available(macOS 14, *), keepWindowsInPlace, !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        monitor.start()
    }

    /// Whether actions can be held back, which needs a captured backdrop to hide their thumbnails.
    private var canDefer: Bool {
        guard #available(macOS 14, *), keepWindowsInPlace, CGPreflightScreenCaptureAccess() else { return false }
        return !backgrounds.isEmpty || captureTask != nil
    }

    // MARK: Tracking

    private func missionControlChanged(_ active: Bool) {
        if active && enabled {
            closing.removeAll()
            quitting.removeAll()
            dockScannedAt = .distantPast
            captureBackground()
            trackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.track() }
            RunLoop.main.add(trackTimer!, forMode: .common)
            track()
        } else {
            trackTimer?.invalidate()
            trackTimer = nil
            // Mission Control is gone, so nothing can rearrange any more.
            commit(pending.commitAll())
            captureTask?.cancel()
            captureTask = nil
            backgrounds = []
            committedCovers.removeAll()
            covers.removeAll()
            overlay.hide()
            allWindows = []
            windows = []
            allDockApps = []
            dockApps = []
        }
    }

    private func captureBackground() {
        guard #available(macOS 14, *), keepWindowsInPlace, CGPreflightScreenCaptureAccess() else { return }
        captureTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.captureDelay)
            guard !Task.isCancelled else { return }
            do {
                let captured = try await BackgroundCapture.capture()
                guard !Task.isCancelled, let self else { return }
                self.backgrounds = captured
                debugLog("captured backdrop for \(captured.count) display(s)")
            } catch {
                NSLog("MCClose: couldn't capture the Mission Control backdrop, so actions will take effect immediately: %@",
                      String(describing: error))
            }
            guard let self, !Task.isCancelled else { return }
            self.captureTask = nil
            // Anything queued while capturing can't be hidden after all.
            if self.backgrounds.isEmpty { self.commit(self.pending.commitAll()) }
            self.track()
        }
    }

    private var coveredWindowIDs: Set<CGWindowID> {
        pending.hiddenWindowIDs.union(committedCovers.keys.compactMap { if case .window(let id) = $0 { id } else { nil } })
    }

    private func track() {
        allWindows = WindowScanner.visibleWindows()
        let mouse = NSEvent.mouseLocation
        scanDockIfNeeded(mouse: mouse)
        commitIfDue(mouse: mouse)
        let covered = coveredWindowIDs
        windows = allWindows.filter { !closing.contains($0.id) && !covered.contains($0.id) }
        updateCovers()
        if let current = refreshed(overlay.target), overlay.contains(mouse) {
            overlay.show(for: current)
        } else if let hovered = target(at: mouse) {
            overlay.show(for: hovered)
        } else {
            overlay.hide()
        }
    }

    private func commitIfDue(mouse: NSPoint) {
        guard !pending.isEmpty else { return }
        let area = CoverGeometry.activeArea(thumbnails: allWindows.map(\.frame), dockItems: allDockApps.map(\.frame))
        commit(pending.commitIfDue(now: Date(), commandHeld: Self.commandHeld, pointerInActiveArea: area.contains(mouse)))
    }

    private static var commandHeld: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
    }

    /// Dock icons rarely move, so rescan them slowly unless the pointer is near the Dock, where icons may slide or
    /// magnify and the overlay needs every frame to tell when they've settled.
    private func scanDockIfNeeded(mouse: NSPoint) {
        let nearDock = dockApps.reduce(NSRect.null) { $0.union($1.frame) }.insetBy(dx: -40, dy: -40).contains(mouse)
        let interval: TimeInterval = nearDock ? 0 : 0.5
        guard Date().timeIntervalSince(dockScannedAt) >= interval else { return }
        dockScannedAt = Date()
        allDockApps = DockScanner.runningApps()
        dockApps = allDockApps.filter { !quitting.contains($0.pid) }
    }

    private func updateCovers() {
        let now = Date()
        committedCovers = committedCovers.filter { key, committedAt in
            guard now.timeIntervalSince(committedAt) < Self.committedCoverTimeout else { return false }
            switch key {
            case .window(let id): return allWindows.contains { $0.id == id }
            case .dockApp(let pid): return allDockApps.contains { $0.pid == pid }
            }
        }
        let coveredWindows = coveredWindowIDs
        let coveredApps = pending.hiddenAppPIDs.union(committedCovers.keys.compactMap { if case .dockApp(let pid) = $0 { pid } else { nil } })
        let neighbors = allWindows.filter { !coveredWindows.contains($0.id) }.map(\.frame)
        var items: [Covers.Item] = []
        for window in allWindows where coveredWindows.contains(window.id) {
            let rect = CoverGeometry.coverRect(for: window.frame).integral
            guard let background = background(containing: window.frame), let visible = background.visiblePart(of: rect) else { continue }
            items.append(Covers.Item(key: .window(window.id), frame: visible,
                                     holes: CoverGeometry.holes(in: visible, neighbors: neighbors),
                                     image: { background.crop(visible) }))
        }
        for app in allDockApps where coveredApps.contains(app.pid) {
            let gap = CapturedBackground.dockGapRect(for: app.frame)
            guard let background = background(containing: app.frame), background.visiblePart(of: gap) == gap else { continue }
            items.append(Covers.Item(key: .dockApp(app.pid), frame: gap, holes: [], image: { background.dockGap(gap) }))
        }
        covers.update(items)
    }

    private func background(containing rect: NSRect) -> CapturedBackground? {
        backgrounds.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }
    }

    /// The target with its current frame, or nil if it's gone.
    private func refreshed(_ target: HoverTarget?) -> HoverTarget? {
        switch target {
        case .window(let w): return windows.first { $0.id == w.id }.map(HoverTarget.window)
        case .dockApp(let a): return dockApps.first { $0.pid == a.pid && $0.frame.intersects(a.frame) }.map(HoverTarget.dockApp)
        case nil: return nil
        }
    }

    /// Dock icons are checked first because the Dock draws above window thumbnails.
    private func target(at point: NSPoint) -> HoverTarget? {
        if let app = DockScanner.app(at: point, in: dockApps) { return .dockApp(app) }
        return WindowScanner.window(at: point, in: windows).map(HoverTarget.window)
    }

    private var hoveredTarget: HoverTarget? {
        overlay.target ?? target(at: NSEvent.mouseLocation)
    }

    // MARK: Actions

    private func handleHotkey(_ command: Hotkeys.Command) -> Bool {
        guard let target = hoveredTarget else { return false }
        DispatchQueue.main.async { self.request(command, on: target) }
        return true
    }

    /// Hides what the action will remove and holds the action back so nothing rearranges yet, or performs it now when
    /// it can't be hidden. Opening a window always happens now; it leaves Mission Control, which commits the rest.
    private func request(_ command: Hotkeys.Command, on target: HoverTarget) {
        overlay.hide()
        guard command != .open, canDefer else {
            perform(command, on: target)
            track()
            return
        }
        let pid = target.pid
        let windowIDs: [CGWindowID]
        switch (command, target) {
        case (.close, .window(let w)), (.minimize, .window(let w)):
            windowIDs = [w.id]
        case (.hideOthers, _):
            windowIDs = windows.filter { $0.pid != pid && NSRunningApplication(processIdentifier: $0.pid)?.activationPolicy == .regular }.map(\.id)
        default:
            windowIDs = windows.filter { $0.pid == pid }.map(\.id)
        }
        var apps: Set<pid_t> = []
        if command == .quit {
            quitting.insert(pid)
            if case .dockApp(let app) = target, DockScanner.removesIconOnQuit(app) { apps.insert(pid) }
        }
        let action = PendingCommand(command: command, target: target, hiddenWindows: Set(windowIDs), hidesDockIcon: !apps.isEmpty)
        debugLog("defer \(command) on \(target), hiding \(windowIDs.count) window(s)")
        pending.enqueue(action, hidingWindows: action.hiddenWindows, hidingApps: apps, at: Date(), commandHeld: Self.commandHeld)
        track()
    }

    /// Performs held-back actions. Their covers stay up until what they hid is actually gone.
    private func commit(_ actions: [PendingCommand]) {
        guard !actions.isEmpty else { return }
        debugLog("commit \(actions.count) action(s)")
        let now = Date()
        for action in actions {
            action.hiddenWindows.forEach { committedCovers[.window($0)] = now }
            if action.hidesDockIcon { committedCovers[.dockApp(action.target.pid)] = now }
            perform(action.command, on: action.target)
        }
    }

    private func perform(_ command: Hotkeys.Command, on target: HoverTarget) {
        switch target {
        case .window(let window): perform(command, on: window)
        case .dockApp(let app): perform(command, on: app)
        }
    }

    private func perform(_ command: Hotkeys.Command, on window: ScreenWindow) {
        switch command {
        case .close:
            closing.insert(window.id)
            Actions.closeWindow(window)
        case .closeAll:
            allWindows.filter { $0.pid == window.pid }.forEach { closing.insert($0.id) }
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
            allWindows.filter { $0.pid == window.pid }.forEach { closing.insert($0.id) }
            Actions.quit(pid: window.pid)
        case .open:
            overlay.hide()
            Actions.open(window)
        }
    }

    /// Window-level commands act on all of the app's windows when a Dock icon is hovered.
    private func perform(_ command: Hotkeys.Command, on app: DockApp) {
        switch command {
        case .close, .closeAll:
            allWindows.filter { $0.pid == app.pid }.forEach { closing.insert($0.id) }
            Actions.closeAllWindows(of: app.pid)
        case .minimize, .minimizeAll:
            Actions.minimizeAll(of: app.pid)
        case .hide:
            Actions.hide(pid: app.pid)
        case .hideOthers:
            Actions.hideOthers(except: app.pid)
        case .quit:
            debugLog("quit dock app \(app.name) pid=\(app.pid)")
            quitting.insert(app.pid)
            dockApps.removeAll { $0.pid == app.pid }
            allWindows.filter { $0.pid == app.pid }.forEach { closing.insert($0.id) }
            Actions.quit(pid: app.pid)
        case .open:
            overlay.hide()
            Actions.activate(app)
        }
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
        if #available(macOS 14, *) {
            let keep = NSMenuItem(title: "Keep Windows in Place While Closing", action: #selector(toggleKeepInPlace), keyEquivalent: "")
            keep.target = self
            keep.state = keepWindowsInPlace ? .on : .off
            keep.toolTip = "Needs the Screen Recording permission. Turn off to act immediately without it."
            menu.addItem(keep)
        }
        if #available(macOS 14, *), keepWindowsInPlace, !CGPreflightScreenCaptureAccess() {
            let item = NSMenuItem(title: "Allow Screen Recording to Keep Windows in Place…",
                                  action: #selector(openScreenRecording), keyEquivalent: "")
            item.target = self
            item.toolTip = "Lets closed windows vanish without the rest of Mission Control rearranging until you're done."
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let title = NSMenuItem(title: "In Mission Control, hover a window or Dock icon and press:", action: nil, keyEquivalent: "")
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

    @objc private func toggleKeepInPlace() {
        keepWindowsInPlace.toggle()
        if keepWindowsInPlace {
            if #available(macOS 14, *), !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        } else {
            // Run whatever is held back now, as nothing will cover it any more.
            commit(pending.commitAll())
            captureTask?.cancel()
            captureTask = nil
            backgrounds = []
            covers.removeAll()
        }
    }

    @objc private func openScreenRecording() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
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
