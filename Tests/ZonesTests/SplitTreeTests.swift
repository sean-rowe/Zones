import XCTest
@testable import ZonesCore

final class SplitTreeTests: XCTestCase {

    private func assertRects(_ actual: [CGRect], _ expected: [CGRect],
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a.minX, e.minX, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(a.minY, e.minY, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(a.width, e.width, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(a.height, e.height, accuracy: 1e-9, file: file, line: line)
        }
    }

    func testPresetsMatchPineOS() {
        XCTAssertEqual(SplitTree(preset: .halves).leafCount, 2)
        XCTAssertEqual(SplitTree(preset: .thirds).leafCount, 3)
        XCTAssertEqual(SplitTree(preset: .quarters).leafCount, 4)
        let wide = SplitTree(preset: .widescreen).zoneRects()
        XCTAssertEqual(wide.map(\.width)[0], 0.3, accuracy: 1e-9)
        XCTAssertEqual(wide.map(\.width)[1], 0.4, accuracy: 1e-9)
        XCTAssertEqual(wide.map(\.width)[2], 0.3, accuracy: 1e-9)
        assertRects(SplitTree(preset: .quarters).zoneRects(), [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])
    }

    func testRebuildsTreeFromZones() {
        let rects = SplitTree(preset: .quarters).zoneRects()
        let rebuilt = SplitTree(zones: rects)
        XCTAssertEqual(rebuilt.leafCount, 4)
        assertRects(rebuilt.zoneRects(), rects)
    }

    func testZonesThatAreNotSplitsCollapseToOneZone() {
        // A pinwheel: no full-height or full-width cut exists.
        let pinwheel = [
            CGRect(x: 0, y: 0, width: 0.6, height: 0.4), CGRect(x: 0.6, y: 0, width: 0.4, height: 0.6),
            CGRect(x: 0.4, y: 0.6, width: 0.6, height: 0.4), CGRect(x: 0, y: 0.4, width: 0.4, height: 0.6),
            CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
        ]
        XCTAssertEqual(SplitTree(zones: pinwheel), .leaf)
    }

    func testClickSplitsZoneWhereClicked() {
        let (tree, hit) = SplitTree.leaf.splitting(at: CGPoint(x: 0.25, y: 0.5), vertical: true)!
        XCTAssertEqual(hit.path, [])
        assertRects(tree.zoneRects(), [CGRect(x: 0, y: 0, width: 0.25, height: 1),
                                       CGRect(x: 0.25, y: 0, width: 0.75, height: 1)])
    }

    func testShiftClickSplitsHorizontally() {
        let (tree, _) = SplitTree.leaf.splitting(at: CGPoint(x: 0.5, y: 0.7), vertical: false)!
        assertRects(tree.zoneRects(), [CGRect(x: 0, y: 0, width: 1, height: 0.7),
                                       CGRect(x: 0, y: 0.7, width: 1, height: 0.3)])
    }

    func testSplitRatioIsClamped() {
        let (tree, _) = SplitTree.leaf.splitting(at: CGPoint(x: 0.01, y: 0.5), vertical: true)!
        XCTAssertEqual(tree.zoneRects()[0].width, SplitTree.minimumRatio, accuracy: 1e-9)
    }

    func testRightClickMergesWithSibling() {
        let merged = SplitTree(preset: .thirds).merging(at: CGPoint(x: 0.9, y: 0.5))!
        assertRects(merged.zoneRects(), [CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1),
                                         CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)])
    }

    func testLastZoneCannotBeMerged() {
        XCTAssertNil(SplitTree.leaf.merging(at: CGPoint(x: 0.5, y: 0.5)))
    }

    func testDividerHitPrefersDeeperDivider() {
        let tree = SplitTree(preset: .thirds)
        let grab = CGSize(width: 0.01, height: 0.01)
        XCTAssertEqual(tree.divider(at: CGPoint(x: 1.0 / 3, y: 0.5), grab: grab)?.path, [])
        XCTAssertEqual(tree.divider(at: CGPoint(x: 2.0 / 3, y: 0.5), grab: grab)?.path, [true])
        XCTAssertNil(tree.divider(at: CGPoint(x: 0.5, y: 0.5), grab: grab))
    }

    func testDraggingDividerOnlyResizesAdjacentZones() {
        let tree = SplitTree(preset: .thirds)
        let hit = tree.divider(at: CGPoint(x: 1.0 / 3, y: 0.5), grab: CGSize(width: 0.01, height: 0.01))!
        let moved = tree.dragging(hit, to: CGPoint(x: 0.2, y: 0.5)).zoneRects()
        XCTAssertEqual(moved[0].width, 0.2, accuracy: 1e-9)
        // The far zone keeps its third; only the middle one grows.
        XCTAssertEqual(moved[2].width, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(moved[1].width, 1 - 0.2 - 1.0 / 3, accuracy: 1e-9)
    }
}
