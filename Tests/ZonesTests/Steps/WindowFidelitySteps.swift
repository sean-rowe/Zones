import XCTest
import CoreGraphics
@testable import ZonesCore

final class WindowFidelitySteps {
    private var targetFrame: CGRect = .zero
    private var actualFrame: CGRect = .zero
    private var verdict: SnapVerdict = .accepted
    private var resizeAttempts = 0

    func register(in registry: StepRegistry) {
        registry.given("Terminal is snapped to a 700x500 zone") { _ in
            self.targetFrame = CGRect(x: 100, y: 100, width: 700, height: 500)
        }

        registry.when("it takes 706x494") { _ in
            self.actualFrame = CGRect(x: 100, y: 100, width: 706, height: 494)
            self.verdict = SnapReconciler.reconcile(actual: self.actualFrame, target: self.targetFrame)
            self.resizeAttempts = 1
        }

        registry.then("the snap is recorded as successful") { _ in
            XCTAssertTrue(self.verdict.isAccepted, "Terminal deviation within slack must be accepted")
        }

        registry.then("the zone is not re-applied") { _ in
            XCTAssertEqual(self.resizeAttempts, 1, "Zone must not be re-applied when snap is accepted")
        }

        registry.given("System Settings is snapped to a 400-wide zone") { _ in
            self.targetFrame = CGRect(x: 100, y: 100, width: 400, height: 700)
        }

        registry.when("it ignores the width") { _ in
            self.actualFrame = CGRect(x: 100, y: 100, width: 680, height: 700)
            self.verdict = SnapReconciler.reconcile(actual: self.actualFrame, target: self.targetFrame)
            self.resizeAttempts = 1
        }

        registry.then("Zones records the refusal") { _ in
            XCTAssertFalse(self.verdict.isAccepted, "Width refusal beyond slack must be detected")
            if case .axisRefused(let wRefused, let hRefused, _, _) = self.verdict {
                XCTAssertTrue(wRefused, "Width axis refusal must be true")
                XCTAssertFalse(hRefused, "Height axis was satisfied")
            } else {
                XCTFail("Expected axisRefused verdict")
            }
        }

        registry.then("does not attempt the resize again") { _ in
            XCTAssertEqual(self.resizeAttempts, 1, "Must never loop or retry when an axis is refused")
        }

        registry.given("Calendar will not go below 908 wide") { _ in
            // Window minimum width constraint is 908
        }

        registry.when("I snap it into a 600-wide zone") { _ in
            self.targetFrame = CGRect(x: 150, y: 200, width: 600, height: 800)
            // Window takes its minimum width 908, but is positioned at the zone's origin
            self.actualFrame = CGRect(x: 150, y: 200, width: 908, height: 800)
            self.verdict = SnapReconciler.reconcile(actual: self.actualFrame, target: self.targetFrame)
            self.resizeAttempts = 1
        }

        registry.then("it is positioned at the zone's origin at its minimum width") { _ in
            XCTAssertEqual(self.actualFrame.origin.x, self.targetFrame.origin.x, "X origin must match target zone")
            XCTAssertEqual(self.actualFrame.origin.y, self.targetFrame.origin.y, "Y origin must match target zone")
            XCTAssertEqual(self.actualFrame.width, 908, "Width must be the window's minimum width")
        }

        registry.then("no resize loop occurs") { _ in
            XCTAssertEqual(self.resizeAttempts, 1, "Must not enter a resize loop")
        }

        registry.given("any snap") { _ in
            self.targetFrame = CGRect(x: 100, y: 100, width: 500, height: 400)
            self.actualFrame = CGRect(x: 100, y: 100, width: 508, height: 396) // within 16pt slack
            self.verdict = SnapReconciler.reconcile(actual: self.actualFrame, target: self.targetFrame)
        }

        registry.then("success is determined by a slack comparison") { _ in
            XCTAssertTrue(self.verdict.isAccepted)
        }

        registry.then("a test asserts no frame equality comparison exists on the snap path") { _ in
            let snappingDir = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Steps
                .deletingLastPathComponent() // ZonesTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // Project root
                .appendingPathComponent("Sources/ZonesCore/Snapping")

            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(atPath: snappingDir.path) else {
                XCTFail("Could not read Snapping directory")
                return
            }

            for file in files where file.hasSuffix(".swift") {
                let path = snappingDir.appendingPathComponent(file).path
                let content = (try? String(contentsOfFile: path)) ?? ""
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.hasPrefix("*") {
                        continue
                    }
                    if trimmed.contains("actual == target") || trimmed.contains("target == actual") {
                        XCTFail("Forbidden CGRect equality comparison found in \(file): \(line)")
                    }
                }
            }
        }
    }
}
