import CoreGraphics
import Foundation

// Pure geometry behind the layout editor's views. Nothing here touches AppKit,
// so every rule the views depend on — where a card goes, where a split lands,
// what a drag selects — is testable without a window.

// MARK: - Unit square <-> view

/// Converts between the model's unit square and a rect in a non-flipped view.
///
/// The model is top-left origin (as CoreGraphics); AppKit views are
/// bottom-left. Every editor surface draws through this one type so the flip
/// is written once, the same way `ZoneResolver` does it.
public struct UnitSquareMapping: Equatable, Sendable {
    /// The view rect the unit square is stretched over.
    public var area: CGRect

    public init(area: CGRect) {
        self.area = area
    }

    /// View rect for a normalized rect.
    public func viewRect(for normalized: CGRect) -> CGRect {
        CGRect(x: area.minX + normalized.minX * area.width,
               y: area.maxY - normalized.maxY * area.height,
               width: normalized.width * area.width,
               height: normalized.height * area.height)
    }

    /// Normalized point for a view point. Not clamped: callers decide whether
    /// a point outside the square means "nothing" or "the nearest edge".
    public func normalizedPoint(for point: CGPoint) -> CGPoint {
        guard area.width > 0, area.height > 0 else { return .zero }
        return CGPoint(x: (point.x - area.minX) / area.width,
                       y: (area.maxY - point.y) / area.height)
    }

    /// View x for a normalized x.
    public func viewX(_ x: Double) -> CGFloat { area.minX + CGFloat(x) * area.width }

    /// View y for a normalized y.
    public func viewY(_ y: Double) -> CGFloat { area.maxY - CGFloat(y) * area.height }

    /// Normalized length for a distance in points along an axis, used to turn
    /// a pointer delta into a model delta.
    public func normalizedDelta(_ delta: CGVector) -> CGVector {
        guard area.width > 0, area.height > 0 else { return .zero }
        // Y flips: dragging up in the view moves towards the model's top.
        return CGVector(dx: delta.dx / area.width, dy: -delta.dy / area.height)
    }
}

// MARK: - Card grid

/// Wrap-panel placement of the layout cards, left to right then down.
///
/// Mirrors the FancyZones editor, where the cards flow and wrap as the window
/// is resized rather than stretching. Coordinates are top-left origin, for the
/// flipped document view the picker lays them out in.
public struct CardGridLayout: Equatable, Sendable {
    public var cardSize: CGSize
    public var spacing: CGFloat

    public init(cardSize: CGSize, spacing: CGFloat) {
        self.cardSize = cardSize
        self.spacing = spacing
    }

    /// How many cards fit across a width. Never zero: a window narrower than
    /// one card still shows a column, clipped, rather than nothing at all.
    public func columns(forWidth width: CGFloat) -> Int {
        guard cardSize.width > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (cardSize.width + spacing)).rounded(.down)))
    }

    /// Frames for `count` cards in a width, starting at `origin`.
    public func frames(count: Int, width: CGFloat, origin: CGPoint = .zero) -> [CGRect] {
        let columns = columns(forWidth: width)
        return (0..<max(0, count)).map { index in
            let column = index % columns
            let row = index / columns
            return CGRect(x: origin.x + CGFloat(column) * (cardSize.width + spacing),
                          y: origin.y + CGFloat(row) * (cardSize.height + spacing),
                          width: cardSize.width, height: cardSize.height)
        }
    }

    /// Height the cards occupy, with no trailing spacing.
    public func height(count: Int, width: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = (count + columns(forWidth: width) - 1) / columns(forWidth: width)
        return CGFloat(rows) * cardSize.height + CGFloat(rows - 1) * spacing
    }
}

// MARK: - Monitor strip

/// Placement of the monitor thumbnails along the top of the picker.
public enum MonitorStripLayout {

    /// Frames for displays of the given sizes, in a strip of the given bounds.
    ///
    /// One shared scale for every display, so a laptop panel next to a large
    /// external monitor reads as the smaller of the two — the point of drawing
    /// them proportionally. The scale is the largest that fits both the
    /// tallest display into the strip's height and the whole row into its
    /// width. The row is centred horizontally and each thumbnail vertically.
    /// Top-left origin, like the card grid.
    public static func frames(for sizes: [CGSize], in bounds: CGSize,
                              spacing: CGFloat) -> [CGRect] {
        guard !sizes.isEmpty,
              let tallest = sizes.map(\.height).max(), tallest > 0 else { return [] }
        let totalWidth = sizes.reduce(0) { $0 + $1.width }
        let availableWidth = bounds.width - spacing * CGFloat(sizes.count - 1)
        guard totalWidth > 0, availableWidth > 0 else { return sizes.map { _ in .zero } }

        let scale = min(bounds.height / tallest, availableWidth / totalWidth)
        let rowWidth = totalWidth * scale + spacing * CGFloat(sizes.count - 1)
        var x = (bounds.width - rowWidth) / 2
        return sizes.map { size in
            let frame = CGRect(x: x, y: (bounds.height - size.height * scale) / 2,
                               width: size.width * scale, height: size.height * scale)
            x += frame.width + spacing
            return frame
        }
    }

    /// Display order for the strip: left to right as arranged in System
    /// Settings, ties broken top to bottom. The number on each thumbnail is
    /// its position in this order, as FancyZones numbers them.
    public static func order(of frames: [CGRect]) -> [Int] {
        frames.indices.sorted { a, b in
            if abs(frames[a].minX - frames[b].minX) > 0.5 {
                return frames[a].minX < frames[b].minX
            }
            // AppKit frames grow upwards, so the higher display has the larger y.
            return frames[a].maxY > frames[b].maxY
        }
    }
}

// MARK: - Grid zone editor

/// Where the grid editor's preview line sits, and so where a click splits.
public enum GridSplitPreview {

    /// The split position for a pointer inside a zone, or nil when the zone is
    /// too small to split along that axis at all.
    ///
    /// Clamped so both parts keep the minimum size. Clamping the preview,
    /// rather than refusing the click, means the line the user sees is always
    /// the cut they get — it simply stops moving near the edge.
    public static func position(for point: CGPoint, in zone: CGRect,
                                axis: SplitterAxis,
                                minimum: Double = LayoutEditing.minimumZoneFraction) -> Double? {
        let lower = Double(axis == .vertical ? zone.minX : zone.minY)
        let upper = Double(axis == .vertical ? zone.maxX : zone.maxY)
        guard upper - lower >= minimum * 2 else { return nil }
        let raw = Double(axis == .vertical ? point.x : point.y)
        return min(max(raw, lower + minimum), upper - minimum)
    }

    /// The axis a split runs along for the modifier state.
    ///
    /// Vertical by default and Shift for horizontal, as in FancyZones.
    public static func axis(shiftHeld: Bool) -> SplitterAxis {
        shiftHeld ? .horizontal : .vertical
    }
}

/// Turns a drag across zones into a selection that can always be merged.
public enum ZoneDragSelection {

    /// Every zone a drag from one zone to another covers.
    ///
    /// Starts from the bounding rect of the two zones and keeps growing it to
    /// take in any zone it cuts through, until it stops changing. The result
    /// is always a rectangle made of whole zones, which is exactly what
    /// `LayoutEditing.canMerge` requires — so "Merge zones" never appears for a
    /// selection it would then refuse. This is how the FancyZones grid editor
    /// behaves, too: the selection snaps outwards to whole zones.
    public static func selection(from startID: UUID, to endID: UUID,
                                 in layout: ZoneLayout) -> Set<UUID> {
        guard let start = layout.zones.first(where: { $0.id == startID }),
              let end = layout.zones.first(where: { $0.id == endID }) else { return [] }
        let epsilon: CGFloat = 0.0001
        var bounds = start.rect.union(end.rect)
        var selected: Set<UUID> = []

        // Each pass can only grow the set, and it is bounded by the zone count.
        for _ in 0...layout.zones.count {
            let covered = layout.zones.filter { zone in
                let overlap = zone.rect.intersection(bounds)
                return !overlap.isNull && overlap.width > epsilon && overlap.height > epsilon
            }
            selected = Set(covered.map(\.id))
            let grown = covered.dropFirst().reduce(covered.first?.rect ?? bounds) { $0.union($1.rect) }
            if abs(grown.minX - bounds.minX) < epsilon, abs(grown.minY - bounds.minY) < epsilon,
               abs(grown.maxX - bounds.maxX) < epsilon, abs(grown.maxY - bounds.maxY) < epsilon {
                break
            }
            bounds = grown
        }
        return selected
    }

    /// Bounding rect of a selection, for placing the merge button beside it.
    public static func bounds(of ids: Set<UUID>, in layout: ZoneLayout) -> CGRect? {
        let rects = layout.zones.filter { ids.contains($0.id) }.map(\.rect)
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }
}

// MARK: - Canvas zone editor

/// A resize handle on a canvas zone. Top means the zone's visual top, which
/// is its smallest normalized y.
public enum CanvasHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    var movesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
    var movesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
    var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
    var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }

    /// The handle's anchor point on a normalized rect.
    public func point(on rect: CGRect) -> CGPoint {
        let x = movesLeft ? rect.minX : (movesRight ? rect.maxX : rect.midX)
        let y = movesTop ? rect.minY : (movesBottom ? rect.maxY : rect.midY)
        return CGPoint(x: x, y: y)
    }
}

/// Pure edits for free-form canvas zones, all in normalized space.
public enum CanvasEditing {

    /// Size of a freshly added zone, as a fraction of the display.
    public static let newZoneSize = CGSize(width: 0.3, height: 0.3)

    /// How far each new zone steps from the last, so a stack of new zones
    /// stays visibly a stack instead of hiding behind the first.
    public static let cascadeStep: CGFloat = 0.04

    /// Move a rect by a delta, kept wholly inside the unit square.
    ///
    /// The size never changes: dragging a zone against the edge stops it there
    /// rather than squashing it, which is what a move should do.
    public static func moved(_ rect: CGRect, by delta: CGVector) -> CGRect {
        let x = min(max(rect.minX + delta.dx, 0), 1 - rect.width)
        let y = min(max(rect.minY + delta.dy, 0), 1 - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// Resize a rect by dragging one handle to a normalized point.
    ///
    /// The opposite edge stays put; the dragged edge is clamped to the unit
    /// square and to the minimum size, so a zone can never be inverted or
    /// shrunk to nothing.
    public static func resized(_ rect: CGRect, handle: CanvasHandle, to point: CGPoint,
                               minimum: Double = LayoutEditing.minimumZoneFraction) -> CGRect {
        let minimum = CGFloat(minimum)
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesLeft { minX = min(max(point.x, 0), maxX - minimum) }
        if handle.movesRight { maxX = max(min(point.x, 1), minX + minimum) }
        if handle.movesTop { minY = min(max(point.y, 0), maxY - minimum) }
        if handle.movesBottom { maxY = max(min(point.y, 1), minY + minimum) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Where to put a new zone so it does not land exactly on an existing one.
    ///
    /// Cascades from the top-left, stepping diagonally past every slot already
    /// taken, and wraps back to the start once it would run off the display.
    public static func newZoneRect(avoiding existing: [CGRect]) -> CGRect {
        let start: CGFloat = 0.05
        let maxOffset = 1 - newZoneSize.width - start
        let slots = max(1, Int((maxOffset / cascadeStep).rounded(.down)) + 1)
        for step in 0..<slots {
            let offset = start + CGFloat(step) * cascadeStep
            let candidate = CGRect(x: offset, y: offset,
                                   width: newZoneSize.width, height: newZoneSize.height)
            let taken = existing.contains {
                abs($0.minX - candidate.minX) < 0.001 && abs($0.minY - candidate.minY) < 0.001
            }
            if !taken { return candidate }
        }
        return CGRect(origin: CGPoint(x: start, y: start), size: newZoneSize)
    }

    /// Topmost zone containing a normalized point. Later zones draw on top, so
    /// they win.
    public static func zone(at point: CGPoint, in layout: ZoneLayout) -> Zone? {
        layout.zones.last { $0.rect.contains(point) }
    }

    /// Replace one zone's rect, keeping its identity and number.
    public static func replacing(_ zoneID: UUID, with rect: CGRect,
                                 in layout: ZoneLayout) -> ZoneLayout {
        var updated = layout
        updated.replaceZones(layout.zones.map {
            $0.id == zoneID ? Zone(id: $0.id, index: $0.index, rect: rect) : $0
        })
        return updated
    }

    /// Append a new zone at the next cascade slot.
    public static func addingZone(to layout: ZoneLayout) -> ZoneLayout {
        var updated = layout
        let rect = newZoneRect(avoiding: layout.zones.map(\.rect))
        updated.replaceZones(layout.zones + [Zone(index: layout.zones.count, rect: rect)])
        return updated
    }

    /// Remove a zone. The rest renumber, so the shortcuts stay contiguous.
    public static func removingZone(_ zoneID: UUID, from layout: ZoneLayout) -> ZoneLayout {
        var updated = layout
        updated.replaceZones(layout.zones.filter { $0.id != zoneID })
        return updated
    }
}
