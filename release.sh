#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

VER="${1:?usage: ./release.sh 3.7 \"notes\"}"
NOTES="${2:-}"

python3 - "$VER" <<'PY'
import json, re, sys, io
v = sys.argv[1]
p = 'Info.plist'
s = io.open(p, encoding='utf-8').read()
s = re.sub(r'(<key>CFBundleShortVersionString</key><string>)[^<]*', r'\g<1>' + v, s)
s = re.sub(r'(<key>CFBundleVersion</key><string>)[^<]*', r'\g<1>' + v.replace('.', ''), s)
io.open(p, 'w', encoding='utf-8').write(s)
print('version ->', v)
PY

./build.sh
./make-zip.sh "$VER"

gh release create "v$VER" "/tmp/ExamOverlay-$VER.zip" --notes "${NOTES:-Release $VER}"

python3 - "$VER" "$NOTES" <<'PY'
import json, sys
v, notes = sys.argv[1], sys.argv[2]
sig = open(f'/tmp/sig-{v}.txt').read().strip()
json.dump({
    "version": v,
    "url": f"https://github.com/shaan-coder/examoverlay/releases/download/v{v}/ExamOverlay-{v}.zip",
    "notes": notes,
    "sig": sig,
}, open('versions.json', 'w'), indent=2)
print(open('versions.json').read())
PY

git add -A
git commit -m "release $VER"
git push
echo "released $VER"
