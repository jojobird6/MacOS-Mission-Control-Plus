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

/// Floating ✕ button that tracks the hovered Mission Control thumbnail.
final class Overlay {
    static let size: CGFloat = 26
    var onClose: ((ScreenWindow) -> Void)?
    private(set) var target: ScreenWindow?
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = CloseButtonView(frame: panel.contentLayoutRect)
        view.onClick = { [weak self] in
            guard let self, let target = self.target else { return }
            self.hide()
            self.onClose?(target)
        }
        panel.contentView = view
    }

    func show(for window: ScreenWindow) {
        target = window
        // Straddle the thumbnail's top-left corner, like a native close button.
        let origin = NSPoint(x: window.frame.minX - Self.size / 2 + 4, y: window.frame.maxY - Self.size / 2 - 4)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        target = nil
        if panel.isVisible { panel.orderOut(nil) }
    }

    /// True if the point is over the ✕, so hovering it keeps its thumbnail targeted.
    func contains(_ point: NSPoint) -> Bool {
        panel.isVisible && panel.frame.contains(point)
    }
}
