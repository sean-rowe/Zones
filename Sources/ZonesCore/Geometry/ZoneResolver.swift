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
    /// `Zone.rect` is normalized **top-left origin, Y down** (CoreGraphics).
    /// `area` is an AppKit rect — **bottom-left origin, Y up** — because it
    /// comes from `NSScreen.visibleFrame`. The Y axis is therefore flipped
    /// here. Mapping `zone.rect.minY` straight onto `area.minY` puts the top
    /// row of a layout along the bottom of the display, which looks plausible
    /// on a symmetric layout and is wrong on every other one.
    /// - Parameter adjacentEdges: which edges abut another zone, and so take
    ///   half a gap. Pass `nil` to infer it from the zone's position in the
    ///   unit square — correct for a regular tiling, approximate for anything
    ///   with a hole or a stepped edge. `resolveAll` computes real adjacency.
    public static func resolve(_ zone: Zone, in area: CGRect,
                               spacing: ZoneSpacing = .none,
                               adjacentEdges: ZoneEdges? = nil) -> CGRect {
        let padded = area.insetBy(dx: spacing.outerPadding, dy: spacing.outerPadding)
        // A display smaller than its own padding would invert the rect.
        guard padded.width > 0, padded.height > 0 else { return .zero }

        let raw = CGRect(
            x: padded.minX + zone.rect.minX * padded.width,
            // Flip: the zone's bottom edge (normalized maxY) is the smallest
            // AppKit y it occupies.
            y: padded.maxY - zone.rect.maxY * padded.height,
            width: zone.rect.width * padded.width,
            height: zone.rect.height * padded.height
        )
        let edges = adjacentEdges ?? inferredEdges(for: zone)
        return applyGap(to: raw, edges: edges, gap: spacing.gap)
    }

    /// Inset each edge that abuts another zone by half the gap.
    ///
    /// Only internal edges: insetting the outer edges too would double the
    /// padding the user asked for at the display's boundary. The vertical
    /// insets are named for what the *user* sees, which after the Y flip means
    /// the zone's normalized top edge moves the rect's `maxY`.
    /// Fallback for a zone resolved without its layout.
    private static func inferredEdges(for zone: Zone) -> ZoneEdges {
        let epsilon = 0.0001
        var edges: ZoneEdges = []
        if zone.rect.minX > epsilon { edges.insert(.left) }
        if zone.rect.maxX < 1 - epsilon { edges.insert(.right) }
        if zone.rect.minY > epsilon { edges.insert(.top) }
        if zone.rect.maxY < 1 - epsilon { edges.insert(.bottom) }
        return edges
    }

    private static func applyGap(to rect: CGRect, edges: ZoneEdges, gap: Double) -> CGRect {
        guard gap > 0 else { return rect }
        let half = gap / 2

        let insetLeft = edges.contains(.left) ? half : 0
        let insetRight = edges.contains(.right) ? half : 0
        let insetAbove = edges.contains(.top) ? half : 0
        let insetBelow = edges.contains(.bottom) ? half : 0

        let result = CGRect(
            x: rect.minX + insetLeft,
            y: rect.minY + insetBelow,
            width: rect.width - insetLeft - insetRight,
            height: rect.height - insetAbove - insetBelow
        )
        // Never hand back an inverted rect for a zone narrower than the gap.
        guard result.width > 0, result.height > 0 else { return .zero }
        return result
    }

    /// Resolve every zone in a layout.
    /// Resolve every zone, using real adjacency within the layout.
    public static func resolveAll(_ layout: ZoneLayout, in area: CGRect,
                                  spacing: ZoneSpacing = .none) -> [CGRect] {
        layout.zones.map {
            resolve($0, in: area, spacing: spacing,
                    adjacentEdges: layout.adjacentEdges(for: $0))
        }
    }
}
