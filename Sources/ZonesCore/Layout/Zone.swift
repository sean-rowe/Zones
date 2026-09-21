import CoreGraphics
import Foundation

/// A single zone, expressed in normalized coordinates.
///
/// The rect is in the unit square: `0...1` on both axes, origin top-left to
/// match CoreGraphics. Storing zones normalized rather than in points is the
/// decision the whole layout model rests on — one layout then survives a
/// resolution change, a scaling change, and being applied to a display it was
/// never designed for, with no conversion step and nothing to migrate.
public struct Zone: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Position in the layout's ordering. Drives the numbered keyboard
    /// shortcuts, so it is part of the model rather than an array index.
    public var index: Int
    /// Normalized rect within the unit square.
    public private(set) var rect: CGRect

    /// The unit square itself — a single zone covering the whole display.
    public static let full = Zone(index: 0, rect: CGRect(x: 0, y: 0, width: 1, height: 1))

    public init(id: UUID = UUID(), index: Int, rect: CGRect) {
        self.id = id
        self.index = index
        self.rect = Zone.clampedToUnitSquare(rect)
    }

    /// Bring a rect inside the unit square.
    ///
    /// Clamped rather than rejected: a zone that escapes the unit square
    /// resolves to a rect partly off the display, and the point at which that
    /// becomes visible is mid-drag, which is far too late. A degenerate rect
    /// collapses to zero area rather than inverting.
    static func clampedToUnitSquare(_ rect: CGRect) -> CGRect {
        let standard = rect.standardized
        let minX = min(max(standard.minX, 0), 1)
        let minY = min(max(standard.minY, 0), 1)
        let maxX = min(max(standard.maxX, 0), 1)
        let maxY = min(max(standard.maxY, 0), 1)
        return CGRect(x: minX, y: minY,
                      width: max(0, maxX - minX),
                      height: max(0, maxY - minY))
    }

    /// Whether this zone occupies any area at all.
    public var isDegenerate: Bool {
        rect.width <= 0 || rect.height <= 0
    }

    /// The smallest zone containing both, used when spanning a selection.
    public func union(_ other: Zone) -> Zone {
        Zone(index: min(index, other.index), rect: rect.union(other.rect))
    }

    private enum CodingKeys: String, CodingKey {
        case id, index, rect
    }

    /// Decoding routes through `init(id:index:rect:)` so the clamp applies.
    ///
    /// The synthesized initializer would assign `rect` directly and skip it,
    /// which means a hand-edited or corrupted file could put a zone outside
    /// the unit square — the one thing construction is supposed to prevent.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  index: try container.decode(Int.self, forKey: .index),
                  rect: try container.decode(CGRect.self, forKey: .rect))
    }
}
