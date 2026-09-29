import CoreGraphics
import Foundation

/// Result of hit-testing a cursor position against resolved zone rects.
public struct ZoneHitTestResult: Equatable, Sendable {
    /// The indices of all zones covered by this hit test.
    public let zoneIndices: Set<Int>
    /// The bounding rect covering all highlighted zones (in CoreGraphics screen coordinates).
    public let boundingCGFrame: CGRect
    /// The primary zone directly under the cursor.
    public let primaryIndex: Int?

    public init(zoneIndices: Set<Int>, boundingCGFrame: CGRect, primaryIndex: Int?) {
        self.zoneIndices = zoneIndices
        self.boundingCGFrame = boundingCGFrame
        self.primaryIndex = primaryIndex
    }
}

/// Hit-tests cursor screen coordinates against resolved zone rectangles.
public struct ZoneHitTester {
    /// Distance from an internal divider edge to trigger multi-zone border snapping.
    public static let defaultDividerProximity: CGFloat = 16.0

    /// Hit test a point against a list of indexed zone rects (in CG coordinates).
    public static func hitTest(
        point: CGPoint,
        zones: [(index: Int, rect: CGRect)],
        isSpanHeld: Bool = false,
        previouslyAccumulated: Set<Int> = [],
        dividerProximity: CGFloat = defaultDividerProximity
    ) -> ZoneHitTestResult? {
        guard !zones.isEmpty else { return nil }

        // 1. Check for border proximity snapping between adjacent zones (if span modifier is not held)
        if !isSpanHeld && dividerProximity > 0 {
            if let borderSnap = checkBorderProximity(point: point, zones: zones, threshold: dividerProximity) {
                return borderSnap
            }
        }

        // 2. Direct containment check
        guard let directIndex = zones.first(where: { $0.rect.contains(point) })?.index else {
            return nil
        }

        if isSpanHeld {
            var accumulated = previouslyAccumulated
            accumulated.insert(directIndex)

            // When spanning multiple zones, calculate the bounding rectangle covering all of them
            let matchingRects = zones.filter { accumulated.contains($0.index) }.map { $0.rect }
            guard let first = matchingRects.first else { return nil }
            let bounding = matchingRects.dropFirst().reduce(first) { $0.union($1) }

            return ZoneHitTestResult(
                zoneIndices: accumulated,
                boundingCGFrame: bounding,
                primaryIndex: directIndex
            )
        } else {
            guard let zone = zones.first(where: { $0.index == directIndex }) else { return nil }
            return ZoneHitTestResult(
                zoneIndices: [directIndex],
                boundingCGFrame: zone.rect,
                primaryIndex: directIndex
            )
        }
    }

    /// Checks if a cursor point is close to a shared boundary between two zones.
    private static func checkBorderProximity(
        point: CGPoint,
        zones: [(index: Int, rect: CGRect)],
        threshold: CGFloat
    ) -> ZoneHitTestResult? {
        for i in 0..<zones.count {
            for j in (i + 1)..<zones.count {
                let z1 = zones[i]
                let z2 = zones[j]

                if let dividerRect = sharedDividerBand(rect1: z1.rect, rect2: z2.rect, threshold: threshold) {
                    if dividerRect.contains(point) {
                        let combined = z1.rect.union(z2.rect)
                        return ZoneHitTestResult(
                            zoneIndices: [z1.index, z2.index],
                            boundingCGFrame: combined,
                            primaryIndex: z1.rect.contains(point) ? z1.index : z2.index
                        )
                    }
                }
            }
        }
        return nil
    }

    /// Calculates a proximity hit band around the shared edge between two adjacent rectangles.
    private static func sharedDividerBand(rect1: CGRect, rect2: CGRect, threshold: CGFloat) -> CGRect? {
        // Vertical divider (rects beside each other)
        let shareVerticalEdge = abs(rect1.maxX - rect2.minX) <= 30 || abs(rect2.maxX - rect1.minX) <= 30
        let verticalOverlap = max(0, min(rect1.maxY, rect2.maxY) - max(rect1.minY, rect2.minY))
        if shareVerticalEdge && verticalOverlap > 20 {
            let midX = (rect1.maxX <= rect2.minX) ? (rect1.maxX + rect2.minX) / 2 : (rect2.maxX + rect1.minX) / 2
            let yMin = max(rect1.minY, rect2.minY)
            return CGRect(x: midX - threshold, y: yMin, width: threshold * 2, height: verticalOverlap)
        }

        // Horizontal divider (rects stacked above/below each other)
        let shareHorizontalEdge = abs(rect1.maxY - rect2.minY) <= 30 || abs(rect2.maxY - rect1.minY) <= 30
        let horizontalOverlap = max(0, min(rect1.maxX, rect2.maxX) - max(rect1.minX, rect2.minX))
        if shareHorizontalEdge && horizontalOverlap > 20 {
            let midY = (rect1.maxY <= rect2.minY) ? (rect1.maxY + rect2.minY) / 2 : (rect2.maxY + rect1.minY) / 2
            let xMin = max(rect1.minX, rect2.minX)
            return CGRect(x: xMin, y: midY - threshold, width: horizontalOverlap, height: threshold * 2)
        }

        return nil
    }
}
