import CoreGraphics
import Foundation

/// The six templates the picker offers, in FancyZones' order.
public enum TemplateKind: String, CaseIterable, Sendable {
    case blank, focus, columns, rows, grid, priorityGrid

    public var title: String {
        switch self {
        case .blank:        return "No layout"
        case .focus:        return "Focus"
        case .columns:      return "Columns"
        case .rows:         return "Rows"
        case .grid:         return "Grid"
        case .priorityGrid: return "Priority Grid"
        }
    }

    /// Zone count a template starts with. Three, as in FancyZones, except the
    /// grid — three zones is not a grid anyone recognises.
    public var defaultZoneCount: Int {
        switch self {
        case .blank: return 0
        case .grid:  return 4
        default:     return 3
        }
    }

    /// Whether the edit dialog offers a zone count.
    public var hasZoneCount: Bool { self != .blank }

    /// Upper bound on the zone count stepper — past this the zones are too
    /// narrow to drop a window into.
    public static let maximumZoneCount = 16

    /// The template a stored layout was generated from, if any.
    public init?(origin: LayoutOrigin) {
        switch origin {
        case .blank:        self = .blank
        case .focus:        self = .focus
        case .columns:      self = .columns
        case .rows:         self = .rows
        case .grid:         self = .grid
        case .priorityGrid: self = .priorityGrid
        case .custom, .canvas: return nil
        }
    }

    /// Generate this template with a zone count.
    public func generate(zoneCount: Int) -> ZoneLayout {
        let count = min(max(1, zoneCount), Self.maximumZoneCount)
        switch self {
        case .blank:        return ZoneLayout(name: title, zones: [], origin: .blank)
        case .focus:        return LayoutTemplate.focus(count)
        case .columns:      return LayoutTemplate.columns(count)
        case .rows:         return LayoutTemplate.rows(count)
        case .grid:         return LayoutTemplate.grid(zoneCount: count)
        case .priorityGrid: return LayoutTemplate.priorityGrid(count)
        }
    }
}

public extension LayoutTemplate {
    /// A grid with exactly `zoneCount` zones.
    ///
    /// The rows are as close to square as the count allows; when it does not
    /// divide evenly the bottom rows take one extra zone each, so the zone
    /// count the user asked for is the zone count they get. A count that does
    /// divide evenly produces the same regular grid as `grid(rows:columns:)`.
    static func grid(zoneCount: Int) -> ZoneLayout {
        let count = max(1, zoneCount)
        let rows = max(1, Int(Double(count).squareRoot().rounded(.down)))
        let baseColumns = count / rows
        let extra = count % rows
        let height = 1.0 / Double(rows)
        var zones: [Zone] = []
        for row in 0..<rows {
            let columns = baseColumns + (row >= rows - extra ? 1 : 0)
            let width = 1.0 / Double(columns)
            for column in 0..<columns {
                zones.append(Zone(index: zones.count,
                                  rect: CGRect(x: Double(column) * width, y: Double(row) * height,
                                               width: width, height: height)))
            }
        }
        let columns = baseColumns + (extra > 0 ? 1 : 0)
        return ZoneLayout(name: "Grid", zones: zones,
                          origin: .grid(rows: rows, columns: columns))
    }
}

/// What the picker shows: one card per template, then the custom layouts.
///
/// A pure function of the stored layouts and the selected display's
/// assignment, so the rules about which stored layout stands for which
/// template can be tested without the window.
public struct LayoutPickerModel: Equatable {

    public struct TemplateEntry: Equatable {
        public let kind: TemplateKind
        /// The stored layout this card applies, or a freshly generated one
        /// that is saved the first time the card is used.
        public let layout: ZoneLayout
        public let isStored: Bool
    }

    public let templates: [TemplateEntry]
    public let custom: [ZoneLayout]
    public let appliedLayoutID: UUID?

    /// - Parameters:
    ///   - layouts: everything in the store, in store order.
    ///   - appliedLayoutID: the selected display's assignment.
    ///
    /// Each template card stands for the *first* stored layout generated from
    /// that template. Any further ones — "2 Columns" and "3 Columns" on a
    /// fresh install — are listed under Custom, so they stay reachable. Choosing
    /// the first rather than the applied one keeps cards from swapping sections
    /// every time a different one is applied.
    public init(layouts: [ZoneLayout], appliedLayoutID: UUID?) {
        var used: Set<UUID> = []
        templates = TemplateKind.allCases.map { kind in
            if let stored = layouts.first(where: { TemplateKind(origin: $0.origin) == kind }) {
                used.insert(stored.id)
                return TemplateEntry(kind: kind, layout: stored, isStored: true)
            }
            return TemplateEntry(kind: kind, layout: kind.generate(zoneCount: kind.defaultZoneCount),
                                 isStored: false)
        }
        custom = layouts.filter { !used.contains($0.id) }
        self.appliedLayoutID = appliedLayoutID
    }

    public func isApplied(_ layout: ZoneLayout) -> Bool {
        layout.id == appliedLayoutID
    }
}

/// The store operations the picker and its dialogs perform.
///
/// Kept apart from the views so each one — apply, regenerate, delete — has
/// one implementation that the tests and the UI both go through.
public enum LayoutCatalog {

    /// Apply a layout to a display, saving it first if it has never been
    /// stored (an unused template card).
    public static func apply(_ layout: ZoneLayout, to display: DisplayIdentity,
                             in store: LayoutStore) {
        if store.layout(id: layout.id) == nil {
            store.save(layout)
        }
        store.assign(layoutID: layout.id, to: display)
        ZonesLog.info("Zones", "applied layout \(layout.name) to display \(display.key)")
    }

    /// A template layout regenerated with a new zone count.
    ///
    /// Keeps the identity, so every display already using it follows the
    /// change instead of being left on a layout that no longer exists.
    public static func regenerate(_ layout: ZoneLayout, kind: TemplateKind,
                                  zoneCount: Int) -> ZoneLayout {
        let generated = kind.generate(zoneCount: zoneCount)
        return ZoneLayout(id: layout.id, name: generated.name,
                          zones: generated.zones, origin: generated.origin)
    }

    /// A name for a new custom layout that is not already taken.
    public static func nextCustomName(existing: [ZoneLayout]) -> String {
        let names = Set(existing.map(\.name))
        var number = 1
        while names.contains("Custom layout \(number)") { number += 1 }
        return "Custom layout \(number)"
    }

    /// The starting point for a new custom layout.
    ///
    /// A grid starts as two columns rather than one zone, so the first thing
    /// on screen already shows a divider to drag; a canvas starts with one
    /// zone to move.
    public static func newLayout(name: String, canvas: Bool) -> ZoneLayout {
        if canvas {
            return CanvasEditing.addingZone(to: ZoneLayout(name: name, zones: [], origin: .canvas))
        }
        return ZoneLayout(name: name, zones: LayoutTemplate.columns(2).zones, origin: .custom)
    }

    /// Delete a layout and move every display that used it to a fallback.
    ///
    /// Never leaves a display with nothing: an unassigned display is treated as
    /// new and handed the default layout later anyway, so falling back now at
    /// least makes that visible while the picker is open.
    public static func delete(_ layout: ZoneLayout, from store: LayoutStore,
                              displays: [DisplayIdentity]) {
        let affected = displays.filter { store.assignedLayout(for: $0)?.id == layout.id }
        store.delete(id: layout.id)
        guard let fallback = store.layouts.first(where: { $0.origin != .blank })
                ?? store.layouts.first else { return }
        for display in affected {
            store.assign(layoutID: fallback.id, to: display)
        }
        ZonesLog.info("Zones", "deleted layout \(layout.name); \(affected.count) display(s) fell back")
    }

    /// Save an edited layout and apply it to the display it was edited for.
    public static func saveEdited(_ layout: ZoneLayout, for display: DisplayIdentity,
                                  in store: LayoutStore) {
        var layout = layout
        if layout.name.trimmingCharacters(in: .whitespaces).isEmpty {
            layout.name = "Untitled Layout"
        }
        store.save(layout)
        store.assign(layoutID: layout.id, to: display)
    }
}

/// The edit dialog's state, separate from its controls.
///
/// Only fields with real backing are here: the name and zone count live on the
/// layout, the spacing in `AppSettings`. FancyZones' per-layout "highlight
/// distance" has no equivalent setting in Zones, so it is not offered.
public struct LayoutEditDraft: Equatable {
    public var layout: ZoneLayout
    public let kind: TemplateKind?
    public var name: String
    public var zoneCount: Int
    public var showSpaceAroundZones: Bool
    /// Gap between zones, in points.
    public var spacing: Double

    /// The gap to offer when spacing is switched back on from zero — the
    /// shipped default, rather than the zero it was switched off at.
    public static let defaultSpacing = AppSettings().zoneGap

    /// - Parameter asTemplate: whether the dialog was opened from a template
    ///   card. A layout generated from a template but listed under Custom —
    ///   the spare "3 Columns" of a fresh install — is edited as a custom
    ///   layout, so it can still be renamed, reshaped and deleted. Nil infers
    ///   it from the origin.
    public init(layout: ZoneLayout, settings: AppSettings, asTemplate: Bool? = nil) {
        self.layout = layout
        let inferred = TemplateKind(origin: layout.origin)
        self.kind = (asTemplate ?? (inferred != nil)) ? inferred : nil
        self.name = kind?.title ?? layout.name
        self.zoneCount = layout.zones.count
        self.showSpaceAroundZones = settings.zoneGap > 0
        self.spacing = settings.zoneGap > 0 ? settings.zoneGap : Self.defaultSpacing
    }

    /// Templates are named by the template, as in FancyZones.
    public var isNameEditable: Bool { kind == nil }
    public var isDeletable: Bool { kind == nil }
    public var canEditZones: Bool { kind == nil }
    public var hasZoneCount: Bool { kind?.hasZoneCount ?? false }

    /// The layout as it should be saved.
    public var editedLayout: ZoneLayout {
        if let kind {
            guard kind.hasZoneCount, zoneCount != layout.zones.count else { return layout }
            return LayoutCatalog.regenerate(layout, kind: kind, zoneCount: zoneCount)
        }
        var edited = layout
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        edited.name = trimmed.isEmpty ? layout.name : trimmed
        return edited
    }

    /// The settings with this draft's spacing applied.
    ///
    /// The gap is global in Zones, so this changes it for every layout; the
    /// dialog says so. Switching it off stores zero rather than inventing a
    /// separate "enabled" flag that nothing else would read.
    public func apply(to settings: AppSettings) -> AppSettings {
        var copy = settings
        copy.zoneGap = showSpaceAroundZones ? max(0, spacing) : 0
        return copy
    }
}
