import Foundation

/// Thrown when a feature file contains a step no one has defined.
struct UndefinedStepError: Error, CustomStringConvertible {
    let keyword: String
    let text: String
    var description: String { "undefined step: \(keyword) \(text)" }
}

/// Maps Gherkin step text to closures, by regular expression.
///
/// Capture groups in the pattern become the `[String]` argument, in order, so a
/// step written `registry.given("a layout with (\\d+) zones")` receives ["4"]
/// for "Given a layout with 4 zones".
final class StepRegistry {
    typealias Step = ([String]) throws -> Void

    private enum Keyword: String {
        case given, when, then
    }

    private var steps: [(keyword: Keyword, regex: NSRegularExpression, body: Step)] = []

    func given(_ pattern: String, _ body: @escaping Step) { add(.given, pattern, body) }
    func when(_ pattern: String, _ body: @escaping Step) { add(.when, pattern, body) }
    func then(_ pattern: String, _ body: @escaping Step) { add(.then, pattern, body) }

    private func add(_ keyword: Keyword, _ pattern: String, _ body: @escaping Step) {
        // Anchored, so "a zone" cannot satisfy "a zone that overlaps another".
        // An unanchored match was the first thing that made a suite lie.
        guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$") else {
            fatalError("step pattern is not a valid regular expression: \(pattern)")
        }
        steps.append((keyword, regex, body))
    }

    /// Run the step matching this keyword and text.
    ///
    /// `And` and `But` are resolved by the caller to the keyword they continue,
    /// so they never reach here.
    func run(keyword: String, text: String) throws {
        guard let kw = Keyword(rawValue: keyword.lowercased()) else {
            throw UndefinedStepError(keyword: keyword, text: text)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for step in steps where step.keyword == kw {
            guard let match = step.regex.firstMatch(in: text, range: range) else { continue }
            var args: [String] = []
            for i in 1..<match.numberOfRanges {
                guard let r = Range(match.range(at: i), in: text) else { continue }
                args.append(String(text[r]))
            }
            try step.body(args)
            return
        }
        throw UndefinedStepError(keyword: keyword, text: text)
    }
}
