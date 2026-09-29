import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public protocol DragMonitorCursorProvider {
    func currentMouseLocation() -> CGPoint
}

public class DefaultDragMonitorCursorProvider: DragMonitorCursorProvider {
    public init() {}
    public func currentMouseLocation() -> CGPoint {
        CoordinateConverter.appKitToCG(NSEvent.mouseLocation)
    }
}

/// Global monitor for window drags, watching mouse events and modifier keys via CGEventTap.
/// Observes drags and passes all events through to underlying applications.
public class DragMonitor {
    public var cursorProvider: DragMonitorCursorProvider = DefaultDragMonitorCursorProvider()
    public var windowProvider: WindowProvider = WindowListProvider()

    /// How far down from a window's top a drag counts as its title bar (in points).
    public var titleBarHeight: CGFloat = 40.0

    /// Minimum cursor movement to consider a gesture a drag.
    public var dragThreshold: CGFloat = 8.0

    /// Movement threshold for windows grabbed outside the title bar.
    public var windowMoveThreshold: CGFloat = 3.0

    /// Seam for reading window origin from window server.
    public var windowOrigin: (CGWindowID) -> CGPoint? = { windowID in
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let bounds = list.first?[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"] else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// Seam for detecting whether a window is in a full-screen Space.
    public var isFullScreenSpace: (WindowInfo) -> Bool = { window in
        guard let axElement = WindowMatcher().findAXElement(for: window) else { return false }
        return AccessibilityElement(axElement).isFullScreen
    }

    // State
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDragging = false
    private var potentialDrag = false
    private var draggedWindow: WindowInfo?
    private var dragStartPos: CGPoint = .zero
    private var candidateWindow: WindowInfo?
    private var candidateOrigin: CGPoint = .zero
    private var isCancelled = false
    private var secondaryClickToggled = false
    private var windowSnapshot: [WindowInfo] = []

    // Callbacks
    public var onDragStarted: ((WindowInfo, CGPoint) -> Void)?
    public var onDragMoved: ((CGPoint, WindowInfo, _ isActivated: Bool, _ isSpanHeld: Bool) -> Void)?
    public var onDragEnded: ((WindowInfo, CGPoint, _ shouldSnap: Bool, _ isSpanHeld: Bool) -> Void)?
    public var onDragCancelled: (() -> Void)?

    public init() {}

    public func start() {
        stop()

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<DragMonitor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                monitor.handleCGEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            ZonesLog.error("Drag", "Could not create drag event tap — drag snapping inactive")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        resetDrag()
    }

    // MARK: - Event Dispatch

    public func handleCGEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDown:
            handleMouseDown(at: event.location)
        case .leftMouseDragged:
            let flags = event.flags
            handleMouseDragged(at: event.location, flags: flags)
        case .leftMouseUp:
            let flags = event.flags
            handleMouseUp(at: event.location, flags: flags)
        case .rightMouseDown:
            handleRightMouseDown()
        case .flagsChanged:
            handleFlagsChanged(flags: event.flags)
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == 53 { // 53 = Escape
                handleEscapeKey()
            }
        default:
            break
        }
    }

    // MARK: - Handlers

    public func handleMouseDown(at location: CGPoint) {
        resetDrag()
        dragStartPos = location
        windowSnapshot = windowProvider.listWindows()

        guard let clicked = windowSnapshot.first(where: { $0.bounds.contains(location) }) else { return }

        if isFullScreenSpace(clicked) {
            ZonesLog.info("Drag", "Declined drag for window in full-screen Space: \(clicked.displayName)")
            return
        }

        let settings = Settings.shared.current
        if let bundleID = clicked.bundleIdentifier,
           settings.excludedBundleIdentifiers.contains(bundleID) {
            return
        }

        let distFromTop = location.y - clicked.bounds.origin.y
        if distFromTop >= 0 && distFromTop <= titleBarHeight {
            beginPotentialDrag(of: clicked)
        } else {
            candidateWindow = clicked
            candidateOrigin = windowOrigin(clicked.windowID) ?? clicked.bounds.origin
        }
    }

    public func handleMouseDragged(at location: CGPoint, flags: CGEventFlags) {
        if !potentialDrag, let candidate = candidateWindow, candidateHasMoved() {
            if isFullScreenSpace(candidate) {
                candidateWindow = nil
                return
            }
            beginPotentialDrag(of: candidate)
        }

        guard potentialDrag, let window = draggedWindow else { return }

        if !isDragging {
            let dx = abs(location.x - dragStartPos.x)
            let dy = abs(location.y - dragStartPos.y)
            if dx < dragThreshold && dy < dragThreshold { return }
            isDragging = true
            onDragStarted?(window, location)
        }

        if isCancelled { return }

        let active = isZoneActive(flags: flags)
        let span = isSpanModifierHeld(flags: flags)
        onDragMoved?(location, window, active, span)
    }

    public func handleMouseUp(at location: CGPoint, flags: CGEventFlags) {
        defer { resetDrag() }

        guard isDragging, !isCancelled, let window = draggedWindow else { return }
        if isFullScreenSpace(window) { return }

        let active = isZoneActive(flags: flags)
        let span = isSpanModifierHeld(flags: flags)
        onDragEnded?(window, location, active, span)
    }

    public func handleRightMouseDown() {
        guard isDragging, !isCancelled, Settings.shared.current.enableSecondaryClickToggle else { return }
        secondaryClickToggled.toggle()
        if let window = draggedWindow {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let active = isZoneActive(flags: flags)
            let span = isSpanModifierHeld(flags: flags)
            onDragMoved?(cursorProvider.currentMouseLocation(), window, active, span)
        }
    }

    public func handleFlagsChanged(flags: CGEventFlags) {
        guard isDragging, !isCancelled, let window = draggedWindow else { return }
        let active = isZoneActive(flags: flags)
        let span = isSpanModifierHeld(flags: flags)
        onDragMoved?(cursorProvider.currentMouseLocation(), window, active, span)
    }

    public func handleEscapeKey() {
        guard isDragging, !isCancelled else { return }
        isCancelled = true
        onDragCancelled?()
    }

    // MARK: - Helpers

    private func beginPotentialDrag(of window: WindowInfo) {
        potentialDrag = true
        draggedWindow = window
        candidateWindow = nil
    }

    private func candidateHasMoved() -> Bool {
        guard let candidate = candidateWindow,
              let now = windowOrigin(candidate.windowID) else { return false }
        return abs(now.x - candidateOrigin.x) > windowMoveThreshold
            || abs(now.y - candidateOrigin.y) > windowMoveThreshold
    }

    private func isZoneActive(flags: CGEventFlags) -> Bool {
        if let window = draggedWindow, isFullScreenSpace(window) {
            return false
        }
        let settings = Settings.shared.current
        if secondaryClickToggled {
            return true
        }
        switch settings.activationPolicy {
        case .alwaysWhileDragging:
            return true
        case .holdModifier:
            return isActivationModifierHeld(flags: flags)
        }
    }

    private func isActivationModifierHeld(flags: CGEventFlags) -> Bool {
        let mod = Settings.shared.current.activationModifier
        return flagMatches(modifier: mod, in: flags)
    }

    private func isSpanModifierHeld(flags: CGEventFlags) -> Bool {
        let mod = Settings.shared.current.spanModifier
        return flagMatches(modifier: mod, in: flags)
    }

    private func flagMatches(modifier: ActivationModifier, in flags: CGEventFlags) -> Bool {
        switch modifier {
        case .shift:   return flags.contains(.maskShift)
        case .control: return flags.contains(.maskControl)
        case .option:  return flags.contains(.maskAlternate)
        case .command: return flags.contains(.maskCommand)
        }
    }

    private func resetDrag() {
        isDragging = false
        potentialDrag = false
        draggedWindow = nil
        candidateWindow = nil
        isCancelled = false
        secondaryClickToggled = false
        windowSnapshot = []
    }

    deinit { stop() }
}
