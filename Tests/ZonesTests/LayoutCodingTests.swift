import XCTest
@testable import ZonesCore

/// Decoding has to enforce the same invariants construction does. Synthesized
/// Codable conformance does not — it assigns stored properties directly — so
/// these tests exist to keep the custom initializers in place.
final class LayoutCodingTests: XCTestCase {

    func testDecodingClampsAZoneOutsideTheUnitSquare() throws {
        // A hand-edited or corrupted file can contain anything.
        let json = """
        {"id":"E1B2C3D4-0000-4000-8000-000000000001","index":0,
         "rect":[[-0.5,-0.5],[3.0,3.0]]}
        """
        let zone = try JSONDecoder().decode(Zone.self, from: Data(json.utf8))
        XCTAssertGreaterThanOrEqual(zone.rect.minX, 0)
        XCTAssertGreaterThanOrEqual(zone.rect.minY, 0)
        XCTAssertLessThanOrEqual(zone.rect.maxX, 1)
        XCTAssertLessThanOrEqual(zone.rect.maxY, 1)
    }

    func testDecodingReindexesZonesRatherThanTrustingStoredIndices() throws {
        // The JSON has to carry the bad indices itself. Building this through
        // replaceZones would reindex before encoding, so the decoder would be
        // handed [0, 1, 2] and the test would pass without proving anything.
        let json = """
        {"id":"E1B2C3D4-0000-4000-8000-0000000000AA","name":"Scrambled",
         "origin":{"custom":{}},
         "zones":[
           {"id":"00000000-0000-4000-8000-000000000001","index":77,
            "rect":[[0.0,0.0],[0.5,1.0]]},
           {"id":"00000000-0000-4000-8000-000000000002","index":77,
            "rect":[[0.5,0.0],[0.5,1.0]]}
         ]}
        """
        let decoded = try JSONDecoder().decode(ZoneLayout.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.zones.map(\.index), [0, 1],
                       "stored indices must be replaced by array order")
    }

    func testRoundTripPreservesIdentityAndGeometry() throws {
        let original = LayoutTemplate.priorityGrid(4)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ZoneLayout.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.origin, original.origin)
        XCTAssertEqual(decoded.coverage, original.coverage, accuracy: 0.0001)
    }
}

/// The newer-archive protection, including the case that defeated the first
/// attempt at it.
final class LayoutStoreVersionGuardTests: XCTestCase {

    private func store(seededWith json: String) -> (LayoutStore, InMemorySettingsStorage) {
        let storage = InMemorySettingsStorage(
            seed: [LayoutStore.storageKey: Data(json.utf8)])
        return (LayoutStore(storage: storage), storage)
    }

    func testANewerArchiveWithAnUnreadableSchemaIsStillProtected() {
        // The case that matters. Checking the version *after* decoding meant a
        // schema change threw, was treated as corruption, and the store came
        // back writable — overwriting the data the check was protecting.
        let json = """
        {"version": 9999, "layouts": "a shape this version cannot decode",
         "assignments": 42, "somethingNew": {"a": 1}}
        """
        let (store, storage) = self.store(seededWith: json)

        XCTAssertTrue(store.isReadOnlyDueToNewerArchive,
                      "a newer archive must be detected even when it cannot be decoded")

        store.installBuiltInsIfEmpty()
        store.save(LayoutTemplate.columns(2))

        XCTAssertEqual(storage.data(forKey: LayoutStore.storageKey), Data(json.utf8),
                       "the newer archive was modified")
    }

    func testEveryMutationIsRefusedWhileReadOnly() {
        let (store, _) = self.store(seededWith: #"{"version": 9999}"#)
        let display = DisplayIdentity(key: "test-display", source: .uuid)
        let layout = LayoutTemplate.columns(2)

        store.save(layout)
        XCTAssertTrue(store.layouts.isEmpty, "save must be refused while read-only")

        store.assign(layoutID: layout.id, to: display)
        XCTAssertNil(store.assignedLayout(for: display),
                     "assign must be refused while read-only")

        // In-memory state and stored state must not diverge: a mutation that
        // is silently kept in memory but never written is worse than one that
        // is refused outright.
        store.delete(id: layout.id)
        store.clearAssignment(for: display)
        XCTAssertTrue(store.layouts.isEmpty)
    }

    func testACurrentVersionArchiveRemainsWritable() {
        let (store, _) = self.store(seededWith: #"{"version": 1, "layouts": [], "assignments": {}}"#)
        XCTAssertFalse(store.isReadOnlyDueToNewerArchive)
        XCTAssertTrue(store.installBuiltInsIfEmpty())
        XCTAssertFalse(store.layouts.isEmpty)
    }

    func testCorruptDataRemainsWritable() {
        // Corrupt is not the same as newer: there is nothing to protect.
        let (store, _) = self.store(seededWith: "absolutely not json")
        XCTAssertFalse(store.isReadOnlyDueToNewerArchive)
        XCTAssertTrue(store.installBuiltInsIfEmpty())
    }
}
