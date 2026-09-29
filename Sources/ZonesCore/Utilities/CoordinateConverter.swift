import AppKit

/// Converts between CoreGraphics coordinates (top-left origin, Y increases downward)
/// and AppKit coordinates (bottom-left origin, Y increases upward).
///
/// Both spaces are anchored to the *primary* display — the one with the menu bar,
/// whose AppKit origin is (0,0) and whose top-left is CG (0,0). Every other
/// display is described relative to it, so a display above the primary has
/// negative CG y and an AppKit y above the primary's height. That makes the
/// primary's height the only reference a conversion ever needs, whatever display
/// the point is on.
///
/// Which is why `NSScreen.main` has no business here: it is the screen with the
/// key window, not the primary. Three conversions in the drag paths used it, so
/// with displays of different heights a detached window jumped by the difference
/// the moment focus moved to the other screen.
public struct CoordinateConverter {
    /// Test seam to inject primary screen height without reading NSScreen.
    public static var primaryScreenHeightProvider: (() -> CGFloat)?

    /// Height of the primary screen in points.
    public static var primaryScreenHeight: CGFloat {
        if let provider = primaryScreenHeightProvider {
            return provider()
        }
        return NSScreen.screens.first?.frame.height ?? 0
    }

    /// Convert a CG rect (top-left origin) to an AppKit rect (bottom-left origin).
    public static func cgToAppKit(_ cgRect: CGRect, primaryHeight: CGFloat = primaryScreenHeight) -> NSRect {
        NSRect(
            x: cgRect.origin.x,
            y: primaryHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    /// Convert an AppKit rect (bottom-left origin) to a CG rect (top-left origin).
    public static func appKitToCG(_ nsRect: NSRect, primaryHeight: CGFloat = primaryScreenHeight) -> CGRect {
        CGRect(
            x: nsRect.origin.x,
            y: primaryHeight - nsRect.origin.y - nsRect.height,
            width: nsRect.width,
            height: nsRect.height
        )
    }

    /// Convert a CG point (top-left origin) to an AppKit point (bottom-left origin).
    public static func cgToAppKit(_ cgPoint: CGPoint, primaryHeight: CGFloat = primaryScreenHeight) -> NSPoint {
        NSPoint(x: cgPoint.x, y: primaryHeight - cgPoint.y)
    }

    /// Convert an AppKit point (bottom-left origin) to a CG point (top-left origin).
    public static func appKitToCG(_ nsPoint: NSPoint, primaryHeight: CGFloat = primaryScreenHeight) -> CGPoint {
        CGPoint(x: nsPoint.x, y: primaryHeight - nsPoint.y)
    }
}
