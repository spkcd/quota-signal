# Changelog

## Unreleased

### Added

- A compact, bounded in-memory Claude Code request index. Streaming snapshots keep the earliest eligible request time and complete winning token breakdown; unchanged transcripts are not reread. Removed/changed files are evicted before replacements are retained. Source, identity and weekly-window changes invalidate the index.
- Chunked transcript reads, per-file temporary-allocation release and reuse of prefetched filesystem attributes. Only symlink entries require path resolution. Background extraction runs at utility priority.
- Cooperative scan budgets for visited entries, changed bytes, per-file/record sizes, indexed requests and elapsed time. Limit hits are explicitly partial, and later scans reuse completed index entries. Limited or concurrently changed transcripts cannot contribute an unverified owner or stale cached count.
- Scan timing/read-attempt information in Log Sources, plus a repeatable synthetic benchmark tracking cold/warm duration and process peak resident memory.

- Structured Claude Code token coverage states distinguish checking, unlinked IDs, no eligible weekly logs, inaccessible folders and unverified ownership. Readable, attributable tokens remain visible as **partial** when selected sources have access or ownership gaps.
- **Coverage…** in account details opens source-specific access and ownership explanations, exclusion counts and scan timing. Unknown logs are never attributed to the currently signed-in account; explanations clarify that ownership gaps across selected folders may concern another account.
- Cache reads and cache writes are separate visible and accessible token fields alongside input/output. The compact detail layout keeps all four fields within the widget.
- Cached transcript reuse rechecks file access. Missing projects folders, unavailable roots and partial file/subfolder failures are distinguished; permission recovery is retried on the next scan.

- **Claude Code Log Sources…** in the menu bar, widget title menu and dashboard account menus. A native folder picker adds readable configuration roots containing `projects` or `.claude.json`; the primary source remains enabled and additional selections persist across restarts. Removing a source leaves its files untouched.
- Per-account source contribution labels and scan times. Directory changes clear previous totals and trigger an immediate or queued scan; the same roots participate in scheduled/wake scans and guided ID discovery.
- Cross-directory session/request deduplication with whole winning-snapshot token breakdowns and source attribution. Canonical paths collapse symlink aliases. Conflicting account-ID email claims and conflicting session ownership across copies are excluded. Authentication remains unchanged.

- **Link Claude Code…** from account details and dashboard context menus. The guide explains the selected email, shows matching local account IDs, verifies metadata again before saving and requests a token rescan immediately or after an existing scan completes.
- Email-specific sign-in instructions with a safely quoted command for the installed CLI and an Open Terminal action. Login is never run automatically; checking/linking leaves active Claude Code authentication unchanged. The guide explains that running the command can change the active CLI account.
- Shared ID discovery excludes conflicting email claims and respects an explicitly supplied configuration directory. Forced token scans requested during another scan are queued instead of discarded.

- **Export Support Diagnostics…** in the menu bar and the widget title context menu. A native save dialog writes a local JSON report; nothing is uploaded. Reports use anonymous account labels and report-local attempt numbers, excluding emails, workspace/profile names, paths, credentials, raw errors and transcript text through a fixed field allowlist.
- Reports include app/build and bundled/reported companion versions, macOS version, Chrome running state, refresh timestamps, elapsed seconds, last-success times and error codes. Companion 1.6.0 reports its version with attempts and readings; older companions remain compatible with version coverage left unknown.
- A persisted, bounded journal retains the latest 50 structured state transitions per account/source using the existing source lock. Late replies do not add false transitions. Missing or unreadable history is explicitly marked, and readable latest status remains available. History starts after this update.

- Chrome companion 1.5.1 hardens the shared Chrome/embedded Usage parser. Capture requires a unique all-model weekly meter and reset, validates meter scale and local reset clocks, and rechecks the account email after Usage loads to detect switches between identically named workspaces.
- English 24-hour reset clocks join the existing AM/PM format. Unsupported languages and ambiguous or malformed readings report a concrete error while preserving the last verified quota and reset.

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

- On an invented 114 MB fixture with 50,000 snapshots, median warm scan time improved from 20.83 to 6.41 ms and process peak RSS from 46.1 to 26.0 MB. Cold time was approximately unchanged; every pass retained the exact 1,380,000-token result. Warm passes performed zero transcript reads and retained 10,000 compact request entries. Measurements are local arm64 observations across three fresh processes, not cross-machine guarantees; full method/results are in `Tests/Benchmarks`.
- Performance fixtures cover changed-file-only indexing, root/identity/window invalidation, deletion, deferred changed-file cache eviction, late conflicting ownership, budget continuation and entry/byte/file/line/index/time caps. Coverage, permission, multi-source and guided-linking regressions pass. Verified installed scan timing/partial-limit UI, universal arm64/x86_64 builds and signatures.

- Verified live dashboard coverage states, partial token totals, the source explanation sheet, and the four-field cache breakdown in the installed widget without clipping.
- Synthetic scanner/store fixtures cover checking, missing IDs, no eligible logs, missing/empty folders, unreadable folders and cached files, permission recovery, missing/unknown/conflicting ownership, partial-count retention, explicit cache totals and duplicate-account ambiguity. Existing multiple-configuration and guided-linking store regressions pass. Universal arm64/x86_64 build and signature checks passed.

- Verified the installed native folder picker, temporary source addition, live primary-source contribution and empty-source labels, then removed the verification source.
- Synthetic scanner fixtures cover copied sessions, independent sessions sharing request IDs, larger snapshots, exact source attribution, aliases, selection validation, metadata conflicts, conflicting owners, warm-cache changes, source removal and unavailable roots. Store fixtures verify duplicate additions, persistence/relaunch, pinned primary, forced rescans, contribution tracking and unchanged authentication metadata. Existing guided-linking fixtures pass. Universal arm64/x86_64 build and signature checks passed.

- Verified live ID discovery/linking for the dev account and observed refreshed Claude Code token totals. Its active Claude Code configuration remained byte-for-byte unchanged. The interactive login command was checked against installed CLI help; no live login switch was performed.
- Isolated fixtures cover current/backups discovery, selected-email matching, missing/conflicting IDs, malformed metadata, shell quoting, changed-ID rejection, verified persistence and immediate/queued token scanning with synthetic logs. Universal macOS build and signature checks passed.

- Verified the installed native export/save flow and inspected a redacted JSON report covering all four connected accounts. Confirmed app/build and bundled companion versions, anonymous source snapshots and absence of real account identifiers.
- Diagnostics fixtures cover deliberately sensitive raw text and invalid version strings, anonymous labels, attempt correlation, elapsed times, error codes, last-success retention, out-of-order events, bounded history, empty accounts and damaged journals. Existing refresh-status and Chrome worker regressions pass. Universal arm64/x86_64 build and signature checks passed.

- Added 26 synthetic, sanitized fixtures executed against a real ephemeral WebKit DOM. Coverage includes both supported English headings, en-US/en-GB clock formats, midnight/noon, cycle rollover, competing model/session meters, missing/duplicate meters and resets, invalid percentages and scales, and identity changes during capture. Fixtures contain invented identities only; they do not claim live coverage of other Claude layouts or locales.
- Worker regression checks prove identity/cycle parsing failures retain the prior verified quota/reset and report the concrete error. Universal macOS build and signature checks passed.

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
