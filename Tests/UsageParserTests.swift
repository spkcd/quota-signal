import AppKit
import WebKit

// Uses real WebKit DOM semantics. All pages and identities are synthetic; no network or real profile is used.
@main
@MainActor
struct UsageParserTests {
    static func main() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let html = try String(contentsOf: root.appending(path: "Tests/Fixtures/Usage/page.html"), encoding: .utf8)
        let data = try Data(contentsOf: root.appending(path: "Tests/Fixtures/Usage/cases.json"))
        let cases = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let parser = try String(contentsOf: root.appending(path: "Chrome/usage.js"), encoding: .utf8)
            .replacingOccurrences(of: "export async function", with: "async function")
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let browser = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800), configuration: config)
        for fixture in cases {
            browser.loadHTMLString(html, baseURL: URL(string: "https://claude.ai/new")!)
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(20))
                if !browser.isLoading { break }
            }
            let setup = fixture["setup"] as? String ?? ""
            // Freeze the local clock to Saturday in the system timezone; assertions use exact seconds, not relative dates.
            let script = """
            \(setup);
            // Static fixtures need no loading delay. Production wait limits are covered by worker timeout tests.
            const setTimeout = callback => callback();
            const NativeDate = globalThis.Date;
            const Date = class extends NativeDate {
              constructor(...args) { super(...(args.length ? args : ['2026-11-07T10:00:00'])); }
            };
            \(parser)
            return await readUsagePage({email:'reader@example.com',workspace:'Fixture Studio',plan:'Ultra'});
            """
            let result = try await browser.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
            let name = fixture["name"] as! String
            guard let result else { fatalError("\(name): missing parser result") }
            if let code = fixture["code"] as? String {
                precondition(result["code"] as? String == code, "\(name): \(result)")
                precondition(result["percent"] == nil && result["reset"] == nil, "Failed capture leaked a reading")
                precondition(!(result["error"] as? String ?? "").isEmpty)
            } else {
                precondition(result["percent"] as? Double == fixture["percent"] as? Double, "\(name): \(result)")
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                formatter.timeZone = .current
                let reset = formatter.date(from: fixture["reset"] as! String)!.timeIntervalSince1970
                precondition(result["reset"] as? Double == reset, "\(name): \(result)")
                precondition(result["email"] as? String == "reader@example.com")
            }
            FileHandle.standardOutput.write(Data("Passed: \(name)\n".utf8))
        }
        print("Usage parser passed \(cases.count) synthetic WebKit layout, locale, cycle and identity fixtures.")
    }
}
