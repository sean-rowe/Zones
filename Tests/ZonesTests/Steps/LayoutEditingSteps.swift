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

        registry.given("a layout of two column pairs separated by a full-width band") { _ in
            // Two columns at the top, one full-width zone across the middle,
            // two columns at the bottom. Both pairs meet at x=0.5, but the band
            // interrupts the line, so these are two dividers that happen to
            // share an x — not one continuous divider. Four equal 0.5x0.5
            // zones would instead BE a 2x2 grid, where one divider is correct.
            self.layout = ZoneLayout(name: "Banded", zones: [
                Zone(index: 0, rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.3)),
                Zone(index: 1, rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.3)),
                Zone(index: 2, rect: CGRect(x: 0, y: 0.3, width: 1, height: 0.3)),
                Zone(index: 3, rect: CGRect(x: 0, y: 0.6, width: 0.5, height: 0.4)),
                Zone(index: 4, rect: CGRect(x: 0.5, y: 0.6, width: 0.5, height: 0.4)),
            ])
            self.reload()
        }

        registry.when("I drag the upper vertical splitter to (0\\.\\d+)") { args in
            // The upper pair occupies normalized y 0...0.5, so its divider is
            // the vertical one whose span starts at 0.
            guard let splitter = self.splitters.first(where: {
                $0.axis == .vertical && $0.span.lowerBound < 0.0001
            }) else { return XCTFail("no upper vertical splitter") }
            self.layout = LayoutEditing.move(splitter, to: Double(args[0])!, in: self.layout)
            self.reload()
        }

        registry.then("there are (\\d+) vertical splitters at (0\\.\\d+)") { args in
            let position = Double(args[1])!
            let matching = self.splitters.filter {
                $0.axis == .vertical && abs($0.position - position) < 0.0001
            }
            XCTAssertEqual(matching.count, Int(args[0])!,
                           "spans: \(matching.map { $0.span })")
        }

        registry.then("the upper pair splits at (0\\.\\d+)") { args in
            let expected = Double(args[0])!
            let upperLeft = self.layout.zones.first { $0.rect.minY < 0.0001 && $0.rect.minX < 0.0001 }
            XCTAssertEqual(Double(upperLeft!.rect.maxX), expected, accuracy: 0.0001)
        }

        registry.then("the lower pair still splits at (0\\.\\d+)") { args in
            let expected = Double(args[0])!
            let lowerLeft = self.layout.zones.first { $0.rect.minY > 0.5 && $0.rect.minX < 0.0001 }
            XCTAssertEqual(Double(lowerLeft!.rect.maxX), expected, accuracy: 0.0001,
                           "dragging one divider moved the other")
        }

        registry.then("that vertical splitter spans the whole height") { _ in
            let splitter = self.splitters.first { $0.axis == .vertical }
            XCTAssertNotNil(splitter)
            XCTAssertEqual(splitter!.span.lowerBound, 0, accuracy: 0.0001)
            XCTAssertEqual(splitter!.span.upperBound, 1, accuracy: 0.0001)
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
