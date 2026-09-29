import XCTest
import AppKit
@testable import ZonesCore

final class ZoneOverlayTests: XCTestCase {
    func testOverlayWindowNeverInterceptsMouseEvents() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let window = ZoneOverlayWindow(screen: screen)

        XCTAssertTrue(window.ignoresMouseEvents, "ZoneOverlayWindow MUST ignore mouse events so drags pass through")
        XCTAssertEqual(window.level, .floating)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
    }

    func testHapticFeedbackTriggersOnZoneHighlightChange() {
        let view = ZoneOverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        var hapticFiredCount = 0
        view.hapticPerformer = { hapticFiredCount += 1 }

        let initial = [
            OverlayZoneModel(index: 0, rect: CGRect(x: 0, y: 0, width: 400, height: 600), isHighlighted: false),
            OverlayZoneModel(index: 1, rect: CGRect(x: 400, y: 0, width: 400, height: 600), isHighlighted: false)
        ]
        view.zones = initial
        XCTAssertEqual(hapticFiredCount, 0, "No haptic when no zone is highlighted")

        // Entering zone 0
        let highlighted0 = [
            OverlayZoneModel(index: 0, rect: CGRect(x: 0, y: 0, width: 400, height: 600), isHighlighted: true),
            OverlayZoneModel(index: 1, rect: CGRect(x: 400, y: 0, width: 400, height: 600), isHighlighted: false)
        ]
        view.zones = highlighted0
        XCTAssertEqual(hapticFiredCount, 1, "Haptic feedback must fire when entering a zone")

        // Same highlight again should not re-trigger
        view.zones = highlighted0
        XCTAssertEqual(hapticFiredCount, 1, "Duplicate highlight state must not fire haptic again")

        // Entering zone 1
        let highlighted1 = [
            OverlayZoneModel(index: 0, rect: CGRect(x: 0, y: 0, width: 400, height: 600), isHighlighted: false),
            OverlayZoneModel(index: 1, rect: CGRect(x: 400, y: 0, width: 400, height: 600), isHighlighted: true)
        ]
        view.zones = highlighted1
        XCTAssertEqual(hapticFiredCount, 2, "Haptic feedback must fire when switching to another zone")
    }
}
