import Foundation

struct TokenCoverage: Sendable {
    enum Access: String, Sendable {
        case scanned, noProjects, unavailable, partial, limited
        var label: String {
            switch self {
            case .scanned: "Folder scanned"
            case .noProjects: "No projects folder yet"
            case .unavailable: "Folder unavailable or inaccessible"
            case .partial: "Some files or subfolders could not be read"
            case .limited: "Scan limit reached; coverage is partial"
            }
        }
    }
    struct Directory: Sendable {
        var access: Access = .scanned
        var unverifiedLogs = 0
        var limitReached = false
    }
    var directories: [URL: Directory] = [:]
    var hasUnavailable: Bool { directories.values.contains { $0.access == .unavailable || $0.access == .partial } }
    var hasUnverifiedOwnership: Bool { directories.values.contains { $0.unverifiedLogs > 0 } }
    var hasLimit: Bool { directories.values.contains { $0.access == .limited || $0.limitReached } }
    var isPartial: Bool { hasUnavailable || hasUnverifiedOwnership || hasLimit }

    var explanation: String {
        var notes = ["Totals cover eligible local Claude Code requests in this account's weekly quota window, not all activity on Claude."]
        if hasLimit { notes.append("A background work limit was reached. Totals include only the indexed requests. Later scans reuse the index and can process more changed files; oversized files or index/entry limits require reducing the selected sources.") }
        if hasUnavailable { notes.append("Some selected folders or files could not be read. Available attributable tokens are included; the total may be incomplete. Check folder access in Log Sources and rescan.") }
        if hasUnverifiedOwnership { notes.append("Some logs have missing, unknown or conflicting ownership and were excluded. They may belong to another account. Review ID links and enabled sources; the app does not guess ownership.") }
        if !isPartial { notes.append("No access or ownership gaps were detected in the files considered by this scan. Missing activity on other devices or unsupported records is not reconstructed.") }
        return notes.joined(separator: " ")
    }
}
