import XCTest
@testable import ZonesCore

final class MoveToApplicationsBDDTests: BDDTestCase {
    private var steps: MoveToApplicationsSteps!

    override func registerSteps() {
        steps = MoveToApplicationsSteps()
        steps.register(in: registry)
    }

    func testMoveToApplications() {
        runFeature("move_to_applications")
    }
}
