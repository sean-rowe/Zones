import CoreGraphics
import AppKit

public protocol WindowProvider {
    func listWindows() -> [WindowInfo]
    func appIcon(for pid: pid_t) -> NSImage?
    func listWindowsResolvingTitles() -> [WindowInfo]
}

extension WindowProvider {
    public func listWindowsResolvingTitles() -> [WindowInfo] { listWindows() }
    public func eligibilityReport() -> [String] { [] }
}

/// What `listWindows` decided about one window the system reported.
public enum WindowAdmission: Equatable {
    case admitted
    /// Not on the normal window layer. Menus, panels, overlays and some
    /// meeting windows live above it; a window Zones moves has to be one the
    /// user thinks of as a window.
    case notNormalLayer(Int)
    /// Smaller than 50pt on a side — utility and invisible windows.
    case tooSmall(CGSize)
    case zonesOwn
    case noBounds

    public var isAdmitted: Bool { self == .admitted }

    public var reason: String {
        switch self {
        case .admitted: return "admitted"
        case .notNormalLayer(let layer): return "rejected: layer \(layer), not 0"
        case .tooSmall(let size):
            return "rejected: \(Int(size.width))x\(Int(size.height)), under 50pt"
        case .zonesOwn: return "rejected: Zones' own window"
        case .noBounds: return "rejected: no bounds reported"
        }
    }
}

/// Enumerates visible windows on the system using CGWindowListCopyWindowInfo
public class WindowListProvider: WindowProvider {
    public init() {}

    /// Returns all visible, normal-layer windows (excluding our own, desktop elements, tiny windows)
    public func listWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let myPID = ProcessInfo.processInfo.processIdentifier

        return windowList.compactMap { dict -> WindowInfo? in
            guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                  let ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let ownerName = dict[kCGWindowOwnerName as String] as? String,
                  let layer = dict[kCGWindowLayer as String] as? Int
            else { return nil }

            // Parse bounds
            guard let boundsDict = dict[kCGWindowBounds as String] as? [String: Any] else { return nil }
            let bounds = CGRect(
                x: (boundsDict["X"] as? CGFloat) ?? 0,
                y: (boundsDict["Y"] as? CGFloat) ?? 0,
                width: (boundsDict["Width"] as? CGFloat) ?? 0,
                height: (boundsDict["Height"] as? CGFloat) ?? 0
            )

            guard Self.admit(layer: layer, ownerPID: ownerPID,
                             myPID: myPID, bounds: bounds).isAdmitted else { return nil }

            let windowTitle = dict[kCGWindowName as String] as? String
            let isOnScreen = dict[kCGWindowIsOnscreen as String] as? Bool ?? false
            let bundleID = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier

            return WindowInfo(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                windowTitle: windowTitle,
                bounds: bounds,
                bundleIdentifier: bundleID,
                layer: layer,
                isOnScreen: isOnScreen
            )
        }
    }

    /// Apply the same rules `listWindows` applies, but keep the verdict.
    public static func admit(layer: Int?, ownerPID: pid_t?, myPID: pid_t,
                             bounds: CGRect?) -> WindowAdmission {
        guard let layer = layer else { return .notNormalLayer(-1) }
        guard let ownerPID = ownerPID else { return .noBounds }
        guard layer == 0 else { return .notNormalLayer(layer) }
        guard ownerPID != myPID else { return .zonesOwn }
        guard let bounds = bounds else { return .noBounds }
        guard bounds.width > 50 && bounds.height > 50 else { return .tooSmall(bounds.size) }
        return .admitted
    }

    public func eligibilityReport() -> [String] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return ["the window server returned no list at all"]
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        var lines: [String] = []
        for dict in windowList {
            let owner = dict[kCGWindowOwnerName as String] as? String ?? "?"
            let layer = dict[kCGWindowLayer as String] as? Int
            let ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t
            let title = dict[kCGWindowName as String] as? String ?? ""
            var bounds: CGRect?
            if let b = dict[kCGWindowBounds as String] as? [String: Any] {
                bounds = CGRect(x: (b["X"] as? CGFloat) ?? 0, y: (b["Y"] as? CGFloat) ?? 0,
                                width: (b["Width"] as? CGFloat) ?? 0,
                                height: (b["Height"] as? CGFloat) ?? 0)
            }
            let verdict = Self.admit(layer: layer, ownerPID: ownerPID,
                                     myPID: myPID, bounds: bounds)
            if verdict == .zonesOwn { continue }
            lines.append("\(owner) '\(title.prefix(40))' — \(verdict.reason)")
        }
        return lines
    }

    /// Get the app icon for a given PID
    public func appIcon(for pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    public func listWindowsResolvingTitles() -> [WindowInfo] {
        let windows = listWindows()
        let pidsNeedingTitles = Set(windows.filter { ($0.windowTitle?.isEmpty ?? true) }
                                           .map { $0.ownerPID })
        guard !pidsNeedingTitles.isEmpty else { return windows }

        var axWindowsByPID: [pid_t: [AccessibilityElement]] = [:]
        for pid in pidsNeedingTitles {
            axWindowsByPID[pid] = AccessibilityElement(pid: pid).windows ?? []
        }

        return windows.map { info in
            guard info.windowTitle?.isEmpty ?? true,
                  let axWindows = axWindowsByPID[info.ownerPID],
                  let title = Self.title(forWindowAt: info.bounds, among: axWindows),
                  !title.isEmpty
            else { return info }

            return WindowInfo(
                windowID: info.windowID,
                ownerPID: info.ownerPID,
                ownerName: info.ownerName,
                windowTitle: title,
                bounds: info.bounds,
                bundleIdentifier: info.bundleIdentifier,
                layer: info.layer,
                isOnScreen: info.isOnScreen
            )
        }
    }

    private static func title(forWindowAt bounds: CGRect,
                              among axWindows: [AccessibilityElement]) -> String? {
        if axWindows.count == 1 {
            return axWindows[0].title
        }

        for axWindow in axWindows {
            guard let frame = axWindow.frame else { continue }
            if abs(frame.origin.x - bounds.origin.x) < 5,
               abs(frame.origin.y - bounds.origin.y) < 5,
               abs(frame.width - bounds.width) < 5,
               abs(frame.height - bounds.height) < 5 {
                return axWindow.title
            }
        }
        return nil
    }
}
