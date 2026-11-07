import Foundation

enum Bridge {
    static var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUOTA_SIGNAL_TEST_DIRECTORY"]!)
    }
}

@main
struct SupportDiagnosticsTests {
    static func main() throws {
        let account = UUID()
        let other = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let secret = "person@example.com Secret Workspace /Users/private/token sk-ant-PRIVATE transcript: secret conversation"
        let first = UUID()
        try RefreshStatus.write(.init(attempt: first, started: now, updated: now,
                                      source: .chrome, state: .refreshing, message: secret,
                                      companionVersion: "1.6.0"), for: account)
        try RefreshStatus.write(.init(attempt: first, started: now, updated: now.addingTimeInterval(4),
                                      source: .chrome, state: .success, lastSuccess: now.addingTimeInterval(4),
                                      message: secret, companionVersion: "1.6.0"), for: account)
        let second = UUID()
        try RefreshStatus.write(.init(attempt: second, started: now.addingTimeInterval(300), updated: now.addingTimeInterval(307),
                                      source: .chrome, state: .mismatch, message: secret,
                                      companionVersion: secret), for: account)
        // A delayed old response must not appear as a new transition.
        try RefreshStatus.write(.init(attempt: first, started: now, updated: now.addingTimeInterval(350),
                                      source: .chrome, state: .network, message: secret), for: account)
        let data = try SupportDiagnostics.data(accountIDs: [account, other])
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in [secret, "person@example.com", "Secret Workspace", "/Users/", "sk-ant-", "secret conversation", account.uuidString, first.uuidString] {
            precondition(!text.contains(forbidden), "Export leaked \(forbidden)")
        }
        let report = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(report["redacted"] as? Bool == true)
        precondition(report["schemaVersion"] as? Int == 1)
        let accounts = report["accounts"] as! [[String: Any]]
        precondition(accounts.map { $0["account"] as! String } == ["Account 1", "Account 2"])
        let sources = accounts[0]["sources"] as! [[String: Any]]
        let chrome = sources.first { $0["source"] as? String == "chrome" }!
        let events = chrome["transitions"] as! [[String: Any]]
        precondition(events.count == 3)
        precondition(events.map { $0["state"] as! String } == ["refreshing", "success", "mismatch"])
        precondition(events[0]["attempt"] as? Int == 1 && events[1]["attempt"] as? Int == 1 && events[2]["attempt"] as? Int == 2)
        precondition(events[1]["reportedCompanionVersion"] as? String == "1.6.0")
        let latest = chrome["latest"] as! [String: Any]
        precondition(latest["elapsedSeconds"] as? Double == 7 && latest["errorCode"] as? String == "mismatch")
        precondition(latest["reportedCompanionVersion"] == nil && latest["lastSuccess"] != nil)
        precondition(sources.first { $0["source"] as? String == "embedded" }!["historyAvailable"] as? Bool == false)
        let journal = try String(contentsOf: RefreshStatus.historyFile(for: account, source: .chrome), encoding: .utf8)
        precondition(!journal.contains(secret) && !journal.contains("message"))
        for index in 1...60 {
            try RefreshStatus.write(.init(attempt: UUID(), started: now.addingTimeInterval(Double(index * 300 + 400)),
                                          updated: now.addingTimeInterval(Double(index * 300 + 401)),
                                          source: .chrome, state: .layout), for: account)
        }
        precondition(RefreshStatus.history(for: account, source: .chrome)?.count == 50)
        let empty = try SupportDiagnostics.data(accountIDs: [])
        precondition(String(decoding: empty, as: UTF8.self).contains("\"accounts\" : ["))
        // Unreadable journals are explicitly marked, while the latest snapshot remains available.
        try Data("broken".utf8).write(to: RefreshStatus.historyFile(for: account, source: .chrome))
        let partial = SupportDiagnostics.report(accountIDs: [account])
        precondition(!partial.accounts[0].sources[0].historyAvailable && partial.accounts[0].sources[0].latest != nil)
        for invalid in [secret, "1.6.0\n", "v1.6.0", "1.2.3-secret"] { precondition(SupportDiagnostics.version(invalid) == nil) }
        print("Diagnostics passed redaction, anonymous labels, versions, timing, error codes, attempt correlation, ordered/bounded history, empty accounts and damaged history.")
    }
}
