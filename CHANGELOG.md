# Changelog

## Unreleased

### Added

- Wake, display-wake, resumed-session and restored-network recovery. Notification bursts are debounced for two seconds and coalesced within a 15-second cooldown.
- Chrome companion 1.5.0 receives recovery signals through a local native messaging connection. Chrome startup, overdue alarms and returning Claude tabs also trigger recovery.
- Per-profile recovery has a persisted maximum of three attempts within five minutes, with 30- and 90-second backoffs for network/unavailable failures. Authentication, layout and workspace mismatch failures stop the cycle.
- Recovery shares the existing per-profile queue with scheduled refreshes, retries and reconnects. Fresh successful readings avoid redundant work. Interrupted sample tabs are tracked and cleaned up without closing unrelated tabs.
- The optional embedded browser retries transient recovery failures using its existing reader. Local Claude Code token scans are requested on wake.
- App polling and embedded refresh timers use common run-loop modes so menu tracking can continue receiving captured readings.

- Dashboard reset rows now show time remaining alongside the exact local reset date and time, refreshing every 15 seconds. Expired cycles show **Awaiting new cycle** until a fresh reading arrives.
- Account-specific **Retry now** and **Reconnect in Chrome…** actions in refresh details and dashboard context menus.
- Chrome companion 1.4.0 accepts expiring, account-scoped commands, verifies the requested workspace, serializes concurrent jobs, and polls reconnect attempts while the user signs in.
- Verified Chrome profile routes are remembered after success. Reconnect offers a profile selector with the remembered route selected. Ambiguous first-time routes require a selection.
- A one-time profile metadata import when macOS prevents direct discovery. Only profile names, directory identifiers and profile email labels are retained.
- Legacy email-only accounts gain their workspace identity after a verified Chrome refresh so they can use retry and reconnect.

- Per-account refresh indicators on the dashboard and a refresh details popover in account details, showing the last attempt, last success, source, and the available failure explanation.
- Separate states for confirmed Claude sign-out, closed Chrome, connection failures, page layout changes, workspace mismatches, and unavailable or timed-out readings.
- Persistent refresh metadata for Chrome, the embedded browser, and Claude Code status-line quota captures. Late replies preserve the newest attempt and successful readings survive failures.
- Chrome companion 1.3.0 remembers the last successfully connected workspace in each profile and verifies that target on scheduled refreshes. A new pairing explicitly discovers another workspace.
- An Active badge below the dashboard percentage for the account signed in to the local Claude Code CLI.

### Compatibility

- Upgrade and reload the Chrome companion to receive attempt and failure details. Old readings remain available. The first successful refresh in a profile establishes its verified target.
- Browser-closed status refers to the Chrome application being closed. A closed or signed-out individual profile requires a companion report or is shown as unavailable or overdue.
- Confirmed offline state or a failed credential-free connection probe is classified as a network error. An inconclusive timeout remains unavailable.

### Verification

- Simulated macOS workspace notifications coalesced into one signal, and all four real accounts completed fresh Chrome recovery attempts. Verified native watcher shutdown when its port disconnects.
- Regression checks cover duplicate triggers, exhausted retry budgets, exact backoffs, worker restart state, expired signals, authentication stops, session navigation, overdue alarms, periodic/backoff collisions and interrupted-tab cleanup.
- Verification used injected workspace notifications and live account reads.

- Verified all four live dashboard countdowns and added checks for minute rounding, reset expiry, missing readings, timezone formatting and both Bucharest daylight saving transitions.
- Verified live retry and reconnect through the dedicated hello and dev Chrome profiles, including progress and successful status updates. Confirmed that a dev-only retry left the other three accounts’ refresh timestamps unchanged.
- Added command-targeting, duplicate-click, expiry, reconnect-polling and profile-routing regression checks.
- Live native messaging refreshes recorded successful status for all four connected accounts.
- Worker regression fixtures cover successful delivery, verified identity targeting, confirmed sign-out, offline and failed connections, layout errors, workspace mismatch, timeout, and native-host rejection.
- Swift persistence fixtures cover out-of-order replies, retained success history, and account/source isolation.
- Checked the dashboard and refresh details popover in the installed macOS app.

## 1.0.0 — 2026-11-07

- Initial public preview with a universal macOS app, floating account dashboard, menu bar quota summary, freshness ordering, Launch at Login, Chrome companion setup, and local Claude Code token breakdowns.
- Published fictional demo screenshots, setup and troubleshooting guides, and the product roadmap.
- Distributed with an ad hoc signature. Developer ID signing and Apple notarization remain pending credential setup.
