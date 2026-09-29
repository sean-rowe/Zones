import Foundation

/// A composite identity for a window, used to remember zone assignments across sessions.
///
/// NOTE: macOS does not provide durable window identifiers. Process IDs (PIDs) and
/// CoreGraphics window IDs (`CGWindowID`) are ephemeral and change whenever an application
/// relaunches or creates a new window. Therefore, `WindowIdentity` composes a heuristic identity
/// from:
///   1. `bundleIdentifier` (or process name if bundle ID is nil)
///   2. `windowTitle` (optional, can be empty or nil)
///   3. `axIndex` (the window's position in the application's AX window list)
///
/// This composite is heuristic and best-effort, but provides stable zone restoration
/// in common workflows (e.g. single-window or titled-window apps).
public struct WindowIdentity: Hashable, Codable, Sendable {
    public let bundleIdentifier: String
    public let windowTitle: String?
    public let axIndex: Int

    public init(bundleIdentifier: String, windowTitle: String? = nil, axIndex: Int = 0) {
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.axIndex = axIndex
    }

    public init(window: WindowInfo, axIndex: Int = 0) {
        self.init(
            bundleIdentifier: window.bundleIdentifier ?? window.ownerName,
            windowTitle: window.windowTitle,
            axIndex: axIndex
        )
    }
}
