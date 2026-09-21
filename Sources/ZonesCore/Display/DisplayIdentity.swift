import AppKit
import CoreGraphics
import Foundation

/// A durable name for a display.
///
/// **`CGDirectDisplayID` must never be used as a persistence key.** macOS
/// recycles those numbers across reconnects, sleep and reboots, so a layout
/// keyed to one comes back attached to whatever display inherited the number —
/// typically the laptop's, wearing the external monitor's layout.
///
/// `CGDisplayCreateUUIDFromDisplayID` is stable for the physical display, so it
/// is the key. Some virtual displays and a few KVMs return nothing, and for
/// those the geometry acts as a fallback name: weaker, because two identical
/// monitors in the same position are indistinguishable, but enough to keep an
/// assignment for the session rather than losing it outright.
public struct DisplayIdentity: Codable, Equatable, Hashable, Sendable {

    /// How this identity was derived. Worth keeping, because a fallback
    /// identity is not as trustworthy as a UUID one and callers may care.
    public enum Source: String, Codable, Sendable {
        case uuid
        case geometry
    }

    public let key: String
    public let source: Source

    public init(key: String, source: Source) {
        self.key = key
        self.source = source
    }

    /// Identity for a display ID, preferring its UUID.
    public static func forDisplay(_ displayID: CGDirectDisplayID,
                                  frame: CGRect) -> DisplayIdentity {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let string = CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
            return DisplayIdentity(key: string, source: .uuid)
        }
        return DisplayIdentity(key: geometryKey(for: frame), source: .geometry)
    }

    /// Identity for an `NSScreen`.
    public static func forScreen(_ screen: NSScreen) -> DisplayIdentity {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return DisplayIdentity(key: geometryKey(for: screen.frame), source: .geometry)
        }
        return forDisplay(CGDirectDisplayID(number.uint32Value), frame: screen.frame)
    }

    /// Position and size as a stable string. Rounded, because a fractional
    /// difference in reported geometry would otherwise produce a new identity
    /// for the same physical display.
    static func geometryKey(for frame: CGRect) -> String {
        let x = Int(frame.origin.x.rounded())
        let y = Int(frame.origin.y.rounded())
        let w = Int(frame.width.rounded())
        let h = Int(frame.height.rounded())
        return "geometry:\(x),\(y),\(w)x\(h)"
    }
}
