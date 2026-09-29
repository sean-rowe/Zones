import Foundation
import CoreGraphics

/// Recorded zone assignment for a window.
public struct ZoneAssignment: Hashable, Codable, Sendable {
    public let windowIdentity: WindowIdentity
    public let displayIdentity: DisplayIdentity
    public let layoutID: UUID
    public let zoneIndex: Int
    public let zoneIndices: [Int]
    public let snappedRect: CGRect
    public let timestamp: Date

    public init(
        windowIdentity: WindowIdentity,
        displayIdentity: DisplayIdentity,
        layoutID: UUID,
        zoneIndex: Int,
        zoneIndices: [Int] = [],
        snappedRect: CGRect,
        timestamp: Date = Date()
    ) {
        self.windowIdentity = windowIdentity
        self.displayIdentity = displayIdentity
        self.layoutID = layoutID
        self.zoneIndex = zoneIndex
        self.zoneIndices = zoneIndices.isEmpty ? [zoneIndex] : zoneIndices
        self.snappedRect = snappedRect
        self.timestamp = timestamp
    }
}

/// Persists and manages zone assignments across app relaunches and display changes.
public class ZoneAssignmentStore {
    public static let shared = ZoneAssignmentStore()

    public let fileURL: URL
    private var assignments: [WindowIdentity: ZoneAssignment] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.pinyridgelabs.Zones.ZoneAssignmentStore", qos: .utility)

    public init(fileURL: URL = ZoneAssignmentStore.defaultStorageURL) {
        self.fileURL = fileURL
        load()
    }

    public static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let zonesDir = appSupport.appendingPathComponent("com.pinyridgelabs.Zones", isDirectory: true)
        return zonesDir.appendingPathComponent("zone_assignments.json")
    }

    public func assign(
        window: WindowInfo,
        display: DisplayIdentity,
        layoutID: UUID,
        zoneIndex: Int,
        zoneIndices: [Int] = [],
        snappedRect: CGRect
    ) {
        let identity = WindowIdentity(window: window)
        let assignment = ZoneAssignment(
            windowIdentity: identity,
            displayIdentity: display,
            layoutID: layoutID,
            zoneIndex: zoneIndex,
            zoneIndices: zoneIndices,
            snappedRect: snappedRect
        )
        lock.lock()
        assignments[identity] = assignment
        lock.unlock()
        save()
    }

    public func assignment(for identity: WindowIdentity) -> ZoneAssignment? {
        lock.lock()
        defer { lock.unlock() }
        return assignments[identity]
    }

    public func assignment(for window: WindowInfo) -> ZoneAssignment? {
        assignment(for: WindowIdentity(window: window))
    }

    public func removeAssignment(for identity: WindowIdentity) {
        lock.lock()
        let removed = assignments.removeValue(forKey: identity) != nil
        lock.unlock()
        if removed {
            save()
        }
    }

    public func removeAssignment(for window: WindowInfo) {
        removeAssignment(for: WindowIdentity(window: window))
    }

    public func allAssignments() -> [ZoneAssignment] {
        lock.lock()
        defer { lock.unlock() }
        return Array(assignments.values)
    }

    public func clear() {
        lock.lock()
        assignments.removeAll()
        lock.unlock()
        save()
    }

    public func load() {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([ZoneAssignment].self, from: data)
            assignments = Dictionary(uniqueKeysWithValues: decoded.map { ($0.windowIdentity, $0) })
        } catch {
            ZonesLog.error("Memory", "Failed to load zone assignments: \(error)")
        }
    }

    public func save() {
        lock.lock()
        let list = Array(assignments.values)
        lock.unlock()

        queue.async { [fileURL = self.fileURL] in
            do {
                let dir = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(list)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                ZonesLog.error("Memory", "Failed to save zone assignments: \(error)")
            }
        }
    }

    /// Synchronous save for tests
    public func saveSynchronously() throws {
        lock.lock()
        let list = Array(assignments.values)
        lock.unlock()

        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(list)
        try data.write(to: fileURL, options: .atomic)
    }
}
