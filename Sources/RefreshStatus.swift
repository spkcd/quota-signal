import Foundation

struct RefreshStatus: Codable, Equatable {
    enum Source: String, Codable {
        case chrome, embedded, code
        var label: String {
            switch self {
            case .chrome: "Chrome companion"
            case .embedded: "Claude background"
            case .code: "Claude Code status line"
            }
        }
    }

    enum State: String, Codable {
        case refreshing, success, signedOut, network, layout, mismatch, unavailable

        var label: String {
            switch self {
            case .refreshing: "Refreshing…"
            case .success: "Up to date"
            case .signedOut: "Sign-in needed"
            case .network: "Network error"
            case .layout: "Page layout changed"
            case .mismatch: "Workspace mismatch"
            case .unavailable: "Refresh unavailable"
            }
        }

        var detail: String? {
            switch self {
            case .refreshing, .success: nil
            case .signedOut: "Claude displayed its login page. Sign in to the intended workspace."
            case .network: "The browser could not reach Claude. Check the connection and retry."
            case .layout: "The companion could not read the verified weekly meter or account controls."
            case .mismatch: "The signed-in Claude account or workspace differs from the connected workspace."
            case .unavailable: "No verified reading was returned. Check Claude and the companion."
            }
        }
    }

    let attempt: UUID
    let started: Date
    let updated: Date
    let source: Source
    let state: State
    var lastSuccess: Date?
    var message: String?

    static func file(for id: UUID, source: Source) -> URL {
        Bridge.directory.appending(path: id.uuidString + "." + source.rawValue + "-refresh.json")
    }

    static func read(for id: UUID, source: Source) -> Self? {
        guard let data = try? Data(contentsOf: file(for: id, source: source)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func write(_ event: Self, for id: UUID) throws {
        let url = file(for: id, source: event.source)
        try FileManager.default.createDirectory(at: Bridge.directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        let previous = read(for: id, source: event.source)
        var next = event
        if let previous, previous.started > event.started ||
            (previous.started == event.started && previous.updated >= event.updated) {
            next = previous
        }
        next.lastSuccess = [previous?.lastSuccess, event.lastSuccess].compactMap { $0 }.max()
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
    }
}
