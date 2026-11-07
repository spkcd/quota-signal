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
