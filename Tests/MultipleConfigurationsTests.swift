import Foundation

enum Reading { static let week: TimeInterval = 7 * 86400 }

@main
struct MultipleConfigurationsTests {
    static func main() async throws {
        let files = FileManager.default
        let base = files.temporaryDirectory.resolvingSymlinksInPath().appending(path: UUID().uuidString)
        let a = base.appending(path: "A"), b = base.appending(path: "B")
        for root in [a, b] { try files.createDirectory(at: root.appending(path: "projects/fixture"), withIntermediateDirectories: true) }
        let owner = UUID(), otherOwner = UUID(), account = UUID(), otherAccount = UUID()
        func metadata(_ root: URL, _ id: UUID, _ email: String) throws {
            try JSONSerialization.data(withJSONObject: ["oauthAccount": ["accountUuid":id.uuidString, "emailAddress":email]])
                .write(to: root.appending(path: ".claude.json"))
        }
        try metadata(a, owner, "first@example.com")
        try metadata(b, otherOwner, "second@example.com")
        let now = Date.now
        func transcript(_ root: URL, _ session: String, _ id: UUID, _ input: Int, _ output: Int = 0) throws {
            let lines: [[String: Any]] = [
                ["type":"bridge-session", "sessionId":session, "ownerAccountUuid":id.uuidString],
                ["type":"assistant", "sessionId":session, "requestId":"shared-request", "timestamp":ISO8601DateFormatter().string(from: now),
                 "message":["usage":["input_tokens":input,"output_tokens":output]]]
            ]
            let text = try lines.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n") + "\n"
            try Data(text.utf8).write(to: root.appending(path: "projects/fixture/\(session).jsonl"))
        }
        try transcript(a, "one", owner, 10, 2)
        try transcript(b, "one", owner, 10, 2)
        try transcript(b, "two", owner, 30, 3)
        try transcript(b, "three", otherOwner, 200)
        let alias = base.appending(path: "alias")
        try files.createSymbolicLink(at: alias, withDestinationURL: a)
        precondition(ClaudeCodeConfigurations.unique([a, alias, a, b]) == [a,b])
        precondition(ClaudeCodeConfigurations.isSupported(a) && !ClaudeCodeConfigurations.isSupported(base))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set([a.path, alias.path, b.path], forKey: ClaudeCodeConfigurations.preferenceKey)
        precondition(ClaudeCodeConfigurations.directories(defaults: defaults).suffix(2) == [a,b])
        let identities = ClaudeCodeLinking.discover(configs: [a,b])
        precondition(identities.matching("second@example.com") == [otherOwner])
        let queries = [ClaudeCodeTokens.Query(id: account, email: "first@example.com", reset: now.addingTimeInterval(86400)),
                       ClaudeCodeTokens.Query(id: otherAccount, email: "second@example.com", reset: now.addingTimeInterval(86400))]
        let scanner = ClaudeCodeTokens()
        let first = await scanner.scan(for: queries, knownEmails: identities.identities, directories: [a,alias,b])
        precondition(first.totals[account]?.total == 45 && first.totals[otherAccount]?.total == 200)
        precondition(first.contributingDirectories[account] == [a,b])
        precondition(first.scannedDirectories == [a,b])
        let warm = await scanner.scan(for: queries, knownEmails: identities.identities, directories: [a,b])
        precondition(warm.totals[account]?.total == 45)
        try transcript(b, "one", owner, 20, 2)
        let larger = await scanner.scan(for: queries, knownEmails: identities.identities, directories: [a,b])
        precondition(larger.totals[account]?.total == 55 && larger.totals[account]?.output == 5)
        precondition(larger.contributingDirectories[account] == [b])
        try transcript(a, "conflict", owner, 50)
        try transcript(b, "conflict", otherOwner, 70)
        let conflict = await scanner.scan(for: queries, knownEmails: identities.identities, directories: [a,b])
        precondition(conflict.totals[account]?.total == 55 && conflict.totals[otherAccount]?.total == 200)
        let removed = await scanner.scan(for: queries, knownEmails: identities.identities, directories: [a])
        precondition(removed.totals[account]?.total == 62 && removed.totals[otherAccount] == nil)
        try metadata(b, owner, "other@example.com")
        let disputed = ClaudeCodeLinking.discover(configs: [a,b])
        precondition(disputed.conflictingIDs.contains(owner) && disputed.identities[owner] == nil)
        precondition(disputed.conflictingEmails == ["first@example.com", "other@example.com"])
        let missing = await scanner.scan(for: queries, knownEmails: identities.identities, directories: [base.appending(path: "missing")])
        precondition(missing.totals.isEmpty && missing.scannedDirectories.isEmpty)
        print("Multiple configurations passed selection validation, symlink deduplication, persistence, identity merging/conflicts, copied sessions, independent requests, winning-snapshot source attribution, warm-cache updates, removal and unavailable roots.")
    }
}
