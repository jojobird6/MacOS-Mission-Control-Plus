import Foundation

/// Actions the user has taken in Mission Control whose real effect is held back, so the remaining thumbnails don't
/// rearrange while the user is still working, the way Chrome waits to resize tabs until the pointer leaves the tab strip.
///
/// Nothing commits while ⌘ is held. Once ⌘ is up, the queue commits when ⌘ has been released since the last action,
/// when `delay` has passed since the last action, or when the pointer leaves the area of thumbnails and Dock icons.
/// The owner commits everything unconditionally when Mission Control closes.
public struct PendingQueue<Action> {
    public let delay: TimeInterval
    public private(set) var actions: [Action] = []
    /// Windows whose thumbnails are hidden until the queue commits.
    public private(set) var hiddenWindowIDs: Set<UInt32> = []
    /// Apps whose Dock icons are hidden until the queue commits.
    public private(set) var hiddenAppPIDs: Set<Int32> = []
    private var lastEnqueuedAt: Date?
    private var commandHeldWhilePending = false

    public init(delay: TimeInterval = 1.5) {
        self.delay = delay
    }

    public var isEmpty: Bool { actions.isEmpty }

    public mutating func enqueue(_ action: Action, hidingWindows windows: Set<UInt32>, hidingApps apps: Set<Int32> = [],
                                 at now: Date, commandHeld: Bool) {
        actions.append(action)
        hiddenWindowIDs.formUnion(windows)
        hiddenAppPIDs.formUnion(apps)
        lastEnqueuedAt = now
        if commandHeld { commandHeldWhilePending = true }
    }

    /// The actions to perform now, in the order they were taken, or an empty array if they should keep waiting.
    /// Returned actions are removed from the queue, so each is performed exactly once.
    public mutating func commitIfDue(now: Date, commandHeld: Bool, pointerInActiveArea: Bool) -> [Action] {
        guard let lastEnqueuedAt else { return [] }
        if commandHeld {
            commandHeldWhilePending = true
            return []
        }
        let due = commandHeldWhilePending || !pointerInActiveArea || now.timeIntervalSince(lastEnqueuedAt) >= delay
        return due ? commitAll() : []
    }

    public mutating func commitAll() -> [Action] {
        defer { self = PendingQueue(delay: delay) }
        return actions
    }
}
