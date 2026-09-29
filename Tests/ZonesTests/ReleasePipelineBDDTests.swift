import XCTest
@testable import ZonesCore

final class ReleasePipelineBDDTests: BDDTestCase {
    private var steps: ReleasePipelineSteps!

    override func registerSteps() {
        steps = ReleasePipelineSteps()
        steps.register(in: registry)
    }

    func testReleasePipeline() {
        runFeature("notarized_release")
    }
}
