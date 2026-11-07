import Foundation

// Isolate profile routing and command storage from this Mac's real app data.
struct WebIdentity: Codable, Equatable {
    let email: String
    let workspace: String
    let plan: String
    var isValid: Bool { true }
}
struct Account {
    let id: UUID
    let name: String
    let webIdentity: WebIdentity?
}
enum Bridge {
    static var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUOTA_SIGNAL_TEST_DIRECTORY"]!)
            .appending(path: "Feeds")
    }
}

@main
struct ChromeAccountActionsTests {
    static func main() throws {
        let fixture = Data(#"{"profile":{"info_cache":{"Default":{"name":"Work","user_name":"owner@example.com"},"Profile 5":{"name":"owner@example.com"},"../bad":{"name":"Invalid"}}}}"#.utf8)
        let parsed = try ChromeAccountActions.profiles(from: fixture)
        precondition(Set(parsed.map(\.id)) == Set(["Default", "Profile 5"]))
        let account = Account(id: UUID(), name: "Studio", webIdentity: .init(
            email: "owner@example.com", workspace: "Studio", plan: "Ultra"))
        let dedicated = ChromeAccountActions.Profile(id: "Profile 5", name: "owner@example.com", email: "")
        let primary = ChromeAccountActions.Profile(id: "Default", name: "Work", email: "owner@example.com")
        precondition(ChromeAccountActions.suggestedProfile(for: account, profiles: [primary, dedicated])?.id == dedicated.id)
        precondition(ChromeAccountActions.suggestedProfile(for: account, profiles: [
            primary, .init(id: "Profile 9", name: "Other", email: "owner@example.com")
        ]) == nil)
        let key = "chromeProfile." + account.id.uuidString
        UserDefaults.standard.set(primary.id, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        precondition(ChromeAccountActions.suggestedProfile(for: account, profiles: [primary, dedicated])?.id == primary.id)
        precondition(ChromeAccountActions.suggestedProfile(for: account, profiles: [dedicated])?.id == dedicated.id)
        precondition(!ChromeAccountActions.validDirectory("../Default"))
        precondition(!ChromeAccountActions.validDirectory("Profile 5 --incognito"))
        try FileManager.default.createDirectory(at: ChromeAccountActions.directory, withIntermediateDirectories: true)
        let request = ChromeAccountActions.Request(id: UUID(), account: account.id, identity: account.webIdentity!,
            profile: dedicated.id, reconnect: true, started: .now, expires: .now.addingTimeInterval(60))
        try JSONEncoder().encode(request).write(to: ChromeAccountActions.file(for: account.id))
        precondition(ChromeAccountActions.pending(id: request.id)?.account == account.id)
        precondition(ChromeAccountActions.pending(id: UUID()) == nil)
        let expired = ChromeAccountActions.Request(id: request.id, account: account.id, identity: account.webIdentity!,
            profile: dedicated.id, reconnect: false, started: .distantPast, expires: .distantPast)
        try JSONEncoder().encode(expired).write(to: ChromeAccountActions.file(for: account.id))
        precondition(ChromeAccountActions.pending(id: request.id) == nil)
        print("Chrome profile routing passed verified routes, unique email suggestions, ambiguous profiles, safe names, and command expiry.")
    }
}
