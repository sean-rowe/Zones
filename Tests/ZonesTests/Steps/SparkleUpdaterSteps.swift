import XCTest
import Sparkle
import Foundation
@testable import ZonesCore

/// Steps for sparkle_updater.
class SparkleUpdaterSteps {
    private var packageManifest = ""
    private var buildScript = ""
    private var infoPlist: [String: Any]?
    private var controller: ZonesController!
    private var savedMakeController: (() -> SPUStandardUpdaterController?)?

    func tearDown() {
        if let savedMakeController = savedMakeController {
            UpdaterService.shared.makeController = savedMakeController
        }
        savedMakeController = nil
        controller = nil
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Steps
            .deletingLastPathComponent()   // ZonesTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func read(_ relativePath: String) -> String {
        let url = Self.repoRoot.appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("\(relativePath) should exist and read")
            return ""
        }
        return text
    }

    func register(in registry: StepRegistry) {
        registry.given("the package manifest and the updater service") { [self] _ in
            packageManifest = read("Package.swift")
        }

        registry.then("ZonesCore depends on Sparkle and owns an updater service") { [self] _ in
            XCTAssertTrue(packageManifest.contains("sparkle-project/Sparkle"),
                          "the manifest should pull Sparkle")
            XCTAssertTrue(packageManifest.contains(#".product(name: "Sparkle", package: "Sparkle")"#),
                          "ZonesCore should link the Sparkle product")
            XCTAssertFalse(UpdaterService().isStarted)
        }

        registry.given("the app build script") { [self] _ in
            buildScript = read("scripts/build-app.sh")
        }

        registry.then("it places Sparkle in the bundle's Frameworks and signs it before the app") { [self] _ in
            XCTAssertTrue(buildScript.contains(#"cp -R "$(dirname "$BINARY")/Sparkle.framework" "$FRAMEWORKS/""#),
                          "the bundle must carry its own Sparkle copy")
            XCTAssertTrue(buildScript.contains(#"install_name_tool -add_rpath "@executable_path/../Frameworks""#),
                          "the executable must find the framework beside itself, not in .build")
            guard let nested = buildScript.range(of: "XPCServices"),
                  let appSign = buildScript.range(of: #"codesign "${CODESIGN_ARGS[@]}" "$APP_DIR""#) else {
                return XCTFail("nested Sparkle signing and the app signing should both exist")
            }
            XCTAssertTrue(nested.lowerBound < appSign.lowerBound,
                          "nested code signs before the app that contains it")
        }

        registry.given("the packaged Info.plist") { [self] _ in
            let url = Self.repoRoot.appendingPathComponent("packaging/Info.plist")
            let data = try? Data(contentsOf: url)
            infoPlist = data.flatMap {
                try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
            }
            XCTAssertNotNil(infoPlist)
        }

        registry.then("it declares the appcast feed URL and a non-empty EdDSA public key") { [self] _ in
            let feed = infoPlist?["SUFeedURL"] as? String ?? ""
            XCTAssertTrue(feed.hasPrefix("https://"),
                          "the feed must be public HTTPS, got '\(feed)'")
            let key = infoPlist?["SUPublicEDKey"] as? String ?? ""
            XCTAssertFalse(key.isEmpty, "without the public key no update verifies")
            XCTAssertNotNil(Data(base64Encoded: key),
                            "the public key should be base64, got '\(key)'")
        }

        registry.given("the status menu is rebuilt") { [self] _ in
            controller = ZonesController()
            controller.rebuildMenu()
        }

        registry.then("it offers Check for Updates") { [self] _ in
            let titles = controller.statusMenu.items.map(\.title)
            XCTAssertTrue(titles.contains("Check for Updates…"),
                          "manual checking harnesses the impatient, got \(titles)")
        }

        registry.given("a controller that has not run setup") { [self] _ in
            savedMakeController = UpdaterService.shared.makeController
            UpdaterService.shared.makeController = { nil }
            UpdaterService.shared.resetForTesting()
            controller = ZonesController()
        }

        registry.then("no Sparkle updater has been started") { [self] _ in
            XCTAssertFalse(controller.updater.isStarted,
                           "constructing the controller must not start network checks")
        }
    }
}
