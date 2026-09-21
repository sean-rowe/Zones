import XCTest
@testable import ZonesCore

final class LayoutPersistenceSteps {
    private var storage = InMemorySettingsStorage()
    private var store: LayoutStore!
    private var savedIDs: [String: UUID] = [:]
    private var display = DisplayIdentity(key: "unset", source: .uuid)
    private var originalBytes: Data?

    func register(in registry: StepRegistry) {
        registry.given("an empty layout store") { _ in
            self.storage = InMemorySettingsStorage()
            self.store = LayoutStore(storage: self.storage)
            self.savedIDs = [:]
        }

        registry.given("a layout store backed by corrupt storage") { _ in
            self.storage = InMemorySettingsStorage(
                seed: [LayoutStore.storageKey: Data("definitely not json".utf8)])
            self.store = LayoutStore(storage: self.storage)
        }

        registry.given("a layout store whose archive claims a future version") { _ in
            // Carries a field this version knows nothing about, which is the
            // realistic shape of a newer archive and the thing most likely to
            // be silently dropped by a partial rewrite.
            let json = #"""
            {"version": 9999, "layouts": [], "assignments": {},
             "zoneRulesAddedInAFutureVersion": [{"app": "Terminal", "zone": 2}]}
            """#
            let bytes = Data(json.utf8)
            self.originalBytes = bytes
            self.storage = InMemorySettingsStorage(seed: [LayoutStore.storageKey: bytes])
            self.store = LayoutStore(storage: self.storage)
        }

        registry.when("I save a layout named \"(.+)\" with (\\d+) zones") { args in
            let layout = LayoutTemplate.columns(Int(args[1])!)
            var named = ZoneLayout(id: layout.id, name: args[0],
                                   zones: layout.zones, origin: layout.origin)
            named.name = args[0]
            self.savedIDs[args[0]] = named.id
            self.store.save(named)
        }

        registry.when("I assign it to a display identified by UUID") { _ in
            self.display = DisplayIdentity(key: "E1B2C3D4-0000-4000-8000-000000000001",
                                           source: .uuid)
            let id = self.savedIDs.values.first!
            self.store.assign(layoutID: id, to: self.display)
        }

        registry.when("I assign it to a display identified only by geometry") { _ in
            self.display = DisplayIdentity(
                key: DisplayIdentity.geometryKey(for: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                source: .geometry)
            self.store.assign(layoutID: self.savedIDs.values.first!, to: self.display)
        }

        registry.then("that display is assigned the layout named \"(.+)\"") { args in
            XCTAssertEqual(self.store.assignedLayout(for: self.display)?.name, args[0])
        }

        registry.then("the stored archive holds no assignments") { _ in
            guard let data = self.storage.data(forKey: LayoutStore.storageKey),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return XCTFail("nothing was persisted at all") }
            let assignments = json["assignments"] as? [String: Any] ?? [:]
            XCTAssertTrue(assignments.isEmpty,
                          "a geometry key names a position, not a display, and must not persist")
        }

        registry.when("I delete the layout named \"(.+)\"") { args in
            self.store.delete(id: self.savedIDs[args[0]]!)
        }

        registry.when("the store is reloaded from the same storage") { _ in
            // A new instance over the same bytes is what a relaunch actually is.
            self.store = LayoutStore(storage: self.storage)
        }

        registry.then("the layout named \"(.+)\" is present") { args in
            XCTAssertTrue(self.store.layouts.contains { $0.name == args[0] })
        }

        registry.then("it has the same identifier") { _ in
            let expected = self.savedIDs.values.first!
            XCTAssertTrue(self.store.layouts.contains { $0.id == expected })
        }

        registry.then("it has (\\d+) zones") { args in
            XCTAssertEqual(self.store.layouts.first?.zones.count, Int(args[0])!)
        }

        registry.then("that display is still assigned the layout named \"(.+)\"") { args in
            XCTAssertEqual(self.store.assignedLayout(for: self.display)?.name, args[0])
        }

        registry.then("that display has no assigned layout") { _ in
            XCTAssertNil(self.store.assignedLayout(for: self.display))
        }

        registry.when("I install the built-in layouts") { _ in
            self.store.installBuiltInsIfEmpty()
        }

        registry.then("the store is read only") { _ in
            XCTAssertTrue(self.store.isReadOnlyDueToNewerArchive)
        }

        registry.then("the store is not read only") { _ in
            XCTAssertFalse(self.store.isReadOnlyDueToNewerArchive)
        }

        registry.then("the store has some layouts") { _ in
            XCTAssertFalse(self.store.layouts.isEmpty)
        }

        registry.then("the stored bytes are unchanged") { _ in
            guard let data = self.storage.data(forKey: LayoutStore.storageKey) else {
                return XCTFail("the newer archive must not have been deleted")
            }
            // Compared whole. Checking only the version field would accept a
            // rewrite that kept the number and threw away everything the newer
            // version had stored alongside it.
            XCTAssertEqual(data, self.originalBytes,
                           "the newer archive must be left byte-for-byte alone")
        }

        registry.then("the store has no layouts") { _ in
            XCTAssertTrue(self.store.layouts.isEmpty)
        }

        registry.then("the store did not crash") { _ in
            XCTAssertNotNil(self.store)
        }
    }
}
