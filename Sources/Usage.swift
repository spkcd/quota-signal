import Foundation
import AppKit
import SwiftUI

enum ResetOffer: String, Codable, CaseIterable, Identifiable {
    case unknown = "Unknown"
    case available = "Available"
    case none = "None available"
    var id: Self { self }
}

struct Reading: Codable, Identifiable {
    var observed: Date
    var reset: Date
    var percent: Double
    var fromCode = false
    var fromWeb: Bool?
    var backgroundWeb: Bool?
    var webOffer: ResetOffer?
    var id: Date { observed }
    static let week: TimeInterval = 7 * 24 * 60 * 60
}

struct Account: Codable, Identifiable {
    var id = UUID()
    var name: String
    var webIdentity: WebIdentity?
    var offer: ResetOffer = .unknown
    var offerChecked: Date?
    var readings: [Reading] = []

    var latest: Reading? { readings.last }
    var cycle: [Reading] {
        readings
    }

    mutating func record(_ reading: Reading) {
        guard reading.percent.isFinite, (0...100).contains(reading.percent),
              reading.reset > reading.observed,
              reading.reset.timeIntervalSince(reading.observed) <= Reading.week + 3600 else { return }
        if let latest {
            guard reading.observed > latest.observed else { return }
            if abs(latest.reset.timeIntervalSince(reading.reset)) >= 60 { readings.removeAll() }
            else if reading.observed.timeIntervalSince(latest.observed) < 300,
                    latest.percent == reading.percent, latest.fromCode == reading.fromCode,
                    latest.fromWeb == reading.fromWeb {
                readings[readings.count - 1] = reading
                return
            }
        }
        readings.append(reading)
        if readings.count > 2500 { readings.removeFirst(readings.count - 2500) }
    }
}

enum Bridge {
    private struct Payload: Decodable {
        struct Window: Decodable {
            var used_percentage: Double
            var resets_at: Double
        }
        struct Limits: Decodable { var seven_day: Window? }
        var rate_limits: Limits
    }

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Quota Signal/Feeds", directoryHint: .isDirectory)
    }

    static func file(for id: UUID) -> URL {
        directory.appending(path: id.uuidString + ".json")
    }

    static func reading(for id: UUID) -> Reading? {
        guard let data = try? Data(contentsOf: file(for: id)) else { return nil }
        return try? JSONDecoder().decode(Reading.self, from: data)
    }

    static func capture(id: UUID) throws {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = try? JSONDecoder().decode(Payload.self, from: input),
              let week = payload.rate_limits.seven_day,
              (0...100).contains(week.used_percentage), week.resets_at.isFinite else { return }
        let now = Date.now
        let reset = Date(timeIntervalSince1970: week.resets_at)
        guard reset > now, reset.timeIntervalSince(now) <= Reading.week + 3600 else { return }
        let reading = Reading(observed: now, reset: reset, percent: week.used_percentage, fromCode: true)
        try write(reading, for: id)
        try RefreshStatus.write(.init(attempt: UUID(), started: now, updated: now,
                                       source: .code, state: .success, lastSuccess: now), for: id)
        print("Weekly " + week.used_percentage.formatted(.number.precision(.fractionLength(0...1))) + "%")
    }

    static func write(_ reading: Reading, for id: UUID) throws {
        let url = file(for: id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if reading.fromWeb == true {
            // Chrome profiles have separate host processes, so serialize writes per account.
            let descriptor = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o600)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
            if let previous = Self.reading(for: id), previous.fromWeb == true {
                if reading.observed <= previous.observed { return }
                if reading.observed.timeIntervalSince(previous.observed) < 240,
                   reading.percent == previous.percent, reading.reset == previous.reset,
                   reading.webOffer == previous.webOffer, reading.backgroundWeb == previous.backgroundWeb { return }
            }
            try JSONEncoder().encode(reading).write(to: url, options: .atomic)
            return
        }
        try JSONEncoder().encode(reading).write(to: url, options: .atomic)
    }
}

@MainActor
final class UsageStore: ObservableObject {
    enum LocalTokenStatus {
        case checking, needsID, awaitingCycle, ambiguous, noLogs, inaccessible, ownershipUnknown
        case recorded(ClaudeCodeTokens.Counts)
        case partial(ClaudeCodeTokens.Counts)

        var counts: ClaudeCodeTokens.Counts? {
            switch self { case let .recorded(counts), let .partial(counts): counts; default: nil }
        }


        var label: String {
            switch self {
            case .checking: "Checking local logs…"
            case .needsID: "Account ID needed"
            case .awaitingCycle: "Awaiting weekly quota reading"
            case .ambiguous: "Multiple accounts share this email"
            case .noLogs: "No attributable logs this week"
            case .recorded: "Local logs found"
            case .partial: "Partial token coverage"
            case .inaccessible: "Log folders inaccessible"
            case .ownershipUnknown: "Log ownership unverified"
            }
        }
    }

    @Published private(set) var accounts: [Account] = []
    @Published var selected: UUID?
    @Published var showingDetail = false
    @Published private(set) var demo = false
    @Published private var signedInClaudeCodeEmail: String?
    private var checkingClaudeCodeSignIn = false
    private var lastClaudeCodeSignInCheck = Date.distantPast
    private let defaults = UserDefaults.standard
    private let claudeCodeTokens = ClaudeCodeTokens()
    @Published private(set) var localTokenDirectories = ClaudeCodeConfigurations.directories()
    @Published private(set) var contributingTokenDirectories: [UUID: Set<URL>] = [:]
    @Published private(set) var scannedTokenDirectories = Set<URL>()
    @Published var showingLogSources = false
    @Published private(set) var localTokenCoverage = TokenCoverage()
    @Published private(set) var localTokenScanInProgress = false
    private var conflictedTokenEmails = Set<String>()

    @Published private var localTokenTotals: [UUID: ClaudeCodeTokens.Counts] = [:]
    @Published private var linkedTokenEmails: Set<String>?
    @Published private(set) var localTokenScanCompletedAt: Date?
    @Published private var refreshStatuses: [UUID: [RefreshStatus]] = [:]
    @Published private var chromeRunning = true
    private var tokenQueries: [ClaudeCodeTokens.Query] = []
    private var tokenTask: Task<Void, Never>?
    private var lastTokenScan = Date.distantPast
    private var tokenRescanRequested = false
    private var savedSelection: UUID?
    private var savedAccounts: [Account] = []

    init() {
        if let data = defaults.data(forKey: "accounts"),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = decoded
        }
        selected = defaults.string(forKey: "selected").flatMap(UUID.init(uuidString:))
        if !accounts.contains(where: { $0.id == selected }) { selected = accounts.first?.id }
        poll()
    }

    var current: Account? { accounts.first { $0.id == selected } ?? accounts.first }

    func select(_ id: UUID) {
        selected = id
        if !demo { defaults.set(id.uuidString, forKey: "selected") }
    }

    func save(_ account: Account) {
        guard !demo else { return }
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        select(account.id)
        persist()
    }

    func remove(_ id: UUID) {
        guard !demo else { return }
        accounts.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Bridge.file(for: id))
        selected = accounts.first?.id
        defaults.set(selected?.uuidString, forKey: "selected")
        persist()
    }

    func poll() {
        guard !demo else { return }
        refreshClaudeCodeSignIn()
        if let result = WebCapture.pendingConnection() {
            var account = accounts.first { $0.webIdentity == result.identity || $0.id == result.account }
                ?? Account(id: result.account, name: result.identity.email + " · " + result.identity.workspace)
            if account.webIdentity == nil || account.webIdentity == result.identity {
                account.webIdentity = result.identity
                account.record(result.reading)
                if let offer = result.reading.webOffer, account.latest?.observed == result.reading.observed {
                    account.offer = offer
                    account.offerChecked = result.reading.observed
                }
                save(account)
            }
            WebCapture.finishPairing()
        }
        var updated = accounts
        var changed = false
        for index in updated.indices {
            let account = updated[index]
            if let identity = WebCapture.verifiedIdentity(for: account) {
                updated[index].webIdentity = identity
                changed = true
            }
            guard let reading = Bridge.reading(for: account.id),
                  reading.observed > (account.latest?.observed ?? .distantPast) else { continue }
            updated[index].record(reading)
            if let offer = reading.webOffer {
                updated[index].offer = offer
                updated[index].offerChecked = reading.observed
            }
            changed = true
        }
        if changed {
            accounts = updated
            persist()
        }
        let statuses = Dictionary(uniqueKeysWithValues: accounts.map { account in
            (account.id, [RefreshStatus.Source.chrome, .embedded, .code].compactMap {
                RefreshStatus.read(for: account.id, source: $0)
            })
        })
        if statuses != refreshStatuses { refreshStatuses = statuses }
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.google.Chrome" }
        if chromeRunning != running { chromeRunning = running }
    }

    struct RefreshDetails {
        let title: String
        let source: String
        let attempt: Date?
        let success: Date?
        let error: String?
    }

    func refreshDetails(for account: Account, now: Date = .now) -> RefreshDetails {
        if demo {
            return .init(title: "Sample refresh", source: "Demo data", attempt: now, success: now, error: nil)
        }
        let status = refreshStatuses[account.id]?.max { $0.started < $1.started }
        let latest = account.latest
        let success = ((refreshStatuses[account.id] ?? []).compactMap(\.lastSuccess) + [latest?.observed].compactMap { $0 }).max()
        let readingSource = latest.map {
            $0.backgroundWeb == true ? "Claude background" : $0.fromWeb == true ? "Chrome companion" :
                $0.fromCode ? "Claude Code status line" : "Manual"
        } ?? "Unknown"
        let source = status?.source.label ?? readingSource
        if !chromeRunning, (status?.source == .chrome || (status == nil && latest?.fromWeb == true && latest?.backgroundWeb != true)) {
            return .init(title: "Browser closed", source: source, attempt: status?.started,
                         success: success, error: "Google Chrome is closed. Open Chrome to resume companion refreshes.")
        }
        guard let status else {
            return .init(title: "Attempt status unavailable", source: source, attempt: nil,
                         success: success, error: nil)
        }
        let state = status.state == .refreshing && now.timeIntervalSince(status.started) > 120
            ? RefreshStatus.State.unavailable : status.state
        let title = state == .success && success.map({ now.timeIntervalSince($0) >= 900 }) == true
            ? "Refresh overdue" : state.label
        return .init(title: title, source: source, attempt: status.started, success: success,
                     error: status.state == .refreshing ? state.detail : status.message ?? state.detail)
    }

    func recordRefresh(for id: UUID, attempt: UUID, started: Date, state: RefreshStatus.State, message: String? = nil) {
        guard !demo, accounts.contains(where: { $0.id == id }) else { return }
        try? RefreshStatus.write(.init(attempt: attempt, started: started, updated: .now,
                                       source: .embedded, state: state,
                                       lastSuccess: state == .success ? .now : nil, message: message), for: id)
        poll()
    }

    private func tokenEmail(for account: Account) -> String {
        (account.webIdentity?.email ?? account.name).lowercased()
    }

    var activeClaudeCodeAccountID: UUID? {
        guard !demo, let signedInClaudeCodeEmail else { return nil }
        let matches = accounts.filter { tokenEmail(for: $0) == signedInClaudeCodeEmail }
        return matches.count == 1 ? matches.first?.id : nil
    }

    private func refreshClaudeCodeSignIn() {
        guard !checkingClaudeCodeSignIn,
              Date.now.timeIntervalSince(lastClaudeCodeSignInCheck) >= 15 else { return }
        checkingClaudeCodeSignIn = true
        lastClaudeCodeSignInCheck = .now
        Task {
            let email = await Task.detached(priority: .utility) { ClaudeCodeTokens.signedInEmail() }.value
            if signedInClaudeCodeEmail != email { signedInClaudeCodeEmail = email }
            checkingClaudeCodeSignIn = false
        }
    }

    func localTokenStatus(for account: Account) -> LocalTokenStatus {
        if demo { return .recorded(.init(input: 248_600, output: 93_400, cacheWrite: 120_000, cacheRead: 614_000)) }
        guard !localTokenScanInProgress, let linkedTokenEmails else { return .checking }
        let email = tokenEmail(for: account)
        if conflictedTokenEmails.contains(email) { return .ownershipUnknown }
        guard linkedTokenEmails.contains(email) else { return .needsID }
        guard let reset = account.latest?.reset, reset > .now else { return .awaitingCycle }
        let query = ClaudeCodeTokens.Query(id: account.id, email: email, reset: reset)
        guard tokenQueries.contains(query) else {
            let matching = accounts.filter {
                tokenEmail(for: $0) == email && ($0.latest?.reset ?? .distantPast) > .now
            }
            return matching.count > 1 ? .ambiguous : .checking
        }
        guard localTokenScanCompletedAt != nil else { return .checking }
        if let counts = localTokenTotals[account.id] {
            return localTokenCoverage.isPartial ? .partial(counts) : .recorded(counts)
        }
        if localTokenCoverage.hasUnavailable { return .inaccessible }
        if localTokenCoverage.hasUnverifiedOwnership { return .ownershipUnknown }
        return .noLogs
    }

    func tokenCoverageExplanation(for account: Account) -> String {
        let status = localTokenStatus(for: account)
        switch status {
        case .checking: return "A local scan is in progress. Coverage and totals will update when it finishes."
        case .needsID: return "No verified Claude Code ID is linked to this email. Use Link Claude Code to find and verify it; this is different from having no logs this week."
        case .awaitingCycle: return "A current weekly quota/reset reading is needed to choose the token window. Refresh this account first."
        case .ambiguous: return "Multiple Quota Signal accounts use this email. Token requests cannot be assigned to a unique account, so totals are withheld."
        case .noLogs: return "The ID is linked and the scan found no eligible attributable requests in this weekly window. This does not prove that no activity occurred on another device."
        case .ownershipUnknown where conflictedTokenEmails.contains(tokenEmail(for: account)):
            return "Local metadata makes conflicting email claims for a Claude Code ID associated with this account. Conflicting IDs are excluded. Review the selected configurations and link a verified ID."
        default: return localTokenCoverage.explanation
        }
    }

    func refreshLocalTokens(force: Bool = false) {
        guard !demo else { return }
        guard tokenTask == nil else { tokenRescanRequested = tokenRescanRequested || force; return }
        let candidates = accounts.compactMap { account -> ClaudeCodeTokens.Query? in
            let email = tokenEmail(for: account)
            guard email.contains("@"), let reset = account.latest?.reset, reset > .now else { return nil }
            return .init(id: account.id, email: email, reset: reset)
        }
        let counts = Dictionary(grouping: candidates, by: \.email)
        let queries = candidates.filter { counts[$0.email]?.count == 1 }
        guard force || queries != tokenQueries || Date.now.timeIntervalSince(lastTokenScan) >= 300 else { return }
        lastTokenScan = .now
        if queries != tokenQueries {
            localTokenTotals = [:]
            localTokenScanCompletedAt = nil
            tokenQueries = queries
        }
        let directories = localTokenDirectories
        localTokenScanInProgress = true
        tokenTask = Task {
            defer {
                tokenTask = nil
                localTokenScanInProgress = false
                if tokenRescanRequested {
                    tokenRescanRequested = false
                    refreshLocalTokens(force: true)
                }
            }
            let saved = defaults.dictionary(forKey: "claudeCodeLogIdentities") as? [String: String] ?? [:]
            var identities = [UUID: String]()
            for (id, email) in saved {
                if let uuid = UUID(uuidString: id) { identities[uuid] = email.lowercased() }
            }
            let discovery = await Task.detached { ClaudeCodeLinking.discover(configs: directories) }.value
            let disputedEmails = Set(identities.filter { discovery.conflictingIDs.contains($0.key) }.values)
            identities = identities.filter { !discovery.conflictingIDs.contains($0.key) }
            identities.merge(discovery.identities) { _, newer in newer }
            defaults.set(Dictionary(uniqueKeysWithValues: identities.map { ($0.key.uuidString, $0.value) }),
                         forKey: "claudeCodeLogIdentities")
            let result = await claudeCodeTokens.scan(for: queries, knownEmails: identities, directories: directories)
            guard directories == localTokenDirectories else { tokenRescanRequested = true; return }
            conflictedTokenEmails = disputedEmails.union(discovery.conflictingEmails)
            localTokenCoverage = result.coverage
            localTokenTotals = result.totals
            contributingTokenDirectories = result.contributingDirectories
            scannedTokenDirectories = result.scannedDirectories
            linkedTokenEmails = Set(identities.values)
            localTokenScanCompletedAt = .now
        }
    }

    func discoverClaudeCodeIDs() async -> ClaudeCodeLinking.Discovery {
        let directories = localTokenDirectories
        return await Task.detached { ClaudeCodeLinking.discover(configs: directories) }.value
    }

    func addTokenDirectories(_ urls: [URL]) -> Bool {
        guard !demo, urls.allSatisfy(ClaudeCodeConfigurations.isSupported) else { return false }
        updateTokenDirectories(ClaudeCodeConfigurations.unique(localTokenDirectories + urls))
        return true
    }

    func removeTokenDirectory(_ url: URL) {
        guard !demo, url != ClaudeCodeConfigurations.primary else { return }
        updateTokenDirectories(localTokenDirectories.filter { $0 != url })
    }

    private func updateTokenDirectories(_ urls: [URL]) {
        guard urls != localTokenDirectories else { return }
        localTokenDirectories = urls
        defaults.set(urls.dropFirst().map(\.path), forKey: ClaudeCodeConfigurations.preferenceKey)
        localTokenTotals = [:]
        contributingTokenDirectories = [:]
        localTokenCoverage = TokenCoverage()
        scannedTokenDirectories = []
        localTokenScanCompletedAt = nil
        refreshLocalTokens(force: true)
    }

    func linkClaudeCode(for account: Account, expectedIDs: [UUID]) async -> Bool {
        guard !demo, accounts.contains(where: { $0.id == account.id && tokenEmail(for: $0) == tokenEmail(for: account) }) else { return false }
        let directories = localTokenDirectories
        let discovery = await Task.detached { ClaudeCodeLinking.discover(configs: directories) }.value
        guard directories == localTokenDirectories else { return false }
        let ids = discovery.matching(tokenEmail(for: account))
        guard !ids.isEmpty, ids == expectedIDs,
              accounts.contains(where: { $0.id == account.id && tokenEmail(for: $0) == tokenEmail(for: account) }) else { return false }
        var saved = defaults.dictionary(forKey: "claudeCodeLogIdentities") as? [String: String] ?? [:]
        for id in discovery.conflictingIDs { saved.removeValue(forKey: id.uuidString) }
        for id in ids { saved[id.uuidString] = tokenEmail(for: account) }
        defaults.set(saved, forKey: "claudeCodeLogIdentities")
        refreshLocalTokens(force: true)
        return true
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) { defaults.set(data, forKey: "accounts") }
    }

    func toggleDemo() {
        if demo {
            accounts = savedAccounts
            selected = savedSelection
            demo = false
            poll()
            return
        }
        savedAccounts = accounts
        savedSelection = selected
        let now = Date.now
        accounts = [
            example("Studio", percent: [4, 12, 24, 29, 41, 56, 68], reset: now.addingTimeInterval(34 * 3600), offer: .available),
            example("Personal", percent: [6, 10, 18, 22, 31], reset: now.addingTimeInterval(62 * 3600), offer: .none)
        ]
        selected = accounts.first?.id
        demo = true
    }

    private func example(_ name: String, percent: [Double], reset: Date, offer: ResetOffer) -> Account {
        let start = reset.addingTimeInterval(-Reading.week)
        let span = Date.now.timeIntervalSince(start)
        let samples = percent.enumerated().map { index, value in
            Reading(observed: start.addingTimeInterval(span * (0.06 + 0.94 * Double(index) / Double(percent.count - 1))),
                    reset: reset, percent: value, fromCode: true)
        }
        return Account(name: name, offer: offer, offerChecked: .now, readings: samples)
    }
}
