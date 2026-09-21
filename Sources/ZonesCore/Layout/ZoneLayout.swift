import CoreGraphics
import Foundation

/// A named, ordered set of zones.
public struct ZoneLayout: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public private(set) var zones: [Zone]
    /// What generated this layout.
    ///
    /// Provenance, not a live link. Editing a generated layout must not fight
    /// its generator, so nothing regenerates from this — it exists so the
    /// editor can show where a layout came from.
    public var origin: LayoutOrigin

    public init(id: UUID = UUID(), name: String, zones: [Zone],
                origin: LayoutOrigin = .custom) {
        self.id = id
        self.name = name
        self.origin = origin
        self.zones = ZoneLayout.reindexed(zones)
    }

    /// Zones carry their own index, so it is re-derived from array order on any
    /// change rather than left to drift.
    static func reindexed(_ zones: [Zone]) -> [Zone] {
        zones.enumerated().map { position, zone in
            var copy = zone
            copy.index = position
            return copy
        }
    }

    public var isEmpty: Bool { zones.isEmpty }

    public func zone(at index: Int) -> Zone? {
        zones.first { $0.index == index }
    }

    /// Clamp an index into range, so "move to zone 9" on a 3-zone layout lands
    /// in the last zone rather than doing nothing.
    public func zoneClampingIndex(_ index: Int) -> Zone? {
        guard !zones.isEmpty else { return nil }
        return zone(at: min(max(index, 0), zones.count - 1))
    }

    public mutating func replaceZones(_ newZones: [Zone]) {
        zones = ZoneLayout.reindexed(newZones)
    }

    /// Total area covered, in normalized units. A layout that tiles the display
    /// exactly sums to 1.
    public var coverage: Double {
        zones.reduce(0) { $0 + Double($1.rect.width * $1.rect.height) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, zones, origin
    }

    /// Decoding routes through the memberwise initializer so zones are
    /// reindexed. The synthesized one would restore whatever indices were on
    /// disk, which is how a layout edited by an older version comes back with
    /// indices that no longer match its array order.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  name: try container.decode(String.self, forKey: .name),
                  zones: try container.decode([Zone].self, forKey: .zones),
                  origin: try container.decode(LayoutOrigin.self, forKey: .origin))
    }
}

/// Where a layout came from.
public enum LayoutOrigin: Codable, Equatable, Sendable {
    case custom
    case columns(count: Int)
    case rows(count: Int)
    case grid(rows: Int, columns: Int)
    case priorityGrid(count: Int)
    case focus(count: Int)
}
