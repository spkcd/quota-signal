import AppKit
import SwiftUI

struct AccountEditor: View {
    @ObservedObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss
    let original: Account
    @ViewState private var name: String
    @ViewState private var offer: ResetOffer
    @ViewState private var percent: String = ""
    @ViewState private var reset: Date
    @ViewState private var confirmRemove: Bool = false
    @ViewState private var copied: Bool = false

    init(store: UsageStore, original: Account) {
        self.store = store
        self.original = original
        _name = State(initialValue: original.name)
        _offer = State(initialValue: original.offer)
        _reset = State(initialValue: original.latest.flatMap { $0.reset > .now ? $0.reset : nil }
                       ?? .now.addingTimeInterval(86400))
    }

    private var new: Bool { original.name.isEmpty }
    private var value: Double? {
        let input = percent.trimmingCharacters(in: .whitespaces)
        let separator = Locale.current.decimalSeparator ?? "."
        return Double(input.replacingOccurrences(of: separator, with: "."))
    }
    private var hasReading: Bool { !percent.trimmingCharacters(in: .whitespaces).isEmpty }
    private var validReading: Bool {
        guard let value, (0...100).contains(value) else { return false }
        let interval = reset.timeIntervalSinceNow
        return interval > 0 && interval <= Reading.week + 3600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(new ? "Add account" : "Edit account").font(.system(size: 21, weight: .semibold))
            LabeledContent("Account name") {
                TextField("Account name", text: $name, prompt: Text("Work or Personal")).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Manual reading").font(.headline)
                    Spacer()
                    Link("Open Claude Usage", destination: Instrument.settings)
                }
                LabeledContent("Weekly usage (%)") {
                    TextField("Weekly usage (%)", text: $percent, prompt: Text("Optional · 0 to 100")).labelsHidden()
                }
                if hasReading {
                    DatePicker("Weekly reset", selection: $reset, displayedComponents: [.date, .hourAndMinute])
                    if !validReading {
                        Text("Enter 0–100 and a reset within the next week.")
                            .foregroundStyle(Instrument.warning)
                    }
                }
                Picker("Free reset", selection: $offer) {
                    ForEach(ResetOffer.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude Code feed").font(.headline)
                    Text(new ? "Save this account first." : "Use this command in your status line.")
                        .foregroundStyle(Instrument.muted)
                }
                Spacer()
                if !new {
                    Button(copied ? "Copied" : "Copy command") {
                        let path = Bundle.main.executableURL!.path.replacingOccurrences(of: "'", with: "'\\''")
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString("'\(path)' capture \(original.id.uuidString)", forType: .string)
                    }
                }
            }
            HStack {
                if !new {
                    Button("Remove", role: .destructive) { confirmRemove = true }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (hasReading && !validReading))
            }
        }
        .padding(19)
        .frame(width: 374)
        .preferredColorScheme(.dark)
        .alert("Remove this account?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                store.remove(original.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its local weekly history will be deleted.")
        }
    }

    private func save() {
        var account = store.accounts.first { $0.id == original.id } ?? original
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.offer != offer { account.offerChecked = .now }
        account.offer = offer
        if let value, validReading {
            account.record(Reading(observed: .now, reset: reset, percent: value))
        }
        store.save(account)
        dismiss()
    }
}
