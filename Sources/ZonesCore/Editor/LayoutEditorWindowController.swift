import AppKit

/// The layout editor: the one activating window in Zones.
///
/// Everything else Zones shows is a non-activating panel or a click-through
/// overlay. This window takes focus because the user is deliberately working
/// in it.
public final class LayoutEditorWindowController: NSWindowController, NSWindowDelegate {

    private let store: LayoutStore
    private let displayIdentity: DisplayIdentity
    private var preview: LayoutPreviewView!
    private var nameField: NSTextField!
    private var countStepper: NSStepper!
    private var countLabel: NSTextField!
    private var templatePopUp: NSPopUpButton!
    private var mergeButton: NSButton!

    private var working: ZoneLayout {
        didSet {
            preview?.layout = working
            nameField?.stringValue = working.name
            syncTemplateControls()
            updateControls()
        }
    }

    private static let templates: [(title: String, origin: LayoutOrigin)] = [
        ("Columns", .columns(count: 2)),
        ("Rows", .rows(count: 2)),
        ("Grid", .grid(rows: 2, columns: 2)),
        ("Priority Grid", .priorityGrid(count: 3)),
        ("Focus", .focus(count: 3)),
        ("Custom", .custom),
    ]

    public init(store: LayoutStore = .shared,
                display: DisplayIdentity,
                editing layout: ZoneLayout? = nil,
                targetAspectRatio: CGFloat = 16.0 / 9.0) {
        self.store = store
        self.displayIdentity = display
        self.working = layout ?? store.assignedLayout(for: display) ?? LayoutTemplate.columns(2)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit Layout"
        window.center()
        // A sensible floor: below this the preview and the controls fight.
        window.minSize = NSSize(width: 560, height: 400)
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView(targetAspectRatio: targetAspectRatio)
        syncTemplateControls()
        updateControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func makeContentView(targetAspectRatio: CGFloat) -> NSView {
        let container = NSView()

        preview = LayoutPreviewView(layout: working, targetAspectRatio: targetAspectRatio)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.onLayoutChanged = { [weak self] updated in
            self?.working = updated
        }
        preview.onSelectionChanged = { [weak self] _ in
            self?.updateControls()
        }

        templatePopUp = NSPopUpButton()
        templatePopUp.addItems(withTitles: Self.templates.map(\.title))
        templatePopUp.target = self
        templatePopUp.action = #selector(templateChanged)

        countStepper = NSStepper()
        countStepper.minValue = 1
        countStepper.maxValue = 12
        countStepper.target = self
        countStepper.action = #selector(countChanged)
        // No initial value here: syncTemplateControls() sets both this and the
        // pop-up from `working` once the views exist. A literal default would be
        // dead code that reads like the bug where the controls ignored the
        // layout being edited.

        countLabel = NSTextField(labelWithString: "")
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        nameField = NSTextField(string: working.name)
        // Commits on every keystroke, so Save does not depend on the field's
        // action having fired.
        nameField.isContinuous = true
        nameField.placeholderString = "Layout name"
        nameField.target = self
        nameField.action = #selector(nameChanged)

        let splitButton = NSButton(title: "Split", target: self, action: #selector(splitSelected))
        let splitAxis = NSSegmentedControl(labels: ["Vertical", "Horizontal"],
                                           trackingMode: .selectOne,
                                           target: nil, action: nil)
        splitAxis.selectedSegment = 0
        self.splitAxisControl = splitAxis

        mergeButton = NSButton(title: "Merge", target: self, action: #selector(mergeSelected))

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let duplicateButton = NSButton(title: "Duplicate", target: self, action: #selector(duplicate))
        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteLayout))

        let templateRow = NSStackView(views: [
            NSTextField(labelWithString: "Template:"), templatePopUp, countStepper, countLabel,
        ])
        templateRow.spacing = 8
        templateRow.alignment = .centerY

        let editRow = NSStackView(views: [splitAxis, splitButton, mergeButton])
        editRow.spacing = 8

        let actionRow = NSStackView(views: [
            NSTextField(labelWithString: "Name:"), nameField,
            NSView(), duplicateButton, deleteButton, saveButton,
        ])
        actionRow.spacing = 8
        actionRow.alignment = .centerY

        let stack = NSStackView(views: [templateRow, preview, editRow, actionRow])
        stack.orientation = .vertical
        stack.spacing = 12
        // 20pt window margins, matching the spacing AppKit's own dialogs use.
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // The preview takes the slack; the control rows keep their height.
            preview.heightAnchor.constraint(greaterThanOrEqualTo: stack.heightAnchor,
                                            multiplier: 0.5),
        ])
        return container
    }

    private var splitAxisControl: NSSegmentedControl!

    /// Point the template pop-up and stepper at whatever `working` actually is.
    ///
    /// Two bugs live here if this is skipped. Opening the editor on a saved
    /// three-column layout would show "Columns / 2", so the first stepper click
    /// applies a two-column template and discards the layout. And after any
    /// edit the origin becomes .custom while the pop-up still names the old
    /// template, so a stepper click regenerates from it and wipes the edits.
    private func syncTemplateControls() {
        guard let templatePopUp, let countStepper else { return }
        let (index, count) = Self.controlState(for: working)
        templatePopUp.selectItem(at: index)
        countStepper.integerValue = count
    }

    /// The pop-up index and stepper value that represent a layout.
    static func controlState(for layout: ZoneLayout) -> (index: Int, count: Int) {
        func index(of name: String) -> Int {
            templates.firstIndex { $0.title == name } ?? templates.count - 1
        }
        switch layout.origin {
        case .columns(let count):      return (index(of: "Columns"), count)
        case .rows(let count):         return (index(of: "Rows"), count)
        case .grid(let rows, _):       return (index(of: "Grid"), rows)
        case .priorityGrid(let count): return (index(of: "Priority Grid"), count)
        case .focus(let count):        return (index(of: "Focus"), count)
        case .custom:
            // Custom has no count to show, so report the zone count — it is at
            // least honest about the size of what is on screen.
            return (index(of: "Custom"), max(1, layout.zones.count))
        }
    }

    private func updateControls() {
        // Merge needs a selection that actually forms a rectangle, and saying so
        // by disabling the button is clearer than refusing the click later.
        let selection = preview?.selectedZoneIDs ?? []
        mergeButton?.isEnabled = LayoutEditing.canMerge(zoneIDs: selection, in: working)
        countLabel?.stringValue = working.zones.count == 1 ? "1 zone" : "\(working.zones.count) zones"
    }

    // MARK: - Test seams

    /// The layout currently being edited.
    var workingLayoutForTesting: ZoneLayout { working }

    static var templatesForTesting: [(title: String, origin: LayoutOrigin)] { templates }

    func saveForTesting() { save() }
    func duplicateForTesting() { duplicate() }
    func applyTemplateForTesting(origin: LayoutOrigin, count: Int) {
        applyTemplate(origin: origin, count: count)
    }

    /// Deletes without the confirmation alert, which cannot run in a test.
    func deleteForTesting() {
        let assigned = reassignmentTargets()
        store.delete(id: working.id)
        reassign(assigned)
    }

    // MARK: - Actions

    @objc private func templateChanged() {
        applyTemplate(count: countStepper.integerValue)
    }

    @objc private func countChanged() {
        applyTemplate(count: countStepper.integerValue)
    }

    private func applyTemplate(count: Int) {
        applyTemplate(origin: Self.templates[templatePopUp.indexOfSelectedItem].origin,
                      count: count)
    }

    private func applyTemplate(origin: LayoutOrigin, count: Int) {
        var generated: ZoneLayout
        switch origin {
        case .columns:      generated = LayoutTemplate.columns(count)
        case .rows:         generated = LayoutTemplate.rows(count)
        case .grid:         generated = LayoutTemplate.grid(rows: count, columns: count)
        case .priorityGrid: generated = LayoutTemplate.priorityGrid(count)
        case .focus:        generated = LayoutTemplate.focus(count)
        case .custom:       return  // nothing to generate; keep the user's edits
        }
        // Keep the identity and the name: regenerating is an edit of this
        // layout, not the creation of a different one. Losing a name the user
        // typed because they nudged the stepper would be its own bug.
        generated = ZoneLayout(id: working.id, name: working.name,
                               zones: generated.zones, origin: generated.origin)
        working = generated
    }

    @objc private func nameChanged() {
        working.name = nameField.stringValue
    }

    @objc private func splitSelected() {
        guard let id = preview.selectedZoneIDs.first else { return }
        let axis: SplitterAxis = splitAxisControl.selectedSegment == 0 ? .vertical : .horizontal
        working = LayoutEditing.split(zoneID: id, axis: axis, in: working)
    }

    @objc private func mergeSelected() {
        working = LayoutEditing.merge(zoneIDs: preview.selectedZoneIDs, in: working)
        preview.selectedZoneIDs = []
    }

    @objc private func save() {
        // Read the field directly. NSTextField's action fires on Enter or when
        // focus leaves, so typing a name and clicking Save straight afterwards
        // would otherwise persist the old one.
        if let nameField {
            working.name = nameField.stringValue
        }
        if working.name.trimmingCharacters(in: .whitespaces).isEmpty {
            working.name = "Untitled Layout"
        }
        store.save(working)
        store.assign(layoutID: working.id, to: displayIdentity)
        window?.close()
    }

    @objc private func duplicate() {
        // A new UUID, or saving the copy would overwrite the original.
        working = ZoneLayout(name: working.name + " Copy",
                             zones: working.zones, origin: working.origin)
    }

    /// Displays currently using the layout about to be deleted.
    private func reassignmentTargets() -> [DisplayIdentity] {
        var targets = DisplayObserver.currentDisplays()
            .map(\.identity)
            .filter { store.assignedLayout(for: $0)?.id == working.id }
        // The editor's own display counts even if it is not currently attached,
        // which is the case in a test and after a disconnect.
        if store.assignedLayout(for: displayIdentity)?.id == working.id,
           !targets.contains(displayIdentity) {
            targets.append(displayIdentity)
        }
        return targets
    }

    /// Never leave a display with nothing: fall back rather than clearing.
    private func reassign(_ displays: [DisplayIdentity]) {
        guard let fallback = store.layouts.first else { return }
        for display in displays {
            store.assign(layoutID: fallback.id, to: display)
        }
    }

    @objc private func deleteLayout() {
        let assignedElsewhere = reassignmentTargets()

        if !assignedElsewhere.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Delete “\(working.name)”?"
            alert.informativeText = assignedElsewhere.count == 1
                ? "One display is using this layout. It will fall back to a built-in layout."
                : "\(assignedElsewhere.count) displays are using this layout. "
                  + "They will fall back to a built-in layout."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        store.delete(id: working.id)
        reassign(assignedElsewhere)
        window?.close()
    }
}
