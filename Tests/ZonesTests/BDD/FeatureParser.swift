import Foundation

struct ParsedStep {
    let keyword: String   // already resolved: And/But become the step they continue
    let text: String
}

struct ParsedScenario {
    let name: String
    let steps: [ParsedStep]
}

struct ParsedFeature {
    let name: String
    let scenarios: [ParsedScenario]
    /// Lines inside a scenario that matched no step keyword.
    ///
    /// Surfaced rather than skipped: a mistyped keyword ("Give a counter...")
    /// used to vanish silently, so the scenario ran with one fewer step and
    /// still passed. A harness that quietly drops steps is worse than no
    /// harness.
    let unrecognisedLines: [String]
}

/// A deliberately small Gherkin parser: Feature, Scenario, and
/// Given/When/Then/And/But. Enough for the scenarios Zones writes, and no more.
enum FeatureParser {
    static func parse(_ source: String) -> ParsedFeature {
        var featureName = ""
        var scenarios: [ParsedScenario] = []
        var currentName: String?
        var currentSteps: [ParsedStep] = []
        var lastKeyword = "given"
        var unrecognised: [String] = []

        func closeScenario() {
            guard let name = currentName else { return }
            scenarios.append(ParsedScenario(name: name, steps: currentSteps))
            currentName = nil
            currentSteps = []
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if let rest = value(of: "Feature:", in: line) {
                featureName = rest
            } else if let rest = value(of: "Scenario:", in: line) {
                closeScenario()
                currentName = rest
                lastKeyword = "given"
            } else if let (keyword, text) = step(in: line) {
                // And/But continue whichever keyword preceded them.
                let resolved = (keyword == "and" || keyword == "but") ? lastKeyword : keyword
                lastKeyword = resolved
                currentSteps.append(ParsedStep(keyword: resolved, text: text))
            } else if currentName != nil {
                // Prose above the first Scenario is the feature description and
                // is fine. Prose *inside* a scenario is a broken step.
                unrecognised.append(line)
            }
        }
        closeScenario()
        return ParsedFeature(name: featureName, scenarios: scenarios,
                             unrecognisedLines: unrecognised)
    }

    private static func value(of prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func step(in line: String) -> (String, String)? {
        for keyword in ["Given", "When", "Then", "And", "But"] where line.hasPrefix(keyword + " ") {
            let text = String(line.dropFirst(keyword.count + 1)).trimmingCharacters(in: .whitespaces)
            return (keyword.lowercased(), text)
        }
        return nil
    }
}
