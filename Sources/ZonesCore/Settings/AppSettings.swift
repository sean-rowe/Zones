import AppKit
import Foundation

public extension Notification.Name {
    /// Posted whenever any setting changes. Subsystems re-read `Settings.shared`
    /// rather than receiving a diff — the settings object is small and this keeps
    /// every observer honest about reading current state.
    static let settingsDidChange = Notification.Name("com.pinyridgelabs.Zones.settingsDidChange")
}

/// Modifier keys Zones can watch during a drag.
///
/// Raw values are stable strings, not `NSEvent.ModifierFlags` raw integers,
/// so a stored settings file survives a change in how AppKit numbers them.
public enum ActivationModifier: String, Codable, CaseIterable, Sendable {
    case shift, control, option, command

    public var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift:   return .shift
        case .control: return .control
        case .option:  return .option
        case .command: return .command
        }
    }
}

/// Policy for when zones should be displayed during a window drag.
public enum ActivationPolicy: String, Codable, CaseIterable, Sendable {
    /// Only activate zones when the activation modifier is held.
    case holdModifier
    /// Always activate zones whenever any eligible window is being dragged.
    case alwaysWhileDragging
}

/// Every user-facing preference, in one value type.
///
/// Decoding is deliberately tolerant: every property has a default and
/// `init(from:)` falls back to it rather than throwing, so a settings file
/// written by a newer version — or a partially corrupt one — still loads.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Held during a drag to summon the zone overlay. Shift matches FancyZones.
    public var activationModifier: ActivationModifier = .shift
    /// Held to select several zones at once and snap to their bounding rect.
    public var spanModifier: ActivationModifier = .control
    /// Whether zones activate only with modifier or always while dragging.
    public var activationPolicy: ActivationPolicy = .holdModifier
    /// Toggle zone snapping on/off during drag via secondary mouse click (FancyZones feature).
    public var enableSecondaryClickToggle: Bool = true
    /// Bundle identifiers of applications excluded from zone snapping.
    public var excludedBundleIdentifiers: [String] = []
    /// Gap between adjacent zones, in points.
    public var zoneGap: Double = 8
    /// Inset from the display's visible frame, in points.
    public var outerPadding: Double = 8
    /// Overlay fill opacity, 0...1.
    public var overlayOpacity: Double = 0.35
    /// Snap a window into its remembered zone when its app launches.
    public var snapOnAppLaunch: Bool = false
    /// Restore windows to their zones when a display is reattached.
    public var restoreOnDisplayChange: Bool = true
    /// Briefly flash the zones when the active layout changes.
    public var flashZonesOnLayoutSwitch: Bool = true

    public init() {}

    /// Bring every bounded value into range.
    public func normalized() -> AppSettings {
        var copy = self
        copy.zoneGap = max(0, zoneGap)
        copy.outerPadding = max(0, outerPadding)
        copy.overlayOpacity = min(1, max(0, overlayOpacity))
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case activationModifier, spanModifier, activationPolicy
        case enableSecondaryClickToggle, excludedBundleIdentifiers
        case zoneGap, outerPadding
        case overlayOpacity, snapOnAppLaunch, restoreOnDisplayChange
        case flashZonesOnLayoutSwitch
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = defaults
            return
        }
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        activationModifier = value(.activationModifier, defaults.activationModifier)
        spanModifier = value(.spanModifier, defaults.spanModifier)
        activationPolicy = value(.activationPolicy, defaults.activationPolicy)
        enableSecondaryClickToggle = value(.enableSecondaryClickToggle, defaults.enableSecondaryClickToggle)
        excludedBundleIdentifiers = value(.excludedBundleIdentifiers, defaults.excludedBundleIdentifiers)
        zoneGap = value(.zoneGap, defaults.zoneGap)
        outerPadding = value(.outerPadding, defaults.outerPadding)
        overlayOpacity = value(.overlayOpacity, defaults.overlayOpacity)
        snapOnAppLaunch = value(.snapOnAppLaunch, defaults.snapOnAppLaunch)
        restoreOnDisplayChange = value(.restoreOnDisplayChange, defaults.restoreOnDisplayChange)
        flashZonesOnLayoutSwitch = value(.flashZonesOnLayoutSwitch, defaults.flashZonesOnLayoutSwitch)

        self = normalized()
    }
}
