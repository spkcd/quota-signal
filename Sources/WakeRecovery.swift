import AppKit
import Network

struct RecoverySignal: Codable {
    let id: UUID
    let issued: Date

    static var file: URL {
        Bridge.directory.deletingLastPathComponent().appending(path: "recovery-signal.json")
    }

    static func publish() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(Self(id: UUID(), issued: .now)).write(to: file, options: .atomic)
    }

    static func recent(now: Date = .now) -> Self? {
        guard let data = try? Data(contentsOf: file),
              let signal = try? JSONDecoder().decode(Self.self, from: data),
              (0...120).contains(now.timeIntervalSince(signal.issued)) else { return nil }
        return signal
    }
}

@MainActor
final class WakeRecovery: NSObject {
    private let recover: () -> Void
    private let debounce: Duration
    private let cooldown: TimeInterval
    private var task: Task<Void, Never>?
    private var lastRecovery = Date.distantPast
    private var network: NWPathMonitor?
    private var wasOnline: Bool?
    private var started = false

    init(debounce: Duration = .seconds(2), cooldown: TimeInterval = 15, recover: @escaping () -> Void) {
        self.debounce = debounce
        self.cooldown = cooldown
        self.recover = recover
    }

    func start(monitorNetwork: Bool = true) {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(schedule), name: name, object: nil)
        }
        guard monitorNetwork, network == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if self.wasOnline == false && online { self.schedule() }
                self.wasOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "local.quota-signal.network"))
        network = monitor
    }

    @objc private func schedule() {
        guard started, Date.now.timeIntervalSince(lastRecovery) >= cooldown else { return }
        task?.cancel()
        task = Task {
            do { try await Task.sleep(for: debounce) } catch { return }
            lastRecovery = .now
            recover()
            task = nil
        }
    }

    func stop() {
        started = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        task?.cancel()
        task = nil
        network?.cancel()
        network = nil
    }
}
