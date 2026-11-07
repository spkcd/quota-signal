# Usage parser fixtures

These are synthetic, sanitized DOM fixtures, not downloaded Claude pages. All emails use `example.com`; workspace names and percentages are invented. They contain no sessions, credentials, conversation text, paths or real account data. No additional user data collection is needed to run them.

`page.html` models the existing supported semantic controls: workspace menu, a single account email, Usage navigation, labelled weekly meter and its reset row. `cases.json` supplies independent variations. The two supported English headings are `This week` and `Weekly limit · All models`. English weekday names support a 12-hour AM/PM clock and a 24-hour clock, including normalized whitespace. en-US and en-GB are explicitly exercised. Other language formats fail closed and require independently verified fixtures before support is added.

The suite uses a real WebKit DOM with an ephemeral data store, a fixed local clock, no network navigation and no signed-in browser profile. Static fixtures resolve parser waits immediately; worker tests cover timeout handling. It tests competing session/model meters, missing/duplicate meters and resets, malformed percentages/scales/clocks, account and workspace mismatches, and an account switch to the same workspace display name during capture. Exact reset timestamps are checked in the system timezone.

Run from the repository root:

```sh
xcrun swiftc -parse-as-library -swift-version 6 Tests/UsageParserTests.swift -o /tmp/quota-usage-parser-tests
/tmp/quota-usage-parser-tests
node Tests/refresh-worker.test.mjs
```

Synthetic fixtures establish supported behavior and rejection boundaries. They do not certify every current Claude layout or locale. A changed live layout must be verified and represented by a sanitized fixture before broadening the parser.
