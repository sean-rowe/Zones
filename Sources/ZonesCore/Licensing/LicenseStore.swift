import Foundation
import Security

/// Where Zones sells. Checkout runs through Stripe; licensing runs through
/// our own server on the same domain as the update feed.
public enum ZonesStoreConfig {
    public static let checkoutURL: URL? = URL(string: "https://zones.pinyridgelabs.com/#pricing")
    public static let appcastURL: URL? = URL(string: "https://zones.pinyridgelabs.com/appcast.xml")
    public static let apiBase: URL = URL(string: "https://zones.pinyridgelabs.com/api/licenses")!
}

/// Talks to Zones's license server and remembers the answer.
///
/// Activation happens once, online, and writes the key and the instance id
/// to the keychain. After that the install is licensed on the cached
/// activation; revalidation runs opportunistically and only an explicit
/// answer from the server — valid or not — changes anything. No network, no
/// change: a laptop on a plane keeps its license.
public final class LicenseStore {
    public static let shared = LicenseStore()

    public struct Activation: Codable, Equatable, Sendable {
        public let key: String
        public let instanceID: String

        public init(key: String, instanceID: String) {
            self.key = key
            self.instanceID = instanceID
        }
    }

    public enum ActivationError: Error, Equatable, Sendable {
        case refused(reason: String)
        case unreachable
    }

    public static let keychainService = "com.pinyridgelabs.Zones"
    public static let keychainAccount = "license-activation"
    public static let apiBase = ZonesStoreConfig.apiBase

    /// Seams: tests script the network and the keychain.
    public lazy var transport: (URLRequest, @escaping (Data?, Error?) -> Void) -> Void = { request, completion in
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async { completion(data, error) }
        }.resume()
    }

    public lazy var readActivation: () -> Activation? = {
        guard NSClassFromString("XCTestCase") == nil else { return nil }
        return Self.keychainReadActivation()
    }

    public lazy var writeActivation: (Activation?) -> Void = { activation in
        guard NSClassFromString("XCTestCase") == nil else { return }
        Self.keychainWriteActivation(activation)
    }

    /// The one answer the trial gate needs.
    public var isActivated: Bool { readActivation() != nil }

    public init() {}

    /// Activate a key against the server and remember the instance.
    public func activate(key: String, completion: @escaping (Result<Void, ActivationError>) -> Void) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LicenseURL.looksLikeLicenseKey(trimmed) || !trimmed.isEmpty else {
            completion(.failure(.refused(reason: "Invalid license key format")))
            return
        }

        request("activate", body: [
            "license_key": trimmed,
            "instance_name": Host.current().localizedName ?? "Mac",
            "instance_id": Self.machineIdentifier(),
        ]) { [weak self] json in
            guard let self = self else { return }
            guard let json = json else {
                completion(.failure(.unreachable))
                return
            }
            guard (json["activated"] as? Bool) == true,
                  let instance = json["instance"] as? [String: Any],
                  let instanceID = instance["id"] as? String else {
                let reason = json["error"] as? String ?? "the store refused this key"
                completion(.failure(.refused(reason: reason)))
                return
            }
            self.writeActivation(Activation(key: trimmed, instanceID: instanceID))
            completion(.success(()))
        }
    }

    /// Revalidate the remembered activation when the store can be reached.
    /// Only an explicit verdict changes anything; silence keeps the cache.
    public func revalidateRemembered(completion: @escaping (Bool) -> Void = { _ in }) {
        guard let activation = readActivation() else {
            completion(false)
            return
        }
        request("validate", body: [
            "license_key": activation.key,
            "instance_id": activation.instanceID,
        ]) { [weak self] json in
            guard let json = json, let valid = json["valid"] as? Bool else {
                // Unreachable — the cached activation stands.
                completion(true)
                return
            }
            if !valid {
                self?.writeActivation(nil)
            }
            completion(valid)
        }
    }

    /// Deactivate on this machine so the seat can be used elsewhere.
    public func deactivate(completion: @escaping (Bool) -> Void = { _ in }) {
        guard let activation = readActivation() else {
            completion(true)
            return
        }
        request("deactivate", body: [
            "license_key": activation.key,
            "instance_id": activation.instanceID,
        ]) { [weak self] json in
            self?.writeActivation(nil)
            completion((json?["deactivated"] as? Bool) ?? true)
        }
    }

    // MARK: - HTTP

    private func request(_ path: String, body: [String: Any],
                         completion: @escaping ([String: Any]?) -> Void) {
        var req = URLRequest(url: Self.apiBase.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        transport(req) { data, error in
            guard error == nil, let data = data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            completion(object)
        }
    }

    // MARK: - Machine identity

    public static func machineIdentifier() -> String {
        var host = mach_header_64()
        var size = mach_msg_type_number_t(MemoryLayout<mach_header_64>.size)
        // Stable per-machine identifier fallback using IOPlatformUUID if available
        let dev = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if dev != 0 {
            defer { IOObjectRelease(dev) }
            if let uuid = IORegistryEntryCreateCFProperty(dev, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String {
                return uuid
            }
        }
        return UUID().uuidString
    }

    // MARK: - Keychain

    private static func keychainReadActivation() -> Activation? {
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
              let activation = try? JSONDecoder().decode(Activation.self, from: data) else {
            return nil
        }
        return activation
    }

    private static func keychainWriteActivation(_ activation: Activation?) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard let activation = activation,
              let data = try? JSONEncoder().encode(activation) else { return }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
