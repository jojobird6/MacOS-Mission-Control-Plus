import Cocoa
import ScreenCaptureKit

/// Mission Control's backdrop on one display — wallpaper, Spaces bar and Dock — with no window thumbnails on it.
struct CapturedBackground {
    let image: CGImage
    /// Display frame in Cocoa coordinates (origin bottom-left of primary screen).
    let frame: NSRect

    private var scale: CGFloat { CGFloat(image.width) / frame.width }

    /// The part of `rect` that lies on this display, or nil if none of it does.
    func visiblePart(of rect: NSRect) -> NSRect? {
        let r = rect.intersection(frame)
        return r.isNull || r.width < 1 || r.height < 1 ? nil : r
    }

    /// The backdrop under `rect`, which must lie on this display.
    func crop(_ rect: NSRect) -> CGImage? {
        let pixels = CGRect(x: (rect.minX - frame.minX) * scale, y: (frame.maxY - rect.maxY) * scale,
                            width: rect.width * scale, height: rect.height * scale).integral
        return image.cropping(to: pixels)
    }

    /// The part of a Dock item to paint over so its icon looks gone. The item frame spans the Dock's full height; its
    /// top edge is the Dock's highlight line and its bottom few points hold the running indicator, so stay inside both.
    static func dockGapRect(for item: NSRect) -> NSRect {
        NSRect(x: item.minX, y: item.minY + 1, width: item.width, height: item.height - 6).integral
    }

    /// An empty stretch of Dock filling `gap`, made by blending the Dock background just above and below it.
    func dockGap(_ gap: NSRect) -> CGImage? {
        guard let top = crop(NSRect(x: gap.minX, y: gap.maxY - 1, width: gap.width, height: 1)),
              let bottom = crop(NSRect(x: gap.minX, y: gap.minY, width: gap.width, height: 1)) else { return nil }
        let width = Int((gap.width * scale).rounded()), height = Int((gap.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(bottom, in: CGRect(x: 0, y: 0, width: width, height: height))
        for row in 0..<height {
            ctx.setAlpha(CGFloat(row) / CGFloat(max(height - 1, 1)))
            ctx.draw(top, in: CGRect(x: 0, y: row, width: width, height: 1))
        }
        return ctx.makeImage()
    }
}

/// Captures Mission Control's backdrop so a thumbnail can be hidden by painting the backdrop over it.
@available(macOS 14, *)
enum BackgroundCapture {
    /// Apps whose windows draw Mission Control itself rather than thumbnails.
    private static let backdropBundleIDs: Set<String> = ["com.apple.dock", "com.apple.WindowManager", "com.apple.wallpaper.agent"]
    /// The hover outline and title Mission Control draws around a thumbnail.
    private static let highlightTitle = "Window Highlight Overlay"

    static func capture() async throws -> [CapturedBackground] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let excluded = content.windows.filter { window in
            guard let app = window.owningApplication else { return false }
            return app.processID == ownPID || !backdropBundleIDs.contains(app.bundleIdentifier) || window.title == highlightTitle
        }
        let primaryHeight = await MainActor.run { NSScreen.screens.first?.frame.height ?? 0 }
        var result: [CapturedBackground] = []
        for display in content.displays {
            let scale = await MainActor.run { backingScale(of: display.displayID) }
            let config = SCStreamConfiguration()
            config.width = Int(display.frame.width * scale)
            config.height = Int(display.frame.height * scale)
            config.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let f = display.frame
            result.append(CapturedBackground(image: image, frame: NSRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)))
        }
        return result
    }

    @MainActor private static func backingScale(of displayID: CGDirectDisplayID) -> CGFloat {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }?
            .backingScaleFactor ?? 2
    }
}
