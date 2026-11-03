#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="build/ExamOverlay.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift build -c release
cp .build/release/ExamOverlay "$APP/Contents/MacOS/ExamOverlay"
cp Info.plist "$APP/Contents/Info.plist"
cp Sources/ExamOverlay/defaults.json "$APP/Contents/Resources/defaults.json"
ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"ExamOverlay Dev"' | head -1 | tr -d '"' || true)"
if [ -n "$ID" ]; then codesign --force --deep -s "$ID" "$APP"; echo "signed: $ID"
else codesign --force --deep -s - "$APP"; echo "signed: ad-hoc"; fi
echo "!! binary changed - re-grant Screen Recording + Accessibility !!"
echo "built $APP"
