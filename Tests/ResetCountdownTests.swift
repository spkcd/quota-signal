import Foundation

@main
struct ResetCountdownTests {
    @MainActor static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (seconds, expected) in [(1.0, "1m"), (60, "1m"), (61, "2m"), (3600, "1h 0m"),
                                    (3660, "1h 1m"), (86400, "1d 0h"), (90000, "1d 1h")] {
            precondition(Instrument.countdown(to: now.addingTimeInterval(seconds), from: now) == expected)
        }
        let account = Account(name: "Fixture", readings: [
            Reading(observed: now.addingTimeInterval(-600), reset: now, percent: 99)
        ])
        let before = AccountOverviewRow(account: account, now: now.addingTimeInterval(-1))
        precondition(before.resetDescription.hasPrefix("Resets in 1m · "))
        let atReset = AccountOverviewRow(account: account, now: now)
        precondition(atReset.activeReading == nil && atReset.resetDescription == "Awaiting new cycle")
        precondition(AccountOverviewRow(account: Account(name: "Empty"), now: now).resetDescription == "Reset unknown")

        // Bucharest jumps from 03:00 to 04:00 in spring and repeats 03:00 in autumn.
        let parse = ISO8601DateFormatter()
        let springStart = parse.date(from: "2026-03-29T02:30:00+02:00")!
        let springReset = parse.date(from: "2026-03-29T04:30:00+03:00")!
        let autumnStart = parse.date(from: "2026-10-25T03:30:00+03:00")!
        let autumnReset = parse.date(from: "2026-10-25T03:30:00+02:00")!
        precondition(Instrument.countdown(to: springReset, from: springStart) == "1h 0m")
        precondition(Instrument.countdown(to: autumnReset, from: autumnStart) == "1h 0m")
        let bucharest = Instrument.resetDate(springReset, timeZone: TimeZone(identifier: "Europe/Bucharest")!)
        let newYork = Instrument.resetDate(springReset, timeZone: TimeZone(identifier: "America/New_York")!)
        precondition(bucharest != newYork)
        precondition(Instrument.countdown(to: springReset, from: springStart) == "1h 0m")
        print("Reset countdown passed rounding, cycle expiry, missing data, timezone changes, and both DST transitions.")
    }
}
