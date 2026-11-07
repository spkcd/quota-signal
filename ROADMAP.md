# Quota Signal roadmap

Quota Signal helps someone with several Claude workspaces answer three questions quickly. Which workspace has room, when does its quota reset, and can I trust the last reading? A second use case explains local Claude Code activity by account. Each milestone below has a release gate. The order is proposed and estimates are intentionally omitted until the dependencies are tested.

## Baseline

The app has a floating dashboard, a menu bar shortcut, freshness-based account ranking, weekly charts, free reset status, and local token breakdowns. Chrome refresh uses the signed-in profile's Usage page and verifies the workspace before attributing a reading. The Claude Code status line and manual entry offer additional ways to record quota. The initial public package targets macOS 14 and later on Apple silicon and Intel.

Three limitations set the order of work. Browser markup can change, Chrome profiles can lose their sessions, and local logs only cover activity that can be attributed on this Mac. Distribution also needs Developer ID signing and notarization before the app can offer a normal first-run experience.

## 1. Make installation and recovery predictable

| Work | Acceptance criteria | Depends on |
| --- | --- | --- |
| Developer ID signing and notarization | Build both architectures, sign with hardened runtime, notarize and staple the package. Verify a downloaded artifact on clean accounts without a Gatekeeper exception. | Apple Developer membership and release credentials |
| Repeatable release workflow | A tagged commit produces versioned packages, checksums and release notes. A failed signing or smoke check blocks the release. Verify the install path and source checkout separately. | Signed release process |
| Test launch at login across upgrades | Enable, approve if prompted, sign out and back in, then disable. Upgrade in place and check for duplicates, registration changes, and preserved preferences. Test on Intel and Apple silicon. | Clean macOS test machines |
| First-run checklist | The empty state walks through app installation, companion loading, sign-in, and first reading. Manual tracking is accessible before Chrome is configured. Test with an empty macOS account. | Companion setup flow |
| Profile-aware pairing | Pair the intended workspace from its own Chrome profile and confirm email, workspace, and first reading. Adding a second workspace cannot overwrite the first. Test identical display names and switching in an unrelated profile. | Chrome profile discovery or a profile-local entry point |
| Companion delivery and updates | Assess Chrome Web Store distribution and its permissions review. Preserve workspace bindings during extension updates and document the unpacked path if needed. | Stable extension ID strategy and store review |
| Document update and uninstall | Document how to replace the app, remove the extension and native host, and separately remove local data. Verify the supported paths on a clean user. | Finalized package paths |

**Release gate.** A new user can install, pair, obtain a first reading, and enable login launch using the public guide. A returning user can update in place with workspace links intact.

## 2. Make refresh health actionable

| Work | Acceptance criteria | Depends on |
| --- | --- | --- |
| Per-account refresh status — completed 2026-11-07 | Dashboard states and account-detail popovers show last attempt, last success, source, and reported errors. Confirmed login pages show **Sign-in needed**. Browser closed, network, layout, workspace mismatch and timeout states are separate. Last successful quota survives failed refreshes. Verified live Chrome delivery and regression fixtures. | Companion 1.3.0; older companions retain reading timestamps until upgraded |
| Retry and reconnect — completed 2026-11-07 | Retry now and Reconnect controls target a single connected account. Commands open the selected Chrome profile, verify the expected email/workspace, show progress, and remember the route only after success. Reconnect preselects the remembered profile and permits changing it. Failed attempts retain the last good reading and its freshness. Verified live profile routing and regression cases for duplicate requests, mismatches, expiry, and signed-out polling. | Companion 1.4.0; import profile names once if macOS prevents direct discovery |
| Short reset countdowns — completed 2026-11-07 | Each dashboard row shows a compact countdown beside its exact local reset time, updated every 15 seconds. Expired cycles show **Awaiting new cycle** until a fresh reading arrives. Verified all four live rows, minute rounding, expiry, missing data, timezone formatting, and both daylight saving transitions. | Current reset model |
| Refresh after wake — completed 2026-11-07 | Wake, screen-wake, resumed-session and restored-network notifications are coalesced into a background recovery signal. Chrome profiles share one refresh queue with manual and scheduled work, persist a three-attempt recovery budget with 30/90-second backoffs, and stop on authentication or workspace errors. Verified simulated workspace notifications, live four-account recovery, bounded retries, interrupted-tab cleanup and native-port shutdown. | Companion 1.5.0; app running for macOS notifications and Chrome running for companion refresh |
| Parser resilience — completed 2026-11-07 | Added 26 synthetic, sanitized WebKit fixtures for both supported English weekly headings, en-US/en-GB clocks, missing/ambiguous meters and resets, malformed values and identity changes. Capture requires one weekly meter and reset, validates its percentage scale and local clock, and rechecks account identity after navigation. Unsupported language formats fail closed. Worker regression tests verify retention of the last good quota/reset and concrete errors. | Companion 1.5.1; additional live layouts/locales require verified sanitized fixtures |
| Support diagnostics | Export a local report with app and extension versions, timings, state transitions, and error codes. Redact emails, workspace names, paths, credentials, and transcript text by default. | Structured refresh status |

**Release gate.** The app identifies the cause in test scenarios for a closed browser, expired session, changed page layout, and network outage. Recovery never writes a reading to the wrong account.

## 3. Make Claude Code setup and token coverage easier to understand

| Work | Acceptance criteria | Depends on |
| --- | --- | --- |
| Guided ID linking | **Link Claude Code** explains how to sign in with the selected email, verifies the discovered ID, and rescans immediately. Preserve any active Claude Code profile unless the user chooses to change it. | Documented CLI authentication flow |
| Multiple local configurations | Let users select supported local Claude Code directories. Show which directories contributed to the count and deduplicate a session found twice. | ID linking and a safe file selection flow |
| Explain token coverage | Distinguish unlinked, checking, no eligible logs, inaccessible directories, and ambiguous ownership. Show cache reads and writes explicitly in details when space permits. | Structured scanner results |
| Improve scan performance | Benchmark cold and warm scans using sanitized fixtures. Index changed transcripts, invalidate results on config changes, and cap background work. Track scan time and memory with a repeatable test. | Representative fixture set |
| Evaluate additional log formats | Support new formats only after tests prove safe attribution and request deduplication. Use fixtures with account switches, streaming snapshots and overlapping copies. | Verified sample metadata and parser tests |

**Release gate.** Each linked account can explain what contributed to its totals. A wrong or ambiguous ID cannot transfer tokens across accounts.

## 4. Help users plan around quota

| Work | Acceptance criteria | Depends on |
| --- | --- | --- |
| Opt-in macOS alerts | Support 75% and 90% alerts and confirmed reset notices. Deduplicate across sources, restarts, and repeated reads. Exclude stale readings and demo data. | Reliable refresh health and persisted cycle identity |
| Previous weekly cycles | Keep a bounded local history and let users select a previous cycle. Show incomplete coverage when the app first observed a cycle late. Test reset changes and migrations. | A retention policy and stable cycle identity |
| Model-specific quota views | Show other meters only when Claude supplies an identifiable metric and reset. Keep the all-model weekly meter as the default. | Verified source coverage and fixtures |
| Personal dashboard controls | Offer aliases, pinning, an optional compact menu bar label, and a way to show or hide email addresses in shared-screen contexts. Keep availability sorting available. | Updated accessibility and layout checks |
| History export | Export local observations with timestamps, source, cycle, and freshness. Keep quota percentages and Claude Code token counts in separate columns with their coverage caveats. | Stable history schema and redaction options |

**Release gate.** Alerts fire once per relevant event, old cycles cannot affect the current ranking, and every historical value can be traced to its source and window.

## 5. Evaluate broader integration

- **Supported quota source.** Track official Anthropic interfaces for account-scoped quota. Evaluate coverage, authentication, workspace identity and rate limits before replacing any browser reading. Ship only after verification across the supported account configurations.
- **Chrome-independent refresh.** Validate the embedded email flow and document its coverage. Expand it only if account identity and recurring refresh work reliably across several sessions. Google sign-in and multi-workspace support each need separate verification.
- **Additional browsers.** Compare their native messaging and background execution models. Pilot a second browser only when it can match the Chrome identity and recovery checks.
- **Localization and accessibility.** Verify VoiceOver navigation, keyboard-only operation, contrast, long account names, 12-hour and 24-hour clocks, and localized reset parsing. Include these checks in release validation.

## Operating principles and measurement

- Treat an account's verified identity, reading timestamp, and reset window as one record. Preserve the last known good result on refresh failure and expose the source.
- Keep readings and log processing local by default. Require an explicit action for sharing diagnostics or exporting files.
- Measure setup from install to first verified reading, recovery from failure to next successful reading, and refresh delay while the Mac is awake. Collect these measurements in local tests and opt-in reports.
- Review each milestone after testing with a single account, multiple profiles, stale data, and a new quota cycle. Capture known gaps in release notes and keep unverified features labeled as such.
