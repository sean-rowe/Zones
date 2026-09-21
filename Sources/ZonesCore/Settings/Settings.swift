import Foundation

/// Where settings are read from and written to.
///
/// Abstracted so tests can drive a store without touching the real
/// UserDefaults domain, which is shared with whatever else runs in the suite.
public protocol SettingsStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}

// UserDefaults already has both of these, so conformance needs no members.
// Declaring them again here would be an invalid redeclaration.
extension UserDefaults: SettingsStorage {}

/// Owns the single live `AppSettings` value.
///
/// Tack's pattern: one struct, one singleton, persisted to UserDefaults as
/// JSON, changes broadcast by notification. Keeping the state in a value type
/// and the plumbing here means the settings themselves stay trivially testable.
public final class Settings {
    public static let shared = Settings()

    static let storageKey = "com.pinyridgelabs.Zones.settings"

    private let storage: SettingsStorage
    private let notificationCenter: NotificationCenter
    private var value: AppSettings

    public init(storage: SettingsStorage = UserDefaults.standard,
                notificationCenter: NotificationCenter = .default) {
        self.storage = storage
        self.notificationCenter = notificationCenter
        self.value = Settings.load(from: storage)
    }

    /// The current settings. Assigning persists and broadcasts.
    public var current: AppSettings {
        get { value }
        set {
            guard newValue != value else { return }
            value = newValue
            persist()
            notificationCenter.post(name: .settingsDidChange, object: nil)
        }
    }

    /// Mutate in place; persists and broadcasts once, at the end.
    public func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = value
        mutate(&copy)
        current = copy
    }

    /// Discard everything and return to defaults.
    public func resetToDefaults() {
        current = AppSettings()
    }

    private static func load(from storage: SettingsStorage) -> AppSettings {
        guard let data = storage.data(forKey: storageKey) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            // Corrupt stored settings must not stop the app launching. Fall back
            // to defaults and say so; the next write replaces the bad data.
            ZonesLog.error("Zones", "settings unreadable, using defaults: \(error)")
            return AppSettings()
        }
    }

    private func persist() {
        do {
            storage.set(try JSONEncoder().encode(value) as Any?, forKey: Settings.storageKey)
        } catch {
            ZonesLog.error("Zones", "settings could not be written: \(error)")
        }
    }
}
