import Foundation

enum ChromeCompanion {
    static func prepare() throws -> URL {
        let files = FileManager.default
        let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
        let directory = support.appending(path: "Quota Signal", directoryHint: .isDirectory)
        let companion = directory.appending(path: "Chrome Companion", directoryHint: .isDirectory)
        guard let resources = Bundle.main.resourceURL,
              let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        try files.createDirectory(at: companion, withIntermediateDirectories: true)
        for name in ["manifest.json", "worker.js", "usage.js", "setup.html", "setup.js"] {
            let data = try Data(contentsOf: resources.appending(path: "Chrome").appending(path: name))
            try data.write(to: companion.appending(path: name), options: .atomic)
        }
        try Data("export const binding = null;\n".utf8)
            .write(to: companion.appending(path: "binding.js"), options: .atomic)

        let host = directory.appending(path: "chrome-native-host")
        let quotedExecutable = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        try Data("#!/bin/sh\nexec \(quotedExecutable) web-capture\n".utf8).write(to: host, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: host.path)
        let manifests = support.appending(path: "Google/Chrome/NativeMessagingHosts", directoryHint: .isDirectory)
        try files.createDirectory(at: manifests, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "name": "local.quota_signal",
            "description": "Quota Signal local usage bridge",
            "path": host.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://gjjgdcalfbbaphaebkfbkomodcejmina/"]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifests.appending(path: "local.quota_signal.json"), options: .atomic)
        return companion
    }
}
