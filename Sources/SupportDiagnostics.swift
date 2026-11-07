import Foundation

// An allowlisted export, deliberately independent of account names, messages, logs and file paths.
enum SupportDiagnostics {
    struct Report: Encodable {
        let schemaVersion = 1
        let generatedAt: Date
        let redacted = true
        let appVersion: String?
        let appBuild: String?
        let bundledCompanionVersion: String?
        let chromeRunning: Bool?
        let operatingSystem: String
        let historyLimitPerSource = RefreshStatus.historyLimit
        let coverage = "History begins after diagnostics support was installed. Missing or unreadable history is marked; older companions may not report a version. No raw errors or transcript files are included."
        let accounts: [AccountReport]
    }

    struct AccountReport: Encodable {
        let account: String
        let sources: [SourceReport]
    }

    struct SourceReport: Encodable {
        let source: RefreshStatus.Source
        let historyAvailable: Bool
        let latest: Event?
        let transitions: [Event]
    }

    struct Event: Encodable {
        let attempt: Int
        let started: Date
        let updated: Date
        let elapsedSeconds: Double
        let state: RefreshStatus.State
        let errorCode: String?
        let lastSuccess: Date?
        let reportedCompanionVersion: String?
    }

    static func version(_ value: String?) -> String? {
        RefreshStatus.validVersion(value)
    }

    static func report(accountIDs: [UUID], bundle: Bundle = .main, chromeRunning: Bool? = nil, now: Date = .now) -> Report {
        let manifest = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "Chrome")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return Report(generatedAt: now,
                      appVersion: version(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String),
                      appBuild: version(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String),
                      bundledCompanionVersion: version(manifest?["version"] as? String),
                      chromeRunning: chromeRunning,
                      operatingSystem: "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
                      accounts: accountIDs.enumerated().map { index, id in
            AccountReport(account: "Account \(index + 1)", sources: RefreshStatus.Source.allCases.map { source in
                let history = RefreshStatus.history(for: id, source: source)
                let latest = RefreshStatus.read(for: id, source: source).map(RefreshStatus.Transition.init)
                var attempts: [UUID: Int] = [:]
                func event(_ transition: RefreshStatus.Transition) -> Event {
                    if attempts[transition.attempt] == nil { attempts[transition.attempt] = attempts.count + 1 }
                    return Event(attempt: attempts[transition.attempt]!, started: transition.started,
                                 updated: transition.updated,
                                 elapsedSeconds: max(0, transition.updated.timeIntervalSince(transition.started)),
                                 state: transition.state,
                                 errorCode: [.refreshing, .success].contains(transition.state) ? nil : transition.state.rawValue,
                                 lastSuccess: transition.lastSuccess,
                                 reportedCompanionVersion: version(transition.companionVersion))
                }
                let events = (history ?? []).suffix(RefreshStatus.historyLimit).map(event)
                return SourceReport(source: source, historyAvailable: history != nil,
                                    latest: latest.map(event), transitions: events)
            })
        })
    }

    static func data(accountIDs: [UUID], bundle: Bundle = .main, chromeRunning: Bool? = nil) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report(accountIDs: accountIDs, bundle: bundle, chromeRunning: chromeRunning))
    }
}
