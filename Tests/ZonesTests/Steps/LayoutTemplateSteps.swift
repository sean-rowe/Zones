import XCTest
@testable import ZonesCore

final class LayoutTemplateSteps {
    private var layout = ZoneLayout(name: "", zones: [])

    func register(in registry: StepRegistry) {
        registry.given("the columns template with (\\d+)") { args in
            self.layout = LayoutTemplate.columns(Int(args[0])!)
        }
        registry.given("the rows template with (\\d+)") { args in
            self.layout = LayoutTemplate.rows(Int(args[0])!)
        }
        registry.given("the grid template with (\\d+) rows and (\\d+) columns") { args in
            self.layout = LayoutTemplate.grid(rows: Int(args[0])!, columns: Int(args[1])!)
        }
        registry.given("the priority grid template with (\\d+)") { args in
            self.layout = LayoutTemplate.priorityGrid(Int(args[0])!)
        }
        registry.given("the focus template with (\\d+)") { args in
            self.layout = LayoutTemplate.focus(Int(args[0])!)
        }

        registry.then("the layout has (\\d+) zones") { args in
            XCTAssertEqual(self.layout.zones.count, Int(args[0])!)
        }
        registry.then("every zone is (\\d+) high") { args in
            let expected = Double(args[0])!
            for zone in self.layout.zones {
                XCTAssertEqual(zone.rect.height, expected, accuracy: 0.0001)
            }
        }
        registry.then("every zone is (\\d+) wide") { args in
            let expected = Double(args[0])!
            for zone in self.layout.zones {
                XCTAssertEqual(zone.rect.width, expected, accuracy: 0.0001)
            }
        }
        registry.then("zone (\\d+) is wider than zone (\\d+)") { args in
            let a = self.layout.zone(at: Int(args[0])!)
            let b = self.layout.zone(at: Int(args[1])!)
            XCTAssertNotNil(a); XCTAssertNotNil(b)
            XCTAssertGreaterThan(a!.rect.width, b!.rect.width)
        }

        registry.then("the zones tile the unit square exactly") { _ in
            // Two independent checks. Coverage alone would accept two zones
            // that overlap while a third is missing, since the areas can still
            // sum to 1.
            XCTAssertEqual(self.layout.coverage, 1.0, accuracy: 0.0001,
                           "zones do not cover the unit square exactly")
            let zones = self.layout.zones
            for i in zones.indices {
                for j in zones.indices where j > i {
                    let overlap = zones[i].rect.intersection(zones[j].rect)
                    let area = overlap.isNull ? 0 : overlap.width * overlap.height
                    XCTAssertEqual(area, 0, accuracy: 0.0001,
                                   "zones \(i) and \(j) overlap")
                }
            }
        }
    }
}
