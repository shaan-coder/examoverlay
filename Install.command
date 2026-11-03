#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/build/ExamOverlay.app"; [ -d "$SRC" ] || SRC="$HERE/ExamOverlay.app"
DEST="/Applications/ExamOverlay.app"
echo "ExamOverlay installer"
[ -d "$SRC" ] || { echo "no app found - run ./build.sh first"; exit 1; }
osascript -e 'tell application "ExamOverlay" to quit' >/dev/null 2>&1 || true
pkill -f "ExamOverlay.app/Contents/MacOS/ExamOverlay" >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
/usr/bin/ditto "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)"
[ -n "$BID" ] && { tccutil reset ScreenCapture "$BID" >/dev/null 2>&1 || true; tccutil reset Accessibility "$BID" >/dev/null 2>&1 || true; }
echo "installed to $DEST"
open "$DEST"
echo; echo "grant both prompts, quit OV, reopen from Applications"; echo
read -n 1 -s -r -p "press any key to close"
