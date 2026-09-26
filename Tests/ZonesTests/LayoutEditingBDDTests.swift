import XCTest
@testable import ZonesCore

final class LayoutEditingBDDTests: BDDTestCase {
    private var steps: LayoutEditingSteps!
    override func registerSteps() {
        steps = LayoutEditingSteps()
        steps.register(in: registry)
    }
    func testLayoutEditing() { runFeature("layout_editing") }
}
