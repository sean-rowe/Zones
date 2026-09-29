import XCTest
import AppKit
@testable import ZonesCore

final class WindowAdmissionTests: XCTestCase {

    private let mine: pid_t = 501
    private let theirs: pid_t = 900
    private let ordinary = CGRect(x: 0, y: 0, width: 800, height: 600)

    private func admit(layer: Int = 0, pid: pid_t? = nil,
                       bounds: CGRect? = nil) -> WindowAdmission {
        WindowListProvider.admit(layer: layer, ownerPID: pid ?? theirs,
                                 myPID: mine, bounds: bounds ?? ordinary)
    }

    func testAnOrdinaryWindowIsAdmitted() {
        XCTAssertEqual(admit(), .admitted)
    }

    func testAWindowAboveTheNormalLayerIsHeldBackWithItsLayer() {
        XCTAssertEqual(admit(layer: 3), .notNormalLayer(3))
        XCTAssertEqual(admit(layer: 3).reason, "rejected: layer 3, not 0")
    }

    func testZonesWillNotSnapItsOwnWindows() {
        XCTAssertEqual(admit(pid: mine), .zonesOwn)
    }

    func testTinyWindowsAreHeldBackWithTheirSize() {
        let small = CGRect(x: 0, y: 0, width: 40, height: 400)
        XCTAssertEqual(admit(bounds: small), .tooSmall(small.size))
        XCTAssertEqual(admit(bounds: small).reason, "rejected: 40x400, under 50pt")
    }

    func testTheSizeThresholdIsExclusive() {
        let exactly = CGRect(x: 0, y: 0, width: 50, height: 50)
        XCTAssertFalse(admit(bounds: exactly).isAdmitted)
        let justOver = CGRect(x: 0, y: 0, width: 51, height: 51)
        XCTAssertTrue(admit(bounds: justOver).isAdmitted)
    }

    func testAWindowWithNoBoundsIsHeldBack() {
        XCTAssertEqual(WindowListProvider.admit(layer: 0, ownerPID: theirs,
                                                myPID: mine, bounds: nil), .noBounds)
    }

    func testZonesOwnNormalWindowReportsOwnershipNotLayer() {
        XCTAssertEqual(admit(layer: 0, pid: mine), .zonesOwn)
    }
}
