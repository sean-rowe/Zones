import XCTest
import AppKit
import CoreGraphics
@testable import ZonesCore

final class ZoneAssignmentStoreTests: XCTestCase {
    private var tempURL: URL!
    private var store: ZoneAssignmentStore!

    private let testWindow = WindowInfo(
        windowID: 101,
        ownerPID: 500,
        ownerName: "Safari",
        windowTitle: "Piny Ridge Labs",
        bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
        bundleIdentifier: "com.apple.Safari",
        layer: 0,
        isOnScreen: true
    )

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zone_assignments_test_\(UUID().uuidString).json")
        store = ZoneAssignmentStore(fileURL: tempURL)
    }

    override func tearDown() {
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        super.tearDown()
    }

    func testAssignmentRecordedAndSurvivesRelaunch() throws {
        let display = DisplayIdentity(key: "test-display-1", source: .uuid)
        let layoutID = UUID()
        let snappedRect = CGRect(x: 0, y: 0, width: 960, height: 1080)

        // 1. Assign window to zone 2
        store.assign(
            window: testWindow,
            display: display,
            layoutID: layoutID,
            zoneIndex: 2,
            snappedRect: snappedRect
        )

        let initialAssignment = store.assignment(for: testWindow)
        XCTAssertNotNil(initialAssignment)
        XCTAssertEqual(initialAssignment?.zoneIndex, 2)
        XCTAssertEqual(initialAssignment?.displayIdentity, display)

        // Force synchronous flush to disk
        try store.saveSynchronously()

        // 2. Relaunch simulation: create a new store reading from the same file
        let reloadedStore = ZoneAssignmentStore(fileURL: tempURL)
        let restoredAssignment = reloadedStore.assignment(for: testWindow)

        XCTAssertNotNil(restoredAssignment, "Assignment must survive relaunch")
        XCTAssertEqual(restoredAssignment?.zoneIndex, 2)
        XCTAssertEqual(restoredAssignment?.displayIdentity, display)
        XCTAssertEqual(restoredAssignment?.windowIdentity.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(restoredAssignment?.windowIdentity.windowTitle, "Piny Ridge Labs")
    }

    func testDraggedOutsideWithoutSnappingDropsAssignment() {
        let display = DisplayIdentity(key: "test-display-1", source: .uuid)
        store.assign(
            window: testWindow,
            display: display,
            layoutID: UUID(),
            zoneIndex: 2,
            snappedRect: CGRect(x: 0, y: 0, width: 960, height: 1080)
        )

        XCTAssertNotNil(store.assignment(for: testWindow))

        // When dragged outside without snapping, assignment is dropped
        store.removeAssignment(for: testWindow)

        XCTAssertNil(store.assignment(for: testWindow), "Assignment must be dropped when window is moved without snapping")
    }

    func testWindowRestorerRescueOffScreenWindow() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let restorer = WindowRestorer(
            assignmentStore: store,
            settings: Settings.shared,
            layouts: LayoutStore.shared
        )
        restorer.screensProvider = { [screen] }

        // Window far off-screen at x: 10000, y: 10000
        let offScreenWindow = WindowInfo(
            windowID: 202,
            ownerPID: 600,
            ownerName: "Notes",
            windowTitle: "Offscreen",
            bounds: CGRect(x: 10000, y: 10000, width: 600, height: 400),
            bundleIdentifier: "com.apple.Notes",
            layer: 0,
            isOnScreen: false
        )

        XCTAssertTrue(restorer.isWindowOffScreen(window: offScreenWindow, screens: [screen]))

        var rescuedCG: CGRect?
        restorer.onWindowRescued = { _, target in
            rescuedCG = target
        }

        class MockWindowProvider: WindowProvider {
            var windows: [WindowInfo]
            init(_ windows: [WindowInfo]) { self.windows = windows }
            func listWindows() -> [WindowInfo] { windows }
            func appIcon(for pid: pid_t) -> NSImage? { nil }
            func listWindowsResolvingTitles() -> [WindowInfo] { windows }
        }

        restorer.windowProvider = MockWindowProvider([offScreenWindow])
        restorer.handleDisplayChange()

        XCTAssertNotNil(rescuedCG, "Off-screen window must be rescued")
        let appKitRescued = CoordinateConverter.cgToAppKit(rescuedCG!)
        XCTAssertTrue(screen.visibleFrame.intersects(appKitRescued), "Rescued window must land within visibleFrame")
    }
}
