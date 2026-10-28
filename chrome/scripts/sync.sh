#!/usr/bin/env bash
# Refreshes the files chrome/extension/ shares with the Safari extension. Run from anywhere; commit the result.
#  - detector.js: built from detector/ (same build as detector/scripts/sync-to-extension.sh)
#  - every file in shared-files.txt: copied unchanged from ios/ShooExtension/Resources/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXT="$ROOT/chrome/extension"
SAFARI="$ROOT/ios/ShooExtension/Resources"

BODY="$(node "$ROOT/detector/scripts/build.mjs")"   # fails here, before anything is touched, if the build breaks
{
  echo "// GENERATED from detector/ by chrome/scripts/sync.sh — DO NOT EDIT HERE."
  printf '%s\n' "$BODY"
} > "$EXT/detector.js"

grep -v -e '^#' -e '^$' "$ROOT/chrome/scripts/shared-files.txt" | while read -r file; do
  cp "$SAFARI/$file" "$EXT/$file"
done
echo "Synced → $EXT"
