import AppKit

/// Shared drawing for the two full-screen zone editors.
class ZoneEditorCanvasBase: NSView {

    var layout: ZoneLayout {
        didSet {
            layoutDidChange()
            needsDisplay = true
            onLayoutChanged?(layout)
        }
    }
    var onLayoutChanged: ((ZoneLayout) -> Void)?
    let spacing: ZoneSpacing

    init(layout: ZoneLayout, spacing: ZoneSpacing) {
        self.layout = layout
        self.spacing = spacing
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func layoutDidChange() {}

    /// The unit square spread over the view, inside the outer padding.
    var mapping: UnitSquareMapping {
        UnitSquareMapping(area: bounds.insetBy(dx: spacing.outerPadding, dy: spacing.outerPadding))
    }

    func normalized(_ event: NSEvent) -> CGPoint {
        mapping.normalizedPoint(for: convert(event.locationInWindow, from: nil))
    }

    func drawDim() {
        EditorTheme.editorDim.setFill()
        bounds.fill()
    }

    func drawZone(_ rect: CGRect, number: Int, selected: Bool, cornerRadius: CGFloat = 10) {
        guard rect.width > 0, rect.height > 0 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        (selected ? EditorTheme.editorZoneSelectedFill : EditorTheme.editorZoneFill).setFill()
        path.fill()
        EditorTheme.editorZoneBorder.setStroke()
        path.lineWidth = 2
        path.stroke()

        // Large and centred, as FancyZones numbers its editor zones — the
        // number is the shortcut, so it should be unmissable.
        let size = min(96, max(18, min(rect.width, rect.height) * 0.32))
        let text = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: EditorTheme.editorNumber,
        ])
        let textSize = text.size()
        guard textSize.width < rect.width - 8, textSize.height < rect.height - 8 else { return }
        text.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }
}

/// The grid zone editor: split by clicking, resize by dragging dividers, merge
/// by dragging across zones.
///
/// Every edit goes through `LayoutEditing`, so the tiling stays exact and the
/// minimum zone size holds; this view only translates the pointer.
final class GridZoneEditorView: ZoneEditorCanvasBase {

    /// Called when the merge button should appear or disappear, with the
    /// selection's bounds in view coordinates.
    var onSelectionChanged: ((Set<UUID>, CGRect?) -> Void)?

    private(set) var splitters: [Splitter] = []
    private(set) var selection: Set<UUID> = [] {
        didSet {
            guard selection != oldValue else { return }
            needsDisplay = true
            let bounds = selection.count >= 2
                ? ZoneDragSelection.bounds(of: selection, in: layout).map { zoneAreaRect(for: $0) }
                : nil
            onSelectionChanged?(selection, bounds)
        }
    }

    /// The split the next click makes, if the pointer is over a zone.
    private(set) var preview: (zoneID: UUID, axis: SplitterAxis, position: Double)? {
        didSet { needsDisplay = true }
    }
    private var hoveredSplitter: Splitter? { didSet { needsDisplay = true } }
    private var lastPointer: CGPoint?
    private var shiftHeld = false

    private enum Gesture {
        case none
        case dragSplitter(Splitter)
        /// `splits` is false when the press only dismisses a selection.
        case pressZone(UUID, CGPoint, splits: Bool)
        case selecting(from: UUID)
    }
    private var gesture: Gesture = .none
    private var trackingArea: NSTrackingArea?

    /// Points the pointer must travel before a press becomes a drag-select,
    /// so a slightly shaky click still splits.
    static let dragThreshold: CGFloat = 4
    /// Distance from a divider within which it is grabbed instead of the zone.
    static let splitterGrabRadius: CGFloat = 8
    static let thumbLength: CGFloat = 44
    static let thumbThickness: CGFloat = 10

    override init(layout: ZoneLayout, spacing: ZoneSpacing) {
        super.init(layout: layout, spacing: spacing)
        splitters = LayoutEditing.splitters(in: layout)
    }

    override func layoutDidChange() {
        splitters = LayoutEditing.splitters(in: layout)
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Geometry

    /// A normalized rect in view coordinates, before the gap is applied.
    func zoneAreaRect(for normalized: CGRect) -> CGRect { mapping.viewRect(for: normalized) }

    func drawnRect(for zone: Zone) -> CGRect {
        ZoneResolver.resolve(zone, in: mapping.area,
                             spacing: ZoneSpacing(outerPadding: 0, gap: spacing.gap),
                             adjacentEdges: layout.adjacentEdges(for: zone))
    }

    /// The pill each divider is grabbed by, centred on its drawn length.
    func thumbRect(for splitter: Splitter) -> CGRect {
        let mid = (splitter.span.lowerBound + splitter.span.upperBound) / 2
        switch splitter.axis {
        case .vertical:
            let length = min(Self.thumbLength,
                             CGFloat(splitter.span.upperBound - splitter.span.lowerBound) * mapping.area.height - 8)
            return CGRect(x: mapping.viewX(splitter.position) - Self.thumbThickness / 2,
                          y: mapping.viewY(mid) - length / 2,
                          width: Self.thumbThickness, height: max(12, length))
        case .horizontal:
            let length = min(Self.thumbLength,
                             CGFloat(splitter.span.upperBound - splitter.span.lowerBound) * mapping.area.width - 8)
            return CGRect(x: mapping.viewX(mid) - length / 2,
                          y: mapping.viewY(splitter.position) - Self.thumbThickness / 2,
                          width: max(12, length), height: Self.thumbThickness)
        }
    }

    func splitter(at point: CGPoint) -> Splitter? {
        let normalized = mapping.normalizedPoint(for: point)
        for splitter in splitters {
            if thumbRect(for: splitter).insetBy(dx: -4, dy: -4).contains(point) { return splitter }
            switch splitter.axis {
            case .vertical:
                if abs(point.x - mapping.viewX(splitter.position)) <= Self.splitterGrabRadius,
                   splitter.span.contains(Double(normalized.y)) { return splitter }
            case .horizontal:
                if abs(point.y - mapping.viewY(splitter.position)) <= Self.splitterGrabRadius,
                   splitter.span.contains(Double(normalized.x)) { return splitter }
            }
        }
        return nil
    }

    func zone(at point: CGPoint) -> Zone? {
        let normalized = mapping.normalizedPoint(for: point)
        return layout.zones.first { $0.rect.contains(normalized) }
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // activeAlways: the editor window is a borderless overlay, and hover
        // must work the moment it appears, before anything else is clicked.
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        shiftHeld = event.modifierFlags.contains(.shift)
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        lastPointer = nil
        preview = nil
        hoveredSplitter = nil
    }

    override func flagsChanged(with event: NSEvent) {
        shiftHeld = event.modifierFlags.contains(.shift)
        if let lastPointer { updateHover(at: lastPointer) }
    }

    /// Recompute the hovered divider or the split preview for a pointer.
    func updateHover(at point: CGPoint, shift: Bool? = nil) {
        if let shift { shiftHeld = shift }
        lastPointer = point
        if case .none = gesture {} else { return }
        if let splitter = splitter(at: point) {
            hoveredSplitter = splitter
            preview = nil
            (splitter.axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
            return
        }
        hoveredSplitter = nil
        NSCursor.arrow.set()
        guard let zone = zone(at: point) else { preview = nil; return }
        let axis = GridSplitPreview.axis(shiftHeld: shiftHeld)
        let normalized = mapping.normalizedPoint(for: point)
        if let position = GridSplitPreview.position(for: normalized, in: zone.rect, axis: axis) {
            preview = (zone.id, axis, position)
        } else {
            preview = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if let splitter = splitter(at: point) {
            gesture = .dragSplitter(splitter)
            selection = []
            return
        }
        guard let zone = zone(at: point) else {
            gesture = .none
            selection = []
            return
        }
        // With a selection showing, a click dismisses it rather than also
        // splitting whatever zone it landed on.
        gesture = .pressZone(zone.id, point, splits: selection.isEmpty)
        selection = []
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch gesture {
        case .dragSplitter(let splitter):
            let normalized = mapping.normalizedPoint(for: point)
            let target = splitter.axis == .vertical ? Double(normalized.x) : Double(normalized.y)
            layout = LayoutEditing.move(splitter, to: target, in: layout)
            // A splitter's identity includes its position, so find the one
            // that moved by the zones it separates.
            if let moved = splitters.first(where: { $0.axis == splitter.axis
                && Set($0.leadingZoneIDs) == Set(splitter.leadingZoneIDs) }) {
                gesture = .dragSplitter(moved)
                hoveredSplitter = moved
            }
        case .pressZone(let id, let start, _):
            guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else { return }
            gesture = .selecting(from: id)
            preview = nil
            extendSelection(from: id, to: point)
        case .selecting(let id):
            extendSelection(from: id, to: point)
        case .none:
            break
        }
    }

    private func extendSelection(from id: UUID, to point: CGPoint) {
        guard let end = zone(at: point) else { return }
        selection = ZoneDragSelection.selection(from: id, to: end.id, in: layout)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch gesture {
        case .pressZone(_, _, let splits):
            // A click: split where the preview line is.
            updateHoverIgnoringGesture(at: point, event: event)
            if splits, let preview {
                layout = LayoutEditing.split(zoneID: preview.zoneID, axis: preview.axis,
                                             at: preview.position, in: layout)
                ZonesLog.info("Zones", "editor split zone \(preview.axis.rawValue) at \(preview.position)")
            }
            selection = []
        case .selecting:
            // A one-zone "selection" is just a drag that went nowhere.
            if selection.count < 2 { selection = [] }
        case .dragSplitter, .none:
            break
        }
        gesture = .none
        updateHover(at: point)
    }

    private func updateHoverIgnoringGesture(at point: CGPoint, event: NSEvent) {
        let saved = gesture
        gesture = .none
        updateHover(at: point, shift: event.modifierFlags.contains(.shift))
        gesture = saved
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for splitter in splitters {
            let thumb = thumbRect(for: splitter).insetBy(dx: -4, dy: -4)
            addCursorRect(thumb, cursor: splitter.axis == .vertical ? .resizeLeftRight : .resizeUpDown)
        }
    }

    // MARK: Actions

    /// Merge the current selection, if it forms a rectangle.
    func mergeSelection() {
        guard LayoutEditing.canMerge(zoneIDs: selection, in: layout) else { return }
        layout = LayoutEditing.merge(zoneIDs: selection, in: layout)
        selection = []
    }

    func clearSelection() { selection = [] }

    // MARK: Test seams

    func setSelectionForTesting(_ ids: Set<UUID>) { selection = ids }
    func simulateClick(at point: CGPoint, shift: Bool = false) {
        updateHover(at: point, shift: shift)
        if let preview {
            layout = LayoutEditing.split(zoneID: preview.zoneID, axis: preview.axis,
                                         at: preview.position, in: layout)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: CGRect) {
        drawDim()
        for zone in layout.zones {
            drawZone(drawnRect(for: zone), number: zone.index + 1,
                     selected: selection.contains(zone.id))
        }
        if let preview, let zone = layout.zones.first(where: { $0.id == preview.zoneID }) {
            drawPreviewLine(preview.axis, at: preview.position, in: drawnRect(for: zone))
        }
        for splitter in splitters {
            drawThumb(for: splitter, highlighted: splitter.id == hoveredSplitter?.id)
        }
    }

    private func drawPreviewLine(_ axis: SplitterAxis, at position: Double, in zoneRect: CGRect) {
        let path = NSBezierPath()
        switch axis {
        case .vertical:
            let x = mapping.viewX(position)
            path.move(to: CGPoint(x: x, y: zoneRect.minY + 2))
            path.line(to: CGPoint(x: x, y: zoneRect.maxY - 2))
        case .horizontal:
            let y = mapping.viewY(position)
            path.move(to: CGPoint(x: zoneRect.minX + 2, y: y))
            path.line(to: CGPoint(x: zoneRect.maxX - 2, y: y))
        }
        path.lineWidth = 2
        EditorTheme.editorNumber.setStroke()
        path.setLineDash([8, 5], count: 2, phase: 0)
        path.stroke()
    }

    private func drawThumb(for splitter: Splitter, highlighted: Bool) {
        let rect = thumbRect(for: splitter)
        let radius = min(rect.width, rect.height) / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        (highlighted ? EditorTheme.accent : EditorTheme.thumbFill).setFill()
        path.fill()
        EditorTheme.accent.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
