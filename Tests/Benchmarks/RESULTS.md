# Scan benchmark result — 2026-11-07

Measured locally on arm64 macOS 27.2, optimized Swift 6 builds. Baseline: `d39783515a62635e683a5aa92f7b69fc7466816b`. Current implementation: this change. See [the benchmark instructions](README.md) for fixture generation, measurement boundaries and work limits.

Three fresh processes per implementation, each with one empty-index scan and two indexed scans. The generated 114,400,890-byte fixture contains 100 files, 10,000 requests and 50,000 streaming snapshots, with inert content and invented identities only.

| Measurement | Baseline median | Current median |
| --- | ---: | ---: |
| Cold scan | 636.5 ms | 629.1 ms |
| Warm scan (six observations) | 20.83 ms | 6.41 ms |
| Process peak resident bytes | 46,104,576 | 25,968,640 |
| Token total, every pass | 1,380,000 | 1,380,000 |

Warm time decreased approximately 69%; measured peak RSS decreased approximately 44%. Cold time is effectively unchanged at this scale. These are local observations, not performance guarantees for other hardware or transcript distributions. Cold means an empty app index, not a flushed OS cache. Fixture generation runs in a separate process.

The current scanner retained 10,000 compact request entries. Every warm pass reparsed zero files and read zero transcript bytes. The cold pass read the entire fixture without hitting a work limit. Assertions require identical totals.

Additional regression checks verified changed-file-only reads, removal, root/identity/window invalidation, late conflicting ownership, exclusion of stale cached data when changed files are deferred, all work caps, and bounded continuation on subsequent scans. Coverage, configuration and linking fixtures passed. The installed app displayed scan duration/read-attempt counts and explicit partial coverage during a budget-limited live rescan. Both app architectures built and signature verification passed; benchmark timings were measured on arm64 only.
