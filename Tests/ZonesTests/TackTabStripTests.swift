import XCTest
import ApplicationServices
@testable import ZonesCore

final class TackTabStripTests: XCTestCase {
    private let window = CGRect(x: 100, y: 200, width: 800, height: 600)

    // MARK: - Detection

    func testStripLyingOnTheWindowsTopEdgeIsFound() {
        let strip = CGRect(x: 100, y: 164, width: 800, height: 36)
        XCTAssertEqual(TackTabStrip.stripHeight(above: window, among: [strip]), 36)
    }

    func testStripLaggingADragWithinToleranceIsStillFound() {
        let strip = CGRect(x: 117, y: 150, width: 800, height: 36)
        XCTAssertEqual(TackTabStrip.stripHeight(above: window, among: [strip]), 36)
    }

    func testNoTackWindowsMeansNoStrip() {
        XCTAssertNil(TackTabStrip.stripHeight(above: window, among: []))
    }

    func testStripOverAnotherWindowIsIgnored() {
        let elsewhere = CGRect(x: 1200, y: 164, width: 800, height: 36)
        XCTAssertNil(TackTabStrip.stripHeight(above: window, among: [elsewhere]))
    }

    func testStripOfADifferentWidthIsIgnored() {
        let narrower = CGRect(x: 100, y: 164, width: 400, height: 36)
        XCTAssertNil(TackTabStrip.stripHeight(above: window, among: [narrower]))
    }

    func testTallTackWindowIsNotAStrip() {
        let picker = CGRect(x: 100, y: -200, width: 800, height: 400)
        XCTAssertNil(TackTabStrip.stripHeight(above: window, among: [picker]))
    }

    func testClosestStripWins() {
        let near = CGRect(x: 100, y: 164, width: 800, height: 36)
        let far = CGRect(x: 110, y: 150, width: 800, height: 30)
        XCTAssertEqual(TackTabStrip.stripHeight(above: window, among: [far, near]), 36)
    }

    // MARK: - Making room

    func testZoneLosesTheStripsBandOffItsTop() {
        let zone = CGRect(x: 0, y: 25, width: 960, height: 1055)
        let framed = TackTabStrip.frame(zone, leavingRoomFor: 36)
        XCTAssertEqual(framed, CGRect(x: 0, y: 61, width: 960, height: 1019))
        XCTAssertEqual(framed.maxY, zone.maxY, "Window still ends at the zone's bottom edge")
    }

    func testZoneTooShortForBothIsLeftWhole() {
        let zone = CGRect(x: 0, y: 25, width: 960, height: 70)
        XCTAssertEqual(TackTabStrip.frame(zone, leavingRoomFor: 36), zone)
    }

    // MARK: - Detector

    func testDetectorMatchesAWindowAgainstTacksWindows() {
        let detector = TackTabStripDetector()
        detector.windowBounds = { [window] id in id == 7 ? window : nil }
        detector.tackWindowBounds = { [CGRect(x: 100, y: 164, width: 800, height: 36)] }
        XCTAssertEqual(detector.stripHeight(forWindowID: 7), 36)
        XCTAssertNil(detector.stripHeight(forWindowID: 8))
    }

    func testDetectorWithoutTackRunningSkipsTheWindowLookup() {
        let detector = TackTabStripDetector()
        var looked = false
        detector.windowBounds = { _ in looked = true; return nil }
        detector.tackWindowBounds = { [] }
        XCTAssertNil(detector.stripHeight(forWindowID: 7))
        XCTAssertFalse(looked)
    }

    // MARK: - Snapper

    func testSnapperGivesAGroupedWindowTheZoneMinusTheStrip() {
        let snapper = WindowSnapper()
        var requested: CGRect?
        snapper.onSnapFrame = { requested = $0 }
        snapper.tabStripHeight = { _ in 36 }

        let zone = CGRect(x: 0, y: 25, width: 960, height: 1055)
        snapper.snap(element: AXUIElementCreateSystemWide(), to: zone)

        XCTAssertEqual(requested, CGRect(x: 0, y: 61, width: 960, height: 1019))
    }

    func testSnapperGivesAnUngroupedWindowTheWholeZone() {
        let snapper = WindowSnapper()
        var requested: CGRect?
        snapper.onSnapFrame = { requested = $0 }
        snapper.tabStripHeight = { _ in nil }

        let zone = CGRect(x: 0, y: 25, width: 960, height: 1055)
        snapper.snap(element: AXUIElementCreateSystemWide(), to: zone)

        XCTAssertEqual(requested, zone)
    }
}
