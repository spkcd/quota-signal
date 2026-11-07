import Foundation

@main
@MainActor
struct TokenCoverageStoreTests {
    static func main() async throws {
        let manager = FileManager.default
        let root = ClaudeCodeConfigurations.primary
        let projects = root.appending(path:"projects")
        try manager.createDirectory(at:projects,withIntermediateDirectories:true)
        for key in ["accounts","claudeCodeLogIdentities",ClaudeCodeConfigurations.preferenceKey] { UserDefaults.standard.removeObject(forKey:key) }
        let store = UsageStore(), owner = UUID(), now = Date.now
        let account = Account(name:"coverage@example.com",readings:[.init(observed:now,reset:now.addingTimeInterval(86400),percent:10)])
        store.save(account)
        if case .checking = store.localTokenStatus(for:account) {} else { fatalError("Initial status must be checking") }
        func rescan() async throws {
            store.refreshLocalTokens(force:true)
            for _ in 0..<200 {
                if !store.localTokenScanInProgress && store.localTokenScanCompletedAt != nil { return }
                try await Task.sleep(for:.milliseconds(20))
            }
            fatalError("Scan did not complete")
        }
        try await rescan()
        if case .needsID = store.localTokenStatus(for:account) {} else { fatalError("Missing ID mislabeled") }
        precondition(store.tokenCoverageExplanation(for:account).contains("Link Claude Code"))
        let metadata = try JSONSerialization.data(withJSONObject:["oauthAccount":["accountUuid":owner.uuidString,"emailAddress":account.name]])
        try metadata.write(to:root.appending(path:".claude.json"))
        try await rescan()
        if case .noLogs = store.localTokenStatus(for:account) {} else { fatalError("Empty linked logs mislabeled") }
        try manager.setAttributes([.posixPermissions:0],ofItemAtPath:projects.path)
        defer { try? manager.setAttributes([.posixPermissions:0o700],ofItemAtPath:projects.path) }
        try await rescan()
        if case .inaccessible = store.localTokenStatus(for:account) {} else { fatalError("Unreadable folder mislabeled") }
        try manager.setAttributes([.posixPermissions:0o700],ofItemAtPath:projects.path)
        func transcript(_ session:String, _ id:UUID) throws -> URL {
            let rows:[[String:Any]] = [
                ["type":"bridge-session","sessionId":session,"ownerAccountUuid":id.uuidString],
                ["type":"assistant","sessionId":session,"timestamp":ISO8601DateFormatter().string(from:now),"requestId":"request",
                 "message":["usage":["input_tokens":11,"output_tokens":2,"cache_read_input_tokens":30,"cache_creation_input_tokens":4]]]
            ]
            let text = try rows.map { String(decoding:try JSONSerialization.data(withJSONObject:$0),as:UTF8.self) }.joined(separator:"\n") + "\n"
            let url = projects.appending(path:session + ".jsonl")
            try Data(text.utf8).write(to:url)
            return url
        }
        let valid = try transcript("valid",owner)
        _ = try transcript("unknown",UUID())
        try await rescan()
        if case let .partial(counts) = store.localTokenStatus(for:account) { precondition(counts.total == 47 && counts.cacheRead == 30 && counts.cacheWrite == 4) }
        else { fatalError("Partial counts not retained") }
        precondition(store.tokenCoverageExplanation(for:account).contains("excluded"))
        try manager.removeItem(at:valid)
        try await rescan()
        if case .ownershipUnknown = store.localTokenStatus(for:account) {} else { fatalError("Unverified ownership mislabeled") }
        let duplicate = Account(name:account.name,readings:account.readings)
        store.save(duplicate)
        try await rescan()
        if case .ambiguous = store.localTokenStatus(for:account) {} else { fatalError("Duplicate account ambiguity lost") }
        print("Coverage store passed checking, unlinked, no eligible logs, inaccessible folders, partial totals/cache breakdown, unverified ownership and duplicate-account ambiguity.")
    }
}
