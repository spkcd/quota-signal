# Quota Signal walkthrough

## Read the dashboard

Click the waveform in the macOS menu bar. The label shows the account with the highest fresh weekly percentage remaining. On the dashboard, percentages are **used**. Fresh accounts with more quota remaining appear first. Stale readings follow fresh ones, and expired cycles wait for a new reading. Hover over a row to see the exact observation time.

Click an account to see its current weekly history, reset countdown, free reset status, and Claude Code token breakdown. Click the back chevron to return. An unknown free reset offer means the app has no confirmed status. Use **Claude Usage** to check or redeem an offer on Claude's website.

## Set up multiple workspaces

1. Install the companion from the app's menu and load it in each dedicated Chrome profile as described in the README.
2. Sign in to one Claude workspace per profile. If pairing opens in another profile, copy the setup tab URL into the intended profile and close the original setup tab.
3. Start a new pairing with **+** for each workspace. Pairing is temporary. If a setup tab asks you to start again, click **+** to generate a new one.
4. The setup page confirms the observed email and workspace. You can keep the profile windows minimized after pairing. Leave Chrome running for background refreshes.

## Troubleshoot

| What you see | What to check |
| --- | --- |
| Setup page is missing | Load the bundled companion as an unpacked extension in that Chrome profile. |
| Extension icon shows `!` | Hover over the extension icon for the latest error. Confirm Claude is signed in to the intended workspace, then click the icon to retry. |
| Reading is stale | Compare against Claude Usage and check whether Chrome is running. Verify the active workspace in the dedicated profile. |
| Account ID needed | Sign in to Claude Code with the same email. The app looks for account metadata in the standard Claude Code configuration or its `CLAUDE_CONFIG_DIR` environment. |
| No attributable logs this week | The app found an ID but no eligible logs. Sessions on other machines, logs outside the current window, and logs with ambiguous or missing owner IDs are excluded. |
| Start at login needs approval | Open the Quota Signal menu item to jump to System Settings and review Login Items. |
| App or companion moved | Reopen the app from Applications, rerun **Set Up Chrome Companion…**, and recopy any Claude Code status-line commands pointing to the old bundle. |

## Optional embedded refresh

For an existing configured embedded-browser workspace, **Sign in with email for Chrome-free refresh** opens its separate sign-in session. This mode requires a local workspace binding and email sign-in. It does not reuse Google sign-in from Chrome. The standard setup uses the Chrome companion or manual readings.

## How the data moves

1. The Chrome companion reads the current weekly all-model percentage and reset from Claude's Usage page. It verifies account identity before handing the result to the app through Chrome native messaging.
2. Quota Signal stores recent observations on the Mac and uses them to render the current cycle. A new reset window starts a new chart.
3. The independent Claude Code scan reads local transcripts and matches a verified session owner to the account email. Its input, output and cache counts explain local activity. The percentage and reset still come from quota readings.

## Inspect refresh health

On the dashboard, each account shows its refresh state. Open an account and click the info label at the bottom to view the last attempt, last success, source, and any reported error. Failed attempts preserve the last successful quota reading.

**Sign-in needed** appears only after the browser displays Claude's login page. **Browser closed** means the Chrome application is not running. **Network error** requires an offline indication or a failed connection. A missing or changed usage control produces **Page layout changed**. Inconclusive timeouts are **Refresh unavailable**. A successful refresh becomes **Refresh overdue** after 15 minutes without a new success.

Companion 1.3.0 stores the last verified target in each Chrome profile and checks it during scheduled refreshes. Use **+** to pair a different workspace deliberately. Update the companion files and click **Reload** in Chrome's Extensions page to receive failure details. Before a profile's first successful refresh, historical readings still show their successful observation time, while attempt details may be unavailable.

## Run refresh regression checks

```sh
node Tests/refresh-worker.test.mjs
test_directory=$(mktemp -d)
xcrun swiftc -swift-version 6 Sources/RefreshStatus.swift Tests/RefreshStatusTests.swift -o "$test_directory/check"
QUOTA_SIGNAL_TEST_DIRECTORY="$test_directory/status" "$test_directory/check"
rm -r "$test_directory"
```
