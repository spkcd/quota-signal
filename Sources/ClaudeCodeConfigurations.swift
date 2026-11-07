import Foundation

enum ClaudeCodeConfigurations {
    static let preferenceKey = "claudeCodeAdditionalDirectories"

    static var primary: URL {
        canonical(ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude", directoryHint: .isDirectory))
    }

    static func canonical(_ url: URL) -> URL {
        // A folder URL and its symlink can carry different trailing-slash hints.
        URL(fileURLWithPath: url.standardizedFileURL.resolvingSymlinksInPath().path, isDirectory: false)
    }

    static func directories(defaults: UserDefaults = .standard) -> [URL] {
        unique([primary] + (defaults.stringArray(forKey: preferenceKey) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.map(canonical).filter { seen.insert($0).inserted }
    }

    static func isSupported(_ url: URL) -> Bool {
        let root = canonical(url)
        let files = FileManager.default
        var directory: ObjCBool = false
        guard files.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue,
              files.isReadableFile(atPath: root.path) else { return false }
        let projects = root.appending(path: "projects")
        let hasProjects = files.fileExists(atPath: projects.path, isDirectory: &directory) && directory.boolValue
        return hasProjects || files.isReadableFile(atPath: root.appending(path: ".claude.json").path)
    }
}
