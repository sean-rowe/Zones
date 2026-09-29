import XCTest
@testable import ZonesCore

final class WindowFidelityBDDTests: BDDTestCase {
    private var steps: WindowFidelitySteps!

    override func registerSteps() {
        steps = WindowFidelitySteps()
        steps.register(in: registry)
    }

    func testWindowFidelity() {
        runFeature("window_fidelity")
    }
}
