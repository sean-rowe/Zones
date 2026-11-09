import AppKit

/// A display as the editor sees it.
///
/// A value rather than `NSScreen` so the picker can be built, laid out and
/// snapshotted in a test with any arrangement of displays — including more
/// than the machine running the tests has.
public struct EditorDisplay: Equatable {
    public let identity: DisplayIdentity
    /// AppKit frame, for the arrangement order of the monitor strip.
    public let frame: CGRect
    /// Where zones live: the frame minus the menu bar and the Dock.
    public let visibleFrame: CGRect
    /// Native size, for the label on the monitor thumbnail.
    public let pixelSize: CGSize

    public init(identity: DisplayIdentity, frame: CGRect, visibleFrame: CGRect, pixelSize: CGSize) {
        self.identity = identity
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.pixelSize = pixelSize
    }

    public init(screen: NSScreen) {
        self.init(identity: DisplayIdentity.forScreen(screen),
                  frame: screen.frame,
                  visibleFrame: screen.visibleFrame,
                  pixelSize: CGSize(width: screen.frame.width * screen.backingScaleFactor,
                                    height: screen.frame.height * screen.backingScaleFactor))
    }

    /// Aspect ratio of the usable area, which is the shape zones are laid on.
    public var aspectRatio: CGFloat {
        visibleFrame.height > 0 ? visibleFrame.width / visibleFrame.height : 16.0 / 9.0
    }

    /// The live screen for this display, if it is still attached.
    public var screen: NSScreen? {
        NSScreen.screens.first { DisplayIdentity.forScreen($0) == identity }
    }

    public static func current() -> [EditorDisplay] {
        NSScreen.screens.map(EditorDisplay.init(screen:))
    }
}

/// The window the editor opens on: monitors, template cards, custom cards and
/// "Create new layout" — the FancyZones editor's main window.
///
/// Clicking a card applies it to the selected display at once, as in
/// FancyZones; there is no separate Apply step to forget.
final class LayoutPickerWindowController: NSWindowController, NSWindowDelegate {

    private let store: LayoutStore
    private let settings: Settings

    /// Displays in strip order, left to right.
    private(set) var displays: [EditorDisplay]
    private(set) var selectedDisplay: EditorDisplay?

    /// Open the zone editor for a layout on a display.
    var onEditZones: ((ZoneLayout, EditorDisplay) -> Void)?
    /// Open the zone editor on a new, unsaved layout.
    var onCreate: ((ZoneLayout, EditorDisplay) -> Void)?

    private let pickerBody = PickerDocumentView()
    private let scrollView = NSScrollView()
    private(set) var model: LayoutPickerModel
    private var activeSheet: NSWindowController?

    init(store: LayoutStore, settings: Settings, displays: [EditorDisplay],
         selected: DisplayIdentity?) {
        self.store = store
        self.settings = settings
        let order = MonitorStripLayout.order(of: displays.map(\.frame))
        self.displays = order.map { displays[$0] }
        self.selectedDisplay = self.displays.first { $0.identity == selected } ?? self.displays.first
        self.model = LayoutPickerModel(layouts: store.layouts, appliedLayoutID: nil)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Zones Layout Editor"
        // Two cards across is the narrowest the sections still read as a grid.
        window.minSize = NSSize(width: 520, height: 420)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
        window.center()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: State

    func update(displays newDisplays: [EditorDisplay], selecting identity: DisplayIdentity?) {
        let order = MonitorStripLayout.order(of: newDisplays.map(\.frame))
        displays = order.map { newDisplays[$0] }
        let wanted = identity ?? selectedDisplay?.identity
        selectedDisplay = displays.first { $0.identity == wanted } ?? displays.first
        reload()
    }

    /// Rebuild every card from the store. Cheap — a dozen views — and simpler
    /// to keep right than patching individual cards after each change.
    func reload() {
        let applied = selectedDisplay.flatMap { store.assignedLayout(for: $0.identity) }
        model = LayoutPickerModel(layouts: store.layouts, appliedLayoutID: applied?.id)
        let aspect = selectedDisplay?.aspectRatio ?? 16.0 / 9.0

        let templateCards = model.templates.map { entry -> LayoutCardView in
            let card = LayoutCardView(layout: entry.layout, title: entry.kind.title,
                                      isApplied: model.isApplied(entry.layout), aspectRatio: aspect)
            card.onSelect = { [weak self] in self?.apply(entry.layout) }
            card.onEdit = { [weak self] in self?.edit(entry.layout, asTemplate: true) }
            return card
        }
        let customCards = model.custom.map { layout -> LayoutCardView in
            let card = LayoutCardView(layout: layout, title: layout.name,
                                      isApplied: model.isApplied(layout), aspectRatio: aspect)
            card.onSelect = { [weak self] in self?.apply(layout) }
            card.onEdit = { [weak self] in self?.edit(layout, asTemplate: false) }
            return card
        }
        let monitors: [MonitorThumbnailView] = displays.count > 1 ? displays.enumerated().map { index, display in
            let view = MonitorThumbnailView(number: index + 1, pixelSize: display.pixelSize,
                                            isSelected: display.identity == selectedDisplay?.identity)
            view.onSelect = { [weak self] in self?.selectDisplay(display.identity) }
            return view
        } : []
        pickerBody.configure(monitors: monitors,
                           monitorSizes: displays.map(\.frame.size),
                           templateCards: templateCards,
                           customCards: customCards)
        pickerBody.needsLayout = true
    }

    func selectDisplay(_ identity: DisplayIdentity) {
        selectedDisplay = displays.first { $0.identity == identity } ?? selectedDisplay
        reload()
    }

    private func apply(_ layout: ZoneLayout) {
        guard let display = selectedDisplay else { return }
        LayoutCatalog.apply(layout, to: display.identity, in: store)
        reload()
    }

    // MARK: Dialogs

    func edit(_ layout: ZoneLayout, asTemplate: Bool) {
        guard let window else { return }
        let sheet = EditLayoutSheetController(layout: layout, settings: settings.current,
                                              asTemplate: asTemplate)
        sheet.onSave = { [weak self] draft in
            guard let self else { return }
            self.settings.current = draft.apply(to: self.settings.current)
            // Saving from the dialog edits the layout in place; it does not
            // apply it, matching FancyZones, where Save in this dialog leaves
            // the selected display alone.
            if self.store.layout(id: layout.id) != nil || draft.editedLayout != layout {
                self.store.save(draft.editedLayout)
            }
            self.reload()
        }
        sheet.onEditZones = { [weak self] draft in
            guard let self, let display = self.selectedDisplay else { return }
            self.settings.current = draft.apply(to: self.settings.current)
            self.onEditZones?(draft.editedLayout, display)
        }
        sheet.onDelete = { [weak self] in
            guard let self else { return }
            LayoutCatalog.delete(layout, from: self.store,
                                 displays: self.allKnownDisplays())
            self.reload()
        }
        present(sheet, on: window)
    }

    func createNew() {
        guard let window else { return }
        let sheet = CreateLayoutSheetController(
            suggestedName: LayoutCatalog.nextCustomName(existing: store.layouts))
        sheet.onCreate = { [weak self] name, canvas in
            guard let self, let display = self.selectedDisplay else { return }
            self.onCreate?(LayoutCatalog.newLayout(name: name, canvas: canvas), display)
        }
        present(sheet, on: window)
    }

    private func present(_ sheet: NSWindowController, on window: NSWindow) {
        guard let sheetWindow = sheet.window else { return }
        activeSheet = sheet
        window.beginSheet(sheetWindow) { [weak self] _ in self?.activeSheet = nil }
    }

    /// Displays to consider when a deleted layout needs replacing: those on
    /// screen now, plus the picker's own list in case it is out of date.
    private func allKnownDisplays() -> [DisplayIdentity] {
        var identities = DisplayObserver.currentDisplays().map(\.identity)
        for display in displays where !identities.contains(display.identity) {
            identities.append(display.identity)
        }
        return identities
    }

    @objc private func createClicked() { createNew() }

    // MARK: Views

    private func makeContentView() -> NSView {
        let root = BackgroundView(color: EditorTheme.pickerBackground)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        pickerBody.autoresizingMask = [.width]
        pickerBody.frame = CGRect(x: 0, y: 0, width: 920, height: 600)
        scrollView.documentView = pickerBody
        root.addSubview(scrollView)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(separator)

        let create = AccentButton(title: "Create new layout", symbolName: "plus",
                                  target: self, action: #selector(createClicked))
        create.keyEquivalent = "n"
        create.keyEquivalentModifierMask = .command
        create.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(create)
        createButton = create

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -64),
            create.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            create.centerYAnchor.constraint(equalTo: root.bottomAnchor, constant: -32),
        ])
        return root
    }

    private(set) var createButton: AccentButton?

    // MARK: Test seams

    var templateCardsForTesting: [LayoutCardView] { pickerBody.templateCards }
    var customCardsForTesting: [LayoutCardView] { pickerBody.customCards }
    var monitorViewsForTesting: [MonitorThumbnailView] { pickerBody.monitors }
    var activeSheetForTesting: NSWindowController? { activeSheet }
}

/// A view that fills itself with a colour, resolved at draw time so it
/// follows the appearance.
final class BackgroundView: NSView {
    var color: NSColor { didSet { needsDisplay = true } }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: CGRect) {
        color.setFill()
        dirtyRect.fill()
    }
}

/// The scrolling body of the picker: monitor strip, then the two card sections.
///
/// Laid out by hand rather than with constraints, because the card grid
/// reflows with the width — a job `CardGridLayout` already does exactly.
final class PickerDocumentView: NSView {

    private(set) var monitors: [MonitorThumbnailView] = []
    private(set) var templateCards: [LayoutCardView] = []
    private(set) var customCards: [LayoutCardView] = []
    private var monitorSizes: [CGSize] = []

    private let templatesHeading = PickerDocumentView.heading("Templates")
    private let customHeading = PickerDocumentView.heading("Custom")
    private let emptyCustom = NSTextField(wrappingLabelWithString:
        "Custom layouts you create appear here. Use “Create new layout” to design your own.")
    private let monitorBand = BackgroundView(color: EditorTheme.dynamic(
        light: NSColor(white: 0, alpha: 0.035), dark: NSColor(white: 1, alpha: 0.03)))

    static let margin: CGFloat = 28
    static let monitorStripHeight: CGFloat = 92

    private let grid = CardGridLayout(cardSize: EditorTheme.cardSize, spacing: EditorTheme.cardSpacing)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        emptyCustom.textColor = .secondaryLabelColor
        emptyCustom.font = .systemFont(ofSize: 13)
        addSubview(monitorBand)
        addSubview(templatesHeading)
        addSubview(customHeading)
        addSubview(emptyCustom)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    func configure(monitors: [MonitorThumbnailView], monitorSizes: [CGSize],
                   templateCards: [LayoutCardView], customCards: [LayoutCardView]) {
        (self.monitors + self.templateCards + self.customCards).forEach { $0.removeFromSuperview() }
        self.monitors = monitors
        self.monitorSizes = monitorSizes
        self.templateCards = templateCards
        self.customCards = customCards
        (monitors + templateCards + customCards).forEach(addSubview)
        layoutContent()
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContent()
    }

    private var isLayingOut = false

    private func layoutContent() {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }

        // Track the clip view's width: the document only ever scrolls
        // vertically, and a stale width lays cards out past the right edge.
        if let visibleWidth = enclosingScrollView?.contentSize.width,
           visibleWidth > 0, abs(frame.width - visibleWidth) > 0.5 {
            super.setFrameSize(NSSize(width: visibleWidth, height: frame.height))
        }
        let margin = Self.margin
        let width = bounds.width - margin * 2
        var y: CGFloat = 0

        monitorBand.isHidden = monitors.isEmpty
        if monitors.isEmpty {
            y = margin - 4
        } else {
            let bandHeight = Self.monitorStripHeight + 32
            monitorBand.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bandHeight)
            let frames = MonitorStripLayout.frames(
                for: monitorSizes,
                in: CGSize(width: width, height: Self.monitorStripHeight), spacing: 12)
            for (view, frame) in zip(monitors, frames) {
                view.frame = frame.offsetBy(dx: margin, dy: 16)
            }
            y = bandHeight + 20
        }

        templatesHeading.sizeToFit()
        templatesHeading.frame.origin = CGPoint(x: margin, y: y)
        y += templatesHeading.frame.height + 12
        for (card, frame) in zip(templateCards, grid.frames(count: templateCards.count, width: width,
                                                            origin: CGPoint(x: margin, y: y))) {
            card.frame = frame
        }
        y += grid.height(count: templateCards.count, width: width) + 28

        customHeading.sizeToFit()
        customHeading.frame.origin = CGPoint(x: margin, y: y)
        y += customHeading.frame.height + 12
        emptyCustom.isHidden = !customCards.isEmpty
        if customCards.isEmpty {
            emptyCustom.frame = CGRect(x: margin, y: y, width: max(100, width), height: 20)
            y += 20
        } else {
            for (card, frame) in zip(customCards, grid.frames(count: customCards.count, width: width,
                                                              origin: CGPoint(x: margin, y: y))) {
                card.frame = frame
            }
            y += grid.height(count: customCards.count, width: width)
        }
        y += margin

        // Grow to fit the content, but never shrink below the visible area,
        // or the background stops short of the window's bottom edge.
        let visibleHeight = enclosingScrollView?.contentSize.height ?? 0
        let height = max(y, visibleHeight)
        if abs(frame.height - height) > 0.5 {
            super.setFrameSize(NSSize(width: frame.width, height: height))
        }
    }
}
