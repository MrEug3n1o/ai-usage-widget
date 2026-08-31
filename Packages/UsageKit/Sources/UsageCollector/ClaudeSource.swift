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

extension ClaudeSource {
    /// A marker for the source's current contents, cheap enough to ask for on
    /// every poll: the Keychain item's modification date, or the credential
    /// file's. nil when the source cannot be looked at at all.
    ///
    /// The Keychain query is attributes-only and deliberately without
    /// kSecReturnData — metadata is not the secret, so asking for it never
    /// raises the permission dialog. Only `readKeychain` does.
    static func sourceVersion(_ profileDir: URL) -> String? {
        guard let (id, _) = profileSource(profileDir) else { return nil }
        if id.hasPrefix("file:") {
            let path = String(id.dropFirst("file:".count))
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            guard let date = attributes?[.modificationDate] as? Date else { return nil }
            return String(date.timeIntervalSince1970)
        }
        guard id.hasPrefix("keychain:") else { return nil }
        let service = String(id.dropFirst("keychain:".count))
        guard service.hasPrefix(keychainService) else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any],
              let date = attributes[kSecAttrModificationDate as String] as? Date
        else { return nil }
        return String(date.timeIntervalSince1970)
    }
}

/// Which version of its source each profile has already read this run.
///
/// A source-backed profile whose token expired stays expired until the CLI
/// refreshes it, and the poll loop comes back every minute. Without this the
/// app would read the source — and, for a Keychain source, ask for the login
/// password — once a minute for as long as the CLI stays unused. Gating on the
/// source's version means one read per thing there is to read, and a CLI
/// refresh bumps the version, so recovery still happens within one poll.
///
/// In memory on purpose: relaunching the app is then the way to retry a read
/// that was denied, rather than editing a state file.
actor AdoptionGate {
    static let shared = AdoptionGate()
    private var seen: [String: String] = [:]

    /// True when this profile's source is worth reading: it has not been read
    /// this run, or it has changed since. An unreadable version (nil) counts as
    /// a version of its own — a source we cannot even stat is one whose secret
    /// we would fail to read too.
    func shouldRead(profile: String, version: String?) -> Bool {
        let marker = version ?? "unknown"
        guard seen[profile] == marker else {
            seen[profile] = marker
            return true
        }
        return false
    }

    /// Test seam, and what an explicit re-registration should call.
    func forget(profile: String) { seen[profile] = nil }
}
