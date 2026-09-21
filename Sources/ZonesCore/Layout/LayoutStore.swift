import Foundation

/// Everything persisted about layouts, in one versioned envelope.
///
/// Versioned from the first release. Migrating a format is cheap; recovering
/// layouts a user hand-built after an unversioned format changed shape is not
/// possible at all.
struct LayoutArchive: Codable {
    static let currentVersion = 1

    var version: Int = LayoutArchive.currentVersion
    var layouts: [ZoneLayout] = []
    /// Display identity key -> layout UUID.
    var assignments: [String: UUID] = [:]
}

/// Owns the user's layouts and which display each one is assigned to.
public final class LayoutStore {
    public static let shared = LayoutStore()

    static let storageKey = "com.pinyridgelabs.Zones.layouts"

    private let storage: SettingsStorage
    private var archive: LayoutArchive

    /// True when the stored archive was written by a newer Zones.
    ///
    /// In that state the store runs read-only in memory. Saying "ignore it"
    /// and then writing built-in layouts over the top would destroy exactly
    /// the data the version check exists to protect.
    public private(set) var isReadOnlyDueToNewerArchive = false

    public init(storage: SettingsStorage = UserDefaults.standard) {
        self.storage = storage
        let (archive, isNewer) = LayoutStore.load(from: storage)
        self.archive = archive
        self.isReadOnlyDueToNewerArchive = isNewer
    }

    // MARK: - Layouts

    public var layouts: [ZoneLayout] { archive.layouts }

    public func layout(id: UUID) -> ZoneLayout? {
        archive.layouts.first { $0.id == id }
    }

    /// Insert or replace by identity.
    public func save(_ layout: ZoneLayout) {
        if let index = archive.layouts.firstIndex(where: { $0.id == layout.id }) {
            archive.layouts[index] = layout
        } else {
            archive.layouts.append(layout)
        }
        persist()
    }

    /// Remove a layout and any assignment pointing at it.
    ///
    /// Assignments are cleaned up here rather than left dangling, so a deleted
    /// layout cannot leave a display pointing at nothing.
    public func delete(id: UUID) {
        archive.layouts.removeAll { $0.id == id }
        archive.assignments = archive.assignments.filter { $0.value != id }
        persist()
    }

    // MARK: - Assignment

    public func assign(layoutID: UUID, to display: DisplayIdentity) {
        archive.assignments[display.key] = layoutID
        persist()
    }

    /// The layout assigned to a display, if it still exists.
    public func assignedLayout(for display: DisplayIdentity) -> ZoneLayout? {
        guard let id = archive.assignments[display.key] else { return nil }
        return layout(id: id)
    }

    public func clearAssignment(for display: DisplayIdentity) {
        archive.assignments.removeValue(forKey: display.key)
        persist()
    }

    /// Seed the built-in layouts on a first run.
    @discardableResult
    public func installBuiltInsIfEmpty() -> Bool {
        guard !isReadOnlyDueToNewerArchive else { return false }
        guard archive.layouts.isEmpty else { return false }
        archive.layouts = LayoutTemplate.builtIns
        persist()
        return true
    }

    // MARK: - Persistence

    private static func load(from storage: SettingsStorage) -> (LayoutArchive, Bool) {
        guard let data = storage.data(forKey: storageKey) else { return (LayoutArchive(), false) }
        do {
            let archive = try JSONDecoder().decode(LayoutArchive.self, from: data)
            guard archive.version <= LayoutArchive.currentVersion else {
                // Written by a newer Zones. Reading it with this version's
                // assumptions could silently mangle the layouts, so start
                // clean and leave the stored data untouched for the newer
                // version to find.
                ZonesLog.error("Zones", "layout archive version \(archive.version) is newer "
                               + "than \(LayoutArchive.currentVersion); running read-only")
                return (LayoutArchive(), true)
            }
            return (archive, false)
        } catch {
            // Matches AppSettings: unreadable data must not stop the app.
            // Corrupt is not the same as newer — corrupt data is safe to
            // replace, so this path stays writable.
            ZonesLog.error("Zones", "layout archive unreadable, starting empty: \(error)")
            return (LayoutArchive(), false)
        }
    }

    private func persist() {
        guard !isReadOnlyDueToNewerArchive else {
            ZonesLog.info("Zones", "not writing layouts: stored archive is from a newer version")
            return
        }
        do {
            storage.set(try JSONEncoder().encode(archive) as Any?, forKey: LayoutStore.storageKey)
        } catch {
            ZonesLog.error("Zones", "layout archive could not be written: \(error)")
        }
    }
}
