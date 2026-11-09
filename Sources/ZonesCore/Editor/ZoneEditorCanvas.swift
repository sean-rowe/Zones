import AppKit

/// The editor's drawing surface and toolbar. Everything here follows
/// PineOS's `zone_editor.c`: the same dim, colours, labels, help line and
/// mouse rules.
final class ZoneEditorCanvas: NSView {

    /// Border hit radius, in points.
    static let grabRadius: CGFloat = 10
    /// Gap range and step, as PineOS's spin button.
    static let gapRange: ClosedRange<Double> = 0...64
    static let gapStep: Double = 2

    static let helpText = "Click to split vertically  |  Shift+click for horizontal  |  "
        + "Drag borders to resize  |  Right-click to merge  |  Enter to apply  |  Escape to cancel"

    private(set) var tree: SplitTree { didSet { needsDisplay = true } }
    private(set) var gap: Double { didSet { gapField.stringValue = "\(Int(gap))"; needsDisplay = true } }
    let outerPadding: Double

    var onApply: (() -> Void)?
    var onCancel: (() -> Void)?

    private var draggedDivider: SplitTree.Hit?
    private(set) var toolbar: NSView!
    private let gapField = NSTextField()

    init(frame: CGRect, tree: SplitTree, gap: Double, outerPadding: Double) {
        self.tree = tree
        self.gap = gap
        self.outerPadding = outerPadding
        super.init(frame: frame)
        toolbar = makeToolbar()
        addSubview(toolbar)
        gapField.stringValue = "\(Int(gap))"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let size = toolbar.fittingSize
        toolbar.frame = CGRect(x: (bounds.width - size.width) / 2,
                               y: bounds.height - 12 - size.height,
                               width: size.width, height: size.height)
    }

    // MARK: Geometry

    /// View point → normalized, top-left origin.
    func normalized(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / max(bounds.width, 1), y: 1 - p.y / max(bounds.height, 1))
    }

    /// The rects windows will actually snap to, in view coordinates.
    func resolvedZoneRects() -> [CGRect] {
        let zones = tree.zoneRects().enumerated().map { Zone(index: $0.offset, rect: $0.element) }
        let layout = ZoneLayout(name: "Editing", zones: zones)
        return ZoneResolver.resolveAll(layout, in: bounds,
                                       spacing: ZoneSpacing(outerPadding: outerPadding, gap: gap))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        bounds.fill(using: .copy)
        NSColor(white: 0, alpha: 0.45).set()
        bounds.fill(using: .sourceOver)

        let rects = resolvedZoneRects()
        let total = rects.count
        for (i, rect) in rects.enumerated() {
            let hue = total > 1 ? Double(i) / Double(total - 1) : 0.5
            NSColor(srgbRed: 0.15 + 0.5 * hue, green: 0.35 + 0.3 * (1 - hue),
                    blue: 0.75 - 0.3 * hue, alpha: 0.35).setFill()
            rect.fill(using: .sourceOver)
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 2
            NSColor(srgbRed: 0.3 + 0.6 * hue, green: 0.5 + 0.3 * (1 - hue),
                    blue: 0.9 - 0.4 * hue, alpha: 0.85).setStroke()
            outline.stroke()

            let number = NSAttributedString(string: "\(i + 1)", attributes: [
                .font: NSFont.systemFont(ofSize: 48),
                .foregroundColor: NSColor(white: 1, alpha: 0.7),
            ])
            let ns = number.size()
            number.draw(at: CGPoint(x: rect.midX - ns.width / 2, y: rect.midY))

            let dims = NSAttributedString(
                string: "\(Int(rect.width.rounded()))pt × \(Int(rect.height.rounded()))pt",
                attributes: [.font: NSFont.systemFont(ofSize: 16),
                             .foregroundColor: NSColor(white: 1, alpha: 0.5)])
            let ds = dims.size()
            dims.draw(at: CGPoint(x: rect.midX - ds.width / 2, y: rect.midY - 12 - ds.height))
        }

        drawDividers(tree, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let help = NSAttributedString(string: Self.helpText, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor(white: 1, alpha: 0.5),
        ])
        let hs = help.size()
        help.draw(at: CGPoint(x: (bounds.width - hs.width) / 2, y: 12))
    }

    /// White lines on every divider, 4pt short of each end.
    private func drawDividers(_ node: SplitTree, in r: CGRect) {
        guard case let .split(vertical, ratio, first, second) = node else { return }
        let inset: CGFloat = 4
        let w = bounds.width, h = bounds.height
        let path = NSBezierPath()
        path.lineWidth = 3
        if vertical {
            let x = (r.minX + r.width * ratio) * w
            path.move(to: CGPoint(x: x, y: h - r.minY * h - inset))
            path.line(to: CGPoint(x: x, y: h - r.maxY * h + inset))
        } else {
            let y = h - (r.minY + r.height * ratio) * h
            path.move(to: CGPoint(x: r.minX * w + inset, y: y))
            path.line(to: CGPoint(x: r.maxX * w - inset, y: y))
        }
        NSColor(white: 1, alpha: 0.6).setStroke()
        path.stroke()
        let (a, b) = SplitTree.divide(r, vertical: vertical, ratio: ratio)
        drawDividers(first, in: a)
        drawDividers(second, in: b)
    }

    // MARK: Mouse

    private var grab: CGSize {
        CGSize(width: Self.grabRadius / max(bounds.width, 1),
               height: Self.grabRadius / max(bounds.height, 1))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = normalized(convert(event.locationInWindow, from: nil))
        if event.modifierFlags.contains(.control) {
            merge(at: p)
        } else {
            press(at: p, shift: event.modifierFlags.contains(.shift))
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        merge(at: normalized(convert(event.locationInWindow, from: nil)))
    }

    override func mouseDragged(with event: NSEvent) {
        drag(to: normalized(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        draggedDivider = nil
    }

    /// Grab a divider, or split the zone under the point and grab the new
    /// divider so it can be placed in the same motion.
    func press(at p: CGPoint, shift: Bool) {
        if let hit = tree.divider(at: p, grab: grab) {
            draggedDivider = hit
            return
        }
        if let (newTree, hit) = tree.splitting(at: p, vertical: !shift) {
            tree = newTree
            draggedDivider = hit
        }
    }

    func drag(to p: CGPoint) {
        guard let draggedDivider else { return }
        tree = tree.dragging(draggedDivider, to: p)
    }

    func merge(at p: CGPoint) {
        draggedDivider = nil
        if let merged = tree.merging(at: p) { tree = merged }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }

    private func updateCursor(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if toolbar.frame.contains(local) { NSCursor.arrow.set(); return }
        if let hit = tree.divider(at: normalized(local), grab: grab),
           case let .split(vertical, _, _, _)? = tree.node(at: hit.path) {
            (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if !handleKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "") {
            super.keyDown(with: event)
        }
    }

    /// Escape cancels, Return applies, 1–4 load a preset.
    @discardableResult
    func handleKey(keyCode: UInt16, characters: String) -> Bool {
        switch keyCode {
        case 53: onCancel?(); return true
        case 36, 76: onApply?(); return true
        default: break
        }
        if let digit = Int(characters), let preset = SplitTree.Preset(rawValue: digit - 1) {
            load(preset)
            return true
        }
        return false
    }

    func load(_ preset: SplitTree.Preset) {
        draggedDivider = nil
        tree = SplitTree(preset: preset)
    }

    func setGap(_ value: Double) {
        gap = min(max(value, Self.gapRange.lowerBound), Self.gapRange.upperBound)
    }

    // MARK: Toolbar

    private func makeToolbar() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

        for preset in SplitTree.Preset.allCases {
            let button = ToolbarButton(title: "\(preset.rawValue + 1): \(preset.title)", style: .preset) {
                [weak self] in self?.load(preset)
            }
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(spacer())
        stack.addArrangedSubview(label("Gap:"))

        gapField.font = .systemFont(ofSize: 13)
        gapField.textColor = .white
        gapField.drawsBackground = true
        gapField.backgroundColor = NSColor(white: 50.0 / 255, alpha: 0.9)
        gapField.isBordered = false
        gapField.focusRingType = .none
        gapField.alignment = .left
        gapField.wantsLayer = true
        gapField.layer?.cornerRadius = 4
        gapField.layer?.borderWidth = 1
        gapField.layer?.borderColor = NSColor(white: 1, alpha: 0.2).cgColor
        gapField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        gapField.target = self
        gapField.action = #selector(gapFieldCommitted)
        let gapControl = NSStackView(views: [
            gapField,
            ToolbarButton(title: "−", style: .preset) { [weak self] in
                guard let self else { return }
                self.setGap(self.gap - Self.gapStep)
            },
            ToolbarButton(title: "+", style: .preset) { [weak self] in
                guard let self else { return }
                self.setGap(self.gap + Self.gapStep)
            },
        ])
        gapControl.spacing = 2
        stack.addArrangedSubview(gapControl)
        stack.addArrangedSubview(label("pt"))
        stack.addArrangedSubview(spacer())
        stack.addArrangedSubview(ToolbarButton(title: "Cancel", style: .cancel) { [weak self] in self?.onCancel?() })
        stack.addArrangedSubview(ToolbarButton(title: "Apply", style: .action) { [weak self] in self?.onApply?() })

        let bar = ToolbarBackground()
        bar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
        return bar
    }

    @objc private func gapFieldCommitted() {
        setGap(Double(gapField.stringValue) ?? gap)
        window?.makeFirstResponder(self)
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = NSColor(white: 1, alpha: 0.7)
        label.font = .systemFont(ofSize: 13)
        return label
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.widthAnchor.constraint(equalToConstant: 8).isActive = true
        return view
    }
}

/// The toolbar's rounded dark panel. Swallows clicks so they never reach
/// the canvas underneath and split a zone.
private final class ToolbarBackground: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 30.0 / 255, alpha: 0.85).cgColor
        layer?.cornerRadius = 8
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

/// PineOS's three button styles: grey preset, grey cancel, blue action.
final class ToolbarButton: NSButton {
    enum Style { case preset, cancel, action }

    private let style: Style
    private let handler: () -> Void
    private var hovering = false { didSet { updateColors() } }

    init(title: String, style: Style, handler: @escaping () -> Void) {
        self.style = style
        self.handler = handler
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 4
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
        ])
        target = self
        action = #selector(fire)
        updateColors()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        let text = attributedTitle.size()
        let padding: CGFloat = style == .preset ? 12 : 16
        return NSSize(width: ceil(text.width) + padding * 2, height: 28)
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    @objc private func fire() { handler() }

    private func updateColors() {
        switch style {
        case .action:
            layer?.backgroundColor = (hovering
                ? NSColor(srgbRed: 60 / 255, green: 140 / 255, blue: 240 / 255, alpha: 0.9)
                : NSColor(srgbRed: 40 / 255, green: 120 / 255, blue: 220 / 255, alpha: 0.9)).cgColor
            layer?.borderWidth = 0
        case .preset, .cancel:
            let grey: CGFloat = (hovering && style == .preset) ? 80 : 60
            layer?.backgroundColor = NSColor(white: grey / 255, alpha: 0.9).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(white: 1, alpha: 0.2).cgColor
        }
    }
}
