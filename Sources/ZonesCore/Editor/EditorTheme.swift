import AppKit

/// Colours and metrics shared by the picker, its dialogs and the zone editors.
///
/// The FancyZones editor follows the Windows theme; this follows the macOS
/// appearance the same way. Where AppKit has a semantic colour that means the
/// right thing it is used directly. The rest are dynamic colours with a light
/// and a dark value, resolved at draw time, so switching appearance while the
/// picker is open repaints correctly with no observer.
enum EditorTheme {

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    // MARK: Picker

    static let pickerBackground = dynamic(
        light: NSColor(white: 0.953, alpha: 1), dark: NSColor(white: 0.125, alpha: 1))
    static let cardBackground = dynamic(
        light: NSColor(white: 1.0, alpha: 1), dark: NSColor(white: 0.18, alpha: 1))
    static let cardHoverBackground = dynamic(
        light: NSColor(white: 0.975, alpha: 1), dark: NSColor(white: 0.22, alpha: 1))
    static let cardBorder = dynamic(
        light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.08))
    /// The "display" behind a card's mini preview.
    static let previewBackground = dynamic(
        light: NSColor(white: 0.91, alpha: 1), dark: NSColor(white: 0.11, alpha: 1))

    static var accent: NSColor { .controlAccentColor }

    /// Mini-preview zone fill: the accent, softened so a card of six zones
    /// does not shout.
    static var previewZoneFill: NSColor {
        dynamic(light: NSColor.controlAccentColor.withAlphaComponent(0.55),
                dark: NSColor.controlAccentColor.withAlphaComponent(0.70))
    }

    static let cardCornerRadius: CGFloat = 8
    static let cardSize = CGSize(width: 200, height: 156)
    static let cardSpacing: CGFloat = 16

    // MARK: Zone editor

    /// Dims the desktop behind the editor without hiding it, so the user can
    /// still see what they are laying zones over.
    static let editorDim = dynamic(
        light: NSColor(white: 0.97, alpha: 0.55), dark: NSColor(white: 0.0, alpha: 0.55))
    static var editorZoneFill: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.28) }
    static var editorZoneSelectedFill: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.6) }
    static var editorZoneBorder: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.95) }
    static let editorNumber = dynamic(
        light: NSColor(white: 0.1, alpha: 0.9), dark: NSColor(white: 1, alpha: 0.92))
    static let editorToolbarBackground = dynamic(
        light: NSColor(white: 0.99, alpha: 0.97), dark: NSColor(white: 0.17, alpha: 0.97))
    static let thumbFill = dynamic(
        light: NSColor(white: 1, alpha: 1), dark: NSColor(white: 0.92, alpha: 1))

    /// Editor zone spacing: the user's real gap, with a floor so dividers and
    /// their thumbs stay visible even when the gap is set to zero.
    static func editorSpacing(for settings: AppSettings) -> ZoneSpacing {
        ZoneSpacing(outerPadding: max(12, settings.outerPadding), gap: max(16, settings.zoneGap))
    }
}

/// Draws a layout's zones as a thumbnail.
///
/// Shared by the layout cards and anything else that needs a miniature, so
/// they all draw zones the same way.
enum ZonePreviewRenderer {

    static func draw(_ layout: ZoneLayout, in rect: CGRect, gap: CGFloat = 3,
                     cornerRadius: CGFloat = 3) {
        EditorTheme.previewBackground.setFill()
        NSBezierPath(roundedRect: rect, xRadius: cornerRadius + 2, yRadius: cornerRadius + 2).fill()

        let spacing = ZoneSpacing(outerPadding: Double(gap), gap: Double(gap))
        EditorTheme.previewZoneFill.setFill()
        for zone in layout.zones {
            // Canvas zones overlap, so adjacency (which decides where gaps go)
            // only makes sense for tiled layouts. Canvas zones get a uniform
            // inset instead.
            let zoneRect: CGRect
            if layout.origin.isCanvas {
                zoneRect = UnitSquareMapping(area: rect.insetBy(dx: gap, dy: gap))
                    .viewRect(for: zone.rect).insetBy(dx: gap / 2, dy: gap / 2)
            } else {
                zoneRect = ZoneResolver.resolve(zone, in: rect, spacing: spacing,
                                                adjacentEdges: layout.adjacentEdges(for: zone))
            }
            guard zoneRect.width > 0, zoneRect.height > 0 else { continue }
            let path = NSBezierPath(roundedRect: zoneRect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.fill()
            if layout.origin.isCanvas {
                // Overlaps would otherwise merge into one blob.
                EditorTheme.accent.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    /// The largest rect of an aspect ratio that fits, centred.
    static func fit(aspectRatio: CGFloat, in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, aspectRatio > 0 else { return .zero }
        var size = CGSize(width: bounds.width, height: bounds.width / aspectRatio)
        if size.height > bounds.height {
            size = CGSize(width: bounds.height * aspectRatio, height: bounds.height)
        }
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}
