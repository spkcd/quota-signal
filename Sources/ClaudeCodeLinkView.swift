import AppKit
import SwiftUI

struct ClaudeCodeLinkView: View {
    @ObservedObject var store: UsageStore
    let account: Account
    @Environment(\.dismiss) private var dismiss
    @ViewState private var ids: [UUID] = []
    @ViewState private var checking = true
    @ViewState private var message = "Checking local Claude Code account metadata…"
    @ViewState private var copied = false
    @ViewState private var linked = false

    private var email: String { (account.webIdentity?.email ?? account.name).lowercased() }

    private var hasEmail: Bool { email.contains("@") && !email.contains(where: { $0.isWhitespace }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link Claude Code").font(.system(size: 21, weight: .semibold))
            Text(email).font(.headline).textSelection(.enabled)
            Text("Find a Claude Code account ID for this email, verify it, then rescan local tokens. Checking and linking do not change your active Claude Code login.")
                .foregroundStyle(Instrument.muted).fixedSize(horizontal: false, vertical: true)
            Text(message).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("claude-code-link-status")
            if !ids.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(ids, id: \.self) { id in
                            Text(id.uuidString).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }.frame(maxHeight: 76)
            }
            if !linked {
                Divider()
                Text("Need another sign-in?").font(.headline)
                Text("In Terminal, run the copied command and sign in with the email above. Running it can replace your active Claude Code login. Return here and choose Check again. The email hint does not verify the account; local metadata must match.")
                    .font(.system(size: 12)).foregroundStyle(Instrument.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(copied ? "Command copied" : "Copy sign-in command") {
                        guard let executable = ClaudeCodeTokens.executableURL() else { return }
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(ClaudeCodeLinking.loginCommand(email: email, executable: executable), forType: .string)
                    }.disabled(!hasEmail || ClaudeCodeTokens.executableURL() == nil)
                    Button("Open Terminal") { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: .init()) }
                }
                if ClaudeCodeTokens.executableURL() == nil {
                    Text("Claude Code was not found. Install the CLI, then reopen this guide to copy its sign-in command.")
                        .font(.system(size: 12)).foregroundStyle(Instrument.warning)
                }
            }
            HStack {
                Button(linked ? "Done" : "Cancel", role: .cancel) { dismiss() }
                Spacer()
                if !linked {
                    Button("Check again") { Task { await check() } }.disabled(checking)
                    Button("Link verified IDs") {
                        checking = true
                        Task {
                            linked = await store.linkClaudeCode(for: account, expectedIDs: ids)
                            message = linked ? "Linked. Scanning local tokens now, or immediately after the current scan finishes. A linked account can still have no logs this week."
                                : "The discovered identity changed or could not be verified. Check again before linking."
                            if !linked { ids = [] }
                            checking = false
                        }
                    }.disabled(checking || ids.isEmpty)
                }
            }
        }
        .padding(20).frame(width: 410).preferredColorScheme(.dark)
        .task { await check() }
    }

    @MainActor private func check() async {
        checking = true
        guard hasEmail else {
            ids = []
            message = "This account needs a sign-in email. Connect it in Chrome or edit its account name to the Claude email, then reopen this guide."
            checking = false
            return
        }
        let discovery = await Task.detached { ClaudeCodeLinking.discover() }.value
        ids = discovery.matching(email)
        message = ids.isEmpty
            ? "No unambiguous Claude Code ID was found for this email. Sign in using the steps below, then check again."
            : "Found \(ids.count) ID(s) whose local account metadata matches this email. Review the IDs below, then link."
        if !discovery.conflictingIDs.isEmpty { message += " Conflicting ID records were excluded." }
        checking = false
    }
}
