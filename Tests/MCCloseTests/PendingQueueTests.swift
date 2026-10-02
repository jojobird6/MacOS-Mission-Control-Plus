import Foundation
import Testing
@testable import MCCloseCore

@Suite struct PendingQueueTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func emptyQueueNeverCommits() {
        var q = PendingQueue<String>()
        #expect(q.commitIfDue(now: t0, commandHeld: false, pointerInActiveArea: false).isEmpty)
    }

    @Test func waitsForDelayWhilePointerStaysInArea() {
        var q = PendingQueue<String>(delay: 1.5)
        q.enqueue("a", hidingWindows: [1], at: t0, commandHeld: false)
        #expect(q.commitIfDue(now: t0 + 1.4, commandHeld: false, pointerInActiveArea: true).isEmpty)
        #expect(q.hiddenWindowIDs == [1])
        #expect(q.commitIfDue(now: t0 + 1.5, commandHeld: false, pointerInActiveArea: true) == ["a"])
        #expect(q.isEmpty)
        #expect(q.hiddenWindowIDs.isEmpty)
    }

    @Test func eachNewActionRestartsTheDelay() {
        var q = PendingQueue<String>(delay: 1.5)
        q.enqueue("a", hidingWindows: [1], at: t0, commandHeld: false)
        q.enqueue("b", hidingWindows: [2], at: t0 + 1.0, commandHeld: false)
        #expect(q.commitIfDue(now: t0 + 2.0, commandHeld: false, pointerInActiveArea: true).isEmpty)
        #expect(q.commitIfDue(now: t0 + 2.5, commandHeld: false, pointerInActiveArea: true) == ["a", "b"])
    }

    @Test func leavingTheActiveAreaCommitsImmediately() {
        var q = PendingQueue<String>()
        q.enqueue("a", hidingWindows: [1], at: t0, commandHeld: false)
        #expect(q.commitIfDue(now: t0 + 0.1, commandHeld: false, pointerInActiveArea: false) == ["a"])
    }

    @Test func nothingCommitsWhileCommandIsHeld() {
        var q = PendingQueue<String>(delay: 1.5)
        q.enqueue("a", hidingWindows: [1], at: t0, commandHeld: true)
        #expect(q.commitIfDue(now: t0 + 60, commandHeld: true, pointerInActiveArea: false).isEmpty)
        q.enqueue("b", hidingWindows: [2], at: t0 + 61, commandHeld: true)
        #expect(q.commitIfDue(now: t0 + 120, commandHeld: true, pointerInActiveArea: true).isEmpty)
        #expect(q.hiddenWindowIDs == [1, 2])
    }

    @Test func releasingCommandCommitsWithoutWaiting() {
        var q = PendingQueue<String>(delay: 1.5)
        q.enqueue("a", hidingWindows: [1], at: t0, commandHeld: true)
        #expect(q.commitIfDue(now: t0 + 0.05, commandHeld: false, pointerInActiveArea: true) == ["a"])
    }

    @Test func pressingCommandAfterAClickHoldsAndReleaseCommits() {
        var q = PendingQueue<String>(delay: 1.5)
        q.enqueue("a", hidingWindows: [1], at: t0, commandHeld: false)
        #expect(q.commitIfDue(now: t0 + 0.5, commandHeld: true, pointerInActiveArea: true).isEmpty)
        #expect(q.commitIfDue(now: t0 + 0.6, commandHeld: false, pointerInActiveArea: true) == ["a"])
    }

    @Test func commandStateResetsAfterCommit() {
        var q = PendingQueue<String>(delay: 1.5)
        q.enqueue("a", hidingWindows: [1], at: t0, commandHeld: true)
        _ = q.commitIfDue(now: t0 + 0.1, commandHeld: false, pointerInActiveArea: true)
        q.enqueue("b", hidingWindows: [2], at: t0 + 1, commandHeld: false)
        #expect(q.commitIfDue(now: t0 + 1.1, commandHeld: false, pointerInActiveArea: true).isEmpty)
    }

    @Test func commitAllFlushesEverythingOnce() {
        var q = PendingQueue<String>()
        q.enqueue("a", hidingWindows: [1, 2], hidingApps: [42], at: t0, commandHeld: true)
        q.enqueue("b", hidingWindows: [3], at: t0, commandHeld: true)
        #expect(q.hiddenAppPIDs == [42])
        #expect(q.commitAll() == ["a", "b"])
        #expect(q.commitAll().isEmpty)
        #expect(q.hiddenWindowIDs.isEmpty && q.hiddenAppPIDs.isEmpty)
    }
}

@Suite struct CoverGeometryTests {
    @Test func coverReachesFurthestBelowWhereTheShadowFalls() {
        let r = CoverGeometry.coverRect(for: CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(r == CGRect(x: 84, y: 80, width: 232, height: 132))
    }

    @Test func holesClearNearbyThumbnailsOnly() {
        let cover = CGRect(x: 92, y: 92, width: 216, height: 116)
        let near = CGRect(x: 302, y: 100, width: 100, height: 50)
        let far = CGRect(x: 600, y: 600, width: 100, height: 50)
        let holes = CoverGeometry.holes(in: cover, neighbors: [near, far])
        #expect(holes == [CGRect(x: 298, y: 96, width: 10, height: 58)])
    }

    @Test func activeAreaSpansThumbnailsAndDock() {
        let area = CoverGeometry.activeArea(thumbnails: [CGRect(x: 100, y: 300, width: 100, height: 100)],
                                            dockItems: [CGRect(x: 400, y: 0, width: 60, height: 60)])
        #expect(area == CGRect(x: 76, y: -24, width: 408, height: 448))
        #expect(CoverGeometry.activeArea(thumbnails: [], dockItems: []).isNull)
    }
}
