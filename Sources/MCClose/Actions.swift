import Cocoa

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum Actions {
    static func axWindows(pid: pid_t) -> [AXUIElement] {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    static func axWindow(for window: ScreenWindow) -> AXUIElement? {
        axWindows(pid: window.pid).first { el in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(el, &id) == .success && id == window.id
        }
    }

    @discardableResult
    static func close(_ element: AXUIElement) -> Bool {
        var button: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    static func closeWindow(_ window: ScreenWindow) {
        let el = axWindow(for: window)
        let ok = el.map { close($0) } ?? false
        debugLog("close \(window.owner) #\(window.id): found=\(el != nil) pressed=\(ok)")
    }

    static func closeAllWindows(of pid: pid_t) {
        axWindows(pid: pid).forEach { close($0) }
    }

    static func minimize(_ window: ScreenWindow) {
        if let el = axWindow(for: window) {
            AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    static func minimizeAll(of pid: pid_t) {
        axWindows(pid: pid).forEach {
            AXUIElementSetAttributeValue($0, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    static func hide(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.hide()
    }

    static func hideOthers(except pid: pid_t) {
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != pid {
            app.hide()
        }
    }

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    /// Opens the window the same way a user click in Mission Control would.
    static func open(_ window: ScreenWindow) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let p = CGPoint(x: window.frame.midX, y: primaryHeight - window.frame.midY)
        let original = CGEvent(source: nil)?.location
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        if let original { CGWarpMouseCursorPosition(original) }
    }
}

func debugLog(_ message: @autoclosure () -> String) {
    if ProcessInfo.processInfo.environment["MCCLOSE_DEBUG"] != nil { NSLog("MCClose: %@", message()) }
}
