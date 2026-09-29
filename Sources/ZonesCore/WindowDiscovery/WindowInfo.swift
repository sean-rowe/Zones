import CoreGraphics
import Foundation

/// Value type representing a discovered window from CGWindowListCopyWindowInfo
public struct WindowInfo: Identifiable, Hashable {
    public let windowID: CGWindowID
    public let ownerPID: pid_t
    public let ownerName: String
    public let windowTitle: String?
    public let bounds: CGRect
    public let bundleIdentifier: String?
    public let layer: Int
    public let isOnScreen: Bool

    public var id: CGWindowID { windowID }

    /// Display name: prefer window title, fall back to app name
    public var displayName: String {
        if let title = windowTitle, !title.isEmpty {
            return "\(ownerName) — \(title)"
        }
        return ownerName
    }

    public init(
        windowID: CGWindowID,
        ownerPID: pid_t,
        ownerName: String,
        windowTitle: String?,
        bounds: CGRect,
        bundleIdentifier: String?,
        layer: Int,
        isOnScreen: Bool
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.windowTitle = windowTitle
        self.bounds = bounds
        self.bundleIdentifier = bundleIdentifier
        self.layer = layer
        self.isOnScreen = isOnScreen
    }
}
