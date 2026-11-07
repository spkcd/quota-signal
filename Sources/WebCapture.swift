import Foundation

struct WebIdentity: Codable, Equatable {
    let email: String
    let workspace: String
    let plan: String

    var isValid: Bool {
        email.contains("@") && email.count <= 254 &&
            !workspace.isEmpty && workspace.count <= 128 && !plan.isEmpty && plan.count <= 48
    }
}

enum WebCapture {
    private struct Payload: Decodable {
        let attempt: UUID?
        let started: Double?
        let account: UUID?
        let pair: UUID?
        let email: String
        let workspace: String?
        let plan: String?
        let percent: Double
        let reset: Double
        let offer: ResetOffer
    }

    struct Connection: Codable {
        let request: UUID
        let account: UUID
        let identity: WebIdentity
        let reading: Reading
    }

    private struct Request: Codable {
        let id: UUID
        let expires: Date
    }

    private static var requestURL: URL {
        Bridge.directory.deletingLastPathComponent().appending(path: "pairing-request.json")
    }

    private static var connectionURL: URL {
        requestURL.deletingLastPathComponent().appending(path: "pairing-result.json")
    }

    static func beginPairing() throws -> UUID {
        let request = Request(id: UUID(), expires: .now.addingTimeInterval(1800))
        try FileManager.default.createDirectory(at: requestURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
        return request.id
    }

    static func pendingConnection() -> Connection? {
        guard let data = try? Data(contentsOf: connectionURL),
              let result = try? JSONDecoder().decode(Connection.self, from: data),
              isPending(result.request) else { return nil }
        return result
    }

    static func finishPairing() {
        // Leave the request in place until its expiry so a retry can reconnect the same account.
        try? FileManager.default.removeItem(at: connectionURL)
    }

    private static func isPending(_ id: UUID) -> Bool {
        guard let data = try? Data(contentsOf: requestURL),
              let request = try? JSONDecoder().decode(Request.self, from: data) else { return false }
        return request.id == id && request.expires > .now
    }

    private struct Reply: Encodable {
        let ok: Bool
        var alreadyConnected: Bool?
    }

    private struct StatusPayload: Decodable {
        let kind: String
        let identity: WebIdentity
        let attempt: UUID
        let started: Double
        let state: RefreshStatus.State
        let detail: String?
    }

    static func run() {
        let reply = (try? capture()) ?? Reply(ok: false)
        let response = (try? JSONEncoder().encode(reply)) ?? Data(#"{"ok":false}"#.utf8)
        var length = UInt32(response.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(response)
        FileHandle.standardOutput.write(frame)
    }

    private static func capture() throws -> Reply {
        let input = FileHandle.standardInput
        guard let prefix = try input.read(upToCount: 4), prefix.count == 4 else { return Reply(ok: false) }
        let length = Int(prefix.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
        guard (1...4096).contains(length),
              let data = try input.read(upToCount: length), data.count == length else { return Reply(ok: false) }
        let defaults = UserDefaults.standard.persistentDomain(forName: "local.quota-signal.widget")
        let accounts = try (defaults?["accounts"] as? Data).map {
            try JSONDecoder().decode([Account].self, from: $0)
        } ?? []
        let now = Date.now
        if let status = try? JSONDecoder().decode(StatusPayload.self, from: data) {
            guard status.kind == "refresh-status", status.identity.isValid,
                  status.state != .success,
                  status.started.isFinite, abs(now.timeIntervalSince1970 - status.started) <= 600,
                  let account = accounts.first(where: { $0.webIdentity == status.identity }) else {
                return Reply(ok: false)
            }
            try RefreshStatus.write(.init(attempt: status.attempt,
                                           started: Date(timeIntervalSince1970: status.started),
                                           updated: now, source: .chrome, state: status.state,
                                           message: status.detail.map { String($0.prefix(512)) }),
                                    for: account.id)
            return Reply(ok: true)
        }
        let message = try JSONDecoder().decode(Payload.self, from: data)
        let reset = Date(timeIntervalSince1970: message.reset)
        guard (0...100).contains(message.percent), reset > now,
              reset.timeIntervalSince(now) <= Reading.week + 3600 else { return Reply(ok: false) }

        let reading = Reading(observed: now, reset: reset, percent: message.percent,
                              fromWeb: true, webOffer: message.offer)
        let identity = message.workspace.flatMap { workspace in
            message.plan.map { WebIdentity(email: message.email, workspace: workspace, plan: $0) }
        }
        let existing = accounts.first { account in
            if let paired = account.webIdentity { return paired == identity }
            return account.id == message.account &&
                account.name.caseInsensitiveCompare(message.email) == .orderedSame
        }
        if let pair = message.pair {
            guard let identity, identity.isValid, isPending(pair) else { return Reply(ok: false) }
            if existing != nil { return Reply(ok: false, alreadyConnected: true) }
            let connection = Connection(request: pair, account: pair,
                                        identity: identity, reading: reading)
            try JSONEncoder().encode(connection).write(to: connectionURL, options: .atomic)
            return Reply(ok: true)
        }
        guard let existing else { return Reply(ok: false) }
        try Bridge.write(reading, for: existing.id)
        let started = message.started.flatMap { value -> Date? in
            guard value.isFinite, abs(now.timeIntervalSince1970 - value) <= 600 else { return nil }
            return Date(timeIntervalSince1970: value)
        } ?? now
        try RefreshStatus.write(.init(attempt: message.attempt ?? UUID(), started: started,
                                       updated: now, source: .chrome, state: .success, lastSuccess: now),
                                for: existing.id)
        return Reply(ok: true)
    }
}
