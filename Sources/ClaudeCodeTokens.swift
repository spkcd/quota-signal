import Foundation

actor ClaudeCodeTokens {
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
        let request: String
        let time: Date
        let counts: Counts
    }

    private struct Transcript {
        let modified: Date
        let size: Int
        let owner: UUID?
        let samples: [Sample]
    }

    private var cache: [URL: Transcript] = [:]
    private let usageMarker = Data(#""usage":"#.utf8)
    private let ownerMarker = Data(#""ownerAccountUuid":"#.utf8)

    func totals(for queries: [Query], knownEmails: [UUID: String]) -> [UUID: Counts] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? home.appending(path: ".claude", directoryHint: .isDirectory)
        let requested = Set(queries.map(\.email))
        guard knownEmails.values.contains(where: requested.contains),
              let earliest = queries.map({ $0.reset.addingTimeInterval(-Reading.week) }).min() else { return [:] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: config.appending(path: "projects"),
                                                         includingPropertiesForKeys: Array(keys),
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [:] }
        var byEmail: [String: [String: Sample]] = [:]
        var seen: Set<URL> = []
        for case let file as URL in files {
            guard file.pathExtension == "jsonl", let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, let date = values.contentModificationDate,
                  date >= earliest, let size = values.fileSize else { continue }
            seen.insert(file)
            let transcript: Transcript
            if let cached = cache[file], cached.modified == date, cached.size == size {
                transcript = cached
            } else {
                transcript = read(file, modified: date, size: size)
                cache[file] = transcript
            }
            guard let owner = transcript.owner, let email = knownEmails[owner], requested.contains(email) else { continue }
            for sample in transcript.samples where sample.time >= earliest {
                if let prior = byEmail[email]?[sample.request] {
                    // Keep the breakdown from the same snapshot as the winning total.
                    let counts = sample.counts.total > prior.counts.total ? sample.counts : prior.counts
                    byEmail[email]?[sample.request] = Sample(request: sample.request,
                                                            time: min(prior.time, sample.time), counts: counts)
                } else {
                    byEmail[email, default: [:]][sample.request] = sample
                }
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        return Dictionary(uniqueKeysWithValues: queries.compactMap { query in
            let start = query.reset.addingTimeInterval(-Reading.week)
            guard let records = byEmail[query.email]?.values else { return nil }
            let inCycle = records.filter { $0.time >= start && $0.time < query.reset }
            guard !inCycle.isEmpty else { return nil }
            return (query.id, inCycle.reduce(into: Counts()) { $0.add($1.counts) })
        })
    }

    static func localIdentities(config: URL? = nil) -> [UUID: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let directory = config ?? override ?? home.appending(path: ".claude", directoryHint: .isDirectory)
        let backups = (try? FileManager.default.contentsOfDirectory(at: directory.appending(path: "backups"),
                                                                   includingPropertiesForKeys: nil)) ?? []
        let current = override == nil ? home.appending(path: ".claude.json") : directory.appending(path: ".claude.json")
        var identities: [UUID: String] = [:]
        for file in backups.filter({ $0.lastPathComponent.hasPrefix(".claude.json") }) + [current] {
            guard let data = try? Data(contentsOf: file),
                  let account = try? JSONDecoder().decode(AccountFile.self, from: data).oauthAccount else { continue }
            identities[account.accountUuid] = account.emailAddress.lowercased()
        }
        return identities
    }

    private func read(_ file: URL, modified: Date, size: Int) -> Transcript {
        let empty = Transcript(modified: modified, size: size, owner: nil, samples: [])
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
        guard owners.count == 1, let owner = owners.first else { return empty }
        var samples: [Sample] = []
        for line in Self.lines(in: data, containing: usageMarker) {
            guard let event = try? decoder.decode(Event.self, from: line),
                  event.type == "assistant", event.sessionId == session, let time = event.timestamp,
                  let counts = event.message?.usage?.counts, counts.total > 0,
                  let request = event.requestId ?? event.message?.id, !request.isEmpty else { continue }
            samples.append(Sample(request: request, time: time, counts: counts))
        }
        return Transcript(modified: modified, size: size, owner: owner, samples: samples)
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
