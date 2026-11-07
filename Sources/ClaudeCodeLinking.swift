import Foundation

enum ClaudeCodeLinking {
    struct Discovery: Sendable {
        let identities: [UUID: String]
        let conflictingIDs: Set<UUID>
        func matching(_ email: String) -> [UUID] {
            identities.filter { $0.value == email.lowercased() }.keys.sorted { $0.uuidString < $1.uuidString }
        }
    }

    static func discover(config: URL? = nil) -> Discovery {
        struct Metadata: Decodable {
            struct Identity: Decodable { let accountUuid: UUID; let emailAddress: String }
            let oauthAccount: Identity?
        }
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let directory = config ?? override ?? home.appending(path: ".claude", directoryHint: .isDirectory)
        let isDefault = override == nil && ClaudeCodeConfigurations.canonical(directory) == ClaudeCodeConfigurations.canonical(home.appending(path: ".claude"))
        let current = isDefault ? home.appending(path: ".claude.json") : directory.appending(path: ".claude.json")
        let backups = (try? files.contentsOfDirectory(at: directory.appending(path: "backups"), includingPropertiesForKeys: nil)) ?? []
        var owners: [UUID: Set<String>] = [:]
        for url in backups.filter({ $0.lastPathComponent.hasPrefix(".claude.json") }) + [current] {
            guard let data = try? Data(contentsOf: url),
                  let account = try? JSONDecoder().decode(Metadata.self, from: data).oauthAccount else { continue }
            let email = account.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard email.contains("@"), !email.contains(where: { $0.isWhitespace }), email.count <= 254 else { continue }
            owners[account.accountUuid, default: []].insert(email)
        }
        return Discovery(identities: owners.compactMapValues { $0.count == 1 ? $0.first : nil },
                         conflictingIDs: Set(owners.filter { $0.value.count != 1 }.keys))
    }

    static func discover(configs: [URL]) -> Discovery {
        var owners: [UUID: Set<String>] = [:]
        var conflicts = Set<UUID>()
        for root in ClaudeCodeConfigurations.unique(configs) {
            let found = discover(config: root)
            conflicts.formUnion(found.conflictingIDs)
            for (id, email) in found.identities { owners[id, default: []].insert(email) }
        }
        conflicts.formUnion(owners.filter { $0.value.count > 1 }.keys)
        return Discovery(identities: owners.compactMapValues { $0.count == 1 ? $0.first : nil }.filter { !conflicts.contains($0.key) },
                         conflictingIDs: conflicts)
    }

    static func loginCommand(email: String, executable: URL) -> String {
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        let environment = config.map { "/usr/bin/env " + quote("CLAUDE_CONFIG_DIR=" + $0) }
            ?? "/usr/bin/env -u CLAUDE_CONFIG_DIR"
        return environment + " " + quote(executable.path) + " auth login --claudeai --email " + quote(email)
    }
}
