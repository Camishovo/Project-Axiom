import CryptoKit
import Security
import Foundation

/// Manages a stable Ed25519 keypair for device authentication.
/// The private key is stored in the Keychain and reused across sessions.
struct DeviceIdentity {
    let id: String                       // SHA256 hex of public key raw bytes
    let publicKeyBase64: String          // Standard base64 of raw public key (32 bytes)
    let privateKey: Curve25519.Signing.PrivateKey

    // MARK: - Load or Generate

    static func load() -> DeviceIdentity {
        if let existing = loadFromKeychain() {
            return existing
        }
        let new = generate()
        saveToKeychain(new.privateKey)
        return new
    }

    // MARK: - Signing

    /// Signs a UTF-8 string payload with Ed25519. Returns base64url-encoded signature (no padding).
    func sign(payload: String) -> String? {
        guard let data = payload.data(using: .utf8) else { return nil }
        guard let signature = try? privateKey.signature(for: data) else { return nil }
        return Data(signature).base64urlEncoded()
    }

    // MARK: - Private helpers

    private static func generate() -> DeviceIdentity {
        let key = Curve25519.Signing.PrivateKey()
        return makeIdentity(from: key)
    }

    private static func makeIdentity(from key: Curve25519.Signing.PrivateKey) -> DeviceIdentity {
        let pubKeyData = key.publicKey.rawRepresentation      // 32 bytes
        let idHex = SHA256.hash(data: pubKeyData).hexString
        let pubBase64 = pubKeyData.base64EncodedString()
        return DeviceIdentity(id: idHex, publicKeyBase64: pubBase64, privateKey: key)
    }

    private static func loadFromKeychain() -> DeviceIdentity? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      "com.axiom.devicekey",
            kSecAttrAccount as String:      "ed25519-private",
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
        else { return nil }
        return makeIdentity(from: key)
    }

    private static func saveToKeychain(_ key: Curve25519.Signing.PrivateKey) {
        let data = key.rawRepresentation
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: "com.axiom.devicekey",
            kSecAttrAccount as String: "ed25519-private"
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          "com.axiom.devicekey",
            kSecAttrAccount as String:          "ed25519-private",
            kSecValueData as String:            data,
            kSecAttrAccessible as String:       kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrIsSynchronizable as String: false
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

// MARK: - Helpers

private extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    /// Base64url encoding: replace +/- , //_  strip = padding
    func base64urlEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}
