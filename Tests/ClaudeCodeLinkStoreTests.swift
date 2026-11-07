import Foundation

@main
@MainActor
struct ClaudeCodeLinkStoreTests {
    static func main() async throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]!)
        try FileManager.default.createDirectory(at: directory.appending(path: "projects/fixture"), withIntermediateDirectories: true)
        let id = UUID()
        let metadata = try JSONSerialization.data(withJSONObject: ["oauthAccount": ["accountUuid": id.uuidString, "emailAddress": "linked@example.com"]])
        try metadata.write(to: directory.appending(path: ".claude.json"))
        let now = Date.now
        let lines: [[String: Any]] = [
            ["type":"bridge-session", "sessionId":"fixture", "ownerAccountUuid":id.uuidString],
            ["type":"assistant", "sessionId":"fixture", "requestId":"request1", "timestamp":ISO8601DateFormatter().string(from: now),
             "message":["usage":["input_tokens":123, "output_tokens":45, "cache_read_input_tokens":6]]]
        ]
        let transcript = try lines.map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self) }.joined(separator: "\n")
        try Data((transcript + "\n").utf8).write(to: directory.appending(path: "projects/fixture/fixture.jsonl"))
        // This standalone test executable has its own UserDefaults domain, separate from the installed app.
        UserDefaults.standard.removeObject(forKey: "accounts")
        UserDefaults.standard.removeObject(forKey: "claudeCodeLogIdentities")
        let store = UsageStore()
        let account = Account(name: "linked@example.com", readings: [.init(observed: now, reset: now.addingTimeInterval(86400), percent: 10)])
        store.save(account)
        store.refreshLocalTokens(force: true)
        let rejected = await store.linkClaudeCode(for: account, expectedIDs: [UUID()])
        precondition(!rejected)
        let linked = await store.linkClaudeCode(for: account, expectedIDs: [id])
        precondition(linked)
        for _ in 0..<100 {
            if case .recorded = store.localTokenStatus(for: account) { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        guard case let .recorded(counts) = store.localTokenStatus(for: account) else { fatalError("Link did not trigger a token scan") }
        precondition(counts.total == 174)
        precondition((try? Data(contentsOf: directory.appending(path: ".claude.json"))) == metadata)
        let saved = UserDefaults.standard.dictionary(forKey: "claudeCodeLogIdentities") as? [String:String]
        precondition(saved?[id.uuidString] == "linked@example.com")
        print("Guided linking store passed changed-ID rejection, verified persistence, immediate/queued token scan and active-configuration preservation.")
    }
}
