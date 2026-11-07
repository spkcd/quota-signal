import Foundation

enum Reading { static let week: TimeInterval = 7 * 86400 }

@main
struct ScanPerformanceTests {
    static func main() async throws {
        precondition(ClaudeCodeTokens.Limits().maxBytesRead == 2 * 1024 * 1024 * 1024)
        precondition(ClaudeCodeTokens.Limits().maxFileBytes == 512 * 1024 * 1024)
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: UUID().uuidString)
        let projects = root.appending(path:"projects")
        try files.createDirectory(at: projects, withIntermediateDirectories:true)
        let owner = UUID(), id = UUID(), now = Date.now
        let query = ClaudeCodeTokens.Query(id:id,email:"performance@example.com",reset:now.addingTimeInterval(86400))
        let identities = [owner:query.email]
        func write(_ name:String, tokens:Int) throws -> URL {
            let text = "{\"type\":\"bridge-session\",\"sessionId\":\"\(name)\",\"ownerAccountUuid\":\"\(owner)\"}\n" +
            "{\"type\":\"assistant\",\"sessionId\":\"\(name)\",\"timestamp\":\"\(ISO8601DateFormatter().string(from:now))\",\"requestId\":\"request\",\"message\":{\"usage\":{\"input_tokens\":\(tokens)}}}\n"
            let file = projects.appending(path:name + ".jsonl")
            try Data(text.utf8).write(to:file)
            return file
        }
        let one = try write("one",tokens:10), two = try write("two",tokens:20)
        let scanner = ClaudeCodeTokens()
        let cold = await scanner.scan(for:[query],knownEmails:identities,directories:[root])
        precondition(cold.totals[id]?.total == 30 && cold.metrics.filesParsed == 2 && cold.metrics.indexedRequests == 2)
        let warm = await scanner.scan(for:[query],knownEmails:identities,directories:[root])
        precondition(warm.metrics.filesParsed == 0 && warm.metrics.bytesRead == 0 && warm.metrics.cacheHits == 2)
        _ = try write("one",tokens:100)
        let changed = await scanner.scan(for:[query],knownEmails:identities,directories:[root])
        precondition(changed.metrics.filesParsed == 1 && changed.metrics.cacheHits == 1 && changed.totals[id]?.total == 120)
        _ = try write("one",tokens:1111)
        let deferred = await scanner.scan(for:[query],knownEmails:identities,directories:[root],limits:.init(maxBytesRead:0))
        precondition(deferred.coverage.hasLimit && deferred.totals[id]?.total == 20)
        let remapped = await scanner.scan(for:[query],knownEmails:[owner:"other@example.com"],directories:[root])
        precondition(remapped.metrics.filesParsed == 2 && remapped.totals.isEmpty)
        try files.removeItem(at:one)
        let deleted = await scanner.scan(for:[query],knownEmails:[owner:"other@example.com"],directories:[root])
        precondition(deleted.metrics.filesParsed == 0 && deleted.metrics.cacheHits == 1 && deleted.metrics.indexedRequests == 1)
        let alternate = root.appending(path:"alternate")
        try files.createDirectory(at:alternate.appending(path:"projects"),withIntermediateDirectories:true)
        let newRoot = await scanner.scan(for:[query],knownEmails:identities,directories:[alternate])
        precondition(newRoot.metrics.indexedRequests == 0 && newRoot.totals.isEmpty)
        let window = ClaudeCodeTokens.Query(id:id,email:query.email,reset:now.addingTimeInterval(Reading.week+86400))
        let reset = await scanner.scan(for:[window],knownEmails:identities,directories:[root])
        precondition(reset.totals.isEmpty)
        _ = try write("one",tokens:10)
        let size = try Data(contentsOf:two).count
        let limitedScanner = ClaudeCodeTokens()
        let bounded = await limitedScanner.scan(for:[query],knownEmails:identities,directories:[root],limits:.init(maxBytesRead:size))
        precondition(bounded.coverage.hasLimit && bounded.metrics.filesParsed == 1 && bounded.metrics.bytesRead <= size)
        let continued = await limitedScanner.scan(for:[query],knownEmails:identities,directories:[root],limits:.init(maxBytesRead:size))
        precondition(!continued.coverage.hasLimit && continued.totals[id]?.total == 30 && continued.metrics.filesParsed == 1)
        for limits in [ClaudeCodeTokens.Limits(maxEntries:0), .init(maxFileBytes:1), .init(maxLineBytes:1), .init(maxSeconds:0)] {
            let result = await ClaudeCodeTokens().scan(for:[query],knownEmails:identities,directories:[root],limits:limits)
            precondition(result.coverage.hasLimit && result.totals.isEmpty)
        }
        let indexCap = await ClaudeCodeTokens().scan(for:[query],knownEmails:identities,directories:[root],limits:.init(maxIndexedRequests:1))
        precondition(indexCap.coverage.hasLimit && indexCap.metrics.indexedRequests <= 1)
        let ownershipScanner = ClaudeCodeTokens()
        _ = await ownershipScanner.scan(for:[query],knownEmails:identities,directories:[root])
        let output = try FileHandle(forWritingTo:two)
        try output.seekToEnd()
        try output.write(contentsOf:Data("{\"type\":\"bridge-session\",\"sessionId\":\"two\",\"ownerAccountUuid\":\"\(UUID())\"}\n".utf8))
        try output.close()
        let disputed = await ownershipScanner.scan(for:[query],knownEmails:identities,directories:[root])
        precondition(disputed.coverage.hasUnverifiedOwnership && disputed.totals[id]?.total == 10 && disputed.metrics.filesParsed == 1)
        print("Scan performance passed zero-read warm scans, changed-file indexing, identity/root/window invalidation, deletion, bounded byte continuation, entry/file/line/time/index caps and partial coverage.")
    }
}
