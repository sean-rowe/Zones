import XCTest
@testable import ZonesCore

final class HarnessSmokeBDDTests: BDDTestCase {
    private var steps: HarnessSmokeSteps!

    override func registerSteps() {
        steps = HarnessSmokeSteps()
        steps.register(in: registry)
    }

    func testHarnessSmoke() {
        runFeature("harness_smoke")
    }
}

/// The harness must fail loudly on an undefined step, or a suite can pass by
/// simply not defining anything. Tested directly rather than through a feature
/// file, since a feature file that fails on purpose would fail the suite.
final class HarnessFailureModeTests: XCTestCase {
    func testUndefinedStepThrows() {
        let registry = StepRegistry()
        XCTAssertThrowsError(try registry.run(keyword: "given", text: "something nobody defined"))
    }

    func testStepPatternsAreAnchored() throws {
        let registry = StepRegistry()
        var ran = false
        registry.given("a zone") { _ in ran = true }
        // Must NOT match the longer sentence.
        XCTAssertThrowsError(try registry.run(keyword: "given", text: "a zone that overlaps another"))
        XCTAssertFalse(ran)
        try registry.run(keyword: "given", text: "a zone")
        XCTAssertTrue(ran)
    }

    func testProseInsideAScenarioIsReportedNotSkipped() {
        // A mistyped keyword must not vanish. "Give" is not a step keyword, so
        // it has to come back as an unrecognised line rather than leaving the
        // scenario one step shorter and still green.
        let feature = FeatureParser.parse("""
        Feature: F
          Scenario: S
            Given one
            Give two
            Then three
        """)
        XCTAssertEqual(feature.unrecognisedLines, ["Give two"])
        XCTAssertEqual(feature.scenarios.first?.steps.count, 2)
    }

    func testFeatureDescriptionAboveScenariosIsNotFlagged() {
        let feature = FeatureParser.parse("""
        Feature: F
          Some prose describing the feature.
          Spanning two lines.

          Scenario: S
            Given one
        """)
        XCTAssertTrue(feature.unrecognisedLines.isEmpty)
    }

    func testAndContinuesPrecedingKeyword() {
        let feature = FeatureParser.parse("""
        Feature: F
          Scenario: S
            Given one
            And two
            When three
            And four
            Then five
            And six
        """)
        XCTAssertEqual(feature.scenarios.first?.steps.map(\.keyword),
                       ["given", "given", "when", "when", "then", "then"])
    }
}
