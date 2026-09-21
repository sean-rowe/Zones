import Foundation
import os

/// Logging with a stable subsystem so Console can filter on Zones alone.
///
/// Prefixes match the layer doing the work, following Tack's convention:
/// `[Zones]` general, `[Snap]` window snapping, `[Drag]` drag detection,
/// `[Overlay]` the zone overlays.
public enum ZonesLog {
    private static let log = Logger(subsystem: "com.pinyridgelabs.Zones", category: "general")

    public static func info(_ prefix: String, _ message: String) {
        log.info("[\(prefix, privacy: .public)] \(message, privacy: .public)")
    }

    public static func error(_ prefix: String, _ message: String) {
        log.error("[\(prefix, privacy: .public)] \(message, privacy: .public)")
    }
}
