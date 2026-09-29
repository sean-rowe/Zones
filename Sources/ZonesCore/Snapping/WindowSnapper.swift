import ApplicationServices
import CoreGraphics
import Foundation

public struct SnapResult: Equatable, Sendable {
    public let verdict: SnapVerdict
    public let targetFrame: CGRect
    public let actualFrame: CGRect

    public init(verdict: SnapVerdict, targetFrame: CGRect, actualFrame: CGRect) {
        self.verdict = verdict
        self.targetFrame = targetFrame
        self.actualFrame = actualFrame
    }
}

/// Applies target zone frames to windows via Accessibility APIs.
/// Strictly uses the size -> position -> size dance and avoids infinite retry loops.
public class WindowSnapper {
    public var windowMatcher: WindowMatcher = WindowMatcher()
    public var onSnapFrame: ((CGRect) -> Void)?

    public init() {}

    /// Snaps a window identified by WindowInfo to a target frame in CoreGraphics screen coordinates.
    @discardableResult
    public func snap(window: WindowInfo, to targetCGFrame: CGRect) -> SnapResult? {
        guard let axElement = windowMatcher.findAXElement(for: window) else {
            ZonesLog.error("Snap", "Could not find AXElement for window: \(window.displayName)")
            return nil
        }
        return snap(element: axElement, to: targetCGFrame)
    }

    /// Snaps an AXUIElement to a target frame in CoreGraphics screen coordinates.
    @discardableResult
    public func snap(element: AXUIElement, to targetCGFrame: CGRect) -> SnapResult {
        onSnapFrame?(targetCGFrame)
        let ax = AccessibilityElement(element)

        // 1. Apply the size -> position -> size dance
        ax.setFrame(targetCGFrame)
        ax.raise()

        // 2. Read what the window actually took
        var actual = ax.frame ?? targetCGFrame

        // If the window clamped or shifted origin during sizing, ensure it is anchored at target origin
        let xDiff = abs(actual.origin.x - targetCGFrame.origin.x)
        let yDiff = abs(actual.origin.y - targetCGFrame.origin.y)
        if xDiff > 1.0 || yDiff > 1.0 {
            ax.position = targetCGFrame.origin
            actual = ax.frame ?? actual
        }

        // 3. Reconcile against target with quantisation slack
        let verdict = SnapReconciler.reconcile(actual: actual, target: targetCGFrame)

        switch verdict {
        case .accepted:
            ZonesLog.info("Snap", "Snap accepted: target=\(targetCGFrame), actual=\(actual)")
        case .axisRefused(let wRefused, let hRefused, let act, let tgt):
            ZonesLog.info("Snap", "Window refused axis: width=\(wRefused), height=\(hRefused), actual=\(act), target=\(tgt)")
        }

        return SnapResult(verdict: verdict, targetFrame: targetCGFrame, actualFrame: actual)
    }
}
