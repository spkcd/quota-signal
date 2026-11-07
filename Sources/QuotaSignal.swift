import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class WidgetController: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private lazy var browserSync = BrowserSync(store: store)
    private lazy var wakeRecovery = WakeRecovery { [weak self] in
        guard let self, !self.store.demo else { return }
        try? RecoverySignal.publish()
        self.store.poll()
        self.store.refreshLocalTokens(force: true)
        self.browserSync.recover()
    }
    private var panel: FloatingPanel!
    private var status: NSStatusItem!
    private let statusMenu = NSMenu()
    private lazy var loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--demo") || args.contains("--snapshot") {
            store.toggleDemo()
            store.showingDetail = args.contains("--demo-detail")
        }
        let view = PanelView(store: store, hide: { [weak self] in self?.panel.orderOut(nil) },
                             exportDiagnostics: { [weak self] in self?.exportDiagnostics() },
                             addAccount: { [weak self] in self?.addAccountInChrome() },
                             accountAction: { [weak self] account, reconnect in
                                 self?.openAccountAction(account, reconnect: reconnect)
                             })
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Instrument.width, height: Instrument.height),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Quota Signal"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.safeAreaRegions = []
        panel.contentView = host
        if !panel.setFrameUsingName("QuotaSignalPanel") {
            let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - Instrument.width - 20, y: frame.maxY - 20))
        }
        panel.setFrameAutosaveName("QuotaSignalPanel")

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Quota Signal")
        status.button?.imagePosition = .imageLeading
        status.button?.target = self
        status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        for (title, action, key) in [
            ("Open dashboard", #selector(showDashboard), ""),
            ("Hide widget", #selector(hidePanel), ""),
            ("Set Up Chrome Companion…", #selector(prepareChromeCompanion), ""),
            ("Open Claude sign-in in Chrome", #selector(signInInChrome), ""),
            ("Sign in with email for Chrome-free refresh", #selector(signInForRefresh), ""),
            ("Refresh Claude usage now", #selector(refreshClaude), ""),
            ("Export Support Diagnostics…", #selector(exportDiagnostics), ""),
            ("Toggle demo data", #selector(toggleDemo), ""),
            ("Quit Quota Signal", #selector(quit), "q")
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            statusMenu.addItem(item)
        }
        loginItem.target = self
        statusMenu.insertItem(loginItem, at: 2)
        if args.contains("--enable-launch-at-login"), !store.demo, SMAppService.mainApp.status != .enabled {
            toggleLoginItem()
        }
        updateStatus()
        showPanel()
        if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
            let destination = URL(fileURLWithPath: args[index + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                host.layoutSubtreeIfNeeded()
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: destination)
                }
                NSApp.terminate(nil)
            }
        }
        if !args.contains("--demo"), !args.contains("--snapshot") {
            browserSync.start()
            store.refreshLocalTokens()
            wakeRecovery.start()
        }
        let pollTimer = Timer(timeInterval: 5, target: self,
                              selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(pollTimer, forMode: .common)
        timer = pollTimer
    }

    @objc private func showPanel() { panel.orderFrontRegardless() }
    @objc private func showDashboard() {
        store.showingDetail = false
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func statusClicked(_ button: NSStatusBarButton) {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            let loginStatus = SMAppService.mainApp.status
            loginItem.state = loginStatus == .enabled ? .on : .off
            loginItem.title = loginStatus == .requiresApproval ? "Approve Launch at Login…" : "Launch at Login"
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
        } else {
            showDashboard()
        }
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled: try service.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func exportDiagnostics() {
        let save = NSSavePanel()
        save.title = "Export Support Diagnostics"
        save.message = "Saves a local JSON report with anonymous account labels, versions, refresh timings, states and error codes. Emails, workspace names, paths, raw errors and transcript text are excluded. Nothing is uploaded."
        save.nameFieldStringValue = "Quota-Signal-Diagnostics.json"
        save.allowedContentTypes = [.json]
        save.canCreateDirectories = true
        NSApp.activate()
        guard save.runModal() == .OK, let url = save.url else { return }
        do {
            let data = try SupportDiagnostics.data(accountIDs: store.accounts.map(\.id),
                                                   chromeRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty)
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func prepareChromeCompanion() {
        do {
            let folder = try ChromeCompanion.prepare()
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            let alert = NSAlert()
            alert.messageText = "Load the Quota Signal companion"
            alert.informativeText = "Open chrome://extensions in the Chrome profile you use for Claude. Turn on Developer mode, click Load unpacked, and choose the Chrome Companion folder shown in Finder. Then click + in Quota Signal."
            alert.runModal()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func updateStatus() {
        guard let button = status.button else { return }
        let now = Date.now
        let best = store.accounts.lazy.map { AccountOverviewRow(account: $0, now: now) }
            .filter { !$0.isStale && $0.activeReading != nil }
            .min { $0.precedes($1) }
        let title: String
        let description: String
        if let best, let reading = best.activeReading {
            let name = best.account.webIdentity?.email ?? best.account.name
            let compactName = name.count > 28 ? "\(name.prefix(16))…\(name.suffix(10))" : name
            let remaining = Instrument.percentage(100 - reading.percent)
            title = "\(compactName) · \(remaining) left"
            description = "\(name), \(remaining) weekly quota remaining"
        } else {
            title = "Quota Signal"
            description = "Quota Signal, no fresh weekly reading"
        }
        let prefix = store.demo ? "Demo: " : ""
        button.title = prefix + title
        button.setAccessibilityLabel(prefix + description + ". Open dashboard")
        button.toolTip = prefix + description + ". Click to open dashboard. Right-click for options."
    }

    @objc private func hidePanel() { panel.orderOut(nil) }
    @objc private func toggleDemo() {
        store.toggleDemo()
        updateStatus()
        showPanel()
    }
    private func addAccountInChrome() {
        do {
            let request = try WebCapture.beginPairing()
            let setup = URL(string: "chrome-extension://gjjgdcalfbbaphaebkfbkomodcejmina/setup.html#" + request.uuidString)!
            openInChrome(setup)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func openAccountAction(_ account: Account, reconnect: Bool) {
        var profiles = ChromeAccountActions.profiles()
        if profiles.isEmpty {
            let picker = NSOpenPanel()
            picker.title = "Choose Chrome’s Local State file"
            picker.message = "Quota Signal uses the profile names to open the correct Chrome window. Select Chrome’s Local State file."
            picker.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/Google/Chrome")
            picker.canChooseDirectories = false
            picker.allowsMultipleSelection = false
            guard picker.runModal() == .OK, let url = picker.url else { return }
            do {
                profiles = try ChromeAccountActions.profiles(from: Data(contentsOf: url))
                // Retain only profile names and directories, never Chrome's complete configuration.
                UserDefaults.standard.set(try JSONEncoder().encode(profiles), forKey: "chromeProfileNames")
            } catch {
                NSAlert(error: error).runModal()
                return
            }
        }
        var profile = ChromeAccountActions.suggestedProfile(for: account, profiles: profiles)
        if (reconnect || profile == nil), !profiles.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Choose the Chrome profile for this account"
            alert.informativeText = "Select the profile used for \(account.name). Quota Signal verifies the Claude workspace before saving this route."
            let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 330, height: 28))
            picker.addItems(withTitles: profiles.map(\.label))
            if let profile, let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                picker.selectItem(at: index)
            }
            alert.accessoryView = picker
            alert.addButton(withTitle: reconnect ? "Reconnect" : "Retry")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            profile = profiles[picker.indexOfSelectedItem]
        }
        guard let profile else {
            let alert = NSAlert()
            alert.messageText = "No Chrome profile is available"
            alert.informativeText = "Open Chrome, set up a profile, and load the Quota Signal companion."
            alert.runModal()
            return
        }
        do {
            try ChromeAccountActions.open(account: account, reconnect: reconnect, profile: profile)
            store.poll()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func signInInChrome() {
        openInChrome(URL(string: "https://claude.ai/new")!)
    }

    private func openInChrome(_ url: URL) {
        let workspace = NSWorkspace.shared
        guard let chrome = workspace.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            let alert = NSAlert()
            alert.messageText = "Google Chrome is unavailable"
            alert.informativeText = "Install Chrome to use the Claude browser companion."
            alert.runModal()
            return
        }
        workspace.open([url], withApplicationAt: chrome, configuration: .init()) { _, error in
            guard let error else { return }
            Task { @MainActor in
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    @objc private func signInForRefresh() { browserSync.showSignIn() }
    @objc private func refreshClaude() { browserSync.refreshNow() }
    @objc private func poll() {
        store.poll()
        updateStatus()
        store.refreshLocalTokens()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        wakeRecovery.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }
}

@main
struct QuotaSignal {
    @MainActor
    static func main() {
        let args = ProcessInfo.processInfo.arguments
        if args.count >= 2, args[1] == "web-capture" {
            WebCapture.run()
            return
        }
        if args.count == 3, args[1] == "capture", let id = UUID(uuidString: args[2]) {
            do { try Bridge.capture(id: id) }
            catch {
                FileHandle.standardError.write(Data("Quota Signal could not save the reading.\n".utf8))
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        let controller = WidgetController()
        app.delegate = controller
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(controller) { app.run() }
    }
}
