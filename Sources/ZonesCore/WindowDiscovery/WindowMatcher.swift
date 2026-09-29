import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// Gets the CGWindowID out of an AXUIElement. Private API, used by Rectangle,
/// yabai, alt-tab-macos and every other window manager.
///
/// Resolved through `dlsym` rather than declared with `@_silgen_name` for the
/// same reason the SkyLight calls are: a `@_silgen_name` declaration is a link
/// requirement, so if a macOS update ever renames or drops the symbol the
/// process dies in dyld at launch — before the title-and-position fallback
/// below ever gets a chance to run. A nil function pointer just means falling
/// back.
private let axUIElementGetWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
    typealias Fn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
        ZonesLog.info("WindowMatcher", "_AXUIElementGetWindow unavailable — matching windows by title and position")
        return nil
    }
    return unsafeBitCast(symbol, to: Fn.self)
}()

/// The window ID behind an AX element, when the private API is there to say.
private func windowID(of element: AXUIElement) -> CGWindowID? {
    guard let getWindow = axUIElementGetWindow else { return nil }
    var id: CGWindowID = 0
    guard getWindow(element, &id) == .success else { return nil }
    return id
}

/// Bridges CGWindowID (from CGWindowListCopyWindowInfo) to AXUIElement (for manipulation)
public class WindowMatcher {
    public init() {}

    /// Whether the private window-ID lookup resolved on this system.
    public static var resolvesWindowIDsDirectly: Bool { axUIElementGetWindow != nil }

    /// How many times an application is asked for its windows before the
    /// window is given up on.
    public static var resolveAttempts = 4

    /// The wait between asks. A seam, so tests need not spend it.
    public static var resolvePause: () -> Void = { usleep(30_000) }

    /// Stand in for one attempt. The retry policy is the part worth testing and
    /// no real window appears late on demand.
    public var resolveOnceForTesting: ((WindowInfo) -> AXUIElement?)?

    /// Find the AXUIElement for a given WindowInfo.
    public func findAXElement(for windowInfo: WindowInfo) -> AXUIElement? {
        for attempt in 0..<max(1, Self.resolveAttempts) {
            if let element = resolveOnce(windowInfo) { return element }
            if attempt < max(1, Self.resolveAttempts) - 1 { Self.resolvePause() }
        }
        return nil
    }

    private func resolveOnce(_ windowInfo: WindowInfo) -> AXUIElement? {
        if let stub = resolveOnceForTesting { return stub(windowInfo) }
        let appElement = AXUIElementCreateApplication(windowInfo.ownerPID)

        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return nil
        }

        for axWindow in axWindows {
            // Method 1: the private API's own answer, when it is available.
            if windowID(of: axWindow) == windowInfo.windowID {
                return axWindow
            }

            // Method 2: Fallback — match by title and approximate position
            let wrapper = AccessibilityElement(axWindow)
            if let title = wrapper.title,
               title == windowInfo.windowTitle,
               let frame = wrapper.frame,
               abs(frame.origin.x - windowInfo.bounds.origin.x) < 5,
               abs(frame.origin.y - windowInfo.bounds.origin.y) < 5 {
                return axWindow
            }
        }

        return nil
    }

    /// Why `findAXElement(for:)` came back empty.
    public func explainMatchFailure(for windowInfo: WindowInfo) -> String {
        let appElement = AXUIElementCreateApplication(windowInfo.ownerPID)
        var windowsRef: AnyObject?
        let status = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString,
                                                   &windowsRef)
        guard status == .success, let axWindows = windowsRef as? [AXUIElement] else {
            return "the application did not return a window list (AX status \(status.rawValue)); "
                + "Accessibility may not be granted for it, or it does not expose its windows"
        }
        guard !axWindows.isEmpty else {
            return "the application returned an empty window list, so the window Zones can see "
                + "on screen is not one it exposes over Accessibility"
        }
        let ids = axWindows.compactMap { windowID(of: $0) }
        let titles = axWindows.prefix(6).map { AccessibilityElement($0).title ?? "<untitled>" }
        return "\(axWindows.count) window(s) offered over Accessibility "
            + "(ids \(ids.map(String.init).joined(separator: ","))) but none is "
            + "\(windowInfo.windowID); titles: \(titles.joined(separator: " | "))"
            + (Self.resolvesWindowIDsDirectly ? "" : " — matching by title and position only")
    }

    /// Find the AXUIElement for a window by its CGWindowID alone.
    public func findAXElement(windowID wanted: CGWindowID, pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return nil
        }

        return axWindows.first { windowID(of: $0) == wanted }
    }
}
