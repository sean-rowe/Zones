import XCTest
import CoreGraphics
@testable import ZonesCore

final class ZoneHitTesterTests: XCTestCase {
    // Two side-by-side columns:
    // Zone 0: x: 0..500, y: 0..1000
    // Zone 1: x: 500..1000, y: 0..1000
    private let twoColumns: [(index: Int, rect: CGRect)] = [
        (index: 0, rect: CGRect(x: 0, y: 0, width: 500, height: 1000)),
        (index: 1, rect: CGRect(x: 500, y: 0, width: 500, height: 1000))
    ]

    func testSingleZoneHitTestFindsContainingZone() {
        let point = CGPoint(x: 200, y: 400)
        let result = ZoneHitTester.hitTest(point: point, zones: twoColumns, dividerProximity: 0)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.zoneIndices, [0])
        XCTAssertEqual(result?.boundingCGFrame, twoColumns[0].rect)
        XCTAssertEqual(result?.primaryIndex, 0)
    }

    func testPointOutsideAllZonesReturnsNil() {
        let point = CGPoint(x: 1200, y: 500)
        let result = ZoneHitTester.hitTest(point: point, zones: twoColumns, dividerProximity: 0)

        XCTAssertNil(result)
    }

    func testMultiZoneSpanWithSpanModifierAccumulatesZones() {
        let point1 = CGPoint(x: 200, y: 400)
        let res1 = ZoneHitTester.hitTest(point: point1, zones: twoColumns, isSpanHeld: true, dividerProximity: 0)
        XCTAssertEqual(res1?.zoneIndices, [0])

        // Move to second zone while holding span
        let point2 = CGPoint(x: 700, y: 400)
        let res2 = ZoneHitTester.hitTest(
            point: point2,
            zones: twoColumns,
            isSpanHeld: true,
            previouslyAccumulated: res1?.zoneIndices ?? [],
            dividerProximity: 0
        )

        XCTAssertNotNil(res2)
        XCTAssertEqual(res2?.zoneIndices, [0, 1])
        XCTAssertEqual(res2?.boundingCGFrame, CGRect(x: 0, y: 0, width: 1000, height: 1000))
    }

    func testBorderProximitySnapsAcrossAdjacentZones() {
        // Divider is at x = 500. Point at x = 505 is within 16pt divider threshold
        let nearDividerPoint = CGPoint(x: 505, y: 400)
        let result = ZoneHitTester.hitTest(point: nearDividerPoint, zones: twoColumns, dividerProximity: 16)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.zoneIndices, [0, 1], "Border proximity must highlight both adjacent zones")
        XCTAssertEqual(result?.boundingCGFrame, CGRect(x: 0, y: 0, width: 1000, height: 1000))
    }
}
