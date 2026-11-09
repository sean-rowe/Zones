import XCTest
@testable import ZonesCore

/// Templates, the picker's model, and the store operations behind its cards
/// and dialogs.
final class LayoutCatalogTests: XCTestCase {

    private var store: LayoutStore!
    private let display = DisplayIdentity(key: "catalog-display", source: .uuid)
    private let other = DisplayIdentity(key: "catalog-other", source: .uuid)

    override func setUp() {
        super.setUp()
        store = LayoutStore(storage: InMemorySettingsStorage())
    }

    // MARK: Templates

    func testEveryTemplateGeneratesTheZoneCountAskedFor() {
        for kind in TemplateKind.allCases where kind.hasZoneCount {
            for count in 1...10 {
                let layout = kind.generate(zoneCount: count)
                XCTAssertEqual(layout.zones.count, count, "\(kind) with \(count)")
                XCTAssertEqual(layout.coverage, 1, accuracy: 0.0001, "\(kind) with \(count) must tile")
                XCTAssertEqual(TemplateKind(origin: layout.origin), kind)
            }
        }
    }

    func testNoLayoutIsEmptyAndRemembersWhatItIs() {
        let blank = TemplateKind.blank.generate(zoneCount: 3)
        XCTAssertTrue(blank.isEmpty)
        XCTAssertEqual(blank.origin, .blank)
    }

    func testAnEvenGridIsTheRegularGrid() {
        XCTAssertEqual(LayoutTemplate.grid(zoneCount: 6).zones.map(\.rect),
                       LayoutTemplate.grid(rows: 2, columns: 3).zones.map(\.rect))
    }

    func testCustomAndCanvasLayoutsAreNotTemplates() {
        XCTAssertNil(TemplateKind(origin: .custom))
        XCTAssertNil(TemplateKind(origin: .canvas))
    }

    func testZoneCountIsCapped() {
        XCTAssertEqual(TemplateKind.columns.generate(zoneCount: 99).zones.count,
                       TemplateKind.maximumZoneCount)
    }

    // MARK: Picker model

    func testAFreshInstallShowsSixTemplatesAndTheSpareColumnsLayoutAsCustom() {
        store.installBuiltInsIfEmpty()
        let model = LayoutPickerModel(layouts: store.layouts, appliedLayoutID: nil)

        XCTAssertEqual(model.templates.map(\.kind), TemplateKind.allCases)
        let columns = model.templates.first { $0.kind == .columns }
        XCTAssertEqual(columns?.layout.zones.count, 2, "the first stored columns layout")
        XCTAssertTrue(columns?.isStored ?? false)
        XCTAssertFalse(model.templates.first { $0.kind == .rows }?.isStored ?? true,
                       "no rows layout ships, so the card offers a generated one")
        XCTAssertEqual(model.custom.map(\.name), ["3 Columns"],
                       "a second columns layout must stay reachable")
    }

    func testTheAppliedLayoutIsMarked() {
        let layout = LayoutTemplate.columns(2)
        store.save(layout)
        let model = LayoutPickerModel(layouts: store.layouts, appliedLayoutID: layout.id)
        XCTAssertTrue(model.isApplied(layout))
        XCTAssertFalse(model.isApplied(LayoutTemplate.rows(2)))
    }

    func testCustomLayoutsKeepStoreOrder() {
        let a = ZoneLayout(name: "A", zones: [Zone.full])
        let b = ZoneLayout(name: "B", zones: [Zone.full], origin: .canvas)
        store.save(a)
        store.save(b)
        XCTAssertEqual(LayoutPickerModel(layouts: store.layouts, appliedLayoutID: nil).custom.map(\.name),
                       ["A", "B"])
    }

    // MARK: Apply

    func testApplyingAnUnsavedTemplateSavesItFirst() {
        let rows = TemplateKind.rows.generate(zoneCount: 3)
        LayoutCatalog.apply(rows, to: display, in: store)
        XCTAssertEqual(store.layouts.map(\.id), [rows.id])
        XCTAssertEqual(store.assignedLayout(for: display)?.id, rows.id)
    }

    func testApplyingAStoredLayoutDoesNotDuplicateIt() {
        let layout = LayoutTemplate.columns(2)
        store.save(layout)
        LayoutCatalog.apply(layout, to: display, in: store)
        LayoutCatalog.apply(layout, to: other, in: store)
        XCTAssertEqual(store.layouts.count, 1)
        XCTAssertEqual(store.assignedLayout(for: other)?.id, layout.id)
    }

    func testNoLayoutIsAStoredAssignmentNotAMissingOne() {
        // A display with no assignment gets the default layout the next time
        // displays settle, so "No layout" has to be a real, empty layout.
        LayoutCatalog.apply(TemplateKind.blank.generate(zoneCount: 0), to: display, in: store)
        XCTAssertEqual(store.assignedLayout(for: display)?.isEmpty, true)
    }

    // MARK: Edit and delete

    func testRegeneratingKeepsTheIdentity() {
        let layout = LayoutTemplate.columns(2)
        let regenerated = LayoutCatalog.regenerate(layout, kind: .columns, zoneCount: 4)
        XCTAssertEqual(regenerated.id, layout.id)
        XCTAssertEqual(regenerated.zones.count, 4)
    }

    func testDeletingMovesEveryAffectedDisplayToANonEmptyFallback() {
        let blank = TemplateKind.blank.generate(zoneCount: 0)
        let keep = LayoutTemplate.columns(2)
        let doomed = ZoneLayout(name: "Doomed", zones: [Zone.full])
        [blank, keep, doomed].forEach(store.save)
        store.assign(layoutID: doomed.id, to: display)
        store.assign(layoutID: doomed.id, to: other)

        LayoutCatalog.delete(doomed, from: store, displays: [display, other])

        XCTAssertNil(store.layout(id: doomed.id))
        XCTAssertEqual(store.assignedLayout(for: display)?.id, keep.id,
                       "falling back to No layout would silently switch zones off")
        XCTAssertEqual(store.assignedLayout(for: other)?.id, keep.id)
    }

    func testDeletingLeavesUnaffectedDisplaysAlone() {
        let keep = LayoutTemplate.columns(2)
        let doomed = ZoneLayout(name: "Doomed", zones: [Zone.full])
        let mine = LayoutTemplate.rows(2)
        [keep, doomed, mine].forEach(store.save)
        store.assign(layoutID: mine.id, to: display)
        LayoutCatalog.delete(doomed, from: store, displays: [display])
        XCTAssertEqual(store.assignedLayout(for: display)?.id, mine.id)
    }

    func testSavingAnEditedLayoutAppliesItAndNamesTheUnnamed() {
        let unnamed = ZoneLayout(name: "  ", zones: [Zone.full])
        LayoutCatalog.saveEdited(unnamed, for: display, in: store)
        XCTAssertEqual(store.assignedLayout(for: display)?.name, "Untitled Layout")
    }

    func testNewLayoutNamesDoNotCollide() {
        let existing = [ZoneLayout(name: "Custom layout 1", zones: []),
                        ZoneLayout(name: "Custom layout 2", zones: [])]
        XCTAssertEqual(LayoutCatalog.nextCustomName(existing: existing), "Custom layout 3")
    }

    func testNewLayoutsStartEditable() {
        let grid = LayoutCatalog.newLayout(name: "G", canvas: false)
        XCTAssertEqual(grid.origin, .custom)
        XCTAssertEqual(grid.zones.count, 2)
        let canvas = LayoutCatalog.newLayout(name: "C", canvas: true)
        XCTAssertEqual(canvas.origin, .canvas)
        XCTAssertEqual(canvas.zones.count, 1)
    }

    // MARK: Edit dialog draft

    func testATemplateDraftIsNamedByItsTemplateAndRegenerates() {
        let layout = LayoutTemplate.columns(2)
        var draft = LayoutEditDraft(layout: layout, settings: AppSettings())
        XCTAssertEqual(draft.name, "Columns")
        XCTAssertFalse(draft.isNameEditable)
        XCTAssertFalse(draft.isDeletable)
        XCTAssertTrue(draft.hasZoneCount)
        XCTAssertEqual(draft.zoneCount, 2)

        draft.zoneCount = 5
        XCTAssertEqual(draft.editedLayout.zones.count, 5)
        XCTAssertEqual(draft.editedLayout.id, layout.id)
    }

    func testAnUnchangedTemplateDraftIsTheSameLayout() {
        let layout = LayoutTemplate.priorityGrid(3)
        XCTAssertEqual(LayoutEditDraft(layout: layout, settings: AppSettings()).editedLayout, layout)
    }

    func testACustomDraftRenamesButIgnoresABlankName() {
        let layout = ZoneLayout(name: "Mine", zones: [Zone.full])
        var draft = LayoutEditDraft(layout: layout, settings: AppSettings())
        XCTAssertTrue(draft.isNameEditable && draft.isDeletable && draft.canEditZones)
        XCTAssertFalse(draft.hasZoneCount)
        draft.name = "Renamed "
        XCTAssertEqual(draft.editedLayout.name, "Renamed")
        draft.name = "   "
        XCTAssertEqual(draft.editedLayout.name, "Mine")
    }

    func testATemplateLayoutListedUnderCustomEditsAsCustom() {
        let spare = LayoutTemplate.columns(3)
        let draft = LayoutEditDraft(layout: spare, settings: AppSettings(), asTemplate: false)
        XCTAssertTrue(draft.isDeletable && draft.canEditZones && draft.isNameEditable)
        XCTAssertEqual(draft.name, "3 Columns")
    }

    func testSpacingMapsOntoTheGlobalGap() {
        var settings = AppSettings()
        settings.zoneGap = 12
        var draft = LayoutEditDraft(layout: LayoutTemplate.columns(2), settings: settings)
        XCTAssertTrue(draft.showSpaceAroundZones)
        XCTAssertEqual(draft.spacing, 12)

        draft.showSpaceAroundZones = false
        XCTAssertEqual(draft.apply(to: settings).zoneGap, 0)
        draft.showSpaceAroundZones = true
        draft.spacing = 20
        XCTAssertEqual(draft.apply(to: settings).zoneGap, 20)
        XCTAssertEqual(draft.apply(to: settings).outerPadding, settings.outerPadding,
                       "only the gap is the dialog's to change")
    }

    func testSwitchingSpacingBackOnOffersTheDefault() {
        var settings = AppSettings()
        settings.zoneGap = 0
        let draft = LayoutEditDraft(layout: LayoutTemplate.columns(2), settings: settings)
        XCTAssertFalse(draft.showSpaceAroundZones)
        XCTAssertEqual(draft.spacing, AppSettings().zoneGap)
    }

    // MARK: Persistence of the new origins

    func testCanvasAndBlankOriginsRoundTrip() throws {
        for origin in [LayoutOrigin.canvas, .blank] {
            let layout = ZoneLayout(name: "X", zones: [], origin: origin)
            let decoded = try JSONDecoder().decode(ZoneLayout.self,
                                                   from: JSONEncoder().encode(layout))
            XCTAssertEqual(decoded.origin, origin)
        }
    }

    func testAVersionOneArchiveStillLoads() throws {
        let layout = LayoutTemplate.columns(2)
        let json = """
        {"version": 1, "layouts": [\(String(decoding: try JSONEncoder().encode(layout), as: UTF8.self))],
         "assignments": {}}
        """
        let storage = InMemorySettingsStorage(seed: [LayoutStore.storageKey: Data(json.utf8)])
        let loaded = LayoutStore(storage: storage)
        XCTAssertFalse(loaded.isReadOnlyDueToNewerArchive)
        XCTAssertEqual(loaded.layouts.map(\.id), [layout.id])
    }

    func testTheArchiveIsWrittenAsVersionTwo() throws {
        let storage = InMemorySettingsStorage()
        LayoutStore(storage: storage).save(ZoneLayout(name: "C", zones: [], origin: .canvas))
        let data = try XCTUnwrap(storage.data(forKey: LayoutStore.storageKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 2,
                       "an older Zones must see a newer archive and refuse to overwrite it")
    }
}
