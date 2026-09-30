import Cocoa

/// A window as currently laid out on screen. While Mission Control is open, macOS reports the
/// thumbnail rect as the window bounds, so `frame` is the thumbnail frame.
struct ScreenWindow: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    /// Frame in Cocoa coordinates (origin bottom-left of primary screen).
    let frame: NSRect
}

enum WindowScanner {
    private static let ownPID = ProcessInfo.processInfo.processIdentifier
    /// System processes that draw Mission Control chrome (e.g. the hover highlight) at layer 0.
    private static let systemBundleIDs: Set<String> = ["com.apple.WindowManager", "com.apple.dock"]

    private static func excludedPIDs() -> Set<pid_t> {
        var pids: Set<pid_t> = [ownPID]
        for id in systemBundleIDs {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { pids.insert($0.processIdentifier) }
        }
        return pids
    }

    /// Front-to-back list of normal (layer 0) on-screen windows.
    static func visibleWindows() -> [ScreenWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let excluded = excludedPIDs()
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, !excluded.contains(pid),
                  (w[kCGWindowOwnerName as String] as? String) != "Window Server",
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width >= 40, height >= 20
            else { return nil }
            let frame = NSRect(x: x, y: primaryHeight - y - height, width: width, height: height)
            return ScreenWindow(id: id, pid: pid, owner: w[kCGWindowOwnerName as String] as? String ?? "", frame: frame)
        }
    }

    static func window(at point: NSPoint, in windows: [ScreenWindow]) -> ScreenWindow? {
        windows.first { $0.frame.contains(point) }
    }
}
