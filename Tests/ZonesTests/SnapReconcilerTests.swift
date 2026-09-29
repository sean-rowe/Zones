import XCTest
import CoreGraphics
@testable import ZonesCore

final class SnapReconcilerTests: XCTestCase {
    func testExactMatchIsAccepted() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let verdict = SnapReconciler.reconcile(actual: frame, target: frame)
        XCTAssertEqual(verdict, .accepted)
        XCTAssertTrue(verdict.isAccepted)
    }

    func testTerminalCharacterCellQuantisationWithinSlackIsAccepted() {
        // Asked for 700x500, Terminal took 706x494 (diff is 6pt on each axis, <= 16pt slack)
        let target = CGRect(x: 100, y: 100, width: 700, height: 500)
        let actual = CGRect(x: 100, y: 100, width: 706, height: 494)

        let verdict = SnapReconciler.reconcile(actual: actual, target: target)
        XCTAssertEqual(verdict, .accepted, "Deviations within 16pt slack must be accepted as successful snaps")
    }

    func testWindowRefusingWidthAxisIsReported() {
        // Calendar will not go below 908 wide. Asked for 600 wide, actual was 908 (diff 308pt > 16pt)
        let target = CGRect(x: 100, y: 100, width: 600, height: 700)
        let actual = CGRect(x: 100, y: 100, width: 908, height: 700)

        let verdict = SnapReconciler.reconcile(actual: actual, target: target)
        XCTAssertFalse(verdict.isAccepted)
        if case .axisRefused(let wRefused, let hRefused, _, _) = verdict {
            XCTAssertTrue(wRefused, "Width axis refusal must be detected")
            XCTAssertFalse(hRefused, "Height axis was satisfied")
        } else {
            XCTFail("Expected axisRefused verdict")
        }
    }

    func testSourceLevelGuardAgainstCGRectEquality() throws {
        // ZONES-126: Guard test ensuring Snapping/ never compares frames with ==
        let snappingDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ZonesCore/Snapping")

        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(atPath: snappingDir.path)

        for file in files where file.hasSuffix(".swift") {
            let path = snappingDir.appendingPathComponent(file).path
            let content = try String(contentsOfFile: path)
            // Assert no lines compare rect1 == rect2 or actual == target
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("actual == target") || trimmed.contains("target == actual") {
                    XCTFail("Forbidden CGRect equality comparison found in \(file): \(line)")
                }
            }
        }
    }
}
