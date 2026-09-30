import Cocoa

/// Detects Mission Control by looking for the Dock's accessibility group with identifier "mc",
/// which only exists while Mission Control is showing.
final class MissionControlMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isActive = false
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.poll() }
        timer?.tolerance = 0.03
    }

    private func poll() {
        let active = Self.missionControlVisible()
        if active != isActive {
            isActive = active
            onChange?(active)
        }
    }

    static func missionControlVisible() -> Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return false
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return false }
        return children.contains { child in
            var ident: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &ident)
            return (ident as? String) == "mc"
        }
    }
}
