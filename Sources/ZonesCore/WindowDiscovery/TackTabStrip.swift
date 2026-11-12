import AppKit
import CoreGraphics

/// Tack — the sibling app that groups windows into tabs — draws a group's tab
/// strip as a separate borderless window of its own, sitting directly on the
/// active window's top edge and exactly as wide as it.
///
/// Zones has to leave room for that strip. Snapped to the full zone, the window
/// left the strip nowhere to go: Tack's settle pushed the window down by the
/// strip's height to keep the strip below the menu bar, so the window hung out
/// past the bottom of its zone. Zones then saw the window off its target origin
/// and pulled it back up, Tack pushed it down again, and the strip bounced
/// between the two.
///
/// The fix is to give the window the zone *minus* the strip: the strip then
/// fills the top of the zone and the window the rest, which is exactly where
/// Tack wants them, so neither app has anything to correct.
///
/// Detection reads the window server instead of talking to Tack. The strip is a
/// normal-level window owned by Tack, so it is enough to look for one lying
/// along the window's top edge.
public enum TackTabStrip {
    public static let bundleIdentifier = "com.pinyridgelabs.Tack"
    /// The process name a `swift run` build of Tack shows, which has no bundle.
    public static let processName = "Tack"

    /// How far the strip may sit from where it ought to be and still count.
    ///
    /// Tack welds the strip to a dragged window by sampling, and measures its
    /// own worst lag at about seventeen points, so a drop that lands mid-drag
    /// can find the strip that far behind.
    public static let alignmentTolerance: CGFloat = 24

    /// A strip is a short band; anything taller is some other Tack window
    /// (the picker, settings) that merely happens to be nearby.
    public static let heightRange: ClosedRange<CGFloat> = 12...80

    /// The smallest window height left after making room for a strip. A zone
    /// too short to hold both is snapped whole rather than crushed.
    public static let minimumRemainingHeight: CGFloat = 50

    /// The height of the Tack strip on top of a window, if there is one.
    ///
    /// - Parameters:
    ///   - window: the window's bounds, in CG coordinates.
    ///   - strips: bounds of windows owned by Tack, in CG coordinates.
    public static func stripHeight(above window: CGRect,
                                   among strips: [CGRect],
                                   tolerance: CGFloat = alignmentTolerance) -> CGFloat? {
        let matches = strips.filter { strip in
            heightRange.contains(strip.height)
                && abs(strip.maxY - window.minY) <= tolerance
                && abs(strip.minX - window.minX) <= tolerance
                && abs(strip.width - window.width) <= tolerance
        }
        // The closest fit wins if two groups' strips are stacked near each other.
        return matches.min {
            abs($0.maxY - window.minY) + abs($0.minX - window.minX)
                < abs($1.maxY - window.minY) + abs($1.minX - window.minX)
        }?.height
    }

    /// The zone with the strip's band taken off its top.
    public static func frame(_ target: CGRect, leavingRoomFor stripHeight: CGFloat) -> CGRect {
        guard stripHeight > 0,
              target.height - stripHeight >= minimumRemainingHeight else { return target }
        return CGRect(x: target.minX,
                      y: target.minY + stripHeight,
                      width: target.width,
                      height: target.height - stripHeight)
    }

    /// Whether a window-list entry belongs to Tack.
    static func isTack(ownerPID: pid_t, ownerName: String?) -> Bool {
        if ownerName == processName { return true }
        return NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier == bundleIdentifier
    }
}

/// Reads the window server to find a Tack strip on top of a given window.
public final class TackTabStripDetector {
    /// Seam: the current bounds of a window, in CG coordinates.
    public var windowBounds: (CGWindowID) -> CGRect?
    /// Seam: bounds of every on-screen window owned by Tack, in CG coordinates.
    public var tackWindowBounds: () -> [CGRect]

    public init() {
        windowBounds = { id in
            guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
                  let dict = list.first else { return nil }
            return TackTabStripDetector.bounds(of: dict)
        }
        tackWindowBounds = {
            guard let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]] else { return [] }
            return list.compactMap { dict in
                guard (dict[kCGWindowLayer as String] as? Int) == 0,
                      let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                      TackTabStrip.isTack(ownerPID: pid,
                                          ownerName: dict[kCGWindowOwnerName as String] as? String)
                else { return nil }
                return TackTabStripDetector.bounds(of: dict)
            }
        }
    }

    /// The height of the Tack strip on top of this window, or nil when the
    /// window is not the active tab of a Tack group.
    public func stripHeight(forWindowID id: CGWindowID) -> CGFloat? {
        let strips = tackWindowBounds()
        guard !strips.isEmpty, let window = windowBounds(id) else { return nil }
        return TackTabStrip.stripHeight(above: window, among: strips)
    }

    private static func bounds(of dict: [String: Any]) -> CGRect? {
        guard let b = dict[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(x: (b["X"] as? CGFloat) ?? 0,
                      y: (b["Y"] as? CGFloat) ?? 0,
                      width: (b["Width"] as? CGFloat) ?? 0,
                      height: (b["Height"] as? CGFloat) ?? 0)
    }
}
