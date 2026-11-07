import Foundation
import Darwin

enum Reading { static let week: TimeInterval = 7 * 86400 }

// Invented account IDs, no conversation content, no network or real Claude directories.
@main
struct ScanPerformance {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory:true)
        let manager = FileManager.default
        let meta = root.appending(path:"benchmark.json")
        let owner: UUID
        if !CommandLine.arguments.contains("--generate"), let data = try? Data(contentsOf:meta), let value = String(data:data,encoding:.utf8), let id = UUID(uuidString:value) { owner = id }
        else {
            owner = UUID()
            try manager.createDirectory(at:root.appending(path:"projects/fixture"),withIntermediateDirectories:true)
            try Data(owner.uuidString.utf8).write(to:meta)
            let timestamp = ISO8601DateFormatter().string(from:.now)
            for file in 0..<100 {
                let session = "fixture-\(file)"
                var text = "{\"type\":\"bridge-session\",\"sessionId\":\"\(session)\",\"ownerAccountUuid\":\"\(owner)\"}\n"
                for request in 0..<100 {
                    for snapshot in 1...5 {
                        text += "{\"type\":\"assistant\",\"sessionId\":\"\(session)\",\"requestId\":\"request-\(request)\",\"timestamp\":\"\(timestamp)\",\"message\":{\"content\":\"\(String(repeating:"x",count:2048))\",\"usage\":{\"input_tokens\":\(10+snapshot),\"output_tokens\":3,\"cache_read_input_tokens\":100,\"cache_creation_input_tokens\":20}}}\n"
                    }
                }
                try Data(text.utf8).write(to:root.appending(path:"projects/fixture/\(session).jsonl"))
            }
        }
        if CommandLine.arguments.contains("--generate") { print("Sanitized fixture ready."); return }
        let id = UUID()
        let query = ClaudeCodeTokens.Query(id:id,email:"benchmark@example.com",reset:Date.now.addingTimeInterval(86400))
        let scanner = ClaudeCodeTokens()
        var results: [[String:Any]] = []
        for phase in ["cold","warm","warm2"] {
            let start = ProcessInfo.processInfo.systemUptime
            let result = await scanner.scan(for:[query],knownEmails:[owner:"benchmark@example.com"],directories:[root])
            precondition(result.totals[id]?.total == 1_380_000)
            var row: [String:Any] = ["phase":phase,"seconds":ProcessInfo.processInfo.systemUptime-start,"tokens":result.totals[id]!.total]
            #if SCAN_METRICS
            row["filesParsed"] = result.metrics.filesParsed
            row["bytesRead"] = result.metrics.bytesRead
            row["indexedRequests"] = result.metrics.indexedRequests
            row["limited"] = result.coverage.hasLimit
            #endif
            results.append(row)
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF,&usage)
        let report: [String:Any] = ["fixture":"100 files, 100 requests/file, 5 streaming snapshots/request, 2048 inert content bytes/snapshot", "peakResidentBytes":usage.ru_maxrss,"runs":results]
        let output = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        FileHandle.standardOutput.write(output)
        print("")
    }
}
