import XCTest
@testable import ZonesCore

/// The pure geometry behind the editor's views.
final class EditorGeometryTests: XCTestCase {

    // MARK: Unit square mapping

    func testMappingFlipsYSoTheModelTopIsTheViewTop() {
        let mapping = UnitSquareMapping(area: CGRect(x: 10, y: 20, width: 200, height: 100))
        let top = mapping.viewRect(for: CGRect(x: 0, y: 0, width: 1, height: 0.25))
        XCTAssertEqual(top.maxY, 120, accuracy: 0.001, "model y = 0 is the view's top edge")
        XCTAssertEqual(top.height, 25, accuracy: 0.001)
    }

    func testMappingRoundTripsAPoint() {
        let mapping = UnitSquareMapping(area: CGRect(x: 10, y: 20, width: 200, height: 100))
        let point = mapping.normalizedPoint(for: CGPoint(x: mapping.viewX(0.3), y: mapping.viewY(0.7)))
        XCTAssertEqual(point.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.7, accuracy: 0.0001)
    }

    func testDraggingUpIsANegativeModelDelta() {
        let mapping = UnitSquareMapping(area: CGRect(x: 0, y: 0, width: 200, height: 100))
        let delta = mapping.normalizedDelta(CGVector(dx: 20, dy: 10))
        XCTAssertEqual(delta.dx, 0.1, accuracy: 0.0001)
        XCTAssertEqual(delta.dy, -0.1, accuracy: 0.0001)
    }

    // MARK: Card grid

    private let grid = CardGridLayout(cardSize: CGSize(width: 200, height: 150), spacing: 16)

    func testCardsWrapAtTheWidth() {
        XCTAssertEqual(grid.columns(forWidth: 200), 1)
        XCTAssertEqual(grid.columns(forWidth: 415), 1, "two cards need 416 with the spacing")
        XCTAssertEqual(grid.columns(forWidth: 416), 2)
        XCTAssertEqual(grid.columns(forWidth: 50), 1, "never zero columns")
    }

    func testCardFramesFlowLeftToRightThenDown() {
        let frames = grid.frames(count: 3, width: 416, origin: CGPoint(x: 28, y: 40))
        XCTAssertEqual(frames[0].origin, CGPoint(x: 28, y: 40))
        XCTAssertEqual(frames[1].origin, CGPoint(x: 244, y: 40))
        XCTAssertEqual(frames[2].origin, CGPoint(x: 28, y: 206))
    }

    func testCardGridHeightHasNoTrailingSpacing() {
        XCTAssertEqual(grid.height(count: 0, width: 416), 0)
        XCTAssertEqual(grid.height(count: 2, width: 416), 150)
        XCTAssertEqual(grid.height(count: 3, width: 416), 316)
    }

    // MARK: Monitor strip

    func testMonitorsShareOneScaleSoRelativeSizeIsKept() {
        let frames = MonitorStripLayout.frames(
            for: [CGSize(width: 2560, height: 1440), CGSize(width: 1280, height: 720)],
            in: CGSize(width: 1000, height: 90), spacing: 10)
        XCTAssertEqual(frames[0].height, 90, accuracy: 0.001, "the tallest fills the strip")
        XCTAssertEqual(frames[1].height, 45, accuracy: 0.001)
        XCTAssertEqual(frames[0].width / frames[1].width, 2, accuracy: 0.001)
    }

    func testMonitorStripIsCentredAndSpaced() {
        let frames = MonitorStripLayout.frames(
            for: [CGSize(width: 160, height: 90), CGSize(width: 160, height: 90)],
            in: CGSize(width: 1000, height: 90), spacing: 10)
        XCTAssertEqual(frames[1].minX - frames[0].maxX, 10, accuracy: 0.001)
        XCTAssertEqual((frames[0].minX + frames[1].maxX) / 2, 500, accuracy: 0.001)
    }

    func testANarrowStripScalesDownToFitTheWidth() {
        let frames = MonitorStripLayout.frames(
            for: [CGSize(width: 1600, height: 900), CGSize(width: 1600, height: 900)],
            in: CGSize(width: 210, height: 90), spacing: 10)
        XCTAssertLessThanOrEqual(frames[1].maxX, 210.001)
        XCTAssertGreaterThanOrEqual(frames[0].minX, -0.001)
    }

    func testMonitorsAreNumberedLeftToRight() {
        let order = MonitorStripLayout.order(of: [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: -100, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
        ])
        XCTAssertEqual(order, [1, 0, 2])
    }

    // MARK: Split preview

    func testSplitPreviewFollowsThePointer() {
        let zone = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        XCTAssertEqual(GridSplitPreview.position(for: CGPoint(x: 0.2, y: 0.5), in: zone,
                                                 axis: .vertical) ?? .nan, 0.2, accuracy: 0.0001)
        XCTAssertEqual(GridSplitPreview.position(for: CGPoint(x: 0.2, y: 0.7), in: zone,
                                                 axis: .horizontal) ?? .nan, 0.7, accuracy: 0.0001)
    }

    func testSplitPreviewStopsShortOfTheEdges() {
        let zone = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let min = LayoutEditing.minimumZoneFraction
        XCTAssertEqual(GridSplitPreview.position(for: CGPoint(x: 0.501, y: 0.5), in: zone,
                                                 axis: .vertical) ?? .nan, 0.5 + min, accuracy: 0.0001)
        XCTAssertEqual(GridSplitPreview.position(for: CGPoint(x: 0.999, y: 0.5), in: zone,
                                                 axis: .vertical) ?? .nan, 1 - min, accuracy: 0.0001)
    }

    func testAZoneTooSmallToSplitHasNoPreview() {
        let zone = CGRect(x: 0, y: 0, width: 0.08, height: 1)
        XCTAssertNil(GridSplitPreview.position(for: CGPoint(x: 0.04, y: 0.5), in: zone, axis: .vertical))
        XCTAssertNotNil(GridSplitPreview.position(for: CGPoint(x: 0.04, y: 0.5), in: zone,
                                                  axis: .horizontal),
                        "still splittable the other way")
    }

    func testShiftMakesTheSplitHorizontal() {
        XCTAssertEqual(GridSplitPreview.axis(shiftHeld: false), .vertical)
        XCTAssertEqual(GridSplitPreview.axis(shiftHeld: true), .horizontal)
    }

    // MARK: Split at a position

    func testSplittingAtAPositionCutsThere() {
        let layout = LayoutTemplate.columns(1)
        let split = LayoutEditing.split(zoneID: layout.zones[0].id, axis: .vertical, at: 0.3, in: layout)
        XCTAssertEqual(split.zones.count, 2)
        XCTAssertEqual(split.zones[0].rect.width, 0.3, accuracy: 0.0001)
        XCTAssertEqual(split.zones[1].rect.minX, 0.3, accuracy: 0.0001)
        XCTAssertEqual(split.zones[0].id, layout.zones[0].id, "the first part keeps the identity")
        XCTAssertEqual(split.coverage, 1, accuracy: 0.0001)
    }

    func testSplittingIntoASliverIsRefused() {
        let layout = LayoutTemplate.columns(1)
        let split = LayoutEditing.split(zoneID: layout.zones[0].id, axis: .horizontal, at: 0.01, in: layout)
        XCTAssertEqual(split, layout)
    }

    // MARK: Drag selection

    func testDraggingDiagonallyAcrossAGridSelectsAllFour() {
        let layout = LayoutTemplate.grid(rows: 2, columns: 2)
        let selection = ZoneDragSelection.selection(from: layout.zones[0].id, to: layout.zones[3].id,
                                                    in: layout)
        XCTAssertEqual(selection.count, 4)
    }

    func testDraggingToANeighbourSelectsThePair() {
        let layout = LayoutTemplate.grid(rows: 2, columns: 2)
        let selection = ZoneDragSelection.selection(from: layout.zones[0].id, to: layout.zones[1].id,
                                                    in: layout)
        XCTAssertEqual(selection, [layout.zones[0].id, layout.zones[1].id])
    }

    func testASelectionGrowsUntilItIsMergeable() {
        // Priority grid: a tall left zone and two stacked right zones. Dragging
        // from the left to the top right covers the full height, so the bottom
        // right has to come along or the result is an L.
        let layout = LayoutTemplate.priorityGrid(3)
        let selection = ZoneDragSelection.selection(from: layout.zones[0].id, to: layout.zones[1].id,
                                                    in: layout)
        XCTAssertEqual(selection.count, 3)
        XCTAssertTrue(LayoutEditing.canMerge(zoneIDs: selection, in: layout))
    }

    func testEverySelectionOfAMessyLayoutIsMergeable() {
        var layout = LayoutTemplate.grid(rows: 3, columns: 3)
        layout = LayoutEditing.merge(zoneIDs: [layout.zones[0].id, layout.zones[1].id], in: layout)
        layout = LayoutEditing.split(zoneID: layout.zones[4].id, axis: .horizontal, at: 0.4, in: layout)
        for start in layout.zones {
            for end in layout.zones where end.id != start.id {
                let selection = ZoneDragSelection.selection(from: start.id, to: end.id, in: layout)
                XCTAssertTrue(LayoutEditing.canMerge(zoneIDs: selection, in: layout),
                              "selection from \(start.index) to \(end.index) cannot merge")
            }
        }
    }

    func testSelectionBounds() {
        let layout = LayoutTemplate.columns(3)
        let bounds = ZoneDragSelection.bounds(of: [layout.zones[1].id, layout.zones[2].id], in: layout)
        XCTAssertEqual(bounds?.minX ?? .nan, 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(bounds?.maxX ?? .nan, 1, accuracy: 0.0001)
        XCTAssertNil(ZoneDragSelection.bounds(of: [], in: layout))
    }

    // MARK: Canvas

    func testMovingStopsAtTheEdgeWithoutResizing() {
        let rect = CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.3)
        let moved = CanvasEditing.moved(rect, by: CGVector(dx: 0.5, dy: -0.5))
        XCTAssertEqual(moved.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(moved.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(moved.size, rect.size)
    }

    func testResizingKeepsTheOppositeEdge() {
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let resized = CanvasEditing.resized(rect, handle: .bottomRight, to: CGPoint(x: 0.9, y: 0.7))
        XCTAssertEqual(resized.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(resized.minY, 0.2, accuracy: 0.0001)
        XCTAssertEqual(resized.maxX, 0.9, accuracy: 0.0001)
        XCTAssertEqual(resized.maxY, 0.7, accuracy: 0.0001)
    }

    func testResizingNeverInvertsOrShrinksBelowTheMinimum() {
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let resized = CanvasEditing.resized(rect, handle: .left, to: CGPoint(x: 0.95, y: 0.5))
        XCTAssertEqual(resized.maxX, 0.6, accuracy: 0.0001)
        XCTAssertEqual(resized.width, LayoutEditing.minimumZoneFraction, accuracy: 0.0001)
        let top = CanvasEditing.resized(rect, handle: .top, to: CGPoint(x: 0.5, y: -0.5))
        XCTAssertEqual(top.minY, 0, accuracy: 0.0001, "clamped to the display")
    }

    func testNewZonesCascadeInsteadOfStacking() {
        let first = CanvasEditing.newZoneRect(avoiding: [])
        let second = CanvasEditing.newZoneRect(avoiding: [first])
        XCTAssertNotEqual(first.origin, second.origin)
        XCTAssertEqual(second.minX - first.minX, CanvasEditing.cascadeStep, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(second.maxX, 1)
    }

    func testAddingAndRemovingZonesKeepsNumbersContiguous() {
        var layout = ZoneLayout(name: "Canvas", zones: [], origin: .canvas)
        layout = CanvasEditing.addingZone(to: layout)
        layout = CanvasEditing.addingZone(to: layout)
        layout = CanvasEditing.addingZone(to: layout)
        layout = CanvasEditing.removingZone(layout.zones[1].id, from: layout)
        XCTAssertEqual(layout.zones.map(\.index), [0, 1])
        XCTAssertEqual(layout.origin, .canvas)
    }

    func testTopmostCanvasZoneWins() {
        let layout = ZoneLayout(name: "Canvas", zones: [
            Zone(index: 0, rect: CGRect(x: 0, y: 0, width: 0.6, height: 0.6)),
            Zone(index: 1, rect: CGRect(x: 0.4, y: 0.4, width: 0.6, height: 0.6)),
        ], origin: .canvas)
        XCTAssertEqual(CanvasEditing.zone(at: CGPoint(x: 0.5, y: 0.5), in: layout)?.index, 1)
        XCTAssertEqual(CanvasEditing.zone(at: CGPoint(x: 0.1, y: 0.1), in: layout)?.index, 0)
    }

    func testHandlesSitOnTheRectEdges() {
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        XCTAssertEqual(CanvasHandle.topLeft.point(on: rect), CGPoint(x: 0.2, y: 0.2))
        let bottom = CanvasHandle.bottom.point(on: rect)
        XCTAssertEqual(bottom.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(bottom.y, 0.6, accuracy: 0.0001)
    }
}
