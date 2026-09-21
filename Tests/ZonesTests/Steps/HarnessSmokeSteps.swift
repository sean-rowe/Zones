import XCTest

/// Exercises the harness itself: argument capture, ordering, and And-resolution.
final class HarnessSmokeSteps {
    private var counter = 0

    func register(in registry: StepRegistry) {
        registry.given("a counter starting at (\\d+)") { args in
            self.counter = Int(args[0])!
        }
        registry.given("I add (\\d+)") { args in
            self.counter += Int(args[0])!
        }
        registry.when("I add (\\d+)") { args in
            self.counter += Int(args[0])!
        }
        registry.then("the counter is (\\d+)") { args in
            XCTAssertEqual(self.counter, Int(args[0])!)
        }
    }
}
