import Foundation

enum Bridge {
    static var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUOTA_SIGNAL_TEST_DIRECTORY"]!)
    }
}

@main
struct RefreshStatusTests {
    static func main() throws {
        let account = UUID()
        let otherAccount = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = UUID()
        try RefreshStatus.write(.init(attempt: first, started: start, updated: start.addingTimeInterval(1),
                                      source: .chrome, state: .success, lastSuccess: start), for: account)
        let second = UUID()
        let next = start.addingTimeInterval(300)
        try RefreshStatus.write(.init(attempt: second, started: next, updated: next,
                                      source: .chrome, state: .refreshing), for: account)
        try RefreshStatus.write(.init(attempt: second, started: next, updated: next.addingTimeInterval(1),
                                      source: .chrome, state: .layout, message: "Missing weekly meter"), for: account)
        // A late reply from an older attempt must preserve the current failure and retain success history.
        let lateSuccess = start.addingTimeInterval(2)
        try RefreshStatus.write(.init(attempt: first, started: start, updated: next.addingTimeInterval(2),
                                      source: .chrome, state: .success, lastSuccess: lateSuccess), for: account)
        let status = RefreshStatus.read(for: account, source: .chrome)!
        precondition(status.attempt == second && status.state == .layout && status.lastSuccess == lateSuccess)
        precondition(status.message == "Missing weekly meter")
        precondition(RefreshStatus.read(for: otherAccount, source: .chrome) == nil)
        precondition(RefreshStatus.read(for: account, source: .embedded) == nil)
        print("Refresh status passed failed-attempt retention, out-of-order replies, success history, account and source isolation.")
    }
}
