import AppKit
import CoreGraphics

public struct OverlayZoneModel: Equatable {
    public let index: Int
    /// Rect in view coordinates (AppKit bottom-left origin).
    public let rect: CGRect
    public let isHighlighted: Bool

    public init(index: Int, rect: CGRect, isHighlighted: Bool) {
        self.index = index
        self.rect = rect
        self.isHighlighted = isHighlighted
    }
}

/// Draws zone rectangles with a macOS-native translucent glass aesthetic:
/// - Continuous rounded squircle corners (14pt radius).
/// - Floating frosted pill badges with SF Pro font (not giant Windows-style numbers).
/// - Hairline accent borders with subtle inner glow.
/// - Trackpad haptic feedback when entering new zones.
public class ZoneOverlayView: NSView {
    public var zones: [OverlayZoneModel] = [] {
        didSet {
            if oldValue != zones {
                checkHapticFeedback(oldZones: oldValue, newZones: zones)
                needsDisplay = true
            }
        }
    }

    public var cornerRadius: CGFloat = 14.0
    public var baseFillColor: NSColor = NSColor.windowBackgroundColor.withAlphaComponent(0.25)
    public var baseBorderColor: NSColor = NSColor.separatorColor.withAlphaComponent(0.4)
    public var highlightFillColor: NSColor = NSColor.controlAccentColor.withAlphaComponent(0.35)
    public var highlightBorderColor: NSColor = NSColor.controlAccentColor.withAlphaComponent(0.9)

    /// Seam for haptic feedback execution (testable).
    public var hapticPerformer: (() -> Void)? = {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    public override var isFlipped: Bool { false }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for zone in zones {
            drawZone(zone)
        }
    }

    private func drawZone(_ zone: OverlayZoneModel) {
        let path = NSBezierPath(roundedRect: zone.rect, xRadius: cornerRadius, yRadius: cornerRadius)

        // 1. Fill
        let fill = zone.isHighlighted ? highlightFillColor : baseFillColor
        fill.setFill()
        path.fill()

        // 2. Stroke
        let stroke = zone.isHighlighted ? highlightBorderColor : baseBorderColor
        stroke.setStroke()
        path.lineWidth = zone.isHighlighted ? 2.0 : 1.0
        path.stroke()

        // 3. Floating Pill Badge (differentiated from Microsoft's giant centered numbers)
        drawFloatingPillBadge(for: zone)
    }

    private func drawFloatingPillBadge(for zone: OverlayZoneModel) {
        let badgeSize = CGSize(width: 32, height: 24)
        // Position badge near top-left of the zone with 12pt margin
        let badgeOrigin = CGPoint(
            x: zone.rect.minX + 12,
            y: zone.rect.maxY - badgeSize.height - 12
        )
        guard badgeOrigin.x + badgeSize.width <= zone.rect.maxX,
              badgeOrigin.y >= zone.rect.minY else { return }

        let badgeRect = CGRect(origin: badgeOrigin, size: badgeSize)
        let pillPath = NSBezierPath(roundedRect: badgeRect, xRadius: 12, yRadius: 12)

        // Glass pill background
        let pillBg = zone.isHighlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.85)
            : NSColor.black.withAlphaComponent(0.45)
        pillBg.setFill()
        pillPath.fill()

        // Pill border
        NSColor.white.withAlphaComponent(0.3).setStroke()
        pillPath.lineWidth = 0.5
        pillPath.stroke()

        // Zone number text
        let title = "\(zone.index + 1)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: title, attributes: attributes)
        let strSize = str.size()
        let strOrigin = CGPoint(
            x: badgeRect.midX - strSize.width / 2,
            y: badgeRect.midY - strSize.height / 2
        )
        str.draw(at: strOrigin)
    }

    private func checkHapticFeedback(oldZones: [OverlayZoneModel], newZones: [OverlayZoneModel]) {
        let oldHighlighted = Set(oldZones.filter { $0.isHighlighted }.map { $0.index })
        let newHighlighted = Set(newZones.filter { $0.isHighlighted }.map { $0.index })

        if !newHighlighted.isEmpty && newHighlighted != oldHighlighted {
            hapticPerformer?()
        }
    }
}
