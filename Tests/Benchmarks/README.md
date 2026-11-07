# Repeatable Claude Code scan benchmark

Run on macOS with the Command Line Tools installed:

```sh
bash Tests/Benchmarks/run-scan-benchmark.sh
```

The script compiles the scanner at baseline commit `d39783515a62635e683a5aa92f7b69fc7466816b` and the current scanner with `-O`, generates the fixture in a separate process, and runs each executable in three fresh processes. Each process performs one empty-index (cold) scan and two indexed (warm) scans. Cold refers to the app index, not a purged OS filesystem cache. Reports and the median summary are saved under `.build/Benchmarks/`. An optional first argument selects another generated-fixture directory and a second selects a compatible baseline revision.

The fixture contains 100 transcripts, 100 requests per transcript and five streaming snapshots per request, with 2,048 inert content bytes per snapshot. It is approximately 114 MB of JSONL, entirely invented, with generated IDs and an `example.com` email. It has no real transcripts, credentials or conversation content. The expected total is exactly 1,380,000 tokens in every pass.

The benchmark records wall-clock scan seconds and Darwin `getrusage` peak resident bytes for the entire measured process. These are machine-dependent observations, not CI latency or memory guarantees. Fixture generation runs separately to avoid including its allocations in the measured process. Warm current-scanner passes additionally assert zero transcript reads, zero parsed files and 10,000 compact indexed requests instead of retaining 50,000 streaming snapshots. Runtime metrics count parse attempts, including attempts stopped by a limit or read failure.

The scanner index is in memory only. Every pass still inventories selected folders, checks access and file size/modification time, and reaggregates account/window-specific results. Only changed transcripts are reparsed. Changes to roots, identity mappings or the earliest requested weekly window invalidate the index. Removed or changed files are evicted before replacements are retained. Streaming snapshots retain the earliest eligible request time and the complete winning token breakdown.

Background extraction runs at utility priority with cooperative limits: 50,000 visited filesystem entries, 2 GiB of changed transcript reads per pass, 512 MiB per file, 250,000 retained request entries, 4 MiB per JSONL record and a 15-second scan deadline. Checks occur between filesystem/chunk operations; blocking filesystem calls and final aggregation cannot be forcibly interrupted at the deadline. Metadata discovery is separate from these extraction limits. This is a bound on scanner work/index size, not a hard cap on whole-process RSS.

A limit produces explicit partial coverage rather than a complete or zero-usage claim. A later scan can reuse successfully indexed files and spend its read budget on remaining changed files. Oversized files/records and entry/index limits can remain partial until the enabled source footprint is reduced. Nothing is deleted or edited. Read failures and limit flags can coexist. An interrupted/limited transcript is withheld until its full ownership metadata can be verified.

Focused regression checks:

```sh
xcrun swiftc -O -swift-version 6 Sources/TokenCoverage.swift Sources/ClaudeCodeConfigurations.swift Sources/ClaudeCodeLinking.swift Sources/ClaudeCodeTokens.swift Tests/ScanPerformanceTests.swift -o /tmp/quota-perf-tests
/tmp/quota-perf-tests
```

These cover zero-read warm passes, changed-file indexing, removed files, root/identity/window invalidation, bounded continuation, stale-cache exclusion when changed files are deferred, all work limits, and late conflicting ownership metadata. Coverage and multi-configuration suites remain correctness gates.
