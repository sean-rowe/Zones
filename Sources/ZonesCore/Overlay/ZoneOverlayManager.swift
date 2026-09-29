import AppKit
import CoreGraphics
import Foundation

/// Manages overlay windows and hit testing across all connected displays.
public class ZoneOverlayManager {
    public private(set) var overlayWindows: [ZoneOverlayWindow] = []
    public private(set) var activeLayouts: [DisplayIdentity: ZoneLayout] = [:]
    public private(set) var lastHitResult: ZoneHitTestResult?

    public var screensProvider: () -> [NSScreen] = { NSScreen.screens }

    private var accumulatedSpanIndices: Set<Int> = []
    private var flashTimer: Timer?

    public init() {}

    /// Shows zone overlays on all displays for the given active layouts.
    public func show(layouts: [DisplayIdentity: ZoneLayout]) {
        hide()
        activeLayouts = layouts
        accumulatedSpanIndices = []
        lastHitResult = nil

        let settings = Settings.shared.current
        let spacing = ZoneSpacing(settings: settings)

        for screen in screensProvider() {
            let identity = DisplayIdentity.forScreen(screen)
            guard let layout = layouts[identity] else { continue }

            let overlayWindow = ZoneOverlayWindow(screen: screen)
            overlayWindow.overlayView.baseFillColor = NSColor.windowBackgroundColor.withAlphaComponent(settings.overlayOpacity * 0.7)
            overlayWindow.overlayView.highlightFillColor = NSColor.controlAccentColor.withAlphaComponent(settings.overlayOpacity)

            // Resolve zones in screen's visibleFrame
            let resolvedAppKitRects = ZoneResolver.resolveAll(layout, in: screen.visibleFrame, spacing: spacing)

            // Convert to overlay view coordinates (relative to window content rect, which matches screen.frame)
            let viewModels = resolvedAppKitRects.enumerated().map { (idx, appKitRect) -> OverlayZoneModel in
                // appKitRect is in global AppKit coordinates; convert to screen-relative rect
                let relativeRect = CGRect(
                    x: appKitRect.origin.x - screen.frame.origin.x,
                    y: appKitRect.origin.y - screen.frame.origin.y,
                    width: appKitRect.width,
                    height: appKitRect.height
                )
                return OverlayZoneModel(index: idx, rect: relativeRect, isHighlighted: false)
            }

            overlayWindow.overlayView.zones = viewModels
            overlayWindow.orderFrontRegardless()
            overlayWindows.append(overlayWindow)
        }
    }

    /// Updates zone highlights given the current cursor position in CG coordinates.
    @discardableResult
    public func updateHighlight(at cgPoint: CGPoint, isSpanHeld: Bool) -> ZoneHitTestResult? {
        let appKitPoint = CoordinateConverter.cgToAppKit(cgPoint)
        guard let screen = screensProvider().first(where: { $0.frame.contains(appKitPoint) }) else {
            clearHighlight()
            lastHitResult = nil
            return nil
        }
        let identity = DisplayIdentity.forScreen(screen)
        guard let layout = activeLayouts[identity] else {
            clearHighlight()
            lastHitResult = nil
            return nil
        }

        let spacing = ZoneSpacing(settings: Settings.shared.current)
        let resolvedAppKitRects = ZoneResolver.resolveAll(layout, in: screen.visibleFrame, spacing: spacing)

        // Convert resolved AppKit rects to CG screen rects for hit testing
        let cgZones: [(index: Int, rect: CGRect)] = resolvedAppKitRects.enumerated().map { idx, rect in
            (index: idx, rect: CoordinateConverter.appKitToCG(rect))
        }

        let hit = ZoneHitTester.hitTest(
            point: cgPoint,
            zones: cgZones,
            isSpanHeld: isSpanHeld,
            previouslyAccumulated: accumulatedSpanIndices
        )

        lastHitResult = hit

        if let hit = hit {
            if isSpanHeld {
                accumulatedSpanIndices.formUnion(hit.zoneIndices)
            } else {
                accumulatedSpanIndices = []
            }
            applyHighlight(screen: screen, highlightedIndices: hit.zoneIndices)
        } else {
            if !isSpanHeld {
                accumulatedSpanIndices = []
            }
            clearHighlight()
        }

        return hit
    }

    /// Briefly flashes the zone overlays on all displays to orient the user.
    public func flashZones(layouts: [DisplayIdentity: ZoneLayout], duration: TimeInterval = 0.6) {
        show(layouts: layouts)
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    /// Dismisses all overlay windows.
    public func hide() {
        flashTimer?.invalidate()
        flashTimer = nil
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        accumulatedSpanIndices = []
        lastHitResult = nil
    }

    private func applyHighlight(screen: NSScreen, highlightedIndices: Set<Int>) {
        for window in overlayWindows {
            let isThisScreen = (window.frame == screen.frame)
            let updated = window.overlayView.zones.map { zone in
                let highlighted = isThisScreen && highlightedIndices.contains(zone.index)
                return OverlayZoneModel(index: zone.index, rect: zone.rect, isHighlighted: highlighted)
            }
            window.overlayView.zones = updated
        }
    }

    private func clearHighlight() {
        for window in overlayWindows {
            let updated = window.overlayView.zones.map {
                OverlayZoneModel(index: $0.index, rect: $0.rect, isHighlighted: false)
            }
            window.overlayView.zones = updated
        }
    }

    deinit { hide() }
}
