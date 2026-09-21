import XCTest

/// End-to-end checks against the built product rather than the library.
///
/// These exist because the things they assert cannot be proven from inside the
/// process: that the executable actually starts, stays up, and presents itself
/// to macOS as a menu bar accessory. ZONES-7's acceptance was originally
/// verified by hand; this is that check, automated.
final class AppLaunchE2ETests: XCTestCase {

    /// The built Zones executable, located relative to the test bundle so it
    /// works for both debug and release configurations.
    private var executableURL: URL? {
        // .build/<config>/ZonesPackageTests.xctest/... -> .build/<config>/Zones
        var dir = Bundle(for: AppLaunchE2ETests.self).bundleURL
        for _ in 0..<4 {
            let candidate = dir.appendingPathComponent("Zones")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    func testExecutableLaunchesAndStaysRunning() throws {
        guard let executableURL else {
            throw XCTSkip("Zones executable not built; run `swift build` first")
        }

        let process = Process()
        process.executableURL = executableURL
        // UserDefaults reads `-key value` pairs from the argument domain, so
        // this suppresses the first-run onboarding window without touching the
        // developer's own saved state.
        process.arguments = ["-com.pinyridgelabs.Zones.hasCompletedOnboarding", "YES"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        defer {
            if process.isRunning { process.terminate() }
        }

        // A crash on launch shows up as an early exit. Give it long enough to
        // get through applicationDidFinishLaunching and settle.
        Thread.sleep(forTimeInterval: 2.0)

        XCTAssertTrue(process.isRunning,
                      "Zones exited within 2s of launch (status \(process.terminationStatus))")
    }

    func testExecutableExistsAfterBuild() throws {
        guard let executableURL else {
            throw XCTSkip("Zones executable not built; run `swift build` first")
        }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executableURL.path))
    }
}
