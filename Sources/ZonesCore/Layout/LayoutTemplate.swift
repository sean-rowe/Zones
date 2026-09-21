import CoreGraphics
import Foundation

/// Generators for the built-in layouts.
///
/// Every generator tiles the unit square exactly: the zones sum to an area of 1
/// and none overlap. Gaps between zones are a *rendering* concern applied at
/// resolve time from settings, not baked into the model — otherwise changing
/// the gap would mean regenerating every layout the user owns.
public enum LayoutTemplate {

    /// `count` equal full-height columns.
    public static func columns(_ count: Int) -> ZoneLayout {
        let count = max(1, count)
        let width = 1.0 / Double(count)
        let zones = (0..<count).map { i in
            Zone(index: i, rect: CGRect(x: Double(i) * width, y: 0, width: width, height: 1))
        }
        return ZoneLayout(name: count == 1 ? "Single" : "\(count) Columns",
                          zones: zones, origin: .columns(count: count))
    }

    /// `count` equal full-width rows.
    public static func rows(_ count: Int) -> ZoneLayout {
        let count = max(1, count)
        let height = 1.0 / Double(count)
        let zones = (0..<count).map { i in
            Zone(index: i, rect: CGRect(x: 0, y: Double(i) * height, width: 1, height: height))
        }
        return ZoneLayout(name: count == 1 ? "Single" : "\(count) Rows",
                          zones: zones, origin: .rows(count: count))
    }

    /// A regular grid, filled left to right then top to bottom.
    public static func grid(rows: Int, columns: Int) -> ZoneLayout {
        let rows = max(1, rows)
        let columns = max(1, columns)
        let width = 1.0 / Double(columns)
        let height = 1.0 / Double(rows)
        var zones: [Zone] = []
        for row in 0..<rows {
            for column in 0..<columns {
                zones.append(Zone(index: zones.count,
                                  rect: CGRect(x: Double(column) * width,
                                               y: Double(row) * height,
                                               width: width, height: height)))
            }
        }
        return ZoneLayout(name: "\(columns)×\(rows) Grid", zones: zones,
                          origin: .grid(rows: rows, columns: columns))
    }

    /// A wide primary zone with the remaining zones stacked beside it.
    ///
    /// The shape people actually work in: one thing being read or written, the
    /// rest visible alongside. With a count of 1 it degenerates to a single
    /// full zone rather than producing an empty stack.
    public static func priorityGrid(_ count: Int) -> ZoneLayout {
        let count = max(1, count)
        guard count > 1 else {
            return ZoneLayout(name: "Priority Grid", zones: [Zone.full],
                              origin: .priorityGrid(count: 1))
        }
        let primaryWidth = 0.6
        let secondaryCount = count - 1
        let secondaryHeight = 1.0 / Double(secondaryCount)

        var zones = [Zone(index: 0, rect: CGRect(x: 0, y: 0, width: primaryWidth, height: 1))]
        for i in 0..<secondaryCount {
            zones.append(Zone(index: i + 1,
                              rect: CGRect(x: primaryWidth,
                                           y: Double(i) * secondaryHeight,
                                           width: 1 - primaryWidth,
                                           height: secondaryHeight)))
        }
        return ZoneLayout(name: "Priority Grid", zones: zones,
                          origin: .priorityGrid(count: count))
    }

    /// A large centre zone flanked by equal side columns.
    ///
    /// For wide displays, where a full-width window is unreadable. Counts below
    /// 3 fall back to the equivalent column layout, since there is nothing to
    /// flank the centre with.
    public static func focus(_ count: Int) -> ZoneLayout {
        let count = max(1, count)
        guard count >= 3 else {
            var layout = columns(count)
            layout.origin = .focus(count: count)
            layout.name = "Focus"
            return layout
        }
        let sideCount = count - 1
        let leftCount = sideCount / 2
        let rightCount = sideCount - leftCount
        let sideWidth = 0.2
        let centreWidth = 1 - (sideWidth * 2)

        var zones: [Zone] = []
        // Centre first, so it is zone 1 under the keyboard shortcuts.
        zones.append(Zone(index: 0, rect: CGRect(x: sideWidth, y: 0,
                                                 width: centreWidth, height: 1)))
        let leftHeight = leftCount > 0 ? 1.0 / Double(leftCount) : 1
        for i in 0..<leftCount {
            zones.append(Zone(index: zones.count,
                              rect: CGRect(x: 0, y: Double(i) * leftHeight,
                                           width: sideWidth, height: leftHeight)))
        }
        let rightHeight = rightCount > 0 ? 1.0 / Double(rightCount) : 1
        for i in 0..<rightCount {
            zones.append(Zone(index: zones.count,
                              rect: CGRect(x: sideWidth + centreWidth,
                                           y: Double(i) * rightHeight,
                                           width: sideWidth, height: rightHeight)))
        }
        return ZoneLayout(name: "Focus", zones: zones, origin: .focus(count: count))
    }

    /// The layouts offered on a fresh install.
    public static var builtIns: [ZoneLayout] {
        [columns(2), columns(3), grid(rows: 2, columns: 2), priorityGrid(3), focus(3)]
    }
}
