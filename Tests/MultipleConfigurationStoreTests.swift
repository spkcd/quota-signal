import Foundation

@main
@MainActor
struct MultipleConfigurationStoreTests {
    static func main() async throws {
        let root = ClaudeCodeConfigurations.primary
        let extra = root.appending(path: "extra")
        for folder in [root, extra] { try FileManager.default.createDirectory(at: folder.appending(path: "projects/fixture"), withIntermediateDirectories: true) }
        let id = UUID(), now = Date.now
        let metadata = try JSONSerialization.data(withJSONObject: ["oauthAccount":["accountUuid":id.uuidString,"emailAddress":"sources@example.com"]])
        try metadata.write(to: root.appending(path: ".claude.json"))
        func write(_ folder: URL, session: String, tokens: Int) throws {
            let rows: [[String:Any]] = [
                ["type":"bridge-session","sessionId":session,"ownerAccountUuid":id.uuidString],
                ["type":"assistant","sessionId":session,"timestamp":ISO8601DateFormatter().string(from: now),"requestId":"request",
                 "message":["usage":["input_tokens":tokens]]]
            ]
            let text = try rows.map { String(decoding: try JSONSerialization.data(withJSONObject:$0),as:UTF8.self) }.joined(separator:"\n") + "\n"
            try Data(text.utf8).write(to:folder.appending(path:"projects/fixture/\(session).jsonl"))
        }
        try write(root,session:"one",tokens:11)
        try write(extra,session:"one",tokens:11)
        try write(extra,session:"two",tokens:7)
        for key in ["accounts","claudeCodeLogIdentities",ClaudeCodeConfigurations.preferenceKey] { UserDefaults.standard.removeObject(forKey:key) }
        let account = Account(name:"sources@example.com",readings:[.init(observed:now,reset:now.addingTimeInterval(86400),percent:10)])
        let store = UsageStore()
        store.save(account)
        store.refreshLocalTokens(force:true)
        func wait(_ store: UsageStore, total: Int64) async throws {
            for _ in 0..<200 {
                if case let .recorded(counts) = store.localTokenStatus(for:account), counts.total == total { return }
                try await Task.sleep(for:.milliseconds(20))
            }
            fatalError("Source selection did not rescan expected totals")
        }
        try await wait(store,total:11)
        precondition(!store.addTokenDirectories([root.appending(path:"missing")]))
        precondition(store.addTokenDirectories([extra,extra]))
        try await wait(store,total:18)
        precondition(store.localTokenDirectories.count == 2)
        precondition(store.contributingTokenDirectories[account.id]?.count == 2)
        let relaunched = UsageStore()
        precondition(relaunched.localTokenDirectories == store.localTokenDirectories)
        relaunched.refreshLocalTokens(force:true)
        try await wait(relaunched,total:18)
        relaunched.removeTokenDirectory(root)
        precondition(relaunched.localTokenDirectories.count == 2)
        relaunched.removeTokenDirectory(ClaudeCodeConfigurations.canonical(extra))
        try await wait(relaunched,total:11)
        precondition(relaunched.localTokenDirectories == [root])
        precondition((try? Data(contentsOf:root.appending(path:".claude.json"))) == metadata)
        print("Configuration store passed picker validation, duplicate additions, persistence/relaunch, forced rescans, contribution tracking, pinned primary, removal and unchanged authentication metadata.")
    }
}
