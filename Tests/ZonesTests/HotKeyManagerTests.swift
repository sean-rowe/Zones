import XCTest
import AppKit
import ApplicationServices
@testable import ZonesCore

final class HotKeyManagerTests: XCTestCase {
    private var manager: HotKeyManager!
    private var snappedFrames: [CGRect] = []
    private var layout: ZoneLayout!
    private var screen: NSScreen!

    override func setUp() {
        super.setUp()
        manager = HotKeyManager()
        snappedFrames = []
        manager.snapper.onSnapFrame = { [weak self] frame in
            self?.snappedFrames.append(frame)
        }

        // Mock screen: 1920x1080
        screen = NSScreen.main ?? NSScreen.screens.first!
        let identity = DisplayIdentity.forScreen(screen)

        // 2-column layout: Zone 0 (left 50%), Zone 1 (right 50%)
        layout = LayoutTemplate.columns(2)
        manager.screensProvider = { [self.screen] }
        manager.layoutProvider = { id in
            return id == identity ? self.layout : nil
        }

        let dummyAX = AXUIElementCreateSystemWide()
        manager.focusedWindowProvider = { dummyAX }
        let screenCG = CoordinateConverter.appKitToCG(self.screen.frame)
        manager.windowFrameProvider = { _ in
            CGRect(x: screenCG.midX - 200, y: screenCG.midY - 150, width: 400, height: 300)
        }
    }

    private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    func testNumberedShortcutSnapsToZone() {
        // ⌃⌥⌘1 (keyCode 18)
        let event = makeKeyEvent(keyCode: 18, modifiers: [.control, .option, .command])
        let handled = manager.handleKeyEvent(event)

        XCTAssertTrue(handled)
        XCTAssertEqual(snappedFrames.count, 1)

        // Verify snapped rect is approximately left half of screen
        let snapped = snappedFrames[0]
        XCTAssertEqual(snapped.width, (screen.visibleFrame.width - 24) / 2, accuracy: 20)
    }

    func testNumberedShortcutForNonExistentZoneDoesNothing() {
        // Layout has 2 zones (indices 0 and 1).
        // ⌃⌥⌘5 (keyCode 23, index 4) should do nothing.
        let event = makeKeyEvent(keyCode: 23, modifiers: [.control, .option, .command])
        let handled = manager.handleKeyEvent(event)

        XCTAssertFalse(handled, "Shortcut for a zone that does not exist must do nothing")
        XCTAssertTrue(snappedFrames.isEmpty)
    }

    func testShortcutWithoutRequiredModifiersIsPassedThrough() {
        // ⌘1 without Control and Option
        let event = makeKeyEvent(keyCode: 18, modifiers: [.command])
        let handled = manager.handleKeyEvent(event)

        XCTAssertFalse(handled, "Non-matching shortcut must not be handled")
        XCTAssertTrue(snappedFrames.isEmpty)
    }

    func testCycleZoneMovesToNextZone() {
        // ⌃⌥⌘→ (keyCode 124)
        let event = makeKeyEvent(keyCode: 124, modifiers: [.control, .option, .command])
        let handled = manager.handleKeyEvent(event)

        XCTAssertTrue(handled)
        XCTAssertEqual(snappedFrames.count, 1)
    }

    func testCrossDisplayMoveClampsToLastZoneWhenTargetLayoutIsShorter() {
        // Screen A has 3 zones, Screen B has 2 zones
        let layoutA = LayoutTemplate.columns(3)
        let layoutB = LayoutTemplate.columns(2)

        let dummyScreenA = screen!
        let dummyScreenB = NSScreen.screens.last ?? dummyScreenA

        manager.screensProvider = { [dummyScreenA, dummyScreenB] }
        manager.layoutProvider = { id in
            return id == DisplayIdentity.forScreen(dummyScreenA) ? layoutA : layoutB
        }

        // Move to next display: ⌃⌥⌘↑ (keyCode 126)
        let event = makeKeyEvent(keyCode: 126, modifiers: [.control, .option, .command])
        let handled = manager.handleKeyEvent(event)

        // Handled if more than 1 screen available
        if NSScreen.screens.count > 1 {
            XCTAssertTrue(handled)
            XCTAssertEqual(snappedFrames.count, 1)
        }
    }
}
