import XCTest
@testable import ZonesCore

final class ZoneMemoryBDDTests: BDDTestCase {
    private var steps: ZoneMemorySteps!

    override func registerSteps() {
        steps = ZoneMemorySteps()
        steps.register(in: registry)
    }

    func testZoneMemory() {
        runFeature("zone_memory")
    }
}
