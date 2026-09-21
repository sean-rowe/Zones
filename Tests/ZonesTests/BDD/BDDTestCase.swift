import XCTest

/// Base class for feature-file driven tests.
///
/// Subclasses override `registerSteps()` and call `runFeature("name")`. Feature
/// files live in Tests/ZonesTests/Features and reach the test bundle through
/// the `.copy("Features")` resource declaration in Package.swift.
class BDDTestCase: XCTestCase {
    private(set) var registry = StepRegistry()

    /// Override to register step definitions for this feature.
    func registerSteps() {}

    func runFeature(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "feature",
                                          subdirectory: "Features")
            ?? Bundle.module.url(forResource: name, withExtension: "feature") else {
            XCTFail("feature file not found: \(name).feature", file: file, line: line)
            return
        }
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("feature file unreadable: \(name).feature", file: file, line: line)
            return
        }

        let feature = FeatureParser.parse(source)
        XCTAssertFalse(feature.scenarios.isEmpty,
                       "feature '\(name)' parsed to zero scenarios",
                       file: file, line: line)
        for unrecognised in feature.unrecognisedLines {
            XCTFail("unrecognised line in \(name).feature: \(unrecognised)",
                    file: file, line: line)
        }

        for scenario in feature.scenarios {
            // Fresh state per scenario, exactly as a real Gherkin runner does.
            registry = StepRegistry()
            registerSteps()
            for step in scenario.steps {
                do {
                    try registry.run(keyword: step.keyword, text: step.text)
                } catch {
                    XCTFail("\(scenario.name): \(error)", file: file, line: line)
                    break
                }
            }
        }
    }
}
