import Foundation

@main
struct ClaudeCodeLinkingTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appending(path: "backups"), withIntermediateDirectories: true)
        let first = UUID(), second = UUID(), conflict = UUID()
        func write(_ name: String, _ id: UUID, _ email: String) throws {
            let data = try JSONSerialization.data(withJSONObject: ["oauthAccount": ["accountUuid": id.uuidString, "emailAddress": email]])
            try data.write(to: directory.appending(path: name))
        }
        try write(".claude.json", first, "First@Example.com")
        try write("backups/.claude.json.backup-1", second, "second@example.com")
        let before = try Data(contentsOf: directory.appending(path: ".claude.json"))
        let found = ClaudeCodeLinking.discover(config: directory)
        precondition(found.matching("FIRST@example.com") == [first])
        precondition(found.matching("second@example.com") == [second])
        precondition(found.matching("missing@example.com").isEmpty)
        precondition((try? Data(contentsOf: directory.appending(path: ".claude.json"))) == before)
        try write("backups/.claude.json.backup-2", conflict, "first@example.com")
        try write("backups/.claude.json.backup-3", conflict, "other@example.com")
        let rejected = ClaudeCodeLinking.discover(config: directory)
        precondition(rejected.conflictingIDs == [conflict] && rejected.identities[conflict] == nil)
        try Data("broken".utf8).write(to: directory.appending(path: "backups/.claude.json.broken"))
        precondition(ClaudeCodeLinking.discover(config: directory).matching("first@example.com") == [first])
        // Shell quoting protects both the executable path and email. Merely preparing a command runs nothing.
        let command = ClaudeCodeLinking.loginCommand(email: "o'neil@example.com", executable: URL(fileURLWithPath: "/tmp/Claude Code/claude"))
        precondition(command.contains("'/tmp/Claude Code/claude' auth login --claudeai --email 'o'\\''neil@example.com'"))
        precondition((try? Data(contentsOf: directory.appending(path: ".claude.json"))) == before)
        print("Guided linking passed current/backups discovery, email targeting, missing and conflicting IDs, malformed metadata, shell quoting and unchanged active configuration.")
    }
}
