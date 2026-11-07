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

Companion 1.5.0 stores the last verified target in each Chrome profile and checks it during scheduled refreshes. Use **+** to pair a different workspace deliberately. Update the companion files and click **Reload** in Chrome's Extensions page to receive failure details. Before a profile's first successful refresh, historical readings still show their successful observation time, while attempt details may be unavailable.

## Run refresh regression checks

```sh
node Tests/refresh-worker.test.mjs
test_directory=$(mktemp -d)
xcrun swiftc -swift-version 6 Sources/RefreshStatus.swift Tests/RefreshStatusTests.swift -o "$test_directory/check"
QUOTA_SIGNAL_TEST_DIRECTORY="$test_directory/status" "$test_directory/check"
rm -r "$test_directory"
```

## Retry one account or reconnect

Open an account, click its refresh status at the bottom, and choose **Retry now**. You can also right-click its dashboard row and choose **Retry account**. The app opens an account refresh tab in the matching Chrome profile and checks that account's expected email and workspace. The status changes to **Refreshing…**, then records success or the available error. A failed attempt preserves the last quota reading.

Choose **Reconnect in Chrome…** to select the profile for that account. The remembered, verified profile is selected initially. Confirm it or choose another, then sign in or select the expected workspace in the Claude tab that opens. Leave the account refresh tab open while signing in. It retries every five seconds until a verified reading is accepted or the request expires after 30 minutes. Ordinary retry requests expire after two minutes.

The route is saved only after a successful reading matches the requested account. Reconnect never intentionally binds an account to a different Claude identity. If no route is remembered, a unique profile name matching the account email is suggested. Ambiguous profiles require a selection.

If macOS prevents Quota Signal from reading Chrome's profile list, the first action asks you to select **Local State** from `~/Library/Application Support/Google/Chrome/`. The app retains only the parsed profile names, directory identifiers and email labels. This avoids requiring broad disk access. Older email-only Quota Signal accounts are upgraded with their verified workspace identity at their next successful Chrome refresh.

Use companion **1.4.0** for these actions. Rerun **Set Up Chrome Companion…** to prepare the current files, then reload the extension in each dedicated Chrome profile.

Run the profile routing checks with:

```sh
test_directory=$(mktemp -d)
xcrun swiftc -swift-version 6 Sources/ChromeAccountActions.swift Sources/RefreshStatus.swift Tests/ChromeAccountActionsTests.swift -o "$test_directory/check"
QUOTA_SIGNAL_TEST_DIRECTORY="$test_directory/state" "$test_directory/check"
rm -r "$test_directory"
```

## Refresh after wake and session recovery

Keep Quota Signal and Chrome running. Companion **1.5.0** listens for the app's local wake signal through Chrome native messaging. Quota Signal coalesces system wake, display wake, active-session and restored-network events, then requests background refreshes. The four dedicated profile windows can stay minimized.

Each Chrome profile uses the same queue for scheduled refreshes, recovery, retry and reconnect. A recovery cycle permits up to three attempts within five minutes. Network or temporary availability errors retry after 30 seconds and then 90 seconds. Sign-out, workspace mismatch and page layout errors stop the cycle. Further automatic triggers respect the existing budget and backoff, while explicit user actions remain available. Chrome can delay alarms while the Mac is asleep or busy.

A successful reading less than 30 seconds old satisfies recovery without opening another sample tab. Chrome startup, a delayed periodic alarm and an active Claude tab finishing navigation also check for recovery. After a worker interruption, only the tracked sample tab with its matching marker is eligible for cleanup.

The optional embedded browser reuses its reader and makes up to three recovery attempts with the same backoffs for transient failures. Wake events also request a local Claude Code token rescan. Failed quota refreshes keep the last good reading and expose their error in refresh details.

Run the notification and signal checks with:

```sh
test_directory=$(mktemp -d)
xcrun swiftc -swift-version 6 Sources/WakeRecovery.swift Tests/WakeRecoveryTests.swift -o "$test_directory/check"
QUOTA_SIGNAL_TEST_DIRECTORY="$test_directory/state" "$test_directory/check"
rm -r "$test_directory"
node Tests/refresh-worker.test.mjs
```

The notification test injects workspace events inside its own process and uses a temporary signal directory.

## Supported Usage page formats

Companion 1.5.1 and the embedded reader use the same parser. It accepts one labelled all-model weekly meter headed **This week** or **Weekly limit · All models**, with a percentage on a 0–100 scale and an explicit English weekday/reset clock in the same row. English 12-hour AM/PM and 24-hour clocks are supported; en-US and en-GB have regression fixtures. Relative times and other languages are not inferred.

Capture verifies the email, workspace and plan, then checks identity again after Usage loads. Missing or ambiguous meters, invalid resets, unsupported languages and account switches produce a refresh error. The last verified quota and reset remain visible with their original freshness. Open refresh details for the concrete error, correct the account or language, and use **Retry now**.

The offline parser suite uses synthetic, sanitized pages in [Tests/Fixtures/Usage](../Tests/Fixtures/Usage/README.md). It requires no Claude login and never reads your Chrome profile. The fixtures define tested support; additional live page layouts or locales need independently verified, sanitized examples before support is added.

## Export support diagnostics

Right-click the Quota Signal menu bar label or the **Quota Signal** title in the widget, then choose **Export Support Diagnostics…**. Choose a local location in the save dialog. The app saves a JSON report and reveals it in Finder. Canceling the dialog saves nothing. The app does not upload or send the report; sharing is a separate action you control.

The report includes app/build and bundled companion versions, the last companion version reported by each source when known, macOS version, whether Chrome is running, refresh attempt times, elapsed seconds, last-success times, state transitions, and error codes such as `signedOut`, `network`, `layout`, `mismatch` and `unavailable`. Elapsed seconds describe the status timestamp relative to its attempt start; they are not network-only measurements. A bundled companion version does not establish which version a Chrome profile currently has loaded. Reload companion **1.6.0** in each dedicated profile to enable version reporting on subsequent refreshes; older companions remain compatible.

Reports always use anonymous labels such as **Account 1**, with report-local attempt numbers. They omit account IDs, emails, workspace names, Chrome profile names, filesystem paths, credentials, raw error messages, quota percentages, token totals and transcript text. Exact timestamps and account counts remain in the report. Redaction uses a fixed field allowlist rather than trying to remove secrets from arbitrary log text. There is no unredacted export option.

Each account/source keeps at most 50 structured state transitions locally. History starts after this update and survives restarts; earlier transitions cannot be reconstructed. Missing or unreadable history is marked in the report, while a readable latest status is still included. The report does not inspect Claude Code transcripts, Chrome cookies or browser session data. It reads existing refresh metadata only.

Diagnostics regression checks can run without any real accounts:

```sh
fixture=$(mktemp -d)
xcrun swiftc -swift-version 6 Sources/RefreshStatus.swift Sources/SupportDiagnostics.swift Tests/SupportDiagnosticsTests.swift -o "$fixture/diagnostics"
QUOTA_SIGNAL_TEST_DIRECTORY="$fixture/state" "$fixture/diagnostics"
node Tests/refresh-worker.test.mjs
```
