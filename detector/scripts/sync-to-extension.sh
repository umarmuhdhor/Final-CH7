#!/usr/bin/env bash
# Copies the detector build into the Safari extension. Run from anywhere.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/detector/src/detector.js"           # change to dist/ if a bundler is added
DEST="$ROOT/ios/ShooExtension/Resources/detector.js"
{
  echo "// GENERATED from detector/ by detector/scripts/sync-to-extension.sh — DO NOT EDIT HERE."
  cat "$SRC"
} > "$DEST"
echo "Synced → $DEST"
