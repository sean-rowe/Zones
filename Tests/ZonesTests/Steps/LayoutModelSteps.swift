import XCTest
@testable import ZonesCore

final class LayoutModelSteps {
    private var zone = Zone.full
    private var resolved = CGRect.zero
    private var visibleFrame = CGRect.zero

    func register(in registry: StepRegistry) {
        registry.given("a zone covering the left half of the unit square") { _ in
            self.zone = Zone(index: 0, rect: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        }

        registry.given("a zone whose rect escapes the unit square") { _ in
            self.zone = Zone(index: 0, rect: CGRect(x: -0.5, y: -0.5, width: 3, height: 3))
        }

        registry.given("a display (\\d+) by (\\d+) with a visible frame inset by (\\d+) at the top") { args in
            let width = Double(args[0])!, height = Double(args[1])!, inset = Double(args[2])!
            // AppKit's visibleFrame sits above the origin by the menu bar height.
            self.visibleFrame = CGRect(x: 0, y: 0, width: width, height: height - inset)
        }

        registry.when("it is resolved on a display (\\d+) by (\\d+)") { args in
            let area = CGRect(x: 0, y: 0, width: Double(args[0])!, height: Double(args[1])!)
            self.resolved = ZoneResolver.resolve(self.zone, in: area, spacing: .none)
        }

        registry.when("a full-display zone is resolved") { _ in
            self.resolved = ZoneResolver.resolve(.full, in: self.visibleFrame, spacing: .none)
        }

        registry.then("the resolved width is (\\d+)") { args in
            XCTAssertEqual(self.resolved.width, Double(args[0])!, accuracy: 0.001)
        }

        registry.then("the resolved height is (\\d+)") { args in
            XCTAssertEqual(self.resolved.height, Double(args[0])!, accuracy: 0.001)
        }

        registry.then("the zone rect lies inside the unit square") { _ in
            let r = self.zone.rect
            XCTAssertGreaterThanOrEqual(r.minX, 0)
            XCTAssertGreaterThanOrEqual(r.minY, 0)
            XCTAssertLessThanOrEqual(r.maxX, 1)
            XCTAssertLessThanOrEqual(r.maxY, 1)
        }

        registry.then("the resolved rect does not overlap the menu bar area") { _ in
            XCTAssertLessThanOrEqual(self.resolved.maxY, self.visibleFrame.maxY)
            XCTAssertEqual(self.resolved.height, self.visibleFrame.height, accuracy: 0.001)
        }
    }
}
