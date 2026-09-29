import AppKit
import ApplicationServices
import Foundation

/// Polls for an application's window to appear and have valid geometry,
/// avoiding race conditions where an app launches before its window has completed AX layout.
public class WindowAppearanceWaiter {
    public static var maxAttempts = 10
    public static var pauseInterval: TimeInterval = 0.05

    /// Test seam to bypass asynchronous polling in unit tests.
    public static var waiterOverride: ((pid_t, @escaping (AXUIElement?) -> Void) -> Void)?

    public static func waitForWindow(
        pid: pid_t,
        attempts: Int = maxAttempts,
        completion: @escaping (AXUIElement?) -> Void
    ) {
        if let override = waiterOverride {
            override(pid, completion)
            return
        }

        func check(remaining: Int) {
            let appElement = AXUIElementCreateApplication(pid)
            var windowsRef: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement],
               let firstWindow = windows.first {
                let ax = AccessibilityElement(firstWindow)
                if let sz = ax.size, sz.width > 50 && sz.height > 50 {
                    completion(firstWindow)
                    return
                }
            }

            if remaining > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + pauseInterval) {
                    check(remaining: remaining - 1)
                }
            } else {
                completion(nil)
            }
        }

        check(remaining: attempts)
    }
}
