import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Manages global keyboard shortcuts for snapping the focused window:
/// - Move focused window to zone N (⌃⌥⌘1–9)
/// - Cycle to next / previous zone (⌃⌥⌘→ / ⌃⌥⌘←)
/// - Move to matching zone on next display (⌃⌥⌘↑ / ⌃⌥⌘↓)
public class HotKeyManager {
    public var snapper: WindowSnapper = WindowSnapper()

    // Test seams
    public var focusedWindowProvider: () -> AXUIElement? = {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard result == .success, let element = windowRef else { return nil }
        return (element as! AXUIElement)
    }

    public var screensProvider: () -> [NSScreen] = { NSScreen.screens }
    public var windowFrameProvider: (AXUIElement) -> CGRect? = { AccessibilityElement($0).frame }
    public var isFullScreenProvider: (AXUIElement) -> Bool = { AccessibilityElement($0).isFullScreen }
    public var layoutProvider: ((DisplayIdentity) -> ZoneLayout?)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var suspensionObserver: NSObjectProtocol?

    public var isSuspended: Bool = false

    public init() {}

    public func start() {
        stop()

        suspensionObserver = NotificationCenter.default.addObserver(
            forName: .hotKeyInterceptionChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.isSuspended = note.userInfo?["suspended"] as? Bool ?? false
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard !manager.isSuspended, let nsEvent = NSEvent(cgEvent: event) else {
                    return Unmanaged.passUnretained(event)
                }

                let consumed = manager.handleKeyEvent(nsEvent)
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            ZonesLog.error("HotKey", "Could not create hotkey event tap — shortcuts inactive")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        if let o = suspensionObserver {
            NotificationCenter.default.removeObserver(o)
            suspensionObserver = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    @discardableResult
    public func handleKeyEvent(_ event: NSEvent) -> Bool {
        let defaultModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
        let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])
        guard mods == defaultModifiers else { return false }

        // Number keys 1-9: keyCode 18-21 = 1-4, 23 = 5, 22 = 6, 26 = 7, 28 = 8, 25 = 9
        let numberKeys: [UInt16: Int] = [
            18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8
        ]

        if let zoneIndex = numberKeys[event.keyCode] {
            return snapFocusedWindow(toZoneIndex: zoneIndex)
        }

        // Left arrow (123) / Right arrow (124)
        if event.keyCode == 123 {
            return cycleFocusedWindow(direction: -1)
        } else if event.keyCode == 124 {
            return cycleFocusedWindow(direction: 1)
        }

        // Up arrow (126) / Down arrow (125): Next / Previous display
        if event.keyCode == 126 || event.keyCode == 125 {
            let direction = event.keyCode == 126 ? 1 : -1
            return moveFocusedWindowToDisplay(direction: direction)
        }

        return false
    }

    // MARK: - Snapping Logic

    public func snapFocusedWindow(toZoneIndex index: Int) -> Bool {
        guard let (windowElement, screen, layout) = currentTargetContext() else { return false }
        guard index >= 0 && index < layout.zones.count else { return false }

        let targetRect = resolveRect(forZoneIndex: index, in: screen, layout: layout)
        snapper.snap(element: windowElement, to: targetRect)
        return true
    }

    public func cycleFocusedWindow(direction: Int) -> Bool {
        guard let (windowElement, screen, layout) = currentTargetContext() else { return false }
        guard !layout.zones.isEmpty else { return false }

        let currentZoneIndex = currentZoneIndex(for: windowElement, in: screen, layout: layout)
        let count = layout.zones.count
        let nextIndex: Int
        if let cur = currentZoneIndex {
            nextIndex = (cur + direction + count) % count
        } else {
            nextIndex = direction > 0 ? 0 : count - 1
        }

        let targetRect = resolveRect(forZoneIndex: nextIndex, in: screen, layout: layout)
        snapper.snap(element: windowElement, to: targetRect)
        return true
    }

    public func moveFocusedWindowToDisplay(direction: Int) -> Bool {
        guard let (windowElement, currentScreen, currentLayout) = currentTargetContext() else { return false }
        let screens = screensProvider()
        guard screens.count > 1 else { return false }

        guard let curScreenIdx = screens.firstIndex(of: currentScreen) else { return false }
        let nextScreenIdx = (curScreenIdx + direction + screens.count) % screens.count
        let targetScreen = screens[nextScreenIdx]

        let targetIdentity = DisplayIdentity.forScreen(targetScreen)
        guard let targetLayout = layoutProvider?(targetIdentity) else { return false }
        guard !targetLayout.zones.isEmpty else { return false }

        // Find current zone index or default to 0
        let curZoneIdx = currentZoneIndex(for: windowElement, in: currentScreen, layout: currentLayout) ?? 0

        // Clamps to last zone if target layout is shorter
        let clampedIdx = min(curZoneIdx, targetLayout.zones.count - 1)

        let targetRect = resolveRect(forZoneIndex: clampedIdx, in: targetScreen, layout: targetLayout)
        snapper.snap(element: windowElement, to: targetRect)
        return true
    }

    // MARK: - Helpers

    private func currentTargetContext() -> (AXUIElement, NSScreen, ZoneLayout)? {
        guard let windowElement = focusedWindowProvider() else { return nil }
        guard !isFullScreenProvider(windowElement) else { return nil }
        guard let frame = windowFrameProvider(windowElement) else { return nil }

        let windowCenter = CGPoint(x: frame.midX, y: frame.midY)
        let screens = screensProvider()
        guard let screen = screens.first(where: {
            let appKitOrigin = CoordinateConverter.cgToAppKit(windowCenter)
            return $0.frame.contains(appKitOrigin)
        }) ?? screens.first else {
            return nil
        }

        let identity = DisplayIdentity.forScreen(screen)
        guard let layout = layoutProvider?(identity) else { return nil }

        return (windowElement, screen, layout)
    }

    private func currentZoneIndex(for windowElement: AXUIElement, in screen: NSScreen, layout: ZoneLayout) -> Int? {
        guard let frame = windowFrameProvider(windowElement) else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)

        let spacing = ZoneSpacing(settings: Settings.shared.current)
        let resolvedAppKit = ZoneResolver.resolveAll(layout, in: screen.visibleFrame, spacing: spacing)
        let cgZones: [(index: Int, rect: CGRect)] = resolvedAppKit.enumerated().map {
            (index: $0, rect: CoordinateConverter.appKitToCG($1))
        }

        return ZoneHitTester.hitTest(point: center, zones: cgZones)?.primaryIndex
    }

    private func resolveRect(forZoneIndex index: Int, in screen: NSScreen, layout: ZoneLayout) -> CGRect {
        let spacing = ZoneSpacing(settings: Settings.shared.current)
        let resolvedAppKit = ZoneResolver.resolveAll(layout, in: screen.visibleFrame, spacing: spacing)
        let appKitRect = resolvedAppKit[index]
        return CoordinateConverter.appKitToCG(appKitRect)
    }

    deinit { stop() }
}
