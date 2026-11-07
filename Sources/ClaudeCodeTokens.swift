import Foundation

actor ClaudeCodeTokens {
    static func signedInEmail() -> String? {
        struct AuthStatus: Decodable {
            let loggedIn: Bool
            let authMethod: String?
            let email: String?
        }

        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser.path
        // Finder and login items may launch with a minimal PATH.
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = path.split(separator: ":").map(String.init)
            + ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
        guard let executable = directories.map({ URL(fileURLWithPath: $0).appending(path: "claude") })
            .first(where: { files.isExecutableFile(atPath: $0.path) }) else { return nil }

        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["auth", "status", "--json"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = directories.joined(separator: ":")
        process.environment = environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let status = try? JSONDecoder().decode(AuthStatus.self, from: data),
              status.loggedIn, status.authMethod == "claude.ai" else { return nil }
        return status.email?.lowercased()
    }

    static func executableURL() -> URL? {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser.path
        // Finder and login items may launch with a minimal PATH.
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = path.split(separator: ":").map(String.init)
            + ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
        return directories.map({ URL(fileURLWithPath: $0).appending(path: "claude") })
            .first(where: { files.isExecutableFile(atPath: $0.path) })

    }

    struct Counts: Sendable {
        var input: Int64 = 0
        var output: Int64 = 0
        var cacheWrite: Int64 = 0
        var cacheRead: Int64 = 0

        var cache: Int64 { cacheRead + cacheWrite }
        var total: Int64 { input + output + cache }

        mutating func add(_ counts: Self) {
            input += counts.input
            output += counts.output
            cacheWrite += counts.cacheWrite
            cacheRead += counts.cacheRead
        }
    }

    struct Query: Equatable, Sendable {
        let id: UUID
        let email: String
        let reset: Date
    }

    private struct Event: Decodable {
        let type: String?
        let sessionId: String?
        let ownerAccountUuid: UUID?
        let requestId: String?
        let timestamp: Date?
        let message: Message?

        struct Message: Decodable {
            let id: String?
            let usage: Usage?
        }
    }

    private struct Usage: Decodable {
        let input_tokens: Int64?
        let output_tokens: Int64?
        let cache_creation_input_tokens: Int64?
        let cache_read_input_tokens: Int64?

        var counts: Counts? {
            let counts = Counts(input: input_tokens ?? 0, output: output_tokens ?? 0,
                                cacheWrite: cache_creation_input_tokens ?? 0, cacheRead: cache_read_input_tokens ?? 0)
            guard [counts.input, counts.output, counts.cacheWrite, counts.cacheRead]
                .allSatisfy({ (0...1_000_000_000).contains($0) }) else { return nil }
            return counts
        }
    }

    private struct AccountFile: Decodable {
        let oauthAccount: Identity?

        struct Identity: Decodable {
            let accountUuid: UUID
            let emailAddress: String
        }
    }

    private struct Sample {
        let directory: URL
        let session: String
        let request: String
        let time: Date
        let counts: Counts
    }

    private struct Transcript {
        let session: String
        var ambiguousOwner = false
        var unreadable = false
        var limited = false
        let modified: Date
        let size: Int
        let owner: UUID?
        let samples: [Sample]
    }

    private var cache: [URL: Transcript] = [:]
    struct Limits: Sendable {
        var maxEntries = 50_000
        var maxBytesRead = 2 * 1024 * 1024 * 1024
        var maxFileBytes = 512 * 1024 * 1024
        var maxIndexedRequests = 250_000
        var maxLineBytes = 4 * 1024 * 1024
        var maxSeconds: Double = 15
    }

    struct Metrics: Sendable {
        var elapsedSeconds: Double = 0
        var entriesVisited = 0
        var filesParsed = 0
        var cacheHits = 0
        var bytesRead = 0
        var indexedRequests = 0
    }

    private struct Configuration: Equatable {
        let directories: [URL]
        let identities: [UUID: String]
        let earliest: Date
    }
    private var configuration: Configuration?

    private struct FileEntry {
        let file: URL
        let root: URL
        let modified: Date
        let size: Int
    }

    private let usageMarker = Data(#""usage":"#.utf8)
    private let ownerMarker = Data(#""ownerAccountUuid":"#.utf8)

    struct ScanResult: Sendable {
        let totals: [UUID: Counts]
        let contributingDirectories: [UUID: Set<URL>]
        let scannedDirectories: Set<URL>
        var coverage = TokenCoverage()
        var metrics = Metrics()
    }

    func totals(for queries: [Query], knownEmails: [UUID: String]) -> [UUID: Counts] {
        scan(for: queries, knownEmails: knownEmails, directories: [ClaudeCodeConfigurations.primary]).totals
    }

    func scan(for queries: [Query], knownEmails: [UUID: String], directories: [URL], limits: Limits = Limits()) -> ScanResult {
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + limits.maxSeconds
        var metrics = Metrics()
        let roots = ClaudeCodeConfigurations.unique(directories)
        let requested = Set(queries.map(\.email))
        guard let earliest = queries.map({ $0.reset.addingTimeInterval(-Reading.week) }).min() else {
            return ScanResult(totals: [:], contributingDirectories: [:], scannedDirectories: [])
        }
        let inputs = Configuration(directories: roots, identities: knownEmails, earliest: earliest)
        if inputs != configuration { cache.removeAll(); configuration = inputs }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        var transcripts: [(Transcript, URL)] = []
        var inventory: [FileEntry] = []
        var seen = Set<URL>()
        var scanned = Set<URL>()
        var coverage = TokenCoverage()
        func stopped() -> Bool { Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline }
        for root in roots {
            if stopped() || metrics.entriesVisited >= limits.maxEntries {
                coverage.directories[root] = .init(access: .limited, limitReached: true)
                continue
            }
            let projects = root.appending(path: "projects")
            let manager = FileManager.default
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  manager.isReadableFile(atPath: root.path) else {
                coverage.directories[root] = .init(access: .unavailable)
                continue
            }
            guard manager.fileExists(atPath: projects.path) else {
                coverage.directories[root] = .init(access: .noProjects)
                continue
            }
            var failed = false
            var limited = false
            guard manager.isReadableFile(atPath: projects.path),
                  let files = manager.enumerator(at: projects, includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in failed = true; return true }) else {
                coverage.directories[root] = .init(access: .unavailable)
                continue
            }
            for case let entry as URL in files {
                if stopped() || metrics.entriesVisited >= limits.maxEntries { limited = true; break }
                metrics.entriesVisited += 1
                guard entry.pathExtension == "jsonl" else { continue }
                // Use the enumerator's prefetched attributes. Only symlinks need filesystem resolution.
                guard var values = try? entry.resourceValues(forKeys: keys) else { failed = true; continue }
                let file: URL
                if values.isSymbolicLink == true {
                    file = ClaudeCodeConfigurations.canonical(entry)
                    guard let resolved = try? file.resourceValues(forKeys: keys) else { failed = true; continue }
                    values = resolved
                } else { file = URL(fileURLWithPath: entry.path, isDirectory: false) }
                guard let date = values.contentModificationDate, let size = values.fileSize else { failed = true; continue }
                guard values.isRegularFile == true, date >= earliest, seen.insert(file).inserted else { continue }
                guard manager.isReadableFile(atPath: file.path) else { failed = true; cache.removeValue(forKey: file); continue }
                inventory.append(FileEntry(file: file, root: root, modified: date, size: size))
            }
            coverage.directories[root] = .init(access: failed ? .partial : limited ? .limited : .scanned, limitReached: limited)
            if !failed && !limited { scanned.insert(root) }
        }
        // Evict removed/changed files before retaining any new index entries.
        let current = Dictionary(uniqueKeysWithValues: inventory.map { ($0.file, $0) })
        cache = cache.filter { file, transcript in
            guard let entry = current[file] else { return false }
            return entry.modified == transcript.modified && entry.size == transcript.size
        }
        var indexed = cache.values.reduce(0) { $0 + $1.samples.count }
        if indexed > limits.maxIndexedRequests { cache.removeAll(); indexed = 0 }
        for entry in inventory {
            let transcript: Transcript
            if let cached = cache[entry.file] {
                transcript = cached
                metrics.cacheHits += 1
            } else {
                guard !stopped(), entry.size <= limits.maxFileBytes,
                      entry.size <= limits.maxBytesRead - metrics.bytesRead else {
                    if coverage.directories[entry.root]?.access != .partial { coverage.directories[entry.root]?.access = .limited }
                    coverage.directories[entry.root]?.limitReached = true
                    scanned.remove(entry.root)
                    continue
                }
                let result = autoreleasepool {
                    read(entry.file, modified: entry.modified, size: entry.size,
                         limits: limits, capacity: limits.maxIndexedRequests - indexed, deadline: deadline, earliest: earliest)
                }
                transcript = result.0
                metrics.filesParsed += 1
                metrics.bytesRead += result.1
                if !transcript.unreadable && !transcript.limited {
                    cache[entry.file] = transcript
                    indexed += transcript.samples.count
                }
            }
            if transcript.unreadable || transcript.limited {
                if transcript.limited {
                    if coverage.directories[entry.root]?.access != .partial { coverage.directories[entry.root]?.access = .limited }
                    coverage.directories[entry.root]?.limitReached = true
                } else { coverage.directories[entry.root]?.access = .partial }
                scanned.remove(entry.root)
                continue
            }
            transcripts.append((transcript, entry.root))
        }
        // The same session cannot belong to two owners in different configuration copies.
        var owners: [String: Set<UUID>] = [:]
        for (transcript, _) in transcripts {
            if let owner = transcript.owner {
                owners[transcript.session, default: []].insert(owner)
            }
        }
        let ambiguousSessions = Set(transcripts.filter { $0.0.ambiguousOwner }.map { $0.0.session })
        for (transcript, root) in transcripts {
            if transcript.owner == nil || transcript.owner.flatMap({ knownEmails[$0] }) == nil ||
                owners[transcript.session, default: []].count > 1 || ambiguousSessions.contains(transcript.session) {
                coverage.directories[root, default: .init()].unverifiedLogs += 1
            }
        }
        var byEmail: [String: [String: Sample]] = [:]
        for (transcript, root) in transcripts {
            guard let owner = transcript.owner, let email = knownEmails[owner], requested.contains(email) else { continue }
            for item in transcript.samples where item.time >= earliest && owners[item.session]?.count == 1 && !ambiguousSessions.contains(item.session) {
                let sample = Sample(directory: root, session: item.session, request: item.request, time: item.time, counts: item.counts)
                let key = sample.session + ":" + sample.request
                if let prior = byEmail[email]?[key] {
                    let winner = sample.counts.total > prior.counts.total ? sample : prior
                    byEmail[email]?[key] = Sample(directory: winner.directory, session: winner.session, request: winner.request,
                                                 time: min(prior.time, sample.time), counts: winner.counts)
                } else { byEmail[email, default: [:]][key] = sample }
            }
        }
        var totals: [UUID: Counts] = [:]
        var contributors: [UUID: Set<URL>] = [:]
        for query in queries {
            let start = query.reset.addingTimeInterval(-Reading.week)
            let records = (byEmail[query.email] ?? [:]).values.filter { $0.time >= start && $0.time < query.reset }
            guard !records.isEmpty else { continue }
            totals[query.id] = records.reduce(into: Counts()) { $0.add($1.counts) }
            contributors[query.id] = Set(records.map(\.directory))
        }
        metrics.elapsedSeconds = ProcessInfo.processInfo.systemUptime - started
        metrics.indexedRequests = indexed
        return ScanResult(totals: totals, contributingDirectories: contributors, scannedDirectories: scanned, coverage: coverage, metrics: metrics)
    }

    static func localIdentities(config: URL? = nil) -> [UUID: String] {
        ClaudeCodeLinking.discover(config: config).identities
    }

    private func read(_ file: URL, modified: Date, size: Int, limits: Limits, capacity: Int, deadline: Double, earliest: Date) -> (Transcript, Int) {
        var empty = Transcript(session: file.deletingPathExtension().lastPathComponent, modified: modified, size: size, owner: nil, samples: [])
        guard let input = try? FileHandle(forReadingFrom: file) else { empty.unreadable = true; return (empty, 0) }
        defer { try? input.close() }
        let decoder = JSONDecoder()
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let wholeSeconds = Date.ISO8601FormatStyle()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = (try? fractional.parse(string)) ?? (try? wholeSeconds.parse(string)) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid transcript timestamp")
            }
            return date
        }
        let session = empty.session
        var owners = Set<UUID>()
        var requests: [String: Sample] = [:]
        var pending = Data()
        var bytes = 0
        do {
            while bytes < size {
                if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline { empty.limited = true; return (empty, bytes) }
                guard let chunk = try input.read(upToCount: min(256 * 1024, size - bytes)), !chunk.isEmpty else {
                    empty.unreadable = true; return (empty, bytes)
                }
                bytes += chunk.count
                pending.append(chunk)
                var start = pending.startIndex
                while let end = pending[start...].firstIndex(of: 10) {
                    if end - start > limits.maxLineBytes { empty.limited = true; return (empty, bytes) }
                    let line = pending[start..<end]
                    if line.range(of: ownerMarker) != nil || line.range(of: usageMarker) != nil,
                       let event = try? decoder.decode(Event.self, from: line), event.sessionId == session {
                        if event.type == "bridge-session", let owner = event.ownerAccountUuid { owners.insert(owner) }
                        if event.type == "assistant", let time = event.timestamp, time >= earliest, let counts = event.message?.usage?.counts, counts.total > 0,
                           let request = event.requestId ?? event.message?.id, !request.isEmpty {
                            if let prior = requests[request] {
                                // Compact streaming snapshots without losing the earliest request time or winning breakdown.
                                requests[request] = Sample(directory: prior.directory, session: session, request: request,
                                    time: min(prior.time, time), counts: counts.total > prior.counts.total ? counts : prior.counts)
                            } else {
                                guard requests.count < capacity else { empty.limited = true; return (empty, bytes) }
                                requests[request] = Sample(directory: file.deletingLastPathComponent(), session: session, request: request, time: time, counts: counts)
                            }
                        }
                    }
                    start = end + 1
                }
                pending = Data(pending[start...])
                if pending.count > limits.maxLineBytes { empty.limited = true; return (empty, bytes) }
            }
            // Only complete JSONL records are indexed. A concurrently changed file is retried later.
            let fresh = try URL(fileURLWithPath: file.path).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard fresh.contentModificationDate == modified, fresh.fileSize == size else { empty.unreadable = true; return (empty, bytes) }
        } catch { empty.unreadable = true; return (empty, bytes) }
        guard owners.count == 1, let owner = owners.first else {
            empty.ambiguousOwner = owners.count > 1
            return (empty, bytes)
        }
        return (Transcript(session: session, modified: modified, size: size, owner: owner, samples: Array(requests.values)), bytes)
    }
}
