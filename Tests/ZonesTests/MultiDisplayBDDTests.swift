import XCTest
@testable import ZonesCore

final class MultiDisplayBDDTests: BDDTestCase {
    private var steps: MultiDisplaySteps!

    override func registerSteps() {
        steps = MultiDisplaySteps()
        steps.register(in: registry)
    }

    func testMultiDisplay() {
        runFeature("multi_display")
    }
}
