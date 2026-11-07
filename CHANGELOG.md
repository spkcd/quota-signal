# Changelog

## Unreleased

### Added

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

- Live native messaging refreshes recorded successful status for all four connected accounts.
- Worker regression fixtures cover successful delivery, verified identity targeting, confirmed sign-out, offline and failed connections, layout errors, workspace mismatch, timeout, and native-host rejection.
- Swift persistence fixtures cover out-of-order replies, retained success history, and account/source isolation.
- Checked the dashboard and refresh details popover in the installed macOS app.

## 1.0.0 — 2026-11-07

- Initial public preview with a universal macOS app, floating account dashboard, menu bar quota summary, freshness ordering, Launch at Login, Chrome companion setup, and local Claude Code token breakdowns.
- Published fictional demo screenshots, setup and troubleshooting guides, and the product roadmap.
- Distributed with an ad hoc signature. Developer ID signing and Apple notarization remain pending credential setup.
