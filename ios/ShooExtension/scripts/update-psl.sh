#!/usr/bin/env bash
# Refreshes Resources/psl.js from the official Public Suffix List. Run from anywhere; commit the result.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL https://publicsuffix.org/list/public_suffix_list.dat -o "$TMP/public_suffix_list.dat"
node "$DIR/build-psl.mjs" "$TMP/public_suffix_list.dat"
