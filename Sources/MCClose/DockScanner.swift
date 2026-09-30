import Cocoa

/// A running app's icon in the Dock.
struct DockApp: Equatable {
    let pid: pid_t
    let name: String
    /// Frame of the Dock item in Cocoa coordinates (origin bottom-left of primary screen).
    let frame: NSRect
}

/// What the pointer is over in Mission Control: a window thumbnail or a Dock icon.
enum HoverTarget: Equatable {
    case window(ScreenWindow)
    case dockApp(DockApp)

    var frame: NSRect {
        switch self {
        case .window(let w): return w.frame
        case .dockApp(let a): return a.frame
        }
    }

    var pid: pid_t {
        switch self {
        case .window(let w): return w.pid
        case .dockApp(let a): return a.pid
        }
    }
}

enum DockScanner {
    /// Apps that can't meaningfully be quit from the Dock.
    private static let excludedBundleIDs: Set<String> = ["com.apple.finder"]

    private static func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Running, quittable apps in the Dock, with their on-screen icon frames.
    static func runningApps() -> [DockApp] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let children = attr(AXUIElementCreateApplication(dock.processIdentifier), kAXChildrenAttribute) as? [AXUIElement],
              let list = children.first(where: { (attr($0, kAXRoleAttribute) as? String) == kAXListRole }),
              let items = attr(list, kAXChildrenAttribute) as? [AXUIElement] else { return [] }

        var running: [String: pid_t] = [:]
        var pidsByExecutable: [String: pid_t]?
        for app in NSWorkspace.shared.runningApplications {
            guard !app.isTerminated, let url = app.bundleURL,
                  !excludedBundleIDs.contains(app.bundleIdentifier ?? "") else { continue }
            var pid = app.processIdentifier
            // LaunchServices sometimes reports -1 for a running app; find it by executable path instead.
            if pid <= 0, let exe = app.executableURL {
                if pidsByExecutable == nil { pidsByExecutable = allPIDsByExecutable() }
                pid = pidsByExecutable?[key(exe)] ?? -1
            }
            if pid > 0, running[key(url)] == nil { running[key(url)] = pid }
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        return items.compactMap { item in
            guard (attr(item, kAXSubroleAttribute) as? String) == "AXApplicationDockItem",
                  (attr(item, "AXIsApplicationRunning") as? Bool) == true,
                  let url = attr(item, kAXURLAttribute) as? URL,
                  let pid = running[key(url)],
                  let posValue = attr(item, kAXPositionAttribute), let sizeValue = attr(item, kAXSizeAttribute)
            else { return nil }
            var pos = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            guard size.width > 0, size.height > 0 else { return nil }
            let frame = NSRect(x: pos.x, y: primaryHeight - pos.y - size.height, width: size.width, height: size.height)
            return DockApp(pid: pid, name: attr(item, kAXTitleAttribute) as? String ?? "", frame: frame)
        }
    }

    private static func allPIDsByExecutable() -> [String: pid_t] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var result: [String: pid_t] = [:]
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            result[key(URL(fileURLWithPath: String(cString: buffer)))] = pid
        }
        return result
    }

    static func app(at point: NSPoint, in apps: [DockApp]) -> DockApp? {
        apps.first { $0.frame.contains(point) }
    }
}
