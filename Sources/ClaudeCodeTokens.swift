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
        let modified: Date
        let size: Int
        let owner: UUID?
        let samples: [Sample]
    }

    private var cache: [URL: Transcript] = [:]
    private let usageMarker = Data(#""usage":"#.utf8)
    private let ownerMarker = Data(#""ownerAccountUuid":"#.utf8)

    struct ScanResult: Sendable {
        let totals: [UUID: Counts]
        let contributingDirectories: [UUID: Set<URL>]
        let scannedDirectories: Set<URL>
    }

    func totals(for queries: [Query], knownEmails: [UUID: String]) -> [UUID: Counts] {
        scan(for: queries, knownEmails: knownEmails, directories: [ClaudeCodeConfigurations.primary]).totals
    }

    func scan(for queries: [Query], knownEmails: [UUID: String], directories: [URL]) -> ScanResult {
        let requested = Set(queries.map(\.email))
        guard knownEmails.values.contains(where: requested.contains),
              let earliest = queries.map({ $0.reset.addingTimeInterval(-Reading.week) }).min() else {
            return ScanResult(totals: [:], contributingDirectories: [:], scannedDirectories: [])
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var transcripts: [(Transcript, URL)] = []
        var seen = Set<URL>()
        var scanned = Set<URL>()
        for root in ClaudeCodeConfigurations.unique(directories) {
            let projects = root.appending(path: "projects")
            var failed = false
            guard FileManager.default.isReadableFile(atPath: projects.path),
                  let files = FileManager.default.enumerator(at: projects, includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in failed = true; return true }) else { continue }
            for case let entry as URL in files {
                let file = ClaudeCodeConfigurations.canonical(entry)
                guard file.pathExtension == "jsonl", let values = try? file.resourceValues(forKeys: keys),
                      values.isRegularFile == true, let date = values.contentModificationDate,
                      date >= earliest, let size = values.fileSize, seen.insert(file).inserted else { continue }
                let transcript: Transcript
                if let cached = cache[file], cached.modified == date, cached.size == size { transcript = cached }
                else { transcript = read(file, modified: date, size: size); cache[file] = transcript }
                transcripts.append((transcript, root))
            }
            if !failed { scanned.insert(root) }
        }
        cache = cache.filter { seen.contains($0.key) }
        // The same session cannot belong to two owners in different configuration copies.
        var owners: [String: Set<UUID>] = [:]
        for (transcript, _) in transcripts {
            if let owner = transcript.owner {
                owners[transcript.session, default: []].insert(owner)
            }
        }
        let ambiguousSessions = Set(transcripts.filter { $0.0.ambiguousOwner }.map { $0.0.session })
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
        return ScanResult(totals: totals, contributingDirectories: contributors, scannedDirectories: scanned)
    }

    static func localIdentities(config: URL? = nil) -> [UUID: String] {
        ClaudeCodeLinking.discover(config: config).identities
    }

    private func read(_ file: URL, modified: Date, size: Int) -> Transcript {
        let empty = Transcript(session: file.deletingPathExtension().lastPathComponent, modified: modified, size: size, owner: nil, samples: [])
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return empty }
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
        let session = file.deletingPathExtension().lastPathComponent
        var owners: Set<UUID> = []
        for line in Self.lines(in: data, containing: ownerMarker) {
            guard let event = try? decoder.decode(Event.self, from: line),
                  event.type == "bridge-session", event.sessionId == session, let owner = event.ownerAccountUuid else { continue }
            owners.insert(owner)
        }
        guard owners.count == 1, let owner = owners.first else {
            var rejected = empty
            rejected.ambiguousOwner = owners.count > 1
            return rejected
        }
        var samples: [Sample] = []
        for line in Self.lines(in: data, containing: usageMarker) {
            guard let event = try? decoder.decode(Event.self, from: line),
                  event.type == "assistant", event.sessionId == session, let time = event.timestamp,
                  let counts = event.message?.usage?.counts, counts.total > 0,
                  let request = event.requestId ?? event.message?.id, !request.isEmpty else { continue }
            samples.append(Sample(directory: file.deletingLastPathComponent(), session: session, request: request, time: time, counts: counts))
        }
        return Transcript(session: session, modified: modified, size: size, owner: owner, samples: samples)
    }

    private static func lines(in data: Data, containing marker: Data) -> AnySequence<Data> {
        AnySequence {
            var position = data.startIndex
            return AnyIterator<Data> {
                guard position < data.endIndex,
                      let match = data.range(of: marker, in: position..<data.endIndex) else { return nil }
                let start = data[position..<match.lowerBound].lastIndex(of: 10).map { $0 + 1 } ?? position
                guard let end = data[match.upperBound...].firstIndex(of: 10) else { return nil }
                position = end + 1
                return Data(data[start..<end])
            }
        }
    }
}
