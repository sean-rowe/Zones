import AppKit

/// The canvas zone editor: free rects that can overlap, moved by dragging,
/// resized from their edges and corners, and removed with ×.
///
/// The FancyZones canvas editor, where a zone is a window-sized rectangle
/// rather than a cell in a tiling. Geometry lives in `CanvasEditing`.
final class CanvasZoneEditorView: ZoneEditorCanvasBase {

    private(set) var selectedZoneID: UUID? { didSet { needsDisplay = true } }
    private var hoveredZoneID: UUID? { didSet { if hoveredZoneID != oldValue { needsDisplay = true } } }

    private enum Gesture {
        case none
        case move(UUID, start: CGPoint, original: CGRect)
        case resize(UUID, CanvasHandle)
    }
    private var gesture: Gesture = .none
    private var trackingArea: NSTrackingArea?

    static let handleSize: CGFloat = 10
    static let closeSize: CGFloat = 26

    // MARK: Geometry

    func viewRect(for zone: Zone) -> CGRect {
        mapping.viewRect(for: zone.rect).insetBy(dx: 2, dy: 2)
    }

    func closeRect(for zone: Zone) -> CGRect {
        let rect = viewRect(for: zone)
        return CGRect(x: rect.maxX - Self.closeSize - 8, y: rect.maxY - Self.closeSize - 8,
                      width: Self.closeSize, height: Self.closeSize)
    }

    func handleRect(_ handle: CanvasHandle, for zone: Zone) -> CGRect {
        let anchor = mapping.viewRect(for: CGRect(origin: handle.point(on: zone.rect), size: .zero)).origin
        return CGRect(x: anchor.x - Self.handleSize / 2, y: anchor.y - Self.handleSize / 2,
                      width: Self.handleSize, height: Self.handleSize)
    }

    /// Zones in the order they are drawn: as stored, with the selected one
    /// last so its handles are never hidden under a neighbour.
    private var drawOrder: [Zone] {
        let zones = layout.zones
        guard let selectedZoneID, let selected = zones.first(where: { $0.id == selectedZoneID }) else {
            return zones
        }
        return zones.filter { $0.id != selectedZoneID } + [selected]
    }

    private enum Hit {
        case close(Zone), handle(Zone, CanvasHandle), body(Zone)
    }

    private func hit(at point: CGPoint) -> Hit? {
        for zone in drawOrder.reversed() {
            if closeRect(for: zone).contains(point) { return .close(zone) }
            if zone.id == selectedZoneID || zone.id == hoveredZoneID {
                for handle in CanvasHandle.allCases
                where handleRect(handle, for: zone).insetBy(dx: -4, dy: -4).contains(point) {
                    return .handle(zone, handle)
                }
            }
            if viewRect(for: zone).contains(point) { return .body(zone) }
        }
        return nil
    }

    // MARK: Actions

    func addZone() {
        layout = CanvasEditing.addingZone(to: layout)
        selectedZoneID = layout.zones.last?.id
    }

    func deleteZone(_ id: UUID) {
        layout = CanvasEditing.removingZone(id, from: layout)
        if selectedZoneID == id { selectedZoneID = nil }
    }

    func selectForTesting(_ id: UUID?) { selectedZoneID = id }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch hit(at: point) {
        case .handle(let zone, let handle):
            hoveredZoneID = zone.id
            cursor(for: handle).set()
        case .body(let zone):
            hoveredZoneID = zone.id
            NSCursor.openHand.set()
        case .close(let zone):
            hoveredZoneID = zone.id
            NSCursor.arrow.set()
        case nil:
            hoveredZoneID = nil
            NSCursor.arrow.set()
        }
    }

    private func cursor(for handle: CanvasHandle) -> NSCursor {
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        // AppKit has no public diagonal resize cursor; crosshair reads as
        // "resize from here" without pretending to be one axis.
        default: return .crosshair
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        switch hit(at: point) {
        case .close(let zone):
            deleteZone(zone.id)
            gesture = .none
        case .handle(let zone, let handle):
            selectedZoneID = zone.id
            gesture = .resize(zone.id, handle)
        case .body(let zone):
            selectedZoneID = zone.id
            gesture = .move(zone.id, start: mapping.normalizedPoint(for: point), original: zone.rect)
            NSCursor.closedHand.set()
        case nil:
            selectedZoneID = nil
            gesture = .none
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = normalized(event)
        switch gesture {
        case .move(let id, let start, let original):
            let moved = CanvasEditing.moved(original, by: CGVector(dx: point.x - start.x,
                                                                    dy: point.y - start.y))
            layout = CanvasEditing.replacing(id, with: moved, in: layout)
        case .resize(let id, let handle):
            guard let zone = layout.zones.first(where: { $0.id == id }) else { return }
            layout = CanvasEditing.replacing(id, with: CanvasEditing.resized(zone.rect, handle: handle,
                                                                             to: point), in: layout)
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        gesture = .none
        mouseMoved(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Delete or forward-delete removes the selected zone.
        if let selectedZoneID, event.keyCode == 51 || event.keyCode == 117 {
            deleteZone(selectedZoneID)
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: CGRect) {
        drawDim()
        for zone in drawOrder {
            let rect = viewRect(for: zone)
            drawZone(rect, number: zone.index + 1, selected: zone.id == selectedZoneID)
            drawClose(in: closeRect(for: zone))
            if zone.id == selectedZoneID || zone.id == hoveredZoneID {
                for handle in CanvasHandle.allCases { drawHandle(handleRect(handle, for: zone)) }
            }
        }
    }

    private func drawClose(in rect: CGRect) {
        EditorTheme.thumbFill.setFill()
        NSBezierPath(ovalIn: rect).fill()
        let cross = NSBezierPath()
        let inset = rect.insetBy(dx: 8.5, dy: 8.5)
        cross.move(to: CGPoint(x: inset.minX, y: inset.minY))
        cross.line(to: CGPoint(x: inset.maxX, y: inset.maxY))
        cross.move(to: CGPoint(x: inset.minX, y: inset.maxY))
        cross.line(to: CGPoint(x: inset.maxX, y: inset.minY))
        cross.lineWidth = 1.8
        cross.lineCapStyle = .round
        NSColor(white: 0.15, alpha: 1).setStroke()
        cross.stroke()
    }

    private func drawHandle(_ rect: CGRect) {
        let path = NSBezierPath(ovalIn: rect)
        EditorTheme.thumbFill.setFill()
        path.fill()
        EditorTheme.accent.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
