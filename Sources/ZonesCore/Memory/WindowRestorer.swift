import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Coordinates remembering window zone assignments, restoring windows on display reconnect,
/// rescuing stranded off-screen windows, and snapping windows on application launch.
public class WindowRestorer {
    public let assignmentStore: ZoneAssignmentStore
    public let settings: Settings
    public let layouts: LayoutStore
    public var snapper: WindowSnapper
    public var windowProvider: WindowProvider
    public var screensProvider: () -> [NSScreen] = { NSScreen.screens }

    // Test callbacks
    public var onWindowRestored: ((WindowInfo, CGRect) -> Void)?
    public var onWindowRescued: ((WindowInfo, CGRect) -> Void)?

    private var launchObserver: NSObjectProtocol?
    private var displayObserver: NSObjectProtocol?

    public init(
        assignmentStore: ZoneAssignmentStore = .shared,
        settings: Settings = .shared,
        layouts: LayoutStore = .shared,
        snapper: WindowSnapper = WindowSnapper(),
        windowProvider: WindowProvider = WindowListProvider()
    ) {
        self.assignmentStore = assignmentStore
        self.settings = settings
        self.layouts = layouts
        self.snapper = snapper
        self.windowProvider = windowProvider
    }

    public func start() {
        stop()

        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleAppLaunch(notification: note)
        }

        displayObserver = NotificationCenter.default.addObserver(
            forName: .displayConfigurationDidSettle,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplayChange()
        }
    }

    public func stop() {
        if let o = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            launchObserver = nil
        }
        if let o = displayObserver {
            NotificationCenter.default.removeObserver(o)
            displayObserver = nil
        }
    }

    // MARK: - App Launch Restoration

    public func handleAppLaunch(notification: Notification) {
        guard settings.current.snapOnAppLaunch else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }

        // Find assignment for this bundle
        guard let assignment = assignmentStore.allAssignments().first(where: {
            $0.windowIdentity.bundleIdentifier == bundleID
        }) else { return }

        WindowAppearanceWaiter.waitForWindow(pid: app.processIdentifier) { [weak self] axWindow in
            guard let self = self, let axWindow = axWindow else { return }
            self.restore(axWindow: axWindow, to: assignment)
        }
    }

    public func restore(axWindow: AXUIElement, to assignment: ZoneAssignment) {
        let screens = screensProvider()
        let targetScreen = screens.first(where: { DisplayIdentity.forScreen($0) == assignment.displayIdentity })
            ?? screens.first
        guard let screen = targetScreen else { return }

        let targetIdentity = DisplayIdentity.forScreen(screen)
        guard let layout = layouts.assignedLayout(for: targetIdentity) ?? layouts.layouts.first else { return }
        guard !layout.zones.isEmpty else { return }

        let clampedIndex = min(assignment.zoneIndex, layout.zones.count - 1)
        let spacing = ZoneSpacing(settings: settings.current)
        let resolvedAppKit = ZoneResolver.resolveAll(layout, in: screen.visibleFrame, spacing: spacing)
        guard clampedIndex < resolvedAppKit.count else { return }

        let targetCG = CoordinateConverter.appKitToCG(resolvedAppKit[clampedIndex])
        snapper.snap(element: axWindow, to: targetCG)
    }

    // MARK: - Display Change Restoration & Rescue

    public func handleDisplayChange() {
        guard settings.current.restoreOnDisplayChange else { return }

        let screens = screensProvider()
        guard !screens.isEmpty else { return }
        let currentIdentities = Set(screens.map { DisplayIdentity.forScreen($0) })
        let windows = windowProvider.listWindows()

        for window in windows {
            guard let assignment = assignmentStore.assignment(for: window) else {
                // If unassigned window is stranded off-screen, rescue it
                if isWindowOffScreen(window: window, screens: screens) {
                    rescueOffScreenWindow(window: window, screens: screens)
                }
                continue
            }

            if currentIdentities.contains(assignment.displayIdentity) {
                // Display is connected: check if window needs to return to its assigned zone
                guard let screen = screens.first(where: { DisplayIdentity.forScreen($0) == assignment.displayIdentity }) else { continue }
                let layout = layouts.assignedLayout(for: assignment.displayIdentity) ?? layouts.layouts.first
                guard let layout = layout, !layout.zones.isEmpty else { continue }

                let clampedIndex = min(assignment.zoneIndex, layout.zones.count - 1)
                let spacing = ZoneSpacing(settings: settings.current)
                let resolvedAppKit = ZoneResolver.resolveAll(layout, in: screen.visibleFrame, spacing: spacing)
                guard clampedIndex < resolvedAppKit.count else { continue }

                let targetCG = CoordinateConverter.appKitToCG(resolvedAppKit[clampedIndex])
                // Check if window is not already in target zone
                let diffX = abs(window.bounds.origin.x - targetCG.origin.x)
                let diffY = abs(window.bounds.origin.y - targetCG.origin.y)
                if diffX > 32 || diffY > 32 {
                    snapper.snap(window: window, to: targetCG)
                    onWindowRestored?(window, targetCG)
                }
            } else {
                // Display is NOT connected: check if window was left stranded off-screen
                if isWindowOffScreen(window: window, screens: screens) {
                    rescueOffScreenWindow(window: window, screens: screens)
                }
            }
        }
    }

    public func isWindowOffScreen(window: WindowInfo, screens: [NSScreen]) -> Bool {
        let appKitOrigin = CoordinateConverter.cgToAppKit(window.bounds.origin)
        let appKitRect = NSRect(
            x: appKitOrigin.x,
            y: appKitOrigin.y - window.bounds.height,
            width: window.bounds.width,
            height: window.bounds.height
        )

        for screen in screens {
            let intersection = screen.frame.intersection(appKitRect)
            if intersection.width >= 40 && intersection.height >= 40 {
                return false
            }
        }
        return true
    }

    private func rescueOffScreenWindow(window: WindowInfo, screens: [NSScreen]) {
        guard let screen = screens.first else { return }
        ZonesLog.info("Memory", "Rescuing off-screen window '\(window.displayName)' onto display \(screen.localizedName)")

        // Move onto visibleFrame of first screen
        let visible = screen.visibleFrame
        let targetAppKit = NSRect(
            x: visible.minX + 40,
            y: visible.maxY - min(window.bounds.height, visible.height) - 40,
            width: min(window.bounds.width, visible.width - 80),
            height: min(window.bounds.height, visible.height - 80)
        )
        let targetCG = CoordinateConverter.appKitToCG(targetAppKit)
        snapper.snap(window: window, to: targetCG)
        onWindowRescued?(window, targetCG)
    }

    deinit { stop() }
}
