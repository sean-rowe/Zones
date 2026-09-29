import XCTest
import AppKit
import CoreGraphics
@testable import ZonesCore

final class MultiDisplaySteps {
    private var screenFrame: CGRect = .zero
    private var visibleFrame: CGRect = .zero
    private var layout: ZoneLayout = LayoutTemplate.columns(2)
    private var resolvedZones: [CGRect] = []

    private var screenAboveCG: CGRect = .zero
    private var screenLeftCG: CGRect = .zero
    private var snappedCG: CGRect = .zero

    private var cg1080Y: CGFloat = 0
    private var cg4KY: CGFloat = 0

    private var dragMonitor = DragMonitor()
    private var dragStarted = false
    private var overlayAppeared = false
    private var snapAttempted = false

    func register(in registry: StepRegistry) {
        registry.given("a display with the Dock on the left") { _ in
            self.screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            // Dock on left (70pt wide), menu bar at top (25pt high)
            self.visibleFrame = CGRect(x: 70, y: 0, width: 1850, height: 1055)
            self.layout = LayoutTemplate.columns(2)
        }

        registry.when("zones are resolved") { _ in
            self.resolvedZones = ZoneResolver.resolveAll(
                self.layout,
                in: self.visibleFrame,
                spacing: ZoneSpacing.none
            )
        }

        registry.then("no zone overlaps the Dock") { _ in
            for zone in self.resolvedZones {
                XCTAssertGreaterThanOrEqual(zone.minX, 70, "Zone must not overlap the Dock on the left")
            }
        }

        registry.then("no zone overlaps the menu bar") { _ in
            for zone in self.resolvedZones {
                XCTAssertLessThanOrEqual(zone.maxY, 1055, "Zone must not overlap the menu bar at the top")
            }
        }

        registry.given("zones resolved with the Dock at the bottom") { _ in
            self.screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            // Dock at bottom (70pt high), menu bar at top (25pt high)
            self.visibleFrame = CGRect(x: 0, y: 70, width: 1920, height: 985)
            self.layout = LayoutTemplate.columns(2)
            self.resolvedZones = ZoneResolver.resolveAll(self.layout, in: self.visibleFrame, spacing: .none)
        }

        registry.when("I move the Dock to the left") { _ in
            // Move Dock to left: new visibleFrame
            self.visibleFrame = CGRect(x: 70, y: 0, width: 1850, height: 1055)
            self.resolvedZones = ZoneResolver.resolveAll(self.layout, in: self.visibleFrame, spacing: .none)
        }

        registry.then("the zones re-resolve to the new visible frame") { _ in
            for zone in self.resolvedZones {
                XCTAssertGreaterThanOrEqual(zone.minX, 70)
                XCTAssertGreaterThanOrEqual(zone.minY, 0)
                XCTAssertLessThanOrEqual(zone.maxX, 1920)
                XCTAssertLessThanOrEqual(zone.maxY, 1055)
            }
        }

        registry.given("a display positioned above the primary") { _ in
            let primaryHeight: CGFloat = 1080
            let screenAboveAppKit = NSRect(x: 0, y: 1080, width: 1920, height: 1080)
            self.screenAboveCG = CoordinateConverter.appKitToCG(screenAboveAppKit, primaryHeight: primaryHeight)
            self.layout = LayoutTemplate.grid(rows: 2, columns: 2)
            self.visibleFrame = screenAboveAppKit
        }

        registry.when("I snap a window into its top-left zone") { _ in
            let zones = ZoneResolver.resolveAll(self.layout, in: self.visibleFrame, spacing: .none)
            // Top-left zone in AppKit is at the highest Y
            let topLeftAppKit = zones.max(by: { $0.maxY < $1.maxY })!
            self.snappedCG = CoordinateConverter.appKitToCG(topLeftAppKit, primaryHeight: 1080)
        }

        registry.then("the window lands on that display") { _ in
            XCTAssertTrue(self.screenAboveCG.contains(self.snappedCG), "Window must land inside the display above")
        }

        registry.then("not off-screen") { _ in
            XCTAssertGreaterThanOrEqual(self.snappedCG.minY, self.screenAboveCG.minY)
            XCTAssertLessThanOrEqual(self.snappedCG.maxY, self.screenAboveCG.maxY)
        }

        registry.given("a display positioned left of the primary") { _ in
            let primaryHeight: CGFloat = 1080
            let screenLeftAppKit = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
            self.screenLeftCG = CoordinateConverter.appKitToCG(screenLeftAppKit, primaryHeight: primaryHeight)
            self.layout = LayoutTemplate.columns(2)
            self.visibleFrame = screenLeftAppKit
        }

        registry.when("I snap a window into any zone") { _ in
            let zones = ZoneResolver.resolveAll(self.layout, in: self.visibleFrame, spacing: .none)
            let firstZone = zones[0]
            self.snappedCG = CoordinateConverter.appKitToCG(firstZone, primaryHeight: 1080)
        }

        registry.then("the window lands within that display's bounds") { _ in
            XCTAssertTrue(self.screenLeftCG.contains(self.snappedCG), "Window must land inside the left display's bounds")
        }

        registry.given("a 1080p display beside a 4K display") { _ in
            CoordinateConverter.primaryScreenHeightProvider = { 1080 }
        }

        registry.when("I snap a window into a zone on either") { _ in
            let screen1080 = NSRect(x: 0, y: 0, width: 1920, height: 1080)
            let screen4K = NSRect(x: 1920, y: 0, width: 3840, height: 2160)

            let zone1080 = NSRect(x: 0, y: 540, width: 960, height: 540)
            let zone4K = NSRect(x: 1920, y: 1080, width: 1920, height: 1080)

            let cg1080 = CoordinateConverter.appKitToCG(zone1080)
            let cg4K = CoordinateConverter.appKitToCG(zone4K)

            self.cg1080Y = cg1080.origin.y
            self.cg4KY = cg4K.origin.y
        }

        registry.then("the window's Y position is correct on both") { _ in
            // For 1080p: y = 1080 - 540 - 540 = 0
            XCTAssertEqual(self.cg1080Y, 0)
            // For 4K: y = 1080 - 1080 - 1080 = -1080
            XCTAssertEqual(self.cg4KY, -1080)
        }

        registry.then("the window does not jump when focus moves between them") { _ in
            // Conversion is stable across simulated focus shifts
            let convertedAgain = CoordinateConverter.appKitToCG(NSRect(x: 1920, y: 1080, width: 1920, height: 1080))
            XCTAssertEqual(convertedAgain.origin.y, self.cg4KY)
            CoordinateConverter.primaryScreenHeightProvider = nil
        }

        registry.given("the dragged window is in a full-screen Space") { _ in
            self.dragMonitor = DragMonitor()
            self.dragStarted = false
            self.overlayAppeared = false
            self.snapAttempted = false

            let win = WindowInfo(
                windowID: 999,
                ownerPID: 1234,
                ownerName: "TestApp",
                windowTitle: "Fullscreen",
                bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                bundleIdentifier: "com.test.fullscreen",
                layer: 0,
                isOnScreen: true
            )
            let mockWP = SimpleMockWindowProvider(windows: [win])
            self.dragMonitor.windowProvider = mockWP
            self.dragMonitor.isFullScreenSpace = { _ in true }

            self.dragMonitor.onDragStarted = { _, _ in self.dragStarted = true }
            self.dragMonitor.onDragMoved = { _, _, active, _ in
                if active { self.overlayAppeared = true }
            }
            self.dragMonitor.onDragEnded = { _, _, shouldSnap, _ in
                if shouldSnap { self.snapAttempted = true }
            }
        }

        registry.when("I hold the activation modifier") { _ in
            Settings.shared.update {
                $0.activationModifier = .shift
                $0.activationPolicy = .holdModifier
            }
            self.dragMonitor.handleMouseDown(at: CGPoint(x: 100, y: 20))
            self.dragMonitor.handleMouseDragged(at: CGPoint(x: 150, y: 80), flags: [.maskShift])
        }

        registry.then("no overlay appears") { _ in
            XCTAssertFalse(self.dragStarted)
            XCTAssertFalse(self.overlayAppeared)
        }

        registry.then("no snap is attempted") { _ in
            self.dragMonitor.handleMouseUp(at: CGPoint(x: 150, y: 80), flags: [.maskShift])
            XCTAssertFalse(self.snapAttempted)
        }
    }
}

private class SimpleMockWindowProvider: WindowProvider {
    var windows: [WindowInfo]
    init(windows: [WindowInfo]) { self.windows = windows }
    func listWindows() -> [WindowInfo] { windows }
    func appIcon(for pid: pid_t) -> NSImage? { nil }
    func listWindowsResolvingTitles() -> [WindowInfo] { windows }
}
