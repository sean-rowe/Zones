import Foundation

/// The `zones://activate?key=…` link the thanks page offers, so the Mac that
/// just bought a license never has to retype it.
public enum LicenseURL {
    /// The key an activate link carries, or nil for anything else.
    public static func activationKey(from url: URL) -> String? {
        // The path has to be empty: `zones://activate/anything?key=` is not a
        // link this app publishes, and accepting it widens what a handler for
        // this scheme can be talked into doing.
        guard url.scheme?.lowercased() == "zones",
              url.host?.lowercased() == "activate",
              url.path.isEmpty || url.path == "/",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let key = items.first(where: { $0.name == "key" })?.value
        else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return looksLikeLicenseKey(trimmed) ? trimmed : nil
    }

    /// Whether a string has the shape of a Zones key. Pasteboard pre-fill uses
    /// this too — clipboard junk must never land in the field.
    public static func looksLikeLicenseKey(_ candidate: String) -> Bool {
        candidate.range(of: #"^ZONE[S]?(-[A-HJ-NP-Z2-9]{4}){3}$"#,
                        options: .regularExpression) != nil
    }
}
