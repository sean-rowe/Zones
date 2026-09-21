import AppKit
import CoreGraphics
import Foundation

/// Spacing applied when turning normalized zones into real rects.
public struct ZoneSpacing: Equatable, Sendable {
    /// Inset from the display's visible frame.
    public var outerPadding: Double
    /// Space between adjacent zones. Applied as half the gap on each side of
    /// every internal edge, so two neighbours end up a full gap apart.
    public var gap: Double

    public init(outerPadding: Double = 8, gap: Double = 8) {
        self.outerPadding = max(0, outerPadding)
        self.gap = max(0, gap)
    }

    public init(settings: AppSettings) {
        self.init(outerPadding: settings.outerPadding, gap: settings.zoneGap)
    }

    public static let none = ZoneSpacing(outerPadding: 0, gap: 0)
}

/// Turns normalized zones into rects on an actual display.
public enum ZoneResolver {

    /// Resolve a zone against a display area.
    ///
    /// `area` must be the screen's **visibleFrame**, never its `frame`:
    /// visibleFrame excludes the menu bar and the Dock, and resolving against
    /// `frame` puts zones underneath both.
    public static func resolve(_ zone: Zone, in area: CGRect,
                               spacing: ZoneSpacing = .none) -> CGRect {
        let padded = area.insetBy(dx: spacing.outerPadding, dy: spacing.outerPadding)
        // A display smaller than its own padding would invert the rect.
        guard padded.width > 0, padded.height > 0 else { return .zero }

        let raw = CGRect(
            x: padded.minX + zone.rect.minX * padded.width,
            y: padded.minY + zone.rect.minY * padded.height,
            width: zone.rect.width * padded.width,
            height: zone.rect.height * padded.height
        )
        return applyGap(to: raw, zone: zone, within: padded, gap: spacing.gap)
    }

    /// Inset each edge that abuts another zone by half the gap.
    ///
    /// Only internal edges: insetting the outer edges too would double the
    /// padding the user asked for at the display's boundary.
    private static func applyGap(to rect: CGRect, zone: Zone,
                                 within bounds: CGRect, gap: Double) -> CGRect {
        guard gap > 0 else { return rect }
        let half = gap / 2
        let epsilon = 0.0001

        let insetLeft = zone.rect.minX > epsilon ? half : 0
        let insetRight = zone.rect.maxX < 1 - epsilon ? half : 0
        let insetTop = zone.rect.minY > epsilon ? half : 0
        let insetBottom = zone.rect.maxY < 1 - epsilon ? half : 0

        let result = CGRect(
            x: rect.minX + insetLeft,
            y: rect.minY + insetTop,
            width: rect.width - insetLeft - insetRight,
            height: rect.height - insetTop - insetBottom
        )
        // Never hand back an inverted rect for a zone narrower than the gap.
        guard result.width > 0, result.height > 0 else { return .zero }
        return result
    }

    /// Resolve every zone in a layout.
    public static func resolveAll(_ layout: ZoneLayout, in area: CGRect,
                                  spacing: ZoneSpacing = .none) -> [CGRect] {
        layout.zones.map { resolve($0, in: area, spacing: spacing) }
    }
}
