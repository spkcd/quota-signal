import AppKit

enum ChromeAccountActions {
    struct Profile: Identifiable, Codable {
        let id: String
        let name: String
        let email: String
        var label: String { email.isEmpty || name.contains(email) ? name : name + " · " + email }
    }

    struct Request: Codable {
        let id: UUID
        let account: UUID
        let identity: WebIdentity
        let profile: String
        let reconnect: Bool
        let started: Date
        let expires: Date
    }

    static var directory: URL {
        Bridge.directory.deletingLastPathComponent().appending(path: "Commands", directoryHint: .isDirectory)
    }

    static func file(for account: UUID) -> URL {
        directory.appending(path: account.uuidString + ".json")
    }

    static func profiles() -> [Profile] {
        let state = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Google/Chrome/Local State")
        if let data = try? Data(contentsOf: state), let profiles = try? profiles(from: data), !profiles.isEmpty {
            return profiles
        }
        return UserDefaults.standard.data(forKey: "chromeProfileNames").flatMap {
            try? JSONDecoder().decode([Profile].self, from: $0)
        } ?? []
    }

    static func profiles(from data: Data) throws -> [Profile] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        return cache.compactMap { key, value in
            guard validDirectory(key), let name = value["name"] as? String else { return nil }
            return Profile(id: key, name: name, email: value["user_name"] as? String ?? "")
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    static func validDirectory(_ directory: String) -> Bool {
        directory == "Default" || directory.range(of: #"^Profile [0-9]+$"#, options: .regularExpression) != nil
    }

    static func suggestedProfile(for account: Account, profiles: [Profile]) -> Profile? {
        let key = "chromeProfile." + account.id.uuidString
        if let saved = UserDefaults.standard.string(forKey: key), let match = profiles.first(where: { $0.id == saved }) {
            return match
        }
        let email = account.webIdentity?.email.lowercased() ?? account.name.lowercased()
        let named = profiles.filter { $0.name.lowercased().contains(email) }
        if named.count == 1 { return named.first }
        let signedIn = profiles.filter { $0.email.lowercased() == email }
        return signedIn.count == 1 ? signedIn.first : nil
    }

    static func pending(for account: UUID) -> Request? {
        guard let data = try? Data(contentsOf: file(for: account)),
              let request = try? JSONDecoder().decode(Request.self, from: data),
              request.expires > .now else { return nil }
        return request
    }

    static func pending(id: UUID) -> Request? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { file -> Request? in
            guard file.pathExtension == "json", let data = try? Data(contentsOf: file),
                  let request = try? JSONDecoder().decode(Request.self, from: data),
                  request.id == id, request.expires > .now else { return nil }
            return request
        }.first
    }

    @MainActor static func open(account: Account, reconnect: Bool, profile: Profile) throws {
        guard let identity = account.webIdentity, identity.isValid else { throw ActionError.unconnected }
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        let now = Date.now
        let request: Request
        let existing = pending(for: account.id)
        if let existing, existing.identity == identity, existing.reconnect == reconnect, existing.profile == profile.id {
            request = existing
        } else {
            request = Request(id: UUID(), account: account.id, identity: identity, profile: profile.id,
                              reconnect: reconnect, started: now,
                              expires: now.addingTimeInterval(reconnect ? 1800 : 120))
            try JSONEncoder().encode(request).write(to: file(for: account.id), options: .atomic)
        }
        guard validDirectory(request.profile),
              let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            throw ActionError.chromeUnavailable
        }
        if request.id != existing?.id {
            try RefreshStatus.write(.init(attempt: request.id, started: now, updated: now, source: .chrome,
                                           state: .refreshing), for: account.id)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            "--profile-directory=" + request.profile,
            "chrome-extension://gjjgdcalfbbaphaebkfbkomodcejmina/command.html#" + request.id.uuidString
        ]
        NSWorkspace.shared.openApplication(at: chrome, configuration: configuration) { _, error in
            guard let error else { return }
            try? RefreshStatus.write(.init(attempt: request.id, started: now, updated: .now, source: .chrome,
                                            state: .unavailable, message: error.localizedDescription), for: account.id)
        }
    }

    enum ActionError: LocalizedError {
        case unconnected, chromeUnavailable
        var errorDescription: String? {
            switch self {
            case .unconnected: "Connect this account with + before retrying through Chrome."
            case .chromeUnavailable: "Google Chrome is unavailable. Install Chrome and load the companion."
            }
        }
    }
}
