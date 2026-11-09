import AppKit

/// One layout in the picker: a mini preview, its name, and an edit button
/// that appears on hover — the FancyZones layout card.
final class LayoutCardView: NSView {

    let zoneLayout: ZoneLayout
    let title: String
    var isApplied: Bool { didSet { needsDisplay = true; updateAccessibility() } }
    /// Aspect ratio of the display the card previews for.
    var aspectRatio: CGFloat { didSet { needsDisplay = true } }

    var onSelect: (() -> Void)?
    var onEdit: (() -> Void)?

    private(set) var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
            editButton.isHidden = !isHovered
        }
    }

    let editButton: NSButton
    private var trackingArea: NSTrackingArea?

    static let previewInsets = NSEdgeInsets(top: 14, left: 14, bottom: 44, right: 14)

    init(layout: ZoneLayout, title: String, isApplied: Bool, aspectRatio: CGFloat) {
        self.zoneLayout = layout
        self.title = title
        self.isApplied = isApplied
        self.aspectRatio = aspectRatio
        editButton = NSButton()
        super.init(frame: CGRect(origin: .zero, size: EditorTheme.cardSize))

        editButton.bezelStyle = .regularSquare
        editButton.isBordered = false
        editButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Edit")
        editButton.imagePosition = .imageOnly
        editButton.contentTintColor = .labelColor
        editButton.wantsLayer = true
        editButton.layer?.cornerRadius = 13
        editButton.layer?.backgroundColor = EditorTheme.cardBackground.cgColor
        editButton.toolTip = "Edit layout"
        editButton.setAccessibilityLabel("Edit \(title)")
        editButton.target = self
        editButton.action = #selector(editClicked)
        editButton.isHidden = true
        addSubview(editButton)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func updateAccessibility() {
        setAccessibilityLabel(isApplied ? "\(title), applied" : title)
    }

    override func layout() {
        super.layout()
        editButton.frame = CGRect(x: bounds.maxX - 34, y: bounds.maxY - 34, width: 26, height: 26)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Layer colours are CGColors and do not follow the appearance on their own.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            editButton.layer?.backgroundColor = EditorTheme.cardBackground.cgColor
        }
    }

    /// Forces the hover state for snapshots; the real one comes from tracking.
    func setHoveredForTesting(_ hovered: Bool) { isHovered = hovered }

    // MARK: Geometry

    /// Where the mini preview is drawn, letterboxed to the display's shape.
    var previewRect: CGRect {
        let insets = Self.previewInsets
        let available = CGRect(x: insets.left, y: insets.bottom,
                               width: bounds.width - insets.left - insets.right,
                               height: bounds.height - insets.top - insets.bottom)
        return ZonePreviewRenderer.fit(aspectRatio: aspectRatio, in: available)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: CGRect) {
        let card = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: card, xRadius: EditorTheme.cardCornerRadius,
                                yRadius: EditorTheme.cardCornerRadius)
        (isHovered ? EditorTheme.cardHoverBackground : EditorTheme.cardBackground).setFill()
        path.fill()

        if isApplied {
            EditorTheme.accent.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
                                    xRadius: EditorTheme.cardCornerRadius,
                                    yRadius: EditorTheme.cardCornerRadius)
            ring.lineWidth = 2.5
            ring.stroke()
        } else {
            EditorTheme.cardBorder.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let preview = previewRect
        if zoneLayout.origin == .blank {
            drawBlankPreview(in: preview)
        } else {
            ZonePreviewRenderer.draw(zoneLayout, in: preview)
        }

        drawTitle()
        if isApplied { drawCheckmark() }
    }

    private func drawBlankPreview(in rect: CGRect) {
        EditorTheme.previewBackground.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let dash = NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 3, yRadius: 3)
        dash.setLineDash([4, 3], count: 2, phase: 0)
        dash.lineWidth = 1
        NSColor.tertiaryLabelColor.setStroke()
        dash.stroke()
    }

    private func drawTitle() {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let leading: CGFloat = isApplied ? 36 : 14
        let rect = CGRect(x: leading, y: 13, width: bounds.width - leading - 14, height: 18)
        (title as NSString).draw(in: rect, withAttributes: attributes)
    }

    /// A filled accent disc with a tick, beside the name of the applied layout.
    private func drawCheckmark() {
        let disc = CGRect(x: 14, y: 13, width: 17, height: 17)
        EditorTheme.accent.setFill()
        NSBezierPath(ovalIn: disc).fill()
        let tick = NSBezierPath()
        tick.move(to: CGPoint(x: disc.minX + 4.5, y: disc.midY))
        tick.line(to: CGPoint(x: disc.minX + 7.5, y: disc.minY + 5))
        tick.line(to: CGPoint(x: disc.maxX - 4, y: disc.maxY - 5))
        tick.lineWidth = 1.8
        tick.lineCapStyle = .round
        tick.lineJoinStyle = .round
        NSColor.white.setStroke()
        tick.stroke()
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onSelect?()
    }

    // A card is a button to the accessibility tree; let VoiceOver press it.
    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }

    @objc private func editClicked() { onEdit?() }
}

/// A display in the picker's monitor strip: numbered and proportionally sized.
final class MonitorThumbnailView: NSView {

    let number: Int
    let pixelSize: CGSize
    var isSelected: Bool { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?

    private var isHovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(number: Int, pixelSize: CGSize, isSelected: Bool) {
        self.number = number
        self.pixelSize = pixelSize
        self.isSelected = isSelected
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Display \(number)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: CGRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (isHovered ? EditorTheme.cardHoverBackground : EditorTheme.cardBackground).setFill()
        path.fill()
        if isSelected {
            EditorTheme.accent.withAlphaComponent(0.12).setFill()
            path.fill()
            EditorTheme.accent.setStroke()
            path.lineWidth = 2.5
        } else {
            EditorTheme.cardBorder.setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        let numberText = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.systemFont(ofSize: min(26, rect.height * 0.42), weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        let size = numberText.size()
        let sizeText = NSAttributedString(
            string: "\(Int(pixelSize.width)) × \(Int(pixelSize.height))",
            attributes: [.font: NSFont.systemFont(ofSize: 10),
                         .foregroundColor: NSColor.secondaryLabelColor])
        let sub = sizeText.size()
        let showSize = rect.height > 54 && sub.width < rect.width - 8
        let total = size.height + (showSize ? sub.height : 0)
        let top = rect.midY + total / 2
        numberText.draw(at: CGPoint(x: rect.midX - size.width / 2, y: top - size.height))
        if showSize {
            sizeText.draw(at: CGPoint(x: rect.midX - sub.width / 2, y: top - size.height - sub.height))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseUp(with event: NSEvent) { onSelect?() }

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }
}
