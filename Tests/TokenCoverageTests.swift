import Foundation

enum Reading { static let week: TimeInterval = 7 * 86400 }

@main
struct TokenCoverageTests {
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appending(path: UUID().uuidString)
        let projects = root.appending(path: "projects")
        try manager.createDirectory(at: projects, withIntermediateDirectories: true)
        let rootURL = ClaudeCodeConfigurations.canonical(root)
        let owner = UUID(), unknown = UUID(), account = UUID(), now = Date.now
        let query = ClaudeCodeTokens.Query(id: account, email: "coverage@example.com", reset: now.addingTimeInterval(86400))
        let scanner = ClaudeCodeTokens()
        func scan(_ directories: [URL] = [rootURL]) async -> ClaudeCodeTokens.ScanResult {
            await scanner.scan(for: [query], knownEmails: [owner: "coverage@example.com"], directories: directories)
        }
        let empty = await scan()
        precondition(empty.totals.isEmpty && !empty.coverage.isPartial && empty.coverage.directories[rootURL]?.access == .scanned)
        let missing = root.appending(path: "missing")
        let inaccessible = await scan([missing])
        precondition(inaccessible.coverage.hasUnavailable && !inaccessible.coverage.hasUnverifiedOwnership)
        let noProjects = root.appending(path: "empty-config")
        try manager.createDirectory(at: noProjects, withIntermediateDirectories: true)
        let noLogs = await scan([noProjects])
        precondition(!noLogs.coverage.isPartial && noLogs.coverage.directories[ClaudeCodeConfigurations.canonical(noProjects)]?.access == .noProjects)
        func write(_ session: String, owner id: UUID?, secondOwner: UUID? = nil) throws -> URL {
            var rows: [[String:Any]] = []
            if let id { rows.append(["type":"bridge-session","sessionId":session,"ownerAccountUuid":id.uuidString]) }
            if let secondOwner { rows.append(["type":"bridge-session","sessionId":session,"ownerAccountUuid":secondOwner.uuidString]) }
            rows.append(["type":"assistant","sessionId":session,"requestId":"request", "timestamp":ISO8601DateFormatter().string(from: now),
                         "message":["usage":["input_tokens":11,"output_tokens":2,"cache_read_input_tokens":30,"cache_creation_input_tokens":4]]])
            let text = try rows.map { String(decoding: try JSONSerialization.data(withJSONObject:$0), as:UTF8.self) }.joined(separator:"\n") + "\n"
            let url = projects.appending(path: session + ".jsonl")
            try Data(text.utf8).write(to:url)
            return url
        }
        let valid = try write("valid", owner:owner)
        let full = await scan()
        precondition(full.totals[account]?.total == 47 && !full.coverage.isPartial)
        precondition(full.totals[account]?.cacheRead == 30 && full.totals[account]?.cacheWrite == 4)
        let missingOwner = try write("unowned", owner:nil)
        _ = try write("unknown", owner:unknown)
        _ = try write("conflict", owner:owner, secondOwner:unknown)
        let ambiguous = await scan()
        precondition(ambiguous.coverage.hasUnverifiedOwnership && ambiguous.totals[account]?.total == 47)
        precondition(ambiguous.coverage.directories[rootURL]?.unverifiedLogs == 3)
        // Permission revocation must be noticed even after the file was cached successfully.
        try manager.setAttributes([.posixPermissions:0], ofItemAtPath:valid.path)
        defer { try? manager.setAttributes([.posixPermissions:0o600], ofItemAtPath:valid.path) }
        let blockedFile = await scan()
        precondition(blockedFile.coverage.hasUnavailable && blockedFile.coverage.directories[rootURL]?.access == .partial)
        precondition(blockedFile.totals[account] == nil)
        try manager.setAttributes([.posixPermissions:0o600], ofItemAtPath:valid.path)
        let restored = await scan()
        precondition(!restored.coverage.hasUnavailable && restored.totals[account]?.total == 47)
        try manager.setAttributes([.posixPermissions:0], ofItemAtPath:projects.path)
        defer { try? manager.setAttributes([.posixPermissions:0o700], ofItemAtPath:projects.path) }
        let blockedFolder = await scan()
        precondition(blockedFolder.coverage.hasUnavailable && blockedFolder.totals.isEmpty)
        precondition(!restored.coverage.explanation.contains(missingOwner.path))
        print("Token coverage passed clean/empty scans, missing/empty folders, missing/unknown/conflicting ownership, partial totals, explicit cache breakdown, cached-file permission revocation and recovery.")
    }
}
