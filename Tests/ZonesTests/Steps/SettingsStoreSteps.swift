import XCTest
@testable import ZonesCore

/// An in-memory SettingsStorage so the suite never touches the real
/// UserDefaults domain, which is shared with every other test in the process.
final class InMemorySettingsStorage: SettingsStorage {
    var contents: [String: Any] = [:]

    init(seed: [String: Any] = [:]) { contents = seed }

    func data(forKey key: String) -> Data? { contents[key] as? Data }
    func set(_ value: Any?, forKey key: String) { contents[key] = value }
}

final class SettingsStoreSteps {
    private var storage = InMemorySettingsStorage()
    private var settings: Settings!
    private var center: NotificationCenter!
    private var observer: NSObjectProtocol?
    private var notificationCount = 0

    deinit {
        if let observer { center?.removeObserver(observer) }
    }

    private func makeStore(seed: [String: Any] = [:]) {
        storage = InMemorySettingsStorage(seed: seed)
        center = NotificationCenter()
        notificationCount = 0
        settings = Settings(storage: storage, notificationCenter: center)
        observer = center.addObserver(forName: .settingsDidChange, object: nil, queue: nil) { [weak self] _ in
            self?.notificationCount += 1
        }
    }

    private var storedSettings: [String: Any]? {
        guard let data = storage.data(forKey: Settings.storageKey),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    func register(in registry: StepRegistry) {
        registry.given("a settings store backed by empty storage") { _ in
            self.makeStore()
        }

        registry.given("a settings store backed by corrupt storage") { _ in
            self.makeStore(seed: [Settings.storageKey: Data("this is not json".utf8)])
        }

        registry.given("a settings store whose stored JSON has an unknown key") { _ in
            // zoneGap must differ from the default (8), or "the known key
            // survived" is indistinguishable from "everything fell back".
            let json = #"{"zoneGap": 21, "somethingFromTheFuture": {"nested": true}}"#
            self.makeStore(seed: [Settings.storageKey: Data(json.utf8)])
        }

        registry.when("I change the zone gap to (\\d+)") { args in
            self.settings.update { $0.zoneGap = Double(args[0])! }
        }

        registry.when("I change the zone gap to the value it already has") { _ in
            let existing = self.settings.current.zoneGap
            self.settings.update { $0.zoneGap = existing }
        }

        registry.when("I set the zone gap to -(\\d+)") { args in
            self.settings.update { $0.zoneGap = -Double(args[0])! }
        }

        registry.when("I set the overlay opacity to (\\d+)") { args in
            self.settings.update { $0.overlayOpacity = Double(args[0])! }
        }

        registry.when("I set the overlay padding to -(\\d+)") { args in
            self.settings.update { $0.outerPadding = -Double(args[0])! }
        }

        registry.then("the overlay opacity is (\\d+)") { args in
            XCTAssertEqual(self.settings.current.overlayOpacity, Double(args[0])!)
        }

        registry.then("exactly (\\d+) settingsDidChange notification was posted") { args in
            XCTAssertEqual(self.notificationCount, Int(args[0])!)
        }

        registry.then("the stored settings JSON contains a zone gap of (\\d+)") { args in
            let stored = self.storedSettings
            XCTAssertNotNil(stored, "nothing was persisted")
            XCTAssertEqual(stored?["zoneGap"] as? Double, Double(args[0])!)
        }

        registry.then("a settingsDidChange notification was posted") { _ in
            XCTAssertEqual(self.notificationCount, 1)
        }

        registry.then("no settingsDidChange notification was posted") { _ in
            XCTAssertEqual(self.notificationCount, 0)
        }

        registry.then("the settings equal the defaults") { _ in
            XCTAssertEqual(self.settings.current, AppSettings())
        }

        registry.then("the zone gap is (\\d+)") { args in
            XCTAssertEqual(self.settings.current.zoneGap, Double(args[0])!)
        }

        registry.then("the other settings equal the defaults") { _ in
            var expected = AppSettings()
            expected.zoneGap = self.settings.current.zoneGap
            XCTAssertEqual(self.settings.current, expected)
        }

        registry.then("the store did not crash") { _ in
            // Reaching this step at all is the assertion: a throwing decode
            // would have taken the process down before now.
            XCTAssertNotNil(self.settings)
        }
    }
}
