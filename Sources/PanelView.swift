import AppKit
import SwiftUI

// Use the property wrapper on both SDKs that expose State as a macro and older SDKs.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Instrument {
    static let frame = Color(red: 0.078, green: 0.091, blue: 0.105)
    static let surface = Color(red: 0.105, green: 0.122, blue: 0.139)
    static let well = Color(red: 0.068, green: 0.081, blue: 0.096)
    static let rule = Color(red: 0.21, green: 0.24, blue: 0.27)
    static let ink = Color(red: 0.92, green: 0.95, blue: 0.97)
    static let muted = Color(red: 0.62, green: 0.68, blue: 0.73)
    static let signal = Color(red: 0.35, green: 0.89, blue: 0.94)
    static let warning = Color(red: 1, green: 0.74, blue: 0.43)
    static let usageOrange = Color(red: 1, green: 0.62, blue: 0.27)
    static let usageRed = Color(red: 1, green: 0.39, blue: 0.42)
    static let width: CGFloat = 398
    static let height: CGFloat = 475
    static let settings = URL(string: "https://claude.ai/settings/usage")!

    static func usageColor(_ percent: Double?) -> Color {
        guard let percent else { return muted }
        if percent >= 90 { return usageRed }
        if percent >= 75 { return usageOrange }
        return signal
    }

    static func percentage(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }
}

@MainActor struct AccountOverviewRow {
    let account: Account
    let now: Date
    private static let freshnessWindow: TimeInterval = 15 * 60
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var activeReading: Reading? {
        account.latest.flatMap { $0.reset > now ? $0 : nil }
    }

    var isStale: Bool {
        guard let latest = account.latest else { return false }
        return latest.reset <= now || now.timeIntervalSince(latest.observed) >= Self.freshnessWindow
    }

    var freshness: String {
        guard let latest = account.latest else { return "No readings yet" }
        let age = max(0, now.timeIntervalSince(latest.observed))
        let updated = age < 60 ? "Updated just now" : "Updated " + Self.relativeFormatter
            .localizedString(for: latest.observed, relativeTo: now)
        return isStale ? "Stale · " + updated : updated
    }

    func precedes(_ other: Self) -> Bool {
        // Current-cycle readings are comparable even if stale. Put expired and missing readings last.
        let rank = availabilityRank
        let otherRank = other.availabilityRank
        if rank != otherRank { return rank < otherRank }
        return (activeReading?.percent ?? 0) < (other.activeReading?.percent ?? 0)
    }

    private var availabilityRank: Int {
        if activeReading != nil { return isStale ? 1 : 0 }
        return account.latest == nil ? 3 : 2
    }
}

struct PanelView: View {
    @ObservedObject var store: UsageStore
    var hide: () -> Void
    var addAccount: () -> Void
    var accountAction: (Account, Bool) -> Void
    @ViewState private var editor: Account?
    @ViewState private var showingRefreshDetails = false

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 16).frame(height: 49)
            Group {
                if store.accounts.isEmpty {
                    empty
                } else if store.showingDetail, let account = store.current {
                    accountDetail(account)
                } else {
                    accountOverview
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Instrument.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Instrument.rule, lineWidth: 1))
            .padding([.horizontal, .bottom], 8)
        }
        .frame(width: Instrument.width, height: Instrument.height)
        .background(Instrument.frame)
        .foregroundStyle(Instrument.ink)
        .preferredColorScheme(.dark)
        .sheet(item: $editor) { account in
            AccountEditor(store: store, original: account)
        }
        .onChange(of: store.demo) { store.showingDetail = false }
        .onChange(of: store.accounts.map(\.id)) { _, accountIDs in
            if accountIDs.isEmpty { store.showingDetail = false }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if store.showingDetail {
                Button { store.showingDetail = false } label: {
                    Image(systemName: "chevron.left").frame(width: 24, height: 24)
                }
                .help("All accounts").accessibilityLabel("Back to all accounts")
            }
            Image(systemName: "waveform.path").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Instrument.signal).accessibilityHidden(true)
            Text("Quota Signal").font(.system(size: 15, weight: .semibold))
            if store.demo {
                Text("Demo data").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Instrument.warning)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(Instrument.rule))
            }
            Spacer()
            if !store.demo {
                Button(action: addAccount) {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .help("Add account").accessibilityLabel("Add account")
                .contextMenu { Button("Add manually") { editor = Account(name: "") } }
            }
            Button(action: hide) {
                Image(systemName: "minus").frame(width: 24, height: 24)
            }
            .help("Hide widget").accessibilityLabel("Hide widget")
        }
        .buttonStyle(.borderless)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 32, weight: .light))
                .foregroundStyle(Instrument.signal).accessibilityHidden(true)
            Text("Track your Claude week").font(.system(size: 25, weight: .semibold))
            Text("Add an account to see its weekly usage, next reset, and free reset availability.")
                .font(.system(size: 14)).foregroundStyle(Instrument.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Add account", action: addAccount)
                    .controlSize(.large)
                Button("View demo") { store.toggleDemo() }
                    .buttonStyle(.borderless)
                    .controlSize(.large)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var accountOverview: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let now = max(context.date, .now)
            let rows = store.accounts.map { AccountOverviewRow(account: $0, now: now) }
                .sorted { $0.precedes($1) }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Accounts").font(.system(size: 18, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if store.demo {
                        Button("Exit demo") { store.toggleDemo() }.buttonStyle(.borderless)
                    } else {
                        Text(store.accounts.count == 1 ? "1 account" : "\(store.accounts.count) accounts")
                            .font(.system(size: 11)).foregroundStyle(Instrument.muted)
                    }
                }
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(rows, id: \.account.id) { row in
                            accountRow(row)
                        }
                    }
                }
            }
        }
    }

    private func accountRow(_ row: AccountOverviewRow) -> some View {
        let account = row.account
        let latest = account.latest
        let activeReading = row.activeReading
        let percent = activeReading?.percent
        let reset = activeReading.map { "Resets " + resetDate($0.reset) }
            ?? (latest == nil ? "Reset unknown" : "Awaiting new cycle")
        let tokenStatus = store.localTokenStatus(for: account)
        let tokenLabel = "Claude Code · " + tokenStatus.label
        let isActive = store.activeClaudeCodeAccountID == account.id
        let refresh = store.refreshDetails(for: account, now: row.now)
        return Button {
            store.select(account.id)
            store.showingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.name).font(.system(size: 13, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        Text(reset).font(.system(size: 11)).foregroundStyle(Instrument.muted)
                        Text(row.freshness).font(.system(size: 11))
                            .foregroundStyle(row.isStale ? Instrument.warning : Instrument.muted)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(percent.map(Instrument.percentage) ?? "—")
                            .font(.system(size: 19, weight: .medium, design: .monospaced))
                            .foregroundStyle(Instrument.usageColor(percent))
                        if isActive {
                            Text("Active").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Instrument.signal)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Instrument.signal.opacity(0.12), in: Capsule())
                        }
                    }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Instrument.muted).accessibilityHidden(true)
                }
                if !store.demo {
                    Text(tokenLabel).font(.system(size: 11)).foregroundStyle(Instrument.muted)
                    Text(refresh.title).font(.system(size: 11))
                        .foregroundStyle(refresh.error == nil ? Instrument.muted : Instrument.warning)
                        .help(refreshDescription(refresh))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Instrument.well, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(account.name)
        .accessibilityValue((percent.map { Instrument.percentage($0) + " weekly usage" } ?? "Usage unavailable")
                            + ". " + reset + ". " + row.freshness + (store.demo ? "" : ". " + tokenLabel)
                            + (isActive ? ". Active in Claude Code" : "") + ". " + refreshDescription(refresh))
        .help(latest.map { "Last updated " + $0.observed.formatted(date: .abbreviated, time: .shortened) }
              ?? row.freshness)
        .contextMenu {
            Button("Retry account") { accountAction(account, false) }
                .disabled(store.demo || account.webIdentity == nil)
            Button("Reconnect in Chrome…") { accountAction(account, true) }
                .disabled(store.demo || account.webIdentity == nil)
        }
    }

    private func accountDetail(_ account: Account) -> some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let latest = account.latest
            let expired = latest.map { $0.reset <= context.date } ?? false
            let percent = expired ? nil : latest?.percent
            let usageColor = Instrument.usageColor(percent)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Picker("Account", selection: Binding(get: { account.id }, set: store.select)) {
                        ForEach(store.accounts) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Account")
                    .frame(width: 172)
                    Text(store.accounts.count == 1 ? "1 account" : "\(store.accounts.count) accounts")
                        .font(.system(size: 11)).foregroundStyle(Instrument.muted)
                    Spacer()
                    if store.demo {
                        Button("Exit demo") { store.toggleDemo() }.buttonStyle(.borderless)
                    } else {
                        Button { editor = account } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 24, height: 23)
                        }
                        .buttonStyle(.borderless)
                        .help("Edit account").accessibilityLabel("Edit account")
                    }
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Weekly usage").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Instrument.muted)
                        Text(percent.map(Instrument.percentage) ?? "—")
                            .foregroundStyle(usageColor)
                            .font(.system(size: 43, weight: .medium, design: .monospaced))
                            .tracking(-1.5).monospacedDigit()
                            .contentTransition(.identity)
                    }
                    Spacer()
                    Text(expired ? "Awaiting new cycle" : "All models")
                        .font(.system(size: 12)).foregroundStyle(Instrument.muted)
                        .padding(.bottom, 7)
                }
                SegmentMeter(percent: percent, color: usageColor)
                CycleChart(readings: expired ? [] : account.cycle, reset: expired ? nil : latest?.reset,
                           color: usageColor, tokenStatus: store.localTokenStatus(for: account),
                           tokenScanCompletedAt: store.demo || expired ? nil : store.localTokenScanCompletedAt)
                resetRows(account, now: context.date, expired: expired)
                Spacer(minLength: 0)
                footer(account)
            }
        }
    }

    private func resetRows(_ account: Account, now: Date, expired: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").frame(width: 16).accessibilityHidden(true)
                Text("Weekly reset").foregroundStyle(Instrument.muted)
                Spacer()
                if let reset = account.latest?.reset, !expired {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(countdown(to: reset, from: now)).fontWeight(.semibold).monospacedDigit()
                        Text(resetDate(reset))
                            .font(.system(size: 11)).foregroundStyle(Instrument.muted)
                    }
                } else {
                    Text(expired ? "Refresh usage" : "Unknown").foregroundStyle(Instrument.muted)
                }
            }
            .frame(height: 40)
            Rectangle().fill(Instrument.rule).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "ticket").frame(width: 16).accessibilityHidden(true)
                Text("Free reset").foregroundStyle(Instrument.muted)
                Spacer()
                Text(account.offer.rawValue)
                    .fontWeight(.medium)
                    .foregroundStyle(account.offer == .available ? Instrument.signal : Instrument.ink)
                    .help(account.offerChecked.map { "Checked " + $0.formatted() } ?? "Check Claude Usage settings")
            }
            .frame(height: 32)
        }
        .font(.system(size: 12))
    }

    private func footer(_ account: Account) -> some View {
        let refresh = store.refreshDetails(for: account)
        return HStack(spacing: 6) {
            Button {
                showingRefreshDetails = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                    Text(refresh.title).lineLimit(1)
                }
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showingRefreshDetails) {
                refreshPopover(account)
            }
            .accessibilityLabel("Refresh details. " + refresh.title)
            .help(refreshDescription(refresh))
            Spacer()
            Link(destination: Instrument.settings) {
                HStack(spacing: 4) {
                    Text("Claude Usage")
                    Image(systemName: "arrow.up.right").font(.system(size: 8))
                }
            }
            .foregroundStyle(Instrument.ink)
        }
        .font(.system(size: 11))
        .foregroundStyle(Instrument.muted)
    }

    private func refreshDescription(_ details: UsageStore.RefreshDetails) -> String {
        let format: (Date?) -> String = { $0?.formatted(date: .abbreviated, time: .standard) ?? "Not recorded" }
        return details.title + ". Source " + details.source + ". Last attempt " + format(details.attempt)
            + ". Last success " + format(details.success) + (details.error.map { ". " + $0 } ?? "")
    }

    private func refreshPopover(_ account: Account) -> some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let details = store.refreshDetails(for: account, now: context.date)
            VStack(alignment: .leading, spacing: 10) {
                Text("Refresh status").font(.headline)
                Text(account.name).font(.subheadline).textSelection(.enabled)
                Text(details.title).fontWeight(.semibold)
                    .foregroundStyle(details.error == nil ? Instrument.ink : Instrument.warning)
                LabeledContent("Source", value: details.source)
                LabeledContent("Last attempt", value: details.attempt?.formatted(date: .abbreviated, time: .standard) ?? "Not recorded")
                LabeledContent("Last success", value: details.success?.formatted(date: .abbreviated, time: .standard) ?? "Not recorded")
                if let error = details.error {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }
                if details.attempt == nil && !store.demo {
                    Text("Update and reload the Chrome companion to receive attempt details.")
                        .foregroundStyle(Instrument.muted)
                }
                if !store.demo && account.webIdentity != nil {
                    HStack(spacing: 12) {
                        Button("Retry now") { accountAction(account, false) }
                        Button("Reconnect in Chrome…") { accountAction(account, true) }
                    }
                    .disabled(details.title == RefreshStatus.State.refreshing.label)
                    Text("Actions apply to this account. Reconnect opens Claude in its Chrome profile.")
                        .foregroundStyle(Instrument.muted)
                }
            }
            .font(.system(size: 12))
            .padding(16).frame(width: 340)
            .preferredColorScheme(.dark)
        }
    }

    private func resetDate(_ reset: Date) -> String {
        reset.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    private func countdown(to reset: Date, from now: Date) -> String {
        let minutes = max(0, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes / 60) % 24)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

struct SegmentMeter: View {
    var percent: Double?
    var color: Color

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let segment = (proxy.size.width - 23 * 2) / 24
                HStack(spacing: 2) {
                    ForEach(0..<24) { index in
                        let fill = max(0, min(1, (percent ?? 0) * 0.24 - Double(index)))
                        Rectangle().fill(Instrument.rule)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(color).frame(width: segment * fill)
                            }
                            .frame(width: segment)
                    }
                }
            }
            .frame(height: 7)
            HStack {
                Text("0%")
                Spacer()
                Text("100%")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Instrument.muted)
        }
        .accessibilityHidden(true)
    }
}

struct CycleChart: View {
    var readings: [Reading]
    var reset: Date?
    var color: Color
    var tokenStatus: UsageStore.LocalTokenStatus
    var tokenScanCompletedAt: Date?

    private var tokenSummary: String {
        if case let .recorded(counts) = tokenStatus { return "Claude Code · " + counts.total.formatted() + " tokens" }
        return "Claude Code · " + tokenStatus.label
    }

    private var tokenScanStatus: String {
        guard let tokenScanCompletedAt else { return "" }
        return " Last Claude Code log check at " + tokenScanCompletedAt.formatted(
            .dateTime.hour().minute().second()
        ) + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weekly history").font(.system(size: 12, weight: .semibold))
            HStack(alignment: .top, spacing: 7) {
                VStack(alignment: .trailing) {
                    Text("100")
                    Spacer()
                    Text("50")
                    Spacer()
                    Text("0")
                }
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Instrument.muted)
                .frame(height: 52)
                Canvas { context, size in
                    let top = 6.0
                    let height = size.height - 12
                    for fraction in [0.0, 0.5, 1.0] {
                        let y = top + height * fraction
                        var rule = Path()
                        rule.move(to: CGPoint(x: 0, y: y))
                        rule.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(rule, with: .color(Instrument.rule), lineWidth: 1)
                    }
                    guard let reset, !readings.isEmpty else { return }
                    let start = reset.addingTimeInterval(-Reading.week)
                    let points = readings.map { reading in
                        let fraction = max(0, min(1, reading.observed.timeIntervalSince(start) / Reading.week))
                        return CGPoint(x: 4 + (size.width - 8) * fraction, y: top + height * (1 - reading.percent / 100))
                    }
                    var trace = Path()
                    trace.addLines(points)
                    context.stroke(trace, with: .color(color), lineWidth: 1.5)
                    if let point = points.last {
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                                     with: .color(color))
                    }
                }
                .frame(height: 52)
                .overlay {
                    if readings.isEmpty {
                        Text("History appears after your first reading")
                            .font(.system(size: 11)).foregroundStyle(Instrument.muted)
                            .padding(5).background(Instrument.well)
                    }
                }
            }
            HStack {
                Text("Cycle start")
                Spacer()
                Text("Scheduled reset")
            }
            .font(.system(size: 10)).foregroundStyle(Instrument.muted)
            .padding(.leading, 25)
            Text(tokenSummary)
                .font(.system(size: 11)).foregroundStyle(Instrument.muted)
                .help("Tokens attributed to this account from local Claude Code logs in the current weekly quota window. Demo mode uses sample counts." + tokenScanStatus)
            if case let .recorded(counts) = tokenStatus {
                HStack(spacing: 8) {
                    tokenColumn("Input", count: counts.input)
                    tokenColumn("Output", count: counts.output)
                    tokenColumn("Cache", count: counts.cache)
                        .help("Cache read: \(counts.cacheRead.formatted()) · Cache write: \(counts.cacheWrite.formatted())")
                }
            }
        }
        .padding(10)
        .background(Instrument.well, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly history")
        .accessibilityValue((readings.isEmpty ? "No readings. " :
            "From \(Instrument.percentage(readings.first!.percent)) to \(Instrument.percentage(readings.last!.percent)). ")
            + tokenSummary + tokenAccessibilityBreakdown + tokenScanStatus)
    }

    private var tokenAccessibilityBreakdown: String {
        guard case let .recorded(counts) = tokenStatus else { return "." }
        return ". Input \(counts.input.formatted()), output \(counts.output.formatted()), cache \(counts.cache.formatted())."
    }

    private func tokenColumn(_ label: String, count: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(Instrument.muted)
            Text(count.formatted()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
