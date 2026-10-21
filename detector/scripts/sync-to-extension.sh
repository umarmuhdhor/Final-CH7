#!/usr/bin/env bash
# Builds the detector (src/detector.js + data/brands.json -> one plain script) and copies it into the Safari extension.
# Run from anywhere. Needs Node.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/ios/ShooExtension/Resources/detector.js"
BODY="$(node "$ROOT/detector/scripts/build.mjs")"   # fails here, before DEST is touched, if the build breaks
{
  echo "// GENERATED from detector/ by detector/scripts/sync-to-extension.sh — DO NOT EDIT HERE."
  printf '%s\n' "$BODY"
} > "$DEST"
echo "Synced → $DEST"
