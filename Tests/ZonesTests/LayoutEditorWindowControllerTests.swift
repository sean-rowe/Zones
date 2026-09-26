import XCTest
@testable import ZonesCore

final class LayoutEditorWindowControllerTests: XCTestCase {

    private var storage: InMemorySettingsStorage!
    private var store: LayoutStore!
    private let display = DisplayIdentity(key: "editor-test-display", source: .uuid)

    override func setUp() {
        super.setUp()
        storage = InMemorySettingsStorage()
        store = LayoutStore(storage: storage)
    }

    func testTheEditorOpensOnTheLayoutAssignedToTheDisplay() {
        let assigned = LayoutTemplate.grid(rows: 2, columns: 2)
        store.save(assigned)
        store.assign(layoutID: assigned.id, to: display)

        let controller = LayoutEditorWindowController(store: store, display: display)
        XCTAssertEqual(controller.workingLayoutForTesting.id, assigned.id)
    }

    func testTheEditorFallsBackToATemplateWhenNothingIsAssigned() {
        let controller = LayoutEditorWindowController(store: store, display: display)
        XCTAssertFalse(controller.workingLayoutForTesting.zones.isEmpty,
                       "an unassigned display must still open on something editable")
    }

    func testSavingStoresTheLayoutAndAssignsItToTheDisplay() {
        let controller = LayoutEditorWindowController(store: store, display: display)
        controller.saveForTesting()

        XCTAssertEqual(store.layouts.count, 1)
        XCTAssertEqual(store.assignedLayout(for: display)?.id, store.layouts.first?.id)
    }

    func testSavingAnUnnamedLayoutGivesItAName() {
        let unnamed = ZoneLayout(name: "   ", zones: LayoutTemplate.columns(2).zones)
        let controller = LayoutEditorWindowController(store: store, display: display,
                                                     editing: unnamed)
        controller.saveForTesting()
        XCTAssertEqual(store.layouts.first?.name, "Untitled Layout")
    }

    func testDuplicatingProducesANewIdentity() {
        let original = LayoutTemplate.columns(3)
        store.save(original)
        store.assign(layoutID: original.id, to: display)

        let controller = LayoutEditorWindowController(store: store, display: display)
        controller.duplicateForTesting()
        controller.saveForTesting()

        // Two layouts, not one overwritten: a duplicate that kept the id would
        // silently replace the original on save.
        XCTAssertEqual(store.layouts.count, 2)
        XCTAssertNotEqual(store.layouts[0].id, store.layouts[1].id)
        XCTAssertTrue(store.layouts.contains { $0.name.hasSuffix("Copy") })
    }

    func testChangingTheTemplateKeepsTheNameAndIdentity() {
        var named = LayoutTemplate.columns(2)
        named.name = "My Layout"
        store.save(named)
        store.assign(layoutID: named.id, to: display)

        let controller = LayoutEditorWindowController(store: store, display: display)
        controller.applyTemplateForTesting(origin: .rows(count: 3), count: 3)

        XCTAssertEqual(controller.workingLayoutForTesting.name, "My Layout",
                       "nudging the stepper must not discard a name the user typed")
        XCTAssertEqual(controller.workingLayoutForTesting.id, named.id)
        XCTAssertEqual(controller.workingLayoutForTesting.zones.count, 3)
    }

    func testTheTemplateControlsOpenOnTheLayoutBeingEdited() {
        // Opening on a saved three-column layout must not show "Columns / 2",
        // or the first stepper click regenerates two columns and discards it.
        let three = LayoutTemplate.columns(3)
        store.save(three)
        store.assign(layoutID: three.id, to: display)

        let controller = LayoutEditorWindowController(store: store, display: display)
        let state = LayoutEditorWindowController.controlState(
            for: controller.workingLayoutForTesting)
        XCTAssertEqual(state.count, 3)
    }

    func testAGridLayoutOpensWithItsOwnRowCount() {
        let grid = LayoutTemplate.grid(rows: 3, columns: 3)
        store.save(grid)
        store.assign(layoutID: grid.id, to: display)

        let controller = LayoutEditorWindowController(store: store, display: display)
        XCTAssertEqual(
            LayoutEditorWindowController.controlState(for: controller.workingLayoutForTesting).count,
            3)
    }

    func testAnEditedLayoutReportsItselfAsCustom() {
        // After an edit the origin is .custom, and the pop-up has to follow — a
        // stepper click while it still named the old template would regenerate
        // from that template and wipe the edits.
        var edited = LayoutTemplate.columns(2)
        let splitter = LayoutEditing.splitters(in: edited)[0]
        edited = LayoutEditing.move(splitter, to: 0.7, in: edited)

        let controller = LayoutEditorWindowController(store: store, display: display,
                                                     editing: edited)
        let state = LayoutEditorWindowController.controlState(
            for: controller.workingLayoutForTesting)
        let customIndex = LayoutEditorWindowController.templatesForTesting
            .firstIndex { $0.title == "Custom" }
        XCTAssertEqual(state.index, customIndex)
    }

    func testDeletingRemovesTheLayoutAndReassignsTheDisplay() {
        let keep = LayoutTemplate.columns(2)
        let doomed = LayoutTemplate.rows(3)
        store.save(keep)
        store.save(doomed)
        store.assign(layoutID: doomed.id, to: display)

        let controller = LayoutEditorWindowController(store: store, display: display)
        controller.deleteForTesting()

        XCTAssertFalse(store.layouts.contains { $0.id == doomed.id })
        // The display must not be left pointing at nothing.
        XCTAssertNotNil(store.assignedLayout(for: display))
    }
}
