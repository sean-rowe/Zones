import XCTest
import Foundation
@testable import ZonesCore

/// Steps for notarized_release.
class ReleasePipelineSteps {
    private var notarizeScript = ""
    private var releaseScript = ""
    private var releaseRunOutput = ""
    private var releaseRunStatus: Int32 = -1
    private var scriptContents: [String: String] = [:]

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Steps
            .deletingLastPathComponent()   // ZonesTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func read(_ script: String) -> String {
        let url = Self.repoRoot.appendingPathComponent("scripts/\(script)")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("scripts/\(script) should exist and read")
            return ""
        }
        return text
    }

    func register(in registry: StepRegistry) {
        registry.given("the release script") { [self] _ in
            releaseScript = read("release.sh")
        }

        registry.then("it runs the doctor, the release build, the disk image and the notarization in order") { [self] _ in
            let stages = ["release-doctor.sh", "build-app.sh --release",
                          "make-dmg.sh", "notarize.sh"]
            var searchFrom = releaseScript.startIndex
            for stage in stages {
                guard let range = releaseScript.range(of: stage, range: searchFrom..<releaseScript.endIndex) else {
                    return XCTFail("release.sh should run '\(stage)' after the previous stage")
                }
                searchFrom = range.upperBound
            }
        }

        registry.then("a failing doctor stops the release before any build") { [self] _ in
            XCTAssertTrue(releaseScript.contains("set -euo pipefail"),
                          "the pipeline must die on the first failing stage")
            let doctor = releaseScript.range(of: "release-doctor.sh")
            let build = releaseScript.range(of: "build-app.sh")
            XCTAssertNotNil(doctor); XCTAssertNotNil(build)
            if let doctor = doctor, let build = build {
                XCTAssertTrue(doctor.lowerBound < build.lowerBound,
                              "the gate belongs before the minutes-long build")
            }
            XCTAssertTrue(releaseScript.contains("release aborted"),
                          "the refusal should say it refused, not just exit")
        }

        registry.given("the release script runs with version \"(.+)\"") { [self] args in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [Self.repoRoot.appendingPathComponent("scripts/release.sh").path,
                                 "--version", args[0]]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let exited = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in exited.signal() }
            try? process.run()
            _ = exited.wait(timeout: .now() + 30)
            releaseRunOutput = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                      encoding: .utf8) ?? ""
            releaseRunStatus = process.terminationStatus
        }

        registry.then("it refuses before the doctor or any build stage") { [self] _ in
            XCTAssertNotEqual(releaseRunStatus, 0, "a malformed version must not release")
            XCTAssertTrue(releaseRunOutput.contains("version must look like"),
                          "the refusal should say what a version looks like")
            XCTAssertFalse(releaseRunOutput.contains("release doctor"),
                           "validation belongs before even the doctor runs")
        }

        registry.given("the notarize script") { [self] _ in
            notarizeScript = read("notarize.sh")
        }

        registry.then("it staples the ticket and validates the staple") { [self] _ in
            XCTAssertTrue(notarizeScript.contains("stapler staple"),
                          "without stapling, offline first launches fail Gatekeeper")
            XCTAssertTrue(notarizeScript.contains("stapler validate"),
                          "a staple that is not validated is a staple assumed")
        }

        registry.given("the release scripts directory") { [self] _ in
            let scriptsDir = Self.repoRoot.appendingPathComponent("scripts")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: scriptsDir.path)) ?? []
            for file in files where file.hasSuffix(".sh") {
                scriptContents[file] = read(file)
            }
            XCTAssertFalse(scriptContents.isEmpty, "scripts directory should contain .sh files")
        }

        registry.then("every script enforces pipefail") { [self] _ in
            for (filename, text) in scriptContents {
                XCTAssertTrue(text.contains("pipefail"),
                              "\(filename) must enable pipefail to avoid masking pipeline failures")
            }
        }

        registry.then("no script pipes build or notarization into tail") { [self] _ in
            for (filename, text) in scriptContents {
                let hasPipedTail = text.range(of: #"\|\s*tail"#, options: .regularExpression) != nil
                XCTAssertFalse(hasPipedTail,
                               "\(filename) must not pipe into tail (which can mask non-zero exit codes)")
            }
        }
    }
}
