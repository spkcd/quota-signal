import AppKit

enum Bridge {
    static var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUOTA_SIGNAL_TEST_DIRECTORY"]!)
            .appending(path: "Feeds")
    }
}

@main
struct WakeRecoveryTests {
    @MainActor static func main() async throws {
        var calls = 0
        let recovery = WakeRecovery(debounce: .milliseconds(20), cooldown: 0.15) { calls += 1 }
        recovery.start(monitorNetwork: false)
        recovery.start(monitorNetwork: false)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            center.post(name: name, object: nil)
        }
        try await Task.sleep(for: .milliseconds(80))
        precondition(calls == 1)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        precondition(calls == 1)
        try await Task.sleep(for: .milliseconds(120))
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(80))
        precondition(calls == 2)
        recovery.stop()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        precondition(calls == 2)

        try RecoverySignal.publish()
        let signal = RecoverySignal.recent()!
        precondition(RecoverySignal.recent(now: signal.issued.addingTimeInterval(121)) == nil)
        precondition(RecoverySignal.recent(now: signal.issued.addingTimeInterval(-1)) == nil)
        print("Wake notifications passed debounce, duplicate registration, cooldown, resumed sessions, stop, and signal expiry.")
    }
}
