import Foundation
import Security

/// Where an install stands with us.
public enum LicenseState: Equatable, Sendable {
    case trial(daysRemaining: Int)
    case trialExpired
    case licensed
}

/// The fourteen-day clock, and the one question the rest of the app asks:
/// may this install snap windows right now?
public final class TrialManager {
    public static let shared = TrialManager()

    public static let trialLengthDays = 14
    public static let defaultsKey = "ZonesTrialAnchor"
    public static let daysUsedKey = "ZonesTrialDaysUsed"
    public static let keychainService = "com.pinyridgelabs.Zones"
    public static let keychainAccount = "trial-anchor"

    /// Seams: tests script the clock, the stores and the license check.
    public var now: () -> Date = { Date() }
    public var defaults: UserDefaults = .standard

    public lazy var readKeychainAnchor: () -> Date? = {
        guard NSClassFromString("XCTestCase") == nil else { return nil }
        return Self.keychainRead()
    }
    public lazy var writeKeychainAnchor: (Date) -> Void = { date in
        guard NSClassFromString("XCTestCase") == nil else { return }
        Self.keychainWrite(date)
    }

    /// Answered by the license store's remembered activation.
    public var isLicensed: () -> Bool = { LicenseStore.shared.isActivated }

    public init() {}

    /// The current state, establishing the anchor on first use.
    public var state: LicenseState {
        if isLicensed() { return .licensed }
        let anchor = establishedAnchor()
        let counted = max(0, Calendar.current.dateComponents([.day], from: anchor, to: now()).day ?? 0)
        let used = daysUsed(atLeast: counted)
        let remaining = Self.trialLengthDays - used
        return remaining > 0 ? .trial(daysRemaining: remaining) : .trialExpired
    }

    /// Trial days spent: the count just made, or the highest ever recorded,
    /// whichever is larger. Reading it records it.
    private func daysUsed(atLeast counted: Int) -> Int {
        let recorded = defaults.integer(forKey: Self.daysUsedKey)
        let used = max(recorded, counted)
        if used != recorded { defaults.set(used, forKey: Self.daysUsedKey) }
        return used
    }

    /// The one gate: snapping works while the trial runs or a license holds.
    public var canSnap: Bool {
        switch state {
        case .trial, .licensed: return true
        case .trialExpired: return false
        }
    }

    /// The line the status menu shows, when there is something to say.
    public var menuLine: String? {
        switch state {
        case .trial(let days):
            if days == 1 { return "Trial ends tomorrow — Buy Zones…" }
            if days <= 3 { return "Trial: \(days) days left — Buy Zones…" }
            return "Trial: \(days) days left"
        case .trialExpired:
            return "Trial expired — Buy Zones…"
        case .licensed:
            return nil
        }
    }

    /// The anchor, reading keychain first (it survives reinstalls), then
    /// defaults, creating it on a genuinely fresh machine. The older copy
    /// wins, and both stores end up carrying it.
    private func establishedAnchor() -> Date {
        let keychain = readKeychainAnchor()
        let defaultsDate = defaults.object(forKey: Self.defaultsKey) as? Date

        let anchor: Date
        switch (keychain, defaultsDate) {
        case let (.some(k), .some(d)):
            anchor = min(k, d)
        case let (.some(k), .none):
            anchor = k
        case let (.none, .some(d)):
            anchor = d
        case (.none, .none):
            anchor = now()
        }

        if defaultsDate != anchor { defaults.set(anchor, forKey: Self.defaultsKey) }
        if keychain != anchor { writeKeychainAnchor(anchor) }
        return anchor
    }

    // MARK: - Keychain

    private static func keychainRead() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let interval = try? JSONDecoder().decode(TimeInterval.self, from: data) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    private static func keychainWrite(_ date: Date) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard let data = try? JSONEncoder().encode(date.timeIntervalSince1970) else { return }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
