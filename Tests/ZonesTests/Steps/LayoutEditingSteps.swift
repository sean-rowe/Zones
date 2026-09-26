import XCTest
@testable import ZonesCore

final class LayoutEditingSteps {
    private var layout = ZoneLayout(name: "", zones: [])
    private var splitters: [Splitter] = []
    private var mergeAttempted = false
    private var mergeRefused = false

    private func reload() {
        splitters = LayoutEditing.splitters(in: layout)
    }

    // swiftlint:disable:next function_body_length
    func register(in registry: StepRegistry) {
        registry.given("the columns template with (\\d+)") { args in
            self.layout = LayoutTemplate.columns(Int(args[0])!)
            self.reload()
        }
        registry.given("the grid template with (\\d+) rows and (\\d+) columns") { args in
            self.layout = LayoutTemplate.grid(rows: Int(args[0])!, columns: Int(args[1])!)
            self.reload()
        }
        registry.given("an L-shaped layout of three zones") { _ in
            // Left column full height; right column split in two.
            let left = Zone(index: 0, rect: CGRect(x: 0, y: 0, width: 0.5, height: 1))
            let topRight = Zone(index: 1, rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
            let bottomRight = Zone(index: 2, rect: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
            self.layout = ZoneLayout(name: "L", zones: [left, topRight, bottomRight])
            self.reload()
        }

        registry.when("I drag the vertical splitter to (0\\.\\d+)") { args in
            guard let splitter = self.splitters.first(where: { $0.axis == .vertical }) else {
                return XCTFail("no vertical splitter to drag")
            }
            self.layout = LayoutEditing.move(splitter, to: Double(args[0])!, in: self.layout)
            self.reload()
        }
        registry.when("I split zone (\\d+) (vertically|horizontally)") { args in
            guard let zone = self.layout.zone(at: Int(args[0])!) else {
                return XCTFail("no zone at index \(args[0])")
            }
            let axis: SplitterAxis = args[1] == "vertically" ? .vertical : .horizontal
            self.layout = LayoutEditing.split(zoneID: zone.id, axis: axis, in: self.layout)
            self.reload()
        }
        registry.when("I merge zones (\\d+) and (\\d+)") { args in
            let ids = [Int(args[0])!, Int(args[1])!].compactMap { self.layout.zone(at: $0)?.id }
            let before = self.layout.zones.count
            self.layout = LayoutEditing.merge(zoneIDs: Set(ids), in: self.layout)
            self.mergeAttempted = true
            self.mergeRefused = self.layout.zones.count == before
            self.reload()
        }
        registry.when("I try to merge the two zones that do not form a rectangle") { _ in
            // The left column plus only the top-right block: an L.
            let ids = Set([self.layout.zone(at: 0)!.id, self.layout.zone(at: 1)!.id])
            let before = self.layout.zones.count
            self.layout = LayoutEditing.merge(zoneIDs: ids, in: self.layout)
            self.mergeAttempted = true
            self.mergeRefused = self.layout.zones.count == before
        }
        registry.when("I try to merge only zone (\\d+)") { args in
            let ids = Set([self.layout.zone(at: Int(args[0])!)!.id])
            let before = self.layout.zones.count
            self.layout = LayoutEditing.merge(zoneIDs: ids, in: self.layout)
            self.mergeAttempted = true
            self.mergeRefused = self.layout.zones.count == before
        }

        registry.then("there is (\\d+) splitter") { args in
            XCTAssertEqual(self.splitters.count, Int(args[0])!)
        }
        registry.then("there are (\\d+) splitters") { args in
            XCTAssertEqual(self.splitters.count, Int(args[0])!)
        }
        registry.then("splitter (\\d+) is (vertical|horizontal)") { args in
            let expected: SplitterAxis = args[1] == "vertical" ? .vertical : .horizontal
            XCTAssertEqual(self.splitters[Int(args[0])!].axis, expected)
        }
        registry.then("splitter (\\d+) is at (0\\.\\d+)") { args in
            XCTAssertEqual(self.splitters[Int(args[0])!].position, Double(args[1])!, accuracy: 0.0001)
        }
        registry.then("there is a (vertical|horizontal) splitter at (0\\.\\d+)") { args in
            let axis: SplitterAxis = args[0] == "vertical" ? .vertical : .horizontal
            let position = Double(args[1])!
            XCTAssertTrue(self.splitters.contains {
                $0.axis == axis && abs($0.position - position) < 0.0001
            }, "no \(args[0]) splitter at \(position); have \(self.splitters.map(\.id))")
        }
        registry.then("zone (\\d+) is (0\\.\\d+) wide") { args in
            XCTAssertEqual(Double(self.layout.zone(at: Int(args[0])!)!.rect.width),
                           Double(args[1])!, accuracy: 0.0001)
        }
        registry.then("zone (\\d+) is at least the minimum width") { args in
            let width = Double(self.layout.zone(at: Int(args[0])!)!.rect.width)
            XCTAssertGreaterThanOrEqual(width, LayoutEditing.minimumZoneFraction - 0.0001)
        }
        registry.then("all zones on the left of the splitter are (0\\.\\d+) wide") { args in
            let expected = Double(args[0])!
            let left = self.layout.zones.filter { $0.rect.minX < 0.0001 }
            XCTAssertFalse(left.isEmpty)
            for zone in left {
                XCTAssertEqual(Double(zone.rect.width), expected, accuracy: 0.0001)
            }
        }
        registry.then("the layout has (\\d+) zones") { args in
            XCTAssertEqual(self.layout.zones.count, Int(args[0])!)
        }
        registry.then("the layout still has (\\d+) zones") { args in
            XCTAssertEqual(self.layout.zones.count, Int(args[0])!)
        }
        registry.then("the merge is refused") { _ in
            XCTAssertTrue(self.mergeAttempted)
            XCTAssertTrue(self.mergeRefused, "the merge went through when it should have been refused")
        }
        registry.then("the layout origin is custom") { _ in
            XCTAssertEqual(self.layout.origin, .custom)
        }
        registry.then("the zones tile the unit square exactly") { _ in
            XCTAssertEqual(self.layout.coverage, 1.0, accuracy: 0.0001,
                           "coverage is \(self.layout.coverage)")
            let zones = self.layout.zones
            for i in zones.indices {
                for j in zones.indices where j > i {
                    let overlap = zones[i].rect.intersection(zones[j].rect)
                    let area = overlap.isNull ? 0 : overlap.width * overlap.height
                    XCTAssertEqual(area, 0, accuracy: 0.0001, "zones \(i) and \(j) overlap")
                }
            }
        }
    }
}
