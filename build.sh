#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/.build/Quota Signal.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Chrome"
binary="$app/Contents/MacOS/QuotaSignal"
if [[ "${1:-}" == "--universal" ]]; then
    for arch in arm64 x86_64; do
        xcrun swiftc -O -swift-version 6 -target "$arch-apple-macosx14.0" Sources/*.swift -o ".build/QuotaSignal-$arch"
    done
    xcrun lipo -create .build/QuotaSignal-arm64 .build/QuotaSignal-x86_64 -output "$binary"
else
    xcrun swiftc -O -swift-version 6 -target "$(uname -m)-apple-macosx14.0" Sources/*.swift -o "$binary"
fi
sed 's/^export async function/async function/' Chrome/usage.js > "$app/Contents/Resources/usage.js"
cp Chrome/{manifest.json,worker.js,usage.js,setup.html,setup.js} "$app/Contents/Resources/Chrome/"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign "${QUOTA_SIGNAL_SIGNING_IDENTITY:--}" "$app"
printf '%s\n' "$app"
