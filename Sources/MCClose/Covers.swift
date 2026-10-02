import Cocoa

private final class CoverView: NSView {
    let image: CGImage
    /// Areas left transparent, in view coordinates.
    let holes: [NSRect]

    init(frame: NSRect, image: CGImage, holes: [NSRect]) {
        self.image = image
        self.holes = holes
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(image, in: bounds)
        holes.forEach { ctx.clear($0) }
    }

    // Swallow clicks so Mission Control doesn't open a window the user has just closed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

/// Panels that paint Mission Control's backdrop over thumbnails and Dock icons whose action is still pending,
/// so they look gone while the rest of Mission Control stays where it is.
final class Covers {
    enum Key: Hashable {
        case window(CGWindowID)
        case dockApp(pid_t)
    }

    struct Item {
        let key: Key
        /// Cocoa coordinates.
        let frame: NSRect
        /// Cocoa coordinates.
        let holes: [NSRect]
        /// Only called when the panel has to be (re)built.
        let image: () -> CGImage?
    }

    private struct Shown {
        let panel: NSPanel
        let frame: NSRect
        let holes: [NSRect]
    }

    private var shown: [Key: Shown] = [:]

    func update(_ items: [Item]) {
        let keys = Set(items.map(\.key))
        for (key, old) in shown where !keys.contains(key) {
            old.panel.orderOut(nil)
            shown[key] = nil
        }
        for item in items {
            // The window server snaps panel frames to whole points; compare rounded frames so a panel isn't rebuilt
            // every tick.
            let frame = item.frame.integral
            if let old = shown[item.key], old.frame == frame, old.holes == item.holes { continue }
            guard let image = item.image() else { continue }
            // Like the ✕ overlay, a moved cover is replaced rather than moved, since Mission Control animates moves.
            let panel = makePanel(frame: frame, image: image, holes: item.holes)
            panel.orderFrontRegardless()
            shown[item.key]?.panel.orderOut(nil)
            shown[item.key] = Shown(panel: panel, frame: frame, holes: item.holes)
        }
    }

    func removeAll() {
        shown.values.forEach { $0.panel.orderOut(nil) }
        shown.removeAll()
    }

    private func makePanel(frame: NSRect, image: CGImage, holes: [NSRect]) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Just below the ✕ overlay so a neighbor's ✕ is never hidden.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) - 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let localHoles = holes.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        panel.contentView = CoverView(frame: NSRect(origin: .zero, size: frame.size), image: image, holes: localHoles)
        return panel
    }
}
