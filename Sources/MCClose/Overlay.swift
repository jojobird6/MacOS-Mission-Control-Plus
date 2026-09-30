import Cocoa

private final class CloseButtonView: NSView {
    var onClick: (() -> Void)?
    private var hovering = false

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { debugLog("✕ mouseDown") }
    override func mouseUp(with event: NSEvent) {
        debugLog("✕ mouseUp at \(convert(event.locationInWindow, from: nil))")
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 1, dy: 1)
        (hovering ? NSColor(white: 0.12, alpha: 0.95) : NSColor(white: 0.25, alpha: 0.85)).setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor(white: 1, alpha: 0.35).setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5)); ring.lineWidth = 1; ring.stroke()
        let inset = bounds.width * 0.33
        let x = NSBezierPath()
        x.move(to: NSPoint(x: inset, y: inset)); x.line(to: NSPoint(x: bounds.maxX - inset, y: bounds.maxY - inset))
        x.move(to: NSPoint(x: inset, y: bounds.maxY - inset)); x.line(to: NSPoint(x: bounds.maxX - inset, y: inset))
        x.lineWidth = 2; x.lineCapStyle = .round
        NSColor.white.setStroke(); x.stroke()
    }
}

/// Floating ✕ button that tracks the hovered Mission Control thumbnail or Dock icon.
///
/// While Mission Control is open, the system animates any window that moves, so a single panel
/// would glide between thumbnails. Instead, a fresh panel is created at each new position, and the ✕ is hidden while
/// its target is still moving (e.g. Mission Control re-laying out, or the Dock sliding after an app quits).
final class Overlay {
    static let size: CGFloat = 26
    var onClose: ((HoverTarget) -> Void)?
    private(set) var target: HoverTarget?
    private var panel: NSPanel?
    /// The target's frame on the previous tick and how many ticks in a row it hasn't changed.
    private var lastFrame: NSRect?
    private var stableTicks = 0
    private static let ticksToSettle = 2

    private func makePanel(at origin: NSPoint) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: NSSize(width: Self.size, height: Self.size)),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = CloseButtonView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        view.onClick = { [weak self] in
            guard let self, let target = self.target else { return }
            self.hide()
            self.onClose?(target)
        }
        panel.contentView = view
        return panel
    }

    func show(for target: HoverTarget) {
        self.target = target
        let frame = target.frame
        stableTicks = frame == lastFrame ? stableTicks + 1 : 0
        lastFrame = frame
        guard stableTicks >= Self.ticksToSettle else {
            removePanel()
            return
        }
        // Straddle the top-left corner, like a native close button. Dock items include padding around the icon.
        let inset: CGFloat
        if case .dockApp = target { inset = 10 } else { inset = 4 }
        // Rounded because the window server snaps panel frames to whole points; otherwise the comparison below never
        // matches and a new panel is created every tick.
        let origin = NSPoint(x: (frame.minX - Self.size / 2 + inset).rounded(), y: (frame.maxY - Self.size / 2 - inset).rounded())
        if let panel, panel.frame.origin == origin { return }
        debugLog("overlay new panel at \(origin) for \(target)")
        let old = panel
        let new = makePanel(at: origin)
        new.orderFrontRegardless()
        old?.orderOut(nil)
        panel = new
    }

    func hide() {
        target = nil
        lastFrame = nil
        stableTicks = 0
        removePanel()
    }

    private func removePanel() {
        if panel != nil { debugLog("overlay hide") }
        panel?.orderOut(nil)
        panel = nil
    }

    /// True if the point is over the ✕, so hovering it keeps its target.
    func contains(_ point: NSPoint) -> Bool {
        panel?.frame.contains(point) ?? false
    }
}
