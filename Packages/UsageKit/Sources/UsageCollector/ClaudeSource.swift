import Foundation
import CryptoKit
import Security

/// Where a profile's credential was copied from.
///
/// A profile registered from an existing Claude Code login is a *copy* of a
/// session the CLI still owns. Recording the origin is what lets a copy the CLI
/// has rotated past be re-synced instead of registered again by hand — see
/// `Claude.ensureFresh`, which is the whole reason this file exists.
enum ClaudeSource {
    static let sourceFile = "source.json"
    static let keychainService = "Claude Code-credentials"

    /// The (source id, account) recorded at registration. Profiles from
    /// `claude-login` own their login and record none, keeping the plain
    /// snapshot behavior.
    static func profileSource(_ profileDir: URL) -> (id: String, email: String)? {
        guard let record = try? Config.readJSON(profileDir.appendingPathComponent(sourceFile))
                as? [String: Any],
              let id = record.string("source"), !id.isEmpty
        else { return nil }
        return (id, record.string("email") ?? "")
    }

    /// The suffix Claude Code gives a CLAUDE_CONFIG_DIR's Keychain service.
    static func keychainHash(_ dir: URL) -> String {
        SHA256.hash(data: Data(dir.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(8)
            .lowercased()
    }

    static func keychainService(for dir: URL) -> String {
        dir.path == Config.home.appendingPathComponent(".claude").path
            ? keychainService
            : "\(keychainService)-\(keychainHash(dir))"
    }

    /// `~/.claude*` directories, whether or not they hold a credential file —
    /// a Keychain-only config dir has none.
    static func claudeDirs() -> [URL] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: Config.home, includingPropertiesForKeys: [.isDirectoryKey],
            options: [])) ?? []
        return entries
            .filter { $0.lastPathComponent.hasPrefix(".claude") }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.path < $1.path }
    }

    /// The Claude Code config dir a source id belongs to, for the account check.
    static func sourceConfigDir(_ id: String) -> URL? {
        if id.hasPrefix("file:") {
            return URL(fileURLWithPath: String(id.dropFirst("file:".count)))
                .deletingLastPathComponent()
        }
        guard id.hasPrefix("keychain:") else { return nil }
        let service = String(id.dropFirst("keychain:".count))
        if service == keychainService { return Config.home.appendingPathComponent(".claude") }
        let prefix = keychainService + "-"
        guard service.hasPrefix(prefix) else { return nil }
        let suffix = String(service.dropFirst(prefix.count))
        return claudeDirs().first { keychainHash($0) == suffix }
    }

    /// The account a config dir is logged into, from its `.claude.json` — which
    /// sits inside a custom CLAUDE_CONFIG_DIR but next to `~/.claude` for the
    /// default. Metadata only; no credential is touched.
    static func dirActiveEmail(_ dir: URL) -> String {
        let config = dir.path == Config.home.appendingPathComponent(".claude").path
            ? Config.home.appendingPathComponent(".claude.json")
            : dir.appendingPathComponent(".claude.json")
        guard let data = try? Config.readJSON(config) as? [String: Any] else { return "" }
        return data.dict("oauthAccount")?.string("emailAddress") ?? ""
    }

    /// The source's live credential, or nil when there is no source, it cannot
    /// be read, or it has since been logged into a *different* account —
    /// without that identity check a profile could silently change owner.
    static func credential(for profileDir: URL) -> [String: Any]? {
        guard let (id, expected) = profileSource(profileDir) else { return nil }
        if !expected.isEmpty, let dir = sourceConfigDir(id) {
            let current = dirActiveEmail(dir)
            if !current.isEmpty, current.caseInsensitiveCompare(expected) != .orderedSame {
                return nil
            }
        }
        guard let data = try? read(id),
              let oauth = data.dict("claudeAiOauth"),
              oauth.string("accessToken") != nil,
              oauth.string("refreshToken") != nil
        else { return nil }
        return data
    }

    static func read(_ id: String) throws -> [String: Any] {
        if id.hasPrefix("file:") {
            let path = URL(fileURLWithPath: String(id.dropFirst("file:".count)))
            guard let data = try Config.readJSON(path) as? [String: Any] else {
                throw SimpleError("unreadable credential file")
            }
            return data
        }
        guard id.hasPrefix("keychain:") else { throw SimpleError("unknown source: \(id)") }
        let service = String(id.dropFirst("keychain:".count))
        guard service.hasPrefix(keychainService) else {
            throw SimpleError("unexpected keychain service")
        }
        return try readKeychain(service: service)
    }

    /// Reads the secret through the Security framework rather than shelling out
    /// to `security find-generic-password`. Same macOS permission prompt, but
    /// it is attributed to this app and there is no subprocess.
    static func readKeychain(service: String) throws -> [String: Any] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw SimpleError("Keychain read failed or was denied")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimpleError("Keychain item is not a Claude credential")
        }
        return object
    }
}
