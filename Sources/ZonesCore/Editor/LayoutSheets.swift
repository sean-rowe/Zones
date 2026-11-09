import AppKit

/// Shared chrome for the picker's dialogs: a sheet with a bold title, a body,
/// and a button row along the bottom, in the shape of FancyZones' dialogs.
class EditorSheetController: NSWindowController {

    let titleLabel = NSTextField(labelWithString: "")
    let body = NSStackView()
    let buttonRow = NSStackView()

    init(title: String, width: CGFloat) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 14

        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [titleLabel, body, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = BackgroundView(color: EditorTheme.cardBackground)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: width),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -48),
        ])
        window.contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A caption above a control, as FancyZones stacks its labels.
    static func field(_ caption: String, _ control: NSView, note: String? = nil) -> NSStackView {
        let label = NSTextField(labelWithString: caption)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        var views: [NSView] = [label, control]
        if let note {
            let noteLabel = NSTextField(wrappingLabelWithString: note)
            noteLabel.font = .systemFont(ofSize: 11)
            noteLabel.textColor = .secondaryLabelColor
            views.append(noteLabel)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    func close(_ response: NSApplication.ModalResponse) {
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window, returnCode: response)
        } else {
            window.orderOut(nil)
        }
    }

    static func flexibleSpace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        return view
    }
}

/// "Edit layout": name, zone count, spacing, and for custom layouts Edit zones
/// and Delete. The pencil on a card opens it.
final class EditLayoutSheetController: EditorSheetController {

    private(set) var draft: LayoutEditDraft
    var onSave: ((LayoutEditDraft) -> Void)?
    var onEditZones: ((LayoutEditDraft) -> Void)?
    var onDelete: (() -> Void)?

    let nameField = NSTextField()
    let countField = NSTextField()
    let countStepper = NSStepper()
    let spacingSwitch = NSSwitch()
    let spacingField = NSTextField()
    let spacingStepper = NSStepper()

    init(layout: ZoneLayout, settings: AppSettings, asTemplate: Bool? = nil) {
        draft = LayoutEditDraft(layout: layout, settings: settings, asTemplate: asTemplate)
        super.init(title: "Edit “\(draft.name)”", width: 440)
        buildBody()
        syncControls()
    }

    private func buildBody() {
        nameField.stringValue = draft.name
        // A template is named by its template; a disabled field says so
        // more plainly than an editable one that ignores what is typed.
        nameField.isEnabled = draft.isNameEditable
        nameField.isContinuous = true
        nameField.target = self
        nameField.action = #selector(nameChanged)
        nameField.widthAnchor.constraint(equalToConstant: 392).isActive = true
        body.addArrangedSubview(Self.field("Name", nameField))

        if draft.hasZoneCount {
            countStepper.minValue = 1
            countStepper.maxValue = Double(TemplateKind.maximumZoneCount)
            countStepper.target = self
            countStepper.action = #selector(countStepped)
            configureNumberField(countField, action: #selector(countTyped))
            body.addArrangedSubview(Self.field("Number of zones", row(countField, countStepper)))
        }

        spacingSwitch.target = self
        spacingSwitch.action = #selector(spacingToggled)
        let switchLabel = NSTextField(labelWithString: "Show space around zones")
        switchLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let switchRow = NSStackView(views: [switchLabel, Self.flexibleSpace(), spacingSwitch])
        switchRow.widthAnchor.constraint(equalToConstant: 392).isActive = true
        body.addArrangedSubview(switchRow)

        spacingStepper.minValue = 0
        spacingStepper.maxValue = 100
        spacingStepper.target = self
        spacingStepper.action = #selector(spacingStepped)
        configureNumberField(spacingField, action: #selector(spacingTyped))
        let points = NSTextField(labelWithString: "pt")
        points.textColor = .secondaryLabelColor
        body.addArrangedSubview(Self.field("Space around zones",
                                           row(spacingField, spacingStepper, points),
                                           note: "Applies to every layout."))

        if draft.canEditZones {
            let editZones = NSButton(title: "Edit zones", target: self, action: #selector(editZones))
            editZones.image = NSImage(systemSymbolName: "square.split.2x2", accessibilityDescription: nil)
            editZones.imagePosition = .imageLeading
            body.addArrangedSubview(editZones)
        }

        if draft.isDeletable {
            let delete = NSButton(title: "Delete", target: self, action: #selector(deleteLayout))
            delete.hasDestructiveAction = true
            delete.contentTintColor = .systemRed
            buttonRow.addArrangedSubview(delete)
        }
        buttonRow.addArrangedSubview(Self.flexibleSpace())
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(cancel)
        buttonRow.addArrangedSubview(save)
    }

    private func configureNumberField(_ field: NSTextField, action: Selector) {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 0
        field.formatter = formatter
        field.alignment = .right
        field.target = self
        field.action = action
        field.widthAnchor.constraint(equalToConstant: 56).isActive = true
    }

    private func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 6
        return stack
    }

    private func syncControls() {
        countField.integerValue = draft.zoneCount
        countStepper.integerValue = draft.zoneCount
        spacingSwitch.state = draft.showSpaceAroundZones ? .on : .off
        spacingField.integerValue = Int(draft.spacing.rounded())
        spacingStepper.integerValue = Int(draft.spacing.rounded())
        spacingField.isEnabled = draft.showSpaceAroundZones
        spacingStepper.isEnabled = draft.showSpaceAroundZones
    }

    // MARK: Actions

    @objc private func nameChanged() { draft.name = nameField.stringValue }

    @objc private func countStepped() {
        draft.zoneCount = countStepper.integerValue
        syncControls()
    }

    @objc private func countTyped() {
        draft.zoneCount = min(max(1, countField.integerValue), TemplateKind.maximumZoneCount)
        syncControls()
    }

    @objc private func spacingToggled() {
        draft.showSpaceAroundZones = spacingSwitch.state == .on
        syncControls()
    }

    @objc private func spacingStepped() {
        draft.spacing = Double(spacingStepper.integerValue)
        syncControls()
    }

    @objc private func spacingTyped() {
        draft.spacing = Double(min(max(0, spacingField.integerValue), 100))
        syncControls()
    }

    /// Fold in whatever is in the fields, whether or not their actions fired:
    /// typing a value and clicking Save straight away never sends one.
    private func commitFields() {
        if draft.isNameEditable { draft.name = nameField.stringValue }
        if draft.hasZoneCount {
            draft.zoneCount = min(max(1, countField.integerValue), TemplateKind.maximumZoneCount)
        }
        draft.spacing = Double(min(max(0, spacingField.integerValue), 100))
    }

    @objc func save() {
        commitFields()
        close(.OK)
        onSave?(draft)
    }

    @objc private func cancel() { close(.cancel) }

    @objc private func editZones() {
        commitFields()
        close(.OK)
        onEditZones?(draft)
    }

    @objc private func deleteLayout() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(draft.layout.name)”?"
        alert.informativeText = "Displays using this layout switch to another one. This can’t be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.close(.OK)
            self.onDelete?()
        }
    }

    // MARK: Test seams

    func setDraftForTesting(_ mutate: (inout LayoutEditDraft) -> Void) {
        mutate(&draft)
        nameField.stringValue = draft.name
        syncControls()
    }
}

/// "Create new layout": a name and the choice between Grid and Canvas.
final class CreateLayoutSheetController: EditorSheetController {

    var onCreate: ((String, Bool) -> Void)?
    let nameField = NSTextField()
    private(set) var isCanvas = false {
        didSet { gridOption.isSelected = !isCanvas; canvasOption.isSelected = isCanvas }
    }
    let gridOption = LayoutTypeOptionView(title: "Grid",
                                          detail: "Split the screen into zones that fill it.",
                                          canvas: false)
    let canvasOption = LayoutTypeOptionView(title: "Canvas",
                                            detail: "Place zones freely. They can overlap.",
                                            canvas: true)

    init(suggestedName: String) {
        super.init(title: "Create new layout", width: 440)

        nameField.stringValue = suggestedName
        nameField.widthAnchor.constraint(equalToConstant: 392).isActive = true
        body.addArrangedSubview(Self.field("Name", nameField))

        gridOption.isSelected = true
        gridOption.onSelect = { [weak self] in self?.isCanvas = false }
        canvasOption.onSelect = { [weak self] in self?.isCanvas = true }
        let options = NSStackView(views: [gridOption, canvasOption])
        options.spacing = 12
        options.distribution = .fillEqually
        options.widthAnchor.constraint(equalToConstant: 392).isActive = true
        body.addArrangedSubview(Self.field("Layout type", options))

        buttonRow.addArrangedSubview(Self.flexibleSpace())
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let create = NSButton(title: "Create", target: self, action: #selector(create))
        create.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(cancel)
        buttonRow.addArrangedSubview(create)
    }

    func selectCanvasForTesting(_ canvas: Bool) { isCanvas = canvas }

    @objc func create() {
        let trimmed = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        close(.OK)
        onCreate?(trimmed.isEmpty ? "Untitled Layout" : trimmed, isCanvas)
    }

    @objc private func cancel() { close(.cancel) }
}

/// A selectable tile in the create dialog, with a small picture of the type.
final class LayoutTypeOptionView: NSView {
    let title: String
    let detail: String
    let canvas: Bool
    var isSelected = false { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?

    init(title: String, detail: String, canvas: Bool) {
        self.title = title
        self.detail = detail
        self.canvas = canvas
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 150).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: CGRect) {
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        EditorTheme.pickerBackground.setFill()
        path.fill()
        (isSelected ? EditorTheme.accent : EditorTheme.cardBorder).setStroke()
        path.lineWidth = isSelected ? 2.5 : 1
        path.stroke()

        let picture = CGRect(x: rect.minX + 14, y: rect.maxY - 14 - 62, width: rect.width - 28, height: 62)
        let sample: ZoneLayout
        if canvas {
            sample = ZoneLayout(name: "", zones: [
                Zone(index: 0, rect: CGRect(x: 0.06, y: 0.1, width: 0.5, height: 0.6)),
                Zone(index: 1, rect: CGRect(x: 0.42, y: 0.32, width: 0.5, height: 0.58)),
            ], origin: .canvas)
        } else {
            sample = LayoutTemplate.priorityGrid(3)
        }
        ZonePreviewRenderer.draw(sample, in: picture)

        let titleText = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor,
        ])
        titleText.draw(at: CGPoint(x: rect.minX + 14, y: picture.minY - 24))
        let detailRect = CGRect(x: rect.minX + 14, y: rect.minY + 8, width: rect.width - 28,
                                height: picture.minY - 28 - rect.minY - 4)
        (detail as NSString).draw(in: detailRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    override func mouseUp(with event: NSEvent) { onSelect?() }

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }
}
