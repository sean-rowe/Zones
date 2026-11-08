import XCTest
import CoreGraphics
@testable import ZonesCore

private class MockWindowProvider: WindowProvider {
    var windows: [WindowInfo] = []
    func listWindows() -> [WindowInfo] { windows }
    func appIcon(for pid: pid_t) -> NSImage? { nil }
    func listWindowsResolvingTitles() -> [WindowInfo] { windows }
}

private class MockCursorProvider: DragMonitorCursorProvider {
    var location: CGPoint = .zero
    func currentMouseLocation() -> CGPoint { location }
}

final class DragMonitorTests: XCTestCase {
    private var monitor: DragMonitor!
    private var windowProvider: MockWindowProvider!
    private var cursorProvider: MockCursorProvider!

    private let testWindow = WindowInfo(
        windowID: 101,
        ownerPID: 500,
        ownerName: "Safari",
        windowTitle: "Start Page",
        bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
        bundleIdentifier: "com.apple.Safari",
        layer: 0,
        isOnScreen: true
    )

    private let excludedWindow = WindowInfo(
        windowID: 102,
        ownerPID: 501,
        ownerName: "GameApp",
        windowTitle: "Game Window",
        bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
        bundleIdentifier: "com.example.game",
        layer: 0,
        isOnScreen: true
    )

    override func setUp() {
        super.setUp()
        monitor = DragMonitor()
        windowProvider = MockWindowProvider()
        windowProvider.windows = [testWindow, excludedWindow]
        monitor.windowProvider = windowProvider

        cursorProvider = MockCursorProvider()
        cursorProvider.location = CGPoint(x: 200, y: 120)
        monitor.cursorProvider = cursorProvider

        Settings.shared.update {
            $0.activationModifier = .shift
            $0.spanModifier = .control
            $0.activationPolicy = .holdModifier
            $0.enableSecondaryClickToggle = true
            $0.excludedBundleIdentifiers = ["com.example.game"]
        }
    }

    func testTitleBarDragStartsWhenMovedPastThreshold() {
        var startedWindow: WindowInfo?
        monitor.onDragStarted = { win, _ in startedWindow = win }

        // Mouse down in title bar (y: 120 is 20pt below top 100, within 40pt title bar)
        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        XCTAssertNil(startedWindow, "Drag should not start before movement")

        // Mouse dragged within threshold (dx=3, dy=3 < 8)
        monitor.handleMouseDragged(at: CGPoint(x: 203, y: 123), flags: [])
        XCTAssertNil(startedWindow, "Drag should not start under threshold")

        // Mouse dragged past threshold (dx=15, dy=15 >= 8)
        monitor.handleMouseDragged(at: CGPoint(x: 215, y: 135), flags: [])
        XCTAssertEqual(startedWindow?.windowID, testWindow.windowID)
    }

    func testModifierHeldActivatesZones() {
        var movedActive: Bool?
        var movedSpan: Bool?
        monitor.onDragMoved = { _, _, active, span in
            movedActive = active
            movedSpan = span
        }

        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        monitor.handleMouseDragged(at: CGPoint(x: 220, y: 140), flags: [.maskShift])

        XCTAssertEqual(movedActive, true, "Holding Shift should activate zones")
        XCTAssertEqual(movedSpan, false)
    }

    func testModifierNotHeldLeavesZonesInactive() {
        var movedActive: Bool?
        monitor.onDragMoved = { _, _, active, _ in
            movedActive = active
        }

        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        monitor.handleMouseDragged(at: CGPoint(x: 220, y: 140), flags: [])

        XCTAssertEqual(movedActive, false, "Without modifier, zones should be inactive")
    }

    func testPressingModifierMidDragActivatesZones() {
        var movedActive: Bool?
        monitor.onDragMoved = { _, _, active, _ in
            movedActive = active
        }

        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        monitor.handleMouseDragged(at: CGPoint(x: 220, y: 140), flags: [])
        XCTAssertEqual(movedActive, false)

        cursorProvider.location = CGPoint(x: 220, y: 140)
        monitor.handleFlagsChanged(flags: [.maskShift])
        XCTAssertEqual(movedActive, true, "Pressing Shift mid-drag must activate zones")
    }

    func testReleasingModifierMidDragDeactivatesZones() {
        var movedActive: Bool?
        monitor.onDragMoved = { _, _, active, _ in
            movedActive = active
        }

        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        monitor.handleMouseDragged(at: CGPoint(x: 220, y: 140), flags: [.maskShift])
        XCTAssertEqual(movedActive, true)

        cursorProvider.location = CGPoint(x: 220, y: 140)
        monitor.handleFlagsChanged(flags: [])
        XCTAssertEqual(movedActive, false, "Releasing Shift mid-drag must deactivate zones")
    }

    func testAlwaysWhileDraggingPolicyActivatesWithoutModifier() {
        Settings.shared.update { $0.activationPolicy = .alwaysWhileDragging }

        var movedActive: Bool?
        monitor.onDragMoved = { _, _, active, _ in
            movedActive = active
        }

        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        monitor.handleMouseDragged(at: CGPoint(x: 220, y: 140), flags: [])

        XCTAssertEqual(movedActive, true, "AlwaysWhileDragging policy activates zones without modifier")
    }

    func testSecondaryClickTogglesZoneActivation() {
        var movedActive: Bool?
        monitor.onDragMoved = { _, _, active, _ in
            movedActive = active
        }

        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        monitor.handleMouseDragged(at: CGPoint(x: 220, y: 140), flags: [])
        XCTAssertEqual(movedActive, false)

        // Right-click during drag toggles activation on
        cursorProvider.location = CGPoint(x: 220, y: 140)
        monitor.handleRightMouseDown()
        XCTAssertEqual(movedActive, true, "Secondary click must toggle zones on")

        // Right-click again toggles activation off
        monitor.handleRightMouseDown()
        XCTAssertEqual(movedActive, false, "Second secondary click must toggle zones off")
    }

    func testExcludedApplicationIsIgnored() {
        var startedWindow: WindowInfo?
        monitor.onDragStarted = { win, _ in startedWindow = win }

        // Click on excluded app window
        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        windowProvider.windows = [excludedWindow]
        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        monitor.handleMouseDragged(at: CGPoint(x: 250, y: 150), flags: [.maskShift])

        XCTAssertNil(startedWindow, "Excluded applications must never trigger window drag tracking")
    }

    func testEscapeKeyCancelsSnap() {
        var cancelled = false
        var endedShouldSnap: Bool?
        monitor.onDragCancelled = { cancelled = true }
        monitor.onDragEnded = { _, _, shouldSnap, _ in endedShouldSnap = shouldSnap }

        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        monitor.handleMouseDragged(at: CGPoint(x: 220, y: 140), flags: [.maskShift])

        monitor.handleEscapeKey()
        XCTAssertTrue(cancelled, "Escape key must trigger onDragCancelled")

        monitor.handleMouseUp(at: CGPoint(x: 220, y: 140), flags: [.maskShift])
        XCTAssertNil(endedShouldSnap, "Cancelled drag must not report drop on mouse up")
    }

    func testFullScreenSpaceDeclinesDragAndSnap() {
        var startedWindow: WindowInfo?
        var movedActive: Bool?
        var endedShouldSnap: Bool?

        monitor.onDragStarted = { win, _ in startedWindow = win }
        monitor.onDragMoved = { _, _, active, _ in movedActive = active }
        monitor.onDragEnded = { _, _, shouldSnap, _ in endedShouldSnap = shouldSnap }

        // Mark window as in full-screen Space
        monitor.isFullScreenSpace = { _ in true }

        // Attempt drag with modifier held
        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        monitor.handleMouseDragged(at: CGPoint(x: 250, y: 150), flags: [.maskShift])
        monitor.handleMouseUp(at: CGPoint(x: 250, y: 150), flags: [.maskShift])

        XCTAssertNil(startedWindow, "Window in full-screen Space must not trigger drag started")
        XCTAssertNil(movedActive, "Window in full-screen Space must not trigger drag moved")
        XCTAssertNil(endedShouldSnap, "Window in full-screen Space must not trigger drag snap")
    }
}

extension DragMonitorTests {
    /// The full-screen check is an Accessibility round trip into the dragged
    /// app. Made per mouse event it stuttered app-driven drags, and with them
    /// any Tack strip following the window.
    func testFullScreenSpaceIsCheckedOncePerDragNotPerMouseEvent() {
        var checks = 0
        monitor.isFullScreenSpace = { _ in checks += 1; return false }

        monitor.handleMouseDown(at: CGPoint(x: 200, y: 120))
        for step in 1...20 {
            monitor.handleMouseDragged(at: CGPoint(x: 200 + step * 5, y: 120 + step * 3),
                                       flags: [.maskShift])
        }
        monitor.handleFlagsChanged(flags: [])
        monitor.handleMouseUp(at: CGPoint(x: 300, y: 180), flags: [.maskShift])

        XCTAssertEqual(checks, 1)
    }

    /// A press in the window body (testWindow spans y 100–700, title bar to
    /// y 140) becomes a drag once the app moves the window itself.
    private func dragCandidateWindow(fullScreen: Bool?) -> Int {
        var checks = 0
        monitor.isFullScreenSpace = { _ in checks += 1; return fullScreen }
        var origin = CGPoint(x: 100, y: 100)
        monitor.windowOrigin = { _ in origin }

        monitor.handleMouseDown(at: CGPoint(x: 400, y: 400))
        origin = CGPoint(x: 140, y: 130)
        monitor.handleMouseDragged(at: CGPoint(x: 440, y: 430), flags: [.maskShift])
        monitor.handleMouseDragged(at: CGPoint(x: 460, y: 450), flags: [.maskShift])
        monitor.handleMouseUp(at: CGPoint(x: 460, y: 450), flags: [.maskShift])
        return checks
    }

    func testCandidateDragReusesADefiniteFullScreenAnswer() {
        XCTAssertEqual(dragCandidateWindow(fullScreen: false), 1)
    }

    func testCandidateDragRechecksWhenTheFirstLookupWasInconclusive() {
        XCTAssertEqual(dragCandidateWindow(fullScreen: nil), 2)
    }
}
