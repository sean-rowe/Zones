import XCTest
@testable import ZonesCore

/// Coordinate-system tests, kept separate and explicit.
///
/// The bug these exist to prevent — mapping a top-left normalized Y straight
/// onto an AppKit bottom-left Y — is invisible on a symmetric layout and wrong
/// on every asymmetric one. Every assertion here names which edge of the
/// *display* it is talking about.
final class ZoneResolverTests: XCTestCase {

    /// A 1000×1000 AppKit area whose origin is not zero, so an off-by-origin
    /// error cannot hide behind arithmetic that happens to work at 0.
    private let area = CGRect(x: 100, y: 200, width: 1000, height: 1000)

    func testTopHalfZoneResolvesToTheTopOfTheDisplay() {
        let topHalf = Zone(index: 0, rect: CGRect(x: 0, y: 0, width: 1, height: 0.5))
        let rect = ZoneResolver.resolve(topHalf, in: area, spacing: .none)

        // In AppKit, the top of the display is the largest y.
        XCTAssertEqual(rect.maxY, area.maxY, accuracy: 0.001,
                       "the top half must touch the top of the display")
        XCTAssertEqual(rect.minY, area.midY, accuracy: 0.001)
        XCTAssertEqual(rect.height, 500, accuracy: 0.001)
    }

    func testBottomHalfZoneResolvesToTheBottomOfTheDisplay() {
        let bottomHalf = Zone(index: 0, rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        let rect = ZoneResolver.resolve(bottomHalf, in: area, spacing: .none)

        XCTAssertEqual(rect.minY, area.minY, accuracy: 0.001,
                       "the bottom half must touch the bottom of the display")
        XCTAssertEqual(rect.maxY, area.midY, accuracy: 0.001)
    }

    func testTopLeftZoneOfAGridLandsTopLeft() {
        let grid = LayoutTemplate.grid(rows: 2, columns: 2)
        let first = ZoneResolver.resolve(grid.zones[0], in: area, spacing: .none)

        // Zone 0 of a grid is filled left-to-right, top-to-bottom.
        XCTAssertEqual(first.minX, area.minX, accuracy: 0.001)
        XCTAssertEqual(first.maxY, area.maxY, accuracy: 0.001)
    }

    func testLastZoneOfAGridLandsBottomRight() {
        let grid = LayoutTemplate.grid(rows: 2, columns: 2)
        let last = ZoneResolver.resolve(grid.zones[3], in: area, spacing: .none)

        XCTAssertEqual(last.maxX, area.maxX, accuracy: 0.001)
        XCTAssertEqual(last.minY, area.minY, accuracy: 0.001)
    }

    func testResolvedZonesStayInsideTheArea() {
        for layout in LayoutTemplate.builtIns {
            for zone in layout.zones {
                let rect = ZoneResolver.resolve(zone, in: area, spacing: ZoneSpacing(outerPadding: 10, gap: 6))
                XCTAssertTrue(area.contains(rect),
                              "\(layout.name) zone \(zone.index) escaped the display area")
            }
        }
    }

    func testOuterEdgesGetPaddingButNotGap() {
        let columns = LayoutTemplate.columns(2)
        let spacing = ZoneSpacing(outerPadding: 10, gap: 20)
        let left = ZoneResolver.resolve(columns.zones[0], in: area, spacing: spacing)
        let right = ZoneResolver.resolve(columns.zones[1], in: area, spacing: spacing)

        // Outer edges: padding only.
        XCTAssertEqual(left.minX, area.minX + 10, accuracy: 0.001)
        XCTAssertEqual(right.maxX, area.maxX - 10, accuracy: 0.001)
        // Internal edge: a full gap between the two neighbours.
        XCTAssertEqual(right.minX - left.maxX, 20, accuracy: 0.001)
    }

    func testVerticalGapSeparatesStackedZones() {
        let rows = LayoutTemplate.rows(2)
        let spacing = ZoneSpacing(outerPadding: 0, gap: 20)
        // rows[0] is the visual top.
        let top = ZoneResolver.resolve(rows.zones[0], in: area, spacing: spacing)
        let bottom = ZoneResolver.resolve(rows.zones[1], in: area, spacing: spacing)

        XCTAssertEqual(top.maxY, area.maxY, accuracy: 0.001)
        XCTAssertEqual(bottom.minY, area.minY, accuracy: 0.001)
        XCTAssertEqual(top.minY - bottom.maxY, 20, accuracy: 0.001)
    }

    func testAZoneNarrowerThanTheGapCollapsesRatherThanInverting() {
        let many = LayoutTemplate.columns(50)
        let spacing = ZoneSpacing(outerPadding: 0, gap: 100)
        let rect = ZoneResolver.resolve(many.zones[25], in: area, spacing: spacing)
        XCTAssertGreaterThanOrEqual(rect.width, 0)
        XCTAssertGreaterThanOrEqual(rect.height, 0)
    }

    func testPaddingLargerThanTheDisplayYieldsAnEmptyRect() {
        let rect = ZoneResolver.resolve(.full, in: CGRect(x: 0, y: 0, width: 10, height: 10),
                                        spacing: ZoneSpacing(outerPadding: 50, gap: 0))
        XCTAssertEqual(rect, .zero)
    }
}
