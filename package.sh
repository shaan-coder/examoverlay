#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

VER="${1:-3.0}"
NAME="ExamOverlay"
STAGE="build/dmg"

./build.sh

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "build/$NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/READ ME.txt" <<'TXT'
ExamOverlay

1. Drag ExamOverlay onto the Applications folder in this window.
2. Open it from Applications. macOS will refuse the first time because the
   app is signed ad-hoc, not notarised.
3. Right-click the app, choose Open, then Open again in the dialog.
4. Grant Screen Recording and Accessibility when prompted, then quit and
   reopen the app. The setup wizard walks you through the rest.

You need your own API key. Groq's free tier works and the wizard links you
to it. Nothing is sent anywhere except the model provider you choose.

Keys:
  right shift        show / hide overlay
  8 or ctrl-opt-cmd-S solve
  ctrl-opt-cmd-L     cycle density
  ctrl-opt-cmd-J     click the next row down
  ctrl-opt-cmd-Z     undo last click
  ctrl-opt-cmd-Y     review session
  ctrl-opt-cmd-,     preferences
TXT

rm -f "build/$NAME-$VER.dmg"
hdiutil create -volname "$NAME $VER" -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 "build/$NAME-$VER.dmg"

rm -rf "$STAGE"
echo "built build/$NAME-$VER.dmg"
