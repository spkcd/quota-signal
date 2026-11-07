import AppKit
import SwiftUI

struct ClaudeCodeSourcesView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Claude Code Log Sources").font(.system(size: 21, weight: .semibold))
            Text("Choose configuration folders containing projects or .claude.json. These sources apply to all accounts and are read locally. Your active Claude Code login is unchanged.")
                .foregroundStyle(Instrument.muted).fixedSize(horizontal: false, vertical: true)
            if let account = store.current {
                Text("Coverage for \(account.webIdentity?.email ?? account.name)").font(.headline)
                Text(store.localTokenStatus(for: account).label).fontWeight(.semibold)
                Text(store.tokenCoverageExplanation(for: account)).font(.system(size: 12))
                    .foregroundStyle(Instrument.muted).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.localTokenDirectories, id: \.self) { url in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(url == ClaudeCodeConfigurations.primary ? "Primary configuration" : url.lastPathComponent).fontWeight(.semibold)
                                Spacer()
                                if url != ClaudeCodeConfigurations.primary {
                                    Button("Remove") { store.removeTokenDirectory(url) }
                                        .accessibilityLabel("Remove source \(url.path)")
                                }
                            }
                            Text(url.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            Text(status(url)).font(.system(size: 12)).foregroundStyle(Instrument.muted)
                        }
                        Divider()
                    }
                }
            }.frame(height: 205)
            Text("Copied sessions count once. For equal copies, the first source supplies the count; a larger usage snapshot takes precedence. The source labels reflect those included requests.")
                .font(.system(size: 12)).foregroundStyle(Instrument.muted).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(Instrument.warning) }
            HStack {
                Button("Add folder…") { add() }.disabled(store.demo)
                Button("Rescan") { store.refreshLocalTokens(force: true) }.disabled(store.demo)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 450).preferredColorScheme(.dark)
    }

    private func status(_ url: URL) -> String {
        guard !store.localTokenScanInProgress, let date = store.localTokenScanCompletedAt else { return "Checking local logs…" }
        let included = store.current.map { store.contributingTokenDirectories[$0.id]?.contains(url) == true } ?? false
        let state = included ? "Included in this account's total" : store.scannedTokenDirectories.contains(url)
            ? "No unique requests included for this account" : "Not fully scanned or unavailable"
        let coverage = store.localTokenCoverage.directories[url]
        let access = coverage?.access.label ?? "Not considered by this scan"
        let ownership = (coverage?.unverifiedLogs ?? 0) > 0 ? " · Logs with unverified ownership: \(coverage!.unverifiedLogs)" : ""
        return access + " · " + state + ownership + " · Checked " + date.formatted(date: .omitted, time: .standard)
    }

    private func add() {
        let picker = NSOpenPanel()
        picker.title = "Choose Claude Code Configuration Folders"
        picker.message = "Select the configuration root, such as .claude, containing projects or .claude.json."
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = true
        picker.showsHiddenFiles = true
        guard picker.runModal() == .OK else { return }
        error = store.addTokenDirectories(picker.urls) ? nil : "Choose readable configuration folders containing projects or .claude.json. No folders were added."
    }
}
