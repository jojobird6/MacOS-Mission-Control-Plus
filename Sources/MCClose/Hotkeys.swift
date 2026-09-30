import Cocoa
import Carbon.HIToolbox

/// Keyboard shortcuts that are only intercepted while Mission Control is showing.
final class Hotkeys {
    enum Command {
        case close, closeAll, minimize, minimizeAll, hide, hideOthers, quit, open
    }

    /// Return true if the command was handled (the key event is then swallowed).
    var handler: ((Command) -> Bool)?
    var isActive: () -> Bool = { false }
    private var tap: CFMachPort?

    @discardableResult
    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, refcon in
            let me = Unmanaged<Hotkeys>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }, userInfo: refcon) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, isActive(), let command = Self.command(for: event) else {
            return Unmanaged.passUnretained(event)
        }
        return handler?(command) == true ? nil : Unmanaged.passUnretained(event)
    }

    private static func command(for event: CGEvent) -> Command? {
        let flags = event.flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch (flags, key) {
        case ([.maskCommand], kVK_ANSI_W): return .close
        case ([.maskCommand, .maskAlternate], kVK_ANSI_W): return .closeAll
        case ([.maskCommand], kVK_ANSI_M): return .minimize
        case ([.maskCommand, .maskAlternate], kVK_ANSI_M): return .minimizeAll
        case ([.maskCommand], kVK_ANSI_H): return .hide
        case ([.maskCommand, .maskAlternate], kVK_ANSI_H): return .hideOthers
        case ([.maskCommand], kVK_ANSI_Q): return .quit
        case ([], kVK_Return), ([], kVK_ANSI_KeypadEnter): return .open
        default: return nil
        }
    }

    static let reference: [(String, String)] = [
        ("⌘W", "Close window"), ("⌥⌘W", "Close all windows of app"),
        ("⌘M", "Minimize window"), ("⌥⌘M", "Minimize all windows of app"),
        ("⌘H", "Hide app"), ("⌥⌘H", "Hide other apps"),
        ("⌘Q", "Quit app"), ("↩", "Open window"),
    ]
}
