import AppKit
import WebKit

@MainActor
final class BrowserSync: NSObject, NSWindowDelegate, WKNavigationDelegate {
    private struct Binding: Decodable {
        let account: UUID
        let email: String
        let workspace: String
    }

    private static let home = URL(string: "https://claude.ai/new")!
    private let store: UsageStore
    private let binding: Binding?
    private let script: String?
    private var signInWindow: NSWindow?
    private var reader: WKWebView?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var navigationFailure: RefreshStatus.State?

    init(store: UsageStore) {
        self.store = store
        let configuration = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Quota Signal/browser-binding.json")
        binding = (try? Data(contentsOf: configuration)).flatMap {
            try? JSONDecoder().decode(Binding.self, from: $0)
        }
        script = Bundle.main.url(forResource: "usage", withExtension: "js").flatMap {
            try? String(contentsOf: $0, encoding: .utf8)
        }
        super.init()
    }

    func start(showErrors: Bool = false) {
        guard UserDefaults.standard.bool(forKey: "backgroundClaudeEnabled"), timer == nil else { return }
        timer = Timer.scheduledTimer(timeInterval: 300, target: self,
                                     selector: #selector(refresh), userInfo: nil, repeats: true)
        runRefresh(showErrors: showErrors)
    }

    func showSignIn() {
        guard binding != nil else {
            inform("Claude workspace is missing", "Configure a workspace before starting background refresh.")
            return
        }
        if signInWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Claude email sign-in · Close after selecting your Ultra workspace"
            window.isReleasedWhenClosed = false
            window.delegate = self
            let browser = makeBrowser()
            window.contentView = browser
            browser.load(URLRequest(url: Self.home))
            window.center()
            signInWindow = window
        }
        NSApp.activate()
        signInWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        signInWindow = nil
        let alreadyEnabled = timer != nil
        UserDefaults.standard.set(true, forKey: "backgroundClaudeEnabled")
        if alreadyEnabled { refreshNow() }
        else { start(showErrors: true) }
    }

    func refreshNow() {
        guard binding != nil, script != nil else {
            inform("Claude workspace is missing", "Configure a workspace before refreshing.")
            return
        }
        runRefresh(showErrors: true)
    }

    @objc private func refresh() { runRefresh(showErrors: false) }

    private func runRefresh(showErrors: Bool) {
        guard refreshTask == nil, let binding, let script, !store.demo else { return }
        refreshTask = Task {
            defer { refreshTask = nil }
            let attempt = UUID()
            let started = Date.now
            store.recordRefresh(for: binding.account, attempt: attempt, started: started, state: .refreshing)
            do {
                try await read(binding, script: script)
                store.recordRefresh(for: binding.account, attempt: attempt, started: started, state: .success)
            } catch is CancellationError {
                return
            } catch {
                let state = (error as? SyncError)?.state ?? .unavailable
                store.recordRefresh(for: binding.account, attempt: attempt, started: started, state: state,
                                    message: (error as? SyncError)?.message)
                if showErrors { inform("Claude usage could not refresh", error.localizedDescription) }
            }
        }
    }

    private func read(_ binding: Binding, script: String) async throws {
        let browser = reader ?? makeBrowser()
        reader = browser
        navigationFailure = nil
        var request = URLRequest(url: Self.home)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        browser.load(request)
        for _ in 0..<20 {
            try await Task.sleep(for: .seconds(1))
            if let navigationFailure { throw SyncError(message: "Claude navigation failed.", state: navigationFailure) }
            guard !browser.isLoading, browser.url?.host == "claude.ai" else { continue }
            let value = try await browser.callAsyncJavaScript(
                script + "\nreturn (await readUsagePage(expected)) ?? null;",
                arguments: ["expected": ["email": binding.email, "workspace": binding.workspace]],
                in: nil, contentWorld: .defaultClient
            )
            guard let sample = value as? [String: Any] else { continue }
            if let error = sample["error"] as? String {
                throw SyncError(message: error, state: (sample["code"] as? String).flatMap(RefreshStatus.State.init(rawValue:)) ?? .unavailable)
            }
            guard let percent = sample["percent"] as? Double, (0...100).contains(percent),
                  let reset = sample["reset"] as? Double, sample["email"] as? String == binding.email,
                  store.accounts.contains(where: { $0.id == binding.account &&
                      ($0.webIdentity?.email ?? $0.name).caseInsensitiveCompare(binding.email) == .orderedSame }) else {
                throw SyncError(message: "The usage reading did not match the configured account.", state: .mismatch)
            }
            let now = Date.now
            let resetDate = Date(timeIntervalSince1970: reset)
            guard resetDate > now, resetDate.timeIntervalSince(now) <= Reading.week + 3600 else {
                throw SyncError(message: "Claude did not provide a valid weekly reset time.", state: .layout)
            }
            let offer = (sample["offer"] as? String).flatMap(ResetOffer.init(rawValue:))
            try Bridge.write(Reading(observed: now, reset: resetDate, percent: percent,
                                     fromWeb: true, backgroundWeb: true, webOffer: offer), for: binding.account)
            store.poll()
            return
        }
        throw SyncError(message: "No verified Claude reading was available before the refresh timed out.")
    }

    private func makeBrowser() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let browser = WKWebView(frame: NSRect(x: 0, y: 0, width: 1080, height: 760), configuration: configuration)
        browser.navigationDelegate = self
        return browser
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let code = (error as NSError).code
        guard webView === reader, code != NSURLErrorCancelled else { return }
        let networkCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
                            NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut, NSURLErrorDNSLookupFailed]
        navigationFailure = networkCodes.contains(code) ? .network : .unavailable
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    private func inform(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    private struct SyncError: LocalizedError {
        let message: String
        var state: RefreshStatus.State = .unavailable
        var errorDescription: String? { message }
    }
}
