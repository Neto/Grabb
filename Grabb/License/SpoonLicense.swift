import AppKit
import CryptoKit
import Foundation
import Observation
import Security

// Shared by Spin and Grabb. Keep both copies identical.
//
// Trial: the first launch date is kept in the Keychain (it survives reinstalling the app)
// and in UserDefaults. The earlier of the two counts. After `trialDays` the app is locked
// until a license is entered.
//
// License key: "SPOON1.<payload>.<signature>", both parts base64url without padding.
// The payload is JSON {"p": "spin" | "grabb" | "bundle", "e": email, "s": Stripe session, "t": unix time}.
// The license server signs it with Ed25519. The app checks the signature with the public key
// below, with no network call. "bundle" unlocks both apps.

@MainActor
@Observable
final class SpoonLicense {
    enum State: Equatable {
        case trial(daysLeft: Int)
        case expired
        case licensed(email: String)
    }

    static let trialDays = 7
    nonisolated static let publicKey = "N+cxQxngr+z56m2dgCpbzfDu/paxf0d1eJarUltX/wU="
    nonisolated static let supportEmail = "support@spoon.com.br"

    /// "spin" or "grabb".
    let product: String
    /// The Stripe Payment Link for this app.
    let buyURL: URL
    let displayName: String

    private(set) var state: State = .expired
    /// Set when an entered key fails, shown under the key field.
    var activationError: String?

    private let service = "br.com.spoon.license"
    private var trialAccount: String { "trial-\(product)" }
    private var keyAccount: String { "key-\(product)" }
    private var defaultsKey: String { "SpoonTrialStart" }

    init(product: String, displayName: String, buyURL: URL) {
        self.product = product
        self.displayName = displayName
        self.buyURL = buyURL
        refresh()
    }

    var isUnlocked: Bool {
        if case .expired = state { return false }
        return true
    }

    var isLicensed: Bool {
        if case .licensed = state { return true }
        return false
    }

    /// A short status line for menus and banners.
    var statusText: String {
        switch state {
        case .trial(let days):
            return days == 1 ? "Free trial: 1 day left" : "Free trial: \(days) days left"
        case .expired:
            return "Your free trial has ended"
        case .licensed(let email):
            return email.isEmpty ? "Licensed" : "Licensed to \(email)"
        }
    }

    func refresh() {
        if let key = Self.keychainRead(service: service, account: keyAccount),
           let email = Self.verify(key: key, product: product) {
            state = .licensed(email: email)
            return
        }
        let start = trialStart()
        let elapsed = Date().timeIntervalSince(start)
        let daysUsed = Int(floor(max(0, elapsed) / 86_400))
        let left = Self.trialDays - daysUsed
        state = left > 0 ? .trial(daysLeft: left) : .expired
    }

    /// Checks and stores a key. Returns true when the app is now unlocked.
    @discardableResult
    func activate(key raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let email = Self.verify(key: key, product: product) else {
            activationError = "This key is not valid for \(displayName). Copy the whole key, starting with SPOON1."
            return false
        }
        Self.keychainWrite(key, service: service, account: keyAccount)
        activationError = nil
        state = .licensed(email: email)
        return true
    }

    /// Handles spin://activate?key=… and grabb://activate?key=…
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.host() == "activate",
              let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "key" })?.value
        else { return false }
        return activate(key: key)
    }

    func buy() {
        NSWorkspace.shared.open(buyURL)
    }

    func contactSupport() {
        if let url = URL(string: "mailto:\(Self.supportEmail)?subject=\(displayName)%20license") {
            NSWorkspace.shared.open(url)
        }
    }

    #if DEBUG
    /// Test hook: moves the trial start back by the given number of days.
    func debugShiftTrial(days: Int) {
        let start = Date().addingTimeInterval(-Double(days) * 86_400)
        Self.keychainWrite(ISO8601DateFormatter().string(from: start), service: service, account: trialAccount)
        UserDefaults.standard.set(start, forKey: defaultsKey)
        Self.keychainDelete(service: service, account: keyAccount)
        refresh()
    }
    #endif

    // MARK: Trial start

    private func trialStart() -> Date {
        let formatter = ISO8601DateFormatter()
        let fromKeychain = Self.keychainRead(service: service, account: trialAccount).flatMap { formatter.date(from: $0) }
        let fromDefaults = UserDefaults.standard.object(forKey: defaultsKey) as? Date
        let start = [fromKeychain, fromDefaults].compactMap { $0 }.min() ?? Date()
        if fromKeychain == nil {
            Self.keychainWrite(formatter.string(from: start), service: service, account: trialAccount)
        }
        if fromDefaults == nil {
            UserDefaults.standard.set(start, forKey: defaultsKey)
        }
        return start
    }

    // MARK: Key check

    /// Returns the buyer's email when the key is valid for this product.
    nonisolated static func verify(key: String, product: String) -> String? {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "SPOON1",
              let payload = base64URLDecode(String(parts[1])),
              let signature = base64URLDecode(String(parts[2])),
              let publicData = Data(base64Encoded: publicKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData),
              publicKey.isValidSignature(signature, for: Data(parts[1].utf8)),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let licensed = json["p"] as? String,
              licensed == product || licensed == "bundle"
        else { return nil }
        return json["e"] as? String ?? ""
    }

    nonisolated static func base64URLDecode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    // MARK: Keychain

    nonisolated private static func keychainRead(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func keychainWrite(_ value: String, service: String, account: String) {
        keychainDelete(service: service, account: account)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Spoon Software license",
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    nonisolated private static func keychainDelete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
