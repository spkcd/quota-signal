#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
output="$PWD/.build/Benchmarks"
mkdir -p "$output"
fixture="${1:-$output/scan-fixture}"
baseline="${2:-d39783515a62635e683a5aa92f7b69fc7466816b}"
git show "$baseline:Sources/ClaudeCodeTokens.swift" > "$output/ScannerBefore.swift"
common=(Sources/TokenCoverage.swift Sources/ClaudeCodeConfigurations.swift Sources/ClaudeCodeLinking.swift)
xcrun swiftc -O -swift-version 6 "${common[@]}" "$output/ScannerBefore.swift" Tests/Benchmarks/ScanPerformance.swift -o "$output/before"
xcrun swiftc -O -D SCAN_METRICS -swift-version 6 "${common[@]}" Sources/ClaudeCodeTokens.swift Tests/Benchmarks/ScanPerformance.swift -o "$output/after"
"$output/before" "$fixture" --generate
for repeat in 1 2 3; do
    "$output/before" "$fixture" > "$output/before-$repeat.json"
    "$output/after" "$fixture" > "$output/after-$repeat.json"
done
python3 - "$output" <<'PY'
import json,sys,pathlib,statistics
root=pathlib.Path(sys.argv[1]); summary={}
for side in ['before','after']:
    reports=[json.loads((root/f'{side}-{i}.json').read_text()) for i in range(1,4)]
    summary[side]={
        'medianColdSeconds':statistics.median(r['runs'][0]['seconds'] for r in reports),
        'medianWarmSeconds':statistics.median(run['seconds'] for r in reports for run in r['runs'][1:]),
        'medianPeakResidentBytes':statistics.median(r['peakResidentBytes'] for r in reports),
        'tokens':reports[0]['runs'][0]['tokens'],
    }
    if side=='after':
        assert all(run['bytesRead']==0 and run['filesParsed']==0 and not run['limited'] for r in reports for run in r['runs'][1:])
        assert all(run['indexedRequests']==10000 for r in reports for run in r['runs'])
(root/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
PY
