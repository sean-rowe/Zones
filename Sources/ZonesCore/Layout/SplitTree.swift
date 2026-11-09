import CoreGraphics
import Foundation

/// The zone editor's model: the display recursively divided by binary splits.
///
/// A port of PineOS's `fz_split_tree.c`. Every leaf is a zone and every inner
/// node a divider, so gaps and overlaps cannot exist. Rects are normalized,
/// top-left origin, matching `Zone.rect`.
public indirect enum SplitTree: Equatable, Sendable {
    case leaf
    /// `vertical` is a left|right divider. `ratio` places it within the node's rect.
    case split(vertical: Bool, ratio: Double, first: SplitTree, second: SplitTree)

    /// Smallest share of its parent a dragged or clicked divider may give a side.
    public static let minimumRatio = 0.10

    /// Path to a node: `false` steps into `first`, `true` into `second`.
    public typealias Path = [Bool]

    // MARK: Presets

    /// The editor's four presets, bound to keys 1–4 as on PineOS.
    public enum Preset: Int, CaseIterable, Sendable {
        case halves, thirds, quarters, widescreen

        public var title: String {
            switch self {
            case .halves: return "Halves"
            case .thirds: return "Thirds"
            case .quarters: return "Quarters"
            case .widescreen: return "Widescreen"
            }
        }
    }

    public init(preset: Preset) {
        switch preset {
        case .halves:
            self = .split(vertical: true, ratio: 0.5, first: .leaf, second: .leaf)
        case .thirds:
            self = .split(vertical: true, ratio: 1.0 / 3.0, first: .leaf,
                          second: .split(vertical: true, ratio: 0.5, first: .leaf, second: .leaf))
        case .quarters:
            let column = SplitTree.split(vertical: false, ratio: 0.5, first: .leaf, second: .leaf)
            self = .split(vertical: true, ratio: 0.5, first: column, second: column)
        case .widescreen:
            // 30 / 40 / 30.
            self = .split(vertical: true, ratio: 0.3, first: .leaf,
                          second: .split(vertical: true, ratio: 4.0 / 7.0, first: .leaf, second: .leaf))
        }
    }

    // MARK: Zones

    /// Rebuild a tree from flat zones by finding a clean vertical, then
    /// horizontal, cut. Zones that cannot be expressed as binary splits
    /// collapse to one leaf, as on PineOS.
    public init(zones: [CGRect], in rect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) {
        self = SplitTree.build(zones, in: rect)
    }

    private static func build(_ zones: [CGRect], in r: CGRect) -> SplitTree {
        guard zones.count > 1 else { return .leaf }
        let eps = 0.01

        for zone in zones {
            let xs = zone.maxX
            guard xs > r.minX + eps, xs < r.maxX - eps else { continue }
            let left = zones.filter { $0.maxX <= xs + eps && $0.minX >= r.minX - eps }
            let right = zones.filter { $0.minX >= xs - eps }
            if !left.isEmpty, !right.isEmpty, left.count + right.count == zones.count {
                let ratio = (xs - r.minX) / r.width
                let (a, b) = r.divided(atDistance: r.width * ratio, from: .minXEdge)
                return .split(vertical: true, ratio: ratio,
                              first: build(left, in: a), second: build(right, in: b))
            }
        }
        for zone in zones {
            let ys = zone.maxY
            guard ys > r.minY + eps, ys < r.maxY - eps else { continue }
            let top = zones.filter { $0.maxY <= ys + eps && $0.minY >= r.minY - eps }
            let bottom = zones.filter { $0.minY >= ys - eps }
            if !top.isEmpty, !bottom.isEmpty, top.count + bottom.count == zones.count {
                let ratio = (ys - r.minY) / r.height
                let (a, b) = r.divided(atDistance: r.height * ratio, from: .minYEdge)
                return .split(vertical: false, ratio: ratio,
                              first: build(top, in: a), second: build(bottom, in: b))
            }
        }
        return .leaf
    }

    /// Leaf rects in reading order (first before second, depth first).
    public func zoneRects(in rect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [CGRect] {
        switch self {
        case .leaf:
            return [rect]
        case let .split(vertical, ratio, first, second):
            let (a, b) = SplitTree.divide(rect, vertical: vertical, ratio: ratio)
            return first.zoneRects(in: a) + second.zoneRects(in: b)
        }
    }

    public var leafCount: Int {
        switch self {
        case .leaf: return 1
        case let .split(_, _, first, second): return first.leafCount + second.leafCount
        }
    }

    static func divide(_ rect: CGRect, vertical: Bool, ratio: Double) -> (CGRect, CGRect) {
        if vertical {
            let w = rect.width * ratio
            return (CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height),
                    CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height))
        }
        let h = rect.height * ratio
        return (CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h),
                CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h))
    }

    // MARK: Hit testing

    public struct Hit: Equatable {
        public let path: Path
        /// The rect the hit node occupies (for a divider, the rect it divides).
        public let rect: CGRect
    }

    /// The leaf containing a normalized point.
    public func leaf(at p: CGPoint, in rect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                     path: Path = []) -> Hit? {
        switch self {
        case .leaf:
            return (p.x >= rect.minX && p.x < rect.maxX && p.y >= rect.minY && p.y < rect.maxY)
                ? Hit(path: path, rect: rect) : nil
        case let .split(vertical, ratio, first, second):
            let (a, b) = SplitTree.divide(rect, vertical: vertical, ratio: ratio)
            return first.leaf(at: p, in: a, path: path + [false])
                ?? second.leaf(at: p, in: b, path: path + [true])
        }
    }

    /// The divider within `grab` of a normalized point. Deeper dividers win.
    public func divider(at p: CGPoint, grab: CGSize,
                        in rect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                        path: Path = []) -> Hit? {
        guard case let .split(vertical, ratio, first, second) = self else { return nil }
        let (a, b) = SplitTree.divide(rect, vertical: vertical, ratio: ratio)
        if let hit = first.divider(at: p, grab: grab, in: a, path: path + [false]) { return hit }
        if let hit = second.divider(at: p, grab: grab, in: b, path: path + [true]) { return hit }
        if vertical {
            let sx = rect.minX + rect.width * ratio
            if abs(p.x - sx) <= grab.width, p.y >= rect.minY, p.y <= rect.maxY {
                return Hit(path: path, rect: rect)
            }
        } else {
            let sy = rect.minY + rect.height * ratio
            if abs(p.y - sy) <= grab.height, p.x >= rect.minX, p.x <= rect.maxX {
                return Hit(path: path, rect: rect)
            }
        }
        return nil
    }

    // MARK: Edits

    func node(at path: Path) -> SplitTree? {
        guard let step = path.first else { return self }
        guard case let .split(_, _, first, second) = self else { return nil }
        return (step ? second : first).node(at: Array(path.dropFirst()))
    }

    func replacing(at path: Path, with node: SplitTree) -> SplitTree {
        guard let step = path.first else { return node }
        guard case let .split(vertical, ratio, first, second) = self else { return self }
        let rest = Array(path.dropFirst())
        return step
            ? .split(vertical: vertical, ratio: ratio, first: first, second: second.replacing(at: rest, with: node))
            : .split(vertical: vertical, ratio: ratio, first: first.replacing(at: rest, with: node), second: second)
    }

    /// Split the leaf under a normalized point where it was clicked.
    /// Returns the new tree and the new divider, ready to be dragged.
    public func splitting(at p: CGPoint, vertical: Bool) -> (tree: SplitTree, divider: Hit)? {
        guard let hit = leaf(at: p) else { return nil }
        let raw = vertical ? (p.x - hit.rect.minX) / hit.rect.width
                           : (p.y - hit.rect.minY) / hit.rect.height
        let ratio = min(max(raw, Self.minimumRatio), 1 - Self.minimumRatio)
        let tree = replacing(at: hit.path, with: .split(vertical: vertical, ratio: ratio,
                                                        first: .leaf, second: .leaf))
        return (tree, hit)
    }

    /// Merge the leaf under a point into its sibling. The last zone stays.
    public func merging(at p: CGPoint) -> SplitTree? {
        guard let hit = leaf(at: p), !hit.path.isEmpty else { return nil }
        let parentPath = Array(hit.path.dropLast())
        guard case let .split(_, _, first, second)? = node(at: parentPath) else { return nil }
        let sibling = hit.path.last! ? first : second
        return replacing(at: parentPath, with: sibling)
    }

    /// Move a divider to a normalized point, keeping same-direction zones on
    /// the far side of each child fixed so only the adjacent zones resize.
    public func dragging(_ divider: Hit, to p: CGPoint) -> SplitTree {
        guard case let .split(vertical, oldRatio, first, second)? = node(at: divider.path) else { return self }
        let r = divider.rect
        let raw = vertical ? (p.x - r.minX) / r.width : (p.y - r.minY) / r.height
        let newRatio = min(max(raw, Self.minimumRatio), 1 - Self.minimumRatio)
        let range = Self.minimumRatio...(1 - Self.minimumRatio)

        var newFirst = first
        if case let .split(v, fr, ff, fs) = first, v == vertical, newRatio > 0.01 {
            let adjusted = oldRatio * fr / newRatio
            if range.contains(adjusted) { newFirst = .split(vertical: v, ratio: adjusted, first: ff, second: fs) }
        }
        var newSecond = second
        if case let .split(v, sr, sf, ss) = second, v == vertical, 1 - newRatio > 0.01 {
            let adjusted = 1 - (1 - oldRatio) * (1 - sr) / (1 - newRatio)
            if range.contains(adjusted) { newSecond = .split(vertical: v, ratio: adjusted, first: sf, second: ss) }
        }
        return replacing(at: divider.path, with: .split(vertical: vertical, ratio: newRatio,
                                                        first: newFirst, second: newSecond))
    }
}
