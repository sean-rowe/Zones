import XCTest
import AppKit
@testable import ZonesCore

/// An overlay window the manager no longer holds must still come down.
final class ZoneOverlayStrayTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows { window.orderOut(nil) }
        windows = []
        super.tearDown()
    }

    private func overlayOnScreen() throws -> ZoneOverlayWindow {
        let screen = try XCTUnwrap(NSScreen.screens.first, "needs a display")
        let window = ZoneOverlayWindow(screen: screen)
        window.orderFrontRegardless()
        windows.append(window)
        return window
    }

    func testHideClosesAnOverlayWindowItNoLongerHolds() throws {
        let stray = try overlayOnScreen()
        XCTAssertTrue(stray.isVisible)

        let manager = ZoneOverlayManager()
        manager.appWindowsProvider = { [unowned self] in self.windows }
        manager.hide()

        XCTAssertFalse(stray.isVisible, "a stray overlay must not outlive a hide")
    }

    func testTheSweepLeavesOtherWindowsAlone() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first, "needs a display")
        let other = NSPanel(contentRect: NSRect(x: screen.frame.minX + 40, y: screen.frame.minY + 40,
                                                width: 80, height: 40),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.orderFrontRegardless()
        windows.append(other)

        let manager = ZoneOverlayManager()
        manager.appWindowsProvider = { [unowned self] in self.windows }

        XCTAssertEqual(manager.dismissStrays(), 0)
        XCTAssertTrue(other.isVisible, "only overlay windows are swept")
    }

    func testAPressReachesTheControllerHook() {
        let monitor = DragMonitor()
        var presses = 0
        monitor.onPress = { presses += 1 }

        monitor.handleMouseDown(at: CGPoint(x: -10_000, y: -10_000))

        XCTAssertEqual(presses, 1)
    }
}
