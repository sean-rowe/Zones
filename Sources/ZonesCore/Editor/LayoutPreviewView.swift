import AppKit

/// Draws a layout at the target display's proportions and handles splitter drags.
///
/// All geometry and mutation lives in `LayoutEditing`; this view converts points
/// to normalized coordinates, asks the model for the result, and draws it. Colors
/// come from `NSColor`'s semantic values rather than literals, so light mode,
/// dark mode, increased contrast and the user's accent colour all follow the
/// system without a second code path.
public final class LayoutPreviewView: NSView {

    /// Called whenever a drag changes the layout.
    public var onLayoutChanged: ((ZoneLayout) -> Void)?

    public var layout: ZoneLayout {
        didSet {
            splitters = LayoutEditing.splitters(in: layout)
            needsDisplay = true
        }
    }

    /// Aspect ratio the preview is letterboxed to — the target display's.
    ///
    /// Without this the preview takes the window's shape and teaches the user a
    /// layout they did not build.
    public var targetAspectRatio: CGFloat {
        didSet { needsDisplay = true }
    }

    /// Zone the user has selected, for split and merge.
    public var selectedZoneIDs: Set<UUID> = [] {
        didSet { needsDisplay = true }
    }

    private var splitters: [Splitter] = []
    private var activeSplitter: Splitter?
    private var hoveredSplitter: Splitter?

    /// Half-width of a splitter's grab area, in points.
    ///
    /// Wider than the line is drawn, because a 1pt hit target is unusable. This
    /// is the same reason AppKit gives `NSSplitView` dividers a larger
    /// `dividerThickness` for hit-testing than they appear to occupy.
    private static let splitterGrabRadius: CGFloat = 4

    public init(layout: ZoneLayout, targetAspectRatio: CGFloat = 16.0 / 9.0) {
        self.layout = layout
        self.targetAspectRatio = targetAspectRatio
        super.init(frame: .zero)
        splitters = LayoutEditing.splitters(in: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override var isFlipped: Bool { false }

    // MARK: - Geometry

    /// The letterboxed rect the layout is drawn into, centred in the view.
    var previewRect: CGRect {
        let available = bounds.insetBy(dx: 16, dy: 16)
        guard available.width > 0, available.height > 0 else { return .zero }

        var size = CGSize(width: available.width, height: available.width / targetAspectRatio)
        if size.height > available.height {
            size = CGSize(width: available.height * targetAspectRatio, height: available.height)
        }
        return CGRect(x: available.midX - size.width / 2,
                      y: available.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Normalized point (top-left origin) for a point in view coordinates.
    ///
    /// The Y flip is the same one `ZoneResolver` applies: the model is top-left
    /// origin, the view is AppKit's bottom-left.
    func normalizedPoint(for point: CGPoint) -> CGPoint? {
        let rect = previewRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width,
                       y: (rect.maxY - point.y) / rect.height)
    }

    // MARK: - Hit testing

    func splitter(at point: CGPoint) -> Splitter? {
        let rect = previewRect
        guard let normalized = normalizedPoint(for: point) else { return nil }

        for splitter in splitters {
            switch splitter.axis {
            case .vertical:
                let x = rect.minX + CGFloat(splitter.position) * rect.width
                guard abs(point.x - x) <= Self.splitterGrabRadius else { continue }
                guard splitter.span.contains(Double(normalized.y)) else { continue }
                return splitter
            case .horizontal:
                let y = rect.maxY - CGFloat(splitter.position) * rect.height
                guard abs(point.y - y) <= Self.splitterGrabRadius else { continue }
                guard splitter.span.contains(Double(normalized.x)) else { continue }
                return splitter
            }
        }
        return nil
    }

    func zone(at point: CGPoint) -> Zone? {
        guard let normalized = normalizedPoint(for: point) else { return nil }
        return layout.zones.last { $0.rect.contains(normalized) }
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let splitter = splitter(at: point) {
            activeSplitter = splitter
            return
        }
        guard let zone = zone(at: point) else {
            selectedZoneIDs = []
            return
        }
        // Shift extends the selection, matching how AppKit lists behave.
        if event.modifierFlags.contains(.shift) {
            if selectedZoneIDs.contains(zone.id) {
                selectedZoneIDs.remove(zone.id)
            } else {
                selectedZoneIDs.insert(zone.id)
            }
        } else {
            selectedZoneIDs = [zone.id]
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let splitter = activeSplitter else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let normalized = normalizedPoint(for: point) else { return }
        let target = splitter.axis == .vertical ? Double(normalized.x) : Double(normalized.y)

        layout = LayoutEditing.move(splitter, to: target, in: layout)
        // The splitter's identity moves with it, so re-acquire the one now at
        // the dragged position rather than holding a stale position.
        activeSplitter = splitters.first { $0.axis == splitter.axis
            && $0.leadingZoneIDs == splitter.leadingZoneIDs }
        onLayoutChanged?(layout)
    }

    public override func mouseUp(with event: NSEvent) {
        activeSplitter = nil
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        let rect = previewRect
        for splitter in splitters {
            switch splitter.axis {
            case .vertical:
                let x = rect.minX + CGFloat(splitter.position) * rect.width
                addCursorRect(CGRect(x: x - Self.splitterGrabRadius, y: rect.minY,
                                     width: Self.splitterGrabRadius * 2, height: rect.height),
                              cursor: .resizeLeftRight)
            case .horizontal:
                let y = rect.maxY - CGFloat(splitter.position) * rect.height
                addCursorRect(CGRect(x: rect.minX, y: y - Self.splitterGrabRadius,
                                     width: rect.width, height: Self.splitterGrabRadius * 2),
                              cursor: .resizeUpDown)
            }
        }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: CGRect) {
        let rect = previewRect
        guard rect.width > 0 else { return }

        // The letterbox area reads as "the display", so it uses the same
        // semantic colour AppKit gives an inset content area.
        NSColor.underPageBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

        let spacing = ZoneSpacing(outerPadding: 0, gap: 4)
        for zone in layout.zones {
            let zoneRect = ZoneResolver.resolve(zone, in: rect, spacing: spacing,
                                               adjacentEdges: layout.adjacentEdges(for: zone))
            guard zoneRect.width > 0, zoneRect.height > 0 else { continue }
            let path = NSBezierPath(roundedRect: zoneRect, xRadius: 4, yRadius: 4)

            let isSelected = selectedZoneIDs.contains(zone.id)
            if isSelected {
                NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            } else {
                NSColor.controlBackgroundColor.setFill()
            }
            path.fill()

            (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = isSelected ? 2 : 1
            path.stroke()

            drawNumber(zone.index + 1, in: zoneRect)
        }
    }

    private func drawNumber(_ number: Int, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            // System font, not a named family: it follows the user's settings
            // and stays correct on a version that changes the system face.
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let text = NSAttributedString(string: "\(number)", attributes: attributes)
        let size = text.size()
        guard size.width < rect.width, size.height < rect.height else { return }
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
}
