import AppKit

/// A borderless window that can still take key status.
///
/// Borderless windows refuse key by default, which would leave the editor
/// deaf to Esc, Return and Shift — the keyboard half of the interaction.
final class ZoneEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The full-screen zone editor: the chosen display's work area, dimmed, with
/// the zones drawn over it and a floating toolbar at the top.
///
/// Covers the visible frame rather than the whole screen, because that is the
/// area zones resolve against — designing under the menu bar or the Dock would
/// teach a layout the display cannot show.
final class ZoneEditorWindowController: NSWindowController {

    let display: EditorDisplay
    let isCanvas: Bool
    private(set) var layout: ZoneLayout

    var onSave: ((ZoneLayout) -> Void)?
    var onCancel: (() -> Void)?

    private(set) var gridView: GridZoneEditorView?
    private(set) var canvasView: CanvasZoneEditorView?
    let toolbar: EditorToolbarView
    let mergeButton = AccentButton(title: "Merge zones", symbolName: "rectangle.compress.vertical",
                                   target: nil, action: nil)
    private var finished = false

    init(layout: ZoneLayout, display: EditorDisplay, settings: AppSettings) {
        self.layout = layout
        self.display = display
        self.isCanvas = layout.origin.isCanvas
        toolbar = EditorToolbarView(name: layout.name, canvas: layout.origin.isCanvas)

        let window = ZoneEditorWindow(contentRect: display.visibleFrame, styleMask: [.borderless],
                                      backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Above ordinary windows, so the layout being designed is not hidden
        // behind the very windows it is for.
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        super.init(window: window)

        let spacing = EditorTheme.editorSpacing(for: settings)
        let editor: ZoneEditorCanvasBase
        if isCanvas {
            let canvas = CanvasZoneEditorView(layout: layout, spacing: spacing)
            canvasView = canvas
            editor = canvas
        } else {
            let grid = GridZoneEditorView(layout: layout, spacing: spacing)
            grid.onSelectionChanged = { [weak self] ids, rect in
                self?.selectionChanged(ids, rect: rect)
            }
            gridView = grid
            editor = grid
        }
        editor.onLayoutChanged = { [weak self] updated in self?.layout = updated }

        let container = NSView(frame: CGRect(origin: .zero, size: display.visibleFrame.size))
        editor.frame = container.bounds
        editor.autoresizingMask = [.width, .height]
        container.addSubview(editor)

        toolbar.saveButton.target = self
        toolbar.saveButton.action = #selector(save)
        toolbar.cancelButton.target = self
        toolbar.cancelButton.action = #selector(cancel)
        toolbar.addZoneButton?.target = self
        toolbar.addZoneButton?.action = #selector(addZone)
        container.addSubview(toolbar)

        mergeButton.target = self
        mergeButton.action = #selector(merge)
        mergeButton.isHidden = true
        mergeButton.setFrameSize(mergeButton.intrinsicContentSize)
        container.addSubview(mergeButton)

        window.contentView = container
        layoutToolbar()
        window.initialFirstResponder = editor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.setFrame(display.visibleFrame, display: true)
        layoutToolbar()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(gridView ?? canvasView)
    }

    /// Centred at the top, clear of the outer edge.
    func layoutToolbar() {
        guard let content = window?.contentView else { return }
        let size = toolbar.fittingSize
        toolbar.frame = CGRect(x: (content.bounds.width - size.width) / 2,
                               y: content.bounds.maxY - size.height - 24,
                               width: size.width, height: size.height)
    }

    private func selectionChanged(_ ids: Set<UUID>, rect: CGRect?) {
        guard let rect, ids.count >= 2 else {
            mergeButton.isHidden = true
            return
        }
        // Beside the selection, as in FancyZones: at its centre, where the
        // pointer that just made it already is.
        let size = mergeButton.intrinsicContentSize
        mergeButton.frame = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                   width: size.width, height: size.height)
        mergeButton.isHidden = false
    }

    // MARK: Actions

    @objc func save() {
        guard !finished else { return }
        finished = true
        ZonesLog.info("Zones", "zone editor saved \(layout.name) with \(layout.zones.count) zone(s)")
        window?.orderOut(nil)
        onSave?(layout)
    }

    @objc func cancel() {
        guard !finished else { return }
        finished = true
        window?.orderOut(nil)
        onCancel?()
    }

    @objc private func merge() {
        gridView?.mergeSelection()
    }

    @objc private func addZone() {
        canvasView?.addZone()
    }

    /// Esc, from anywhere in the window.
    override func cancelOperation(_ sender: Any?) { cancel() }
}

/// The editor's floating toolbar: layout name, a keyboard hint, and the
/// Save & apply / Cancel pair.
final class EditorToolbarView: NSView {

    let saveButton = NSButton(title: "Save & apply", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private(set) var addZoneButton: NSButton?
    let nameLabel: NSTextField
    let hintLabel: NSTextField

    init(name: String, canvas: Bool) {
        nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        hintLabel = NSTextField(labelWithString: canvas
            ? "Drag to move · Drag edges to resize · Esc to cancel"
            : "Click to split · Hold ⇧ for horizontal · Drag across zones to merge · Esc to cancel")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 12
        shadow = NSShadow()
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .large
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large

        let titleStack = NSStackView(views: [nameLabel, hintLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        var views: [NSView] = [titleStack]
        if canvas {
            let add = NSButton(title: "Add zone", target: nil, action: nil)
            add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            add.imagePosition = .imageLeading
            add.bezelStyle = .rounded
            add.controlSize = .large
            addZoneButton = add
            views.append(add)
        }
        views += [cancelButton, saveButton]

        let stack = NSStackView(views: views)
        stack.spacing = 10
        stack.setCustomSpacing(24, after: titleStack)
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: CGRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        EditorTheme.editorToolbarBackground.setFill()
        path.fill()
        EditorTheme.cardBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
