import CoreGraphics
import Foundation

/// Which way a divider runs.
public enum SplitterAxis: String, Codable, Sendable {
    /// A vertical line; dragging it changes zone widths.
    case vertical
    /// A horizontal line; dragging it changes zone heights.
    case horizontal
}

/// A shared internal edge between two groups of zones.
///
/// Derived from the layout rather than held as view state. A grid has obvious
/// dividers, but a custom layout's divider may be shared by three zones on one
/// side and one on the other, and only the zones that actually meet along it
/// should move. Deriving it keeps that correct; storing it would not survive
/// the first split.
public struct Splitter: Equatable, Identifiable, Sendable {
    public let axis: SplitterAxis
    /// Normalized position on the perpendicular axis: x for vertical, y for horizontal.
    public let position: Double
    /// Zones whose trailing edge lies on this splitter.
    public let leadingZoneIDs: [UUID]
    /// Zones whose leading edge lies on this splitter.
    public let trailingZoneIDs: [UUID]
    /// Extent along the splitter itself, used for hit-testing its drawn length.
    public let span: ClosedRange<Double>

    public var id: String { "\(axis.rawValue)@\(position)-\(span.lowerBound)" }
}

/// Pure edits to a layout. No AppKit, so every rule here is testable.
public enum LayoutEditing {

    /// Smallest fraction of a display a zone may be reduced to by dragging.
    ///
    /// Not zero, and not a point value: the editor works in normalized space,
    /// and a zone that reaches zero width cannot be grabbed again to undo it.
    public static let minimumZoneFraction: Double = 0.05

    static let epsilon = 0.0001

    // MARK: - Splitters

    /// Every draggable divider in a layout.
    public static func splitters(in layout: ZoneLayout) -> [Splitter] {
        var candidates: [Splitter] = []

        for zone in layout.zones {
            for other in layout.zones where other.id != zone.id {
                // Vertical: zone's right edge meets other's left edge.
                if abs(zone.rect.maxX - other.rect.minX) < epsilon,
                   let overlap = verticalOverlap(zone.rect, other.rect) {
                    candidates.append(Splitter(axis: .vertical, position: Double(zone.rect.maxX),
                                               leadingZoneIDs: [zone.id],
                                               trailingZoneIDs: [other.id], span: overlap))
                }
                // Horizontal: zone's bottom edge (larger normalized Y) meets
                // other's top edge.
                if abs(zone.rect.maxY - other.rect.minY) < epsilon,
                   let overlap = horizontalOverlap(zone.rect, other.rect) {
                    candidates.append(Splitter(axis: .horizontal, position: Double(zone.rect.maxY),
                                               leadingZoneIDs: [zone.id],
                                               trailingZoneIDs: [other.id], span: overlap))
                }
            }
        }
        return coalesce(candidates)
    }

    /// Combine candidates that are genuinely the same divider.
    ///
    /// Same axis and position is not enough. Two column pairs stacked one above
    /// the other share an x but are two separate dividers, and merging them
    /// would make dragging either one move zones in the other. They only
    /// combine when their spans also touch or overlap.
    static func coalesce(_ candidates: [Splitter]) -> [Splitter] {
        var groups: [Splitter] = []

        for candidate in candidates {
            // Absorb every existing group this candidate connects to — it may
            // bridge two that were previously disjoint.
            var merged = candidate
            var remaining: [Splitter] = []
            for group in groups {
                if group.axis == merged.axis,
                   abs(group.position - merged.position) < epsilon,
                   spansTouch(group.span, merged.span) {
                    merged = combine(group, merged)
                } else {
                    remaining.append(group)
                }
            }
            remaining.append(merged)
            groups = remaining
        }
        return groups.sorted {
            ($0.axis.rawValue, $0.position, $0.span.lowerBound)
                < ($1.axis.rawValue, $1.position, $1.span.lowerBound)
        }
    }

    private static func spansTouch(_ a: ClosedRange<Double>, _ b: ClosedRange<Double>) -> Bool {
        // Touching counts: two zones stacked against the same divider meet at a
        // shared boundary and form one continuous grab area.
        a.lowerBound <= b.upperBound + epsilon && b.lowerBound <= a.upperBound + epsilon
    }

    private static func combine(_ a: Splitter, _ b: Splitter) -> Splitter {
        let lower = min(a.span.lowerBound, b.span.lowerBound)
        let upper = max(a.span.upperBound, b.span.upperBound)
        var leading = a.leadingZoneIDs
        for id in b.leadingZoneIDs where !leading.contains(id) { leading.append(id) }
        var trailing = a.trailingZoneIDs
        for id in b.trailingZoneIDs where !trailing.contains(id) { trailing.append(id) }
        return Splitter(axis: a.axis, position: a.position,
                        leadingZoneIDs: leading, trailingZoneIDs: trailing,
                        span: lower...upper)
    }

    private static func verticalOverlap(_ a: CGRect, _ b: CGRect) -> ClosedRange<Double>? {
        let lower = max(a.minY, b.minY), upper = min(a.maxY, b.maxY)
        guard upper - lower > epsilon else { return nil }
        let l = Double(lower), u = Double(upper)
        return l...u
    }

    private static func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> ClosedRange<Double>? {
        let lower = max(a.minX, b.minX), upper = min(a.maxX, b.maxX)
        guard upper - lower > epsilon else { return nil }
        let l = Double(lower), u = Double(upper)
        return l...u
    }

    /// The range a splitter may be dragged within, given the minimum zone size.
    public static func allowedRange(for splitter: Splitter, in layout: ZoneLayout) -> ClosedRange<Double> {
        var lower = 0.0, upper = 1.0
        for zone in layout.zones {
            if splitter.leadingZoneIDs.contains(zone.id) {
                // Shrinking a leading zone moves the splitter down/left.
                let edge = splitter.axis == .vertical ? zone.rect.minX : zone.rect.minY
                lower = max(lower, Double(edge) + minimumZoneFraction)
            }
            if splitter.trailingZoneIDs.contains(zone.id) {
                let edge = splitter.axis == .vertical ? zone.rect.maxX : zone.rect.maxY
                upper = min(upper, Double(edge) - minimumZoneFraction)
            }
        }
        // A layout too tight to move at all still yields a valid single point.
        guard lower <= upper else {
            let fixed = (lower + upper) / 2
            return fixed...fixed
        }
        return lower...upper
    }

    /// Move a splitter, clamped so no zone drops below the minimum.
    ///
    /// The tiling stays exact because one group's trailing edge and the other's
    /// leading edge are set to the same value.
    public static func move(_ splitter: Splitter, to position: Double,
                           in layout: ZoneLayout) -> ZoneLayout {
        let range = allowedRange(for: splitter, in: layout)
        let clamped = min(max(position, range.lowerBound), range.upperBound)

        var updated = layout
        let zones = layout.zones.map { zone -> Zone in
            var rect = zone.rect
            if splitter.leadingZoneIDs.contains(zone.id) {
                if splitter.axis == .vertical {
                    rect = CGRect(x: rect.minX, y: rect.minY,
                                  width: clamped - Double(rect.minX), height: rect.height)
                } else {
                    rect = CGRect(x: rect.minX, y: rect.minY,
                                  width: rect.width, height: clamped - Double(rect.minY))
                }
            } else if splitter.trailingZoneIDs.contains(zone.id) {
                if splitter.axis == .vertical {
                    rect = CGRect(x: clamped, y: rect.minY,
                                  width: Double(rect.maxX) - clamped, height: rect.height)
                } else {
                    rect = CGRect(x: rect.minX, y: clamped,
                                  width: rect.width, height: Double(rect.maxY) - clamped)
                }
            }
            return Zone(id: zone.id, index: zone.index, rect: rect)
        }
        updated.replaceZones(zones)
        updated.origin = .custom   // no longer what the template generated
        return updated
    }

    // MARK: - Split and merge

    /// Replace a zone with two halves along an axis.
    public static func split(zoneID: UUID, axis: SplitterAxis,
                             in layout: ZoneLayout) -> ZoneLayout {
        guard let target = layout.zones.first(where: { $0.id == zoneID }) else { return layout }
        let rect = target.rect
        let halves: [CGRect]
        switch axis {
        case .vertical:
            let mid = rect.midX
            halves = [CGRect(x: rect.minX, y: rect.minY, width: mid - rect.minX, height: rect.height),
                      CGRect(x: mid, y: rect.minY, width: rect.maxX - mid, height: rect.height)]
        case .horizontal:
            let mid = rect.midY
            halves = [CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: mid - rect.minY),
                      CGRect(x: rect.minX, y: mid, width: rect.width, height: rect.maxY - mid)]
        }

        var zones: [Zone] = []
        for zone in layout.zones {
            if zone.id == zoneID {
                // First half keeps the original id, so anything pointing at
                // this zone still resolves to part of the same area.
                zones.append(Zone(id: zone.id, index: zone.index, rect: halves[0]))
                zones.append(Zone(index: zone.index + 1, rect: halves[1]))
            } else {
                zones.append(zone)
            }
        }
        var updated = layout
        updated.replaceZones(zones)
        updated.origin = .custom
        return updated
    }

    /// Whether a set of zones exactly tiles its own bounding rect.
    ///
    /// The test that makes merge safe. An L-shaped selection has a bounding
    /// rect larger than the sum of its parts, and merging it would swallow area
    /// belonging to a zone that was not selected.
    public static func canMerge(zoneIDs: Set<UUID>, in layout: ZoneLayout) -> Bool {
        let selected = layout.zones.filter { zoneIDs.contains($0.id) }
        guard selected.count >= 2 else { return false }

        let bounds = selected.dropFirst().reduce(selected[0].rect) { $0.union($1.rect) }
        let boundsArea = Double(bounds.width * bounds.height)
        let sum = selected.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        guard abs(boundsArea - sum) < epsilon else { return false }

        // Equal areas with an overlap would also balance, so rule that out.
        for i in selected.indices {
            for j in selected.indices where j > i {
                let overlap = selected[i].rect.intersection(selected[j].rect)
                let area = overlap.isNull ? 0 : Double(overlap.width * overlap.height)
                if area > epsilon { return false }
            }
        }
        return true
    }

    /// Merge zones into one covering their bounding rect, or return the layout
    /// unchanged when they do not form a rectangle.
    public static func merge(zoneIDs: Set<UUID>, in layout: ZoneLayout) -> ZoneLayout {
        guard canMerge(zoneIDs: zoneIDs, in: layout) else { return layout }
        let selected = layout.zones.filter { zoneIDs.contains($0.id) }
        let bounds = selected.dropFirst().reduce(selected[0].rect) { $0.union($1.rect) }
        let survivor = selected.min { $0.index < $1.index }!

        var zones: [Zone] = []
        for zone in layout.zones {
            if zone.id == survivor.id {
                zones.append(Zone(id: zone.id, index: zone.index, rect: bounds))
            } else if !zoneIDs.contains(zone.id) {
                zones.append(zone)
            }
        }
        var updated = layout
        updated.replaceZones(zones)
        updated.origin = .custom
        return updated
    }
}
