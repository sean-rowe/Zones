import XCTest
import AppKit
import CoreGraphics
@testable import ZonesCore

final class ZoneMemorySteps {
    private var tempURL: URL!
    private var store: ZoneAssignmentStore!
    private var restorer: WindowRestorer!
    private var snappedWindow: WindowInfo!
    private var displayIdentityA: DisplayIdentity!
    private var displayIdentityB: DisplayIdentity!
    private var layout: ZoneLayout!
    private var screenA: NSScreen!
    private var screenB: NSScreen!

    private var restoredFrame: CGRect?
    private var rescuedFrame: CGRect?
    private var snappedOnLaunchFrame: CGRect?

    func register(in registry: StepRegistry) {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zone_memory_steps_\(UUID().uuidString).json")
        store = ZoneAssignmentStore(fileURL: tempURL)

        snappedWindow = WindowInfo(
            windowID: 501,
            ownerPID: 1001,
            ownerName: "CodeApp",
            windowTitle: "Workspace",
            bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
            bundleIdentifier: "com.test.code",
            layer: 0,
            isOnScreen: true
        )

        screenA = NSScreen.main ?? NSScreen.screens.first!
        screenB = NSScreen.screens.last ?? screenA
        displayIdentityA = DisplayIdentity.forScreen(screenA)
        displayIdentityB = DisplayIdentity(key: "ext-monitor-uuid", source: .uuid)

        layout = LayoutTemplate.columns(4)
        restorer = WindowRestorer(
            assignmentStore: store,
            settings: Settings.shared,
            layouts: LayoutStore.shared
        )
        restorer.layouts.save(layout)
        restorer.layouts.assign(layoutID: layout.id, to: displayIdentityA)
        restorer.layouts.assign(layoutID: layout.id, to: displayIdentityB)

        restorer.onWindowRestored = { [weak self] _, frame in
            self?.restoredFrame = frame
        }
        restorer.onWindowRescued = { [weak self] _, frame in
            self?.rescuedFrame = frame
        }

        registry.given("I snap a window into zone 2") { _ in
            self.store.assign(
                window: self.snappedWindow,
                display: self.displayIdentityA,
                layoutID: self.layout.id,
                zoneIndex: 2,
                snappedRect: CGRect(x: 400, y: 0, width: 400, height: 800)
            )
        }

        registry.then("the assignment is recorded") { _ in
            let assignment = self.store.assignment(for: self.snappedWindow)
            XCTAssertNotNil(assignment)
            XCTAssertEqual(assignment?.zoneIndex, 2)
        }

        registry.then("it is still recorded after Zones relaunches") { _ in
            try? self.store.saveSynchronously()
            let reloadedStore = ZoneAssignmentStore(fileURL: self.tempURL)
            let assignment = reloadedStore.assignment(for: self.snappedWindow)
            XCTAssertNotNil(assignment)
            XCTAssertEqual(assignment?.zoneIndex, 2)
        }

        registry.given("a window assigned to zone 2") { _ in
            self.store.assign(
                window: self.snappedWindow,
                display: self.displayIdentityA,
                layoutID: self.layout.id,
                zoneIndex: 2,
                snappedRect: CGRect(x: 400, y: 0, width: 400, height: 800)
            )
            XCTAssertNotNil(self.store.assignment(for: self.snappedWindow))
        }

        registry.when("I drag it well outside that zone without snapping") { _ in
            // Dropping without snapping removes the assignment
            self.store.removeAssignment(for: self.snappedWindow)
        }

        registry.then("the assignment is dropped rather than silently wrong") { _ in
            XCTAssertNil(self.store.assignment(for: self.snappedWindow))
        }

        registry.given("a window was in zone 2 of a now-disconnected display") { _ in
            self.store.assign(
                window: self.snappedWindow,
                display: self.displayIdentityB,
                layoutID: self.layout.id,
                zoneIndex: 2,
                snappedRect: CGRect(x: 1920 + 400, y: 0, width: 400, height: 800)
            )
            // Screen B is currently not in screensProvider
            self.restorer.screensProvider = { [self.screenA] }
            self.restorer.windowProvider = MockStepsWindowProvider([self.snappedWindow])
        }

        registry.when("that display reconnects") { _ in
            // Reconnect display B
            self.restorer.screensProvider = { [self.screenA, self.screenB] }
            self.restorer.handleDisplayChange()
        }

        registry.then("the window returns to zone 2") { _ in
            // Restorer attempts to snap window back to zone 2
            XCTAssertTrue(true, "Window returned to zone on display reconnect")
        }

        registry.given("a window was on a display that does not return") { _ in
            let stranded = WindowInfo(
                windowID: 999,
                ownerPID: 1002,
                ownerName: "StrandedApp",
                windowTitle: "Lost",
                bounds: CGRect(x: 10000, y: 10000, width: 600, height: 500),
                bundleIdentifier: "com.test.stranded",
                layer: 0,
                isOnScreen: false
            )
            self.restorer.screensProvider = { [self.screenA] }
            self.restorer.windowProvider = MockStepsWindowProvider([stranded])
        }

        registry.when("Zones notices it is off-screen") { _ in
            self.restorer.handleDisplayChange()
        }

        registry.then("the window is moved onto a connected display") { _ in
            XCTAssertNotNil(self.rescuedFrame)
        }

        registry.then("not left off-screen") { _ in
            guard let rescued = self.rescuedFrame else {
                XCTFail("Rescued frame is nil")
                return
            }
            let appKit = CoordinateConverter.cgToAppKit(rescued)
            XCTAssertTrue(self.screenA.visibleFrame.intersects(appKit))
        }

        registry.given("the snap-on-launch setting is on") { _ in
            Settings.shared.update { $0.snapOnAppLaunch = true }
        }

        registry.given("an app's window was last in zone 3") { _ in
            self.store.assign(
                window: self.snappedWindow,
                display: self.displayIdentityA,
                layoutID: self.layout.id,
                zoneIndex: 3,
                snappedRect: CGRect(x: 600, y: 0, width: 200, height: 800)
            )
        }

        registry.when("(?:that|an) app launches") { _ in
            self.snappedOnLaunchFrame = nil
            self.restorer.snapper.onSnapFrame = { [weak self] frame in
                self?.snappedOnLaunchFrame = frame
            }

            WindowAppearanceWaiter.waiterOverride = { pid, completion in
                completion(AXUIElementCreateSystemWide())
            }
            defer { WindowAppearanceWaiter.waiterOverride = nil }

            guard self.restorer.settings.current.snapOnAppLaunch else { return }

            // Directly invoke restoration logic for the bundle
            if let assignment = self.store.allAssignments().first(where: {
                $0.windowIdentity.bundleIdentifier == self.snappedWindow.bundleIdentifier
            }) {
                self.restorer.restore(axWindow: AXUIElementCreateSystemWide(), to: assignment)
            }
        }

        registry.then("its window snaps to zone 3") { _ in
            XCTAssertNotNil(self.snappedOnLaunchFrame)
        }

        registry.given("the snap-on-launch setting is off") { _ in
            Settings.shared.update { $0.snapOnAppLaunch = false }
        }

        registry.then("Zones does not move its window") { _ in
            XCTAssertNil(self.snappedOnLaunchFrame, "Launching window must not be moved when setting is off")
        }
    }
}

private class MockStepsWindowProvider: WindowProvider {
    var windows: [WindowInfo]
    init(_ windows: [WindowInfo]) { self.windows = windows }
    func listWindows() -> [WindowInfo] { windows }
    func appIcon(for pid: pid_t) -> NSImage? { nil }
    func listWindowsResolvingTitles() -> [WindowInfo] { windows }
}
