#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
VER="${1:?usage: ./make-zip.sh 3.2}"
OUT="/tmp/ExamOverlay-$VER.zip"
rm -f "$OUT"
cd build
zip -qr "$OUT" ExamOverlay.app
cd ..
unzip -l "$OUT" | head -4
openssl pkeyutl -sign -inkey ~/.examoverlay-update.key -rawin -in "$OUT" \
  | base64 | tr -d '\n' > "/tmp/sig-$VER.txt"
echo "zip: $OUT"
echo "sig: /tmp/sig-$VER.txt"
