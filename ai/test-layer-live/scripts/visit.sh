#!/usr/bin/env bash
# Membuka link satu per satu di Safari simulator dan menyimpan screenshot. Hanya memuat halaman: tanpa mengetik, mengetuk, atau mengunduh.
# Link yang screenshot-nya sudah ada dilewati, jadi tiap link hanya dikunjungi sekali.
#   bash ai/test-layer-live/scripts/visit.sh <udid> [versi] [detik per halaman] [id ...]
set -uo pipefail
SIM=${1:?udid simulator}
VERSION=${2:-v1}
WAIT=${3:-20}
shift $(( $# < 3 ? $# : 3 ))
DIR=$(cd "$(dirname "$0")/.." && pwd)/$VERSION
mkdir -p "$DIR/ss"
while IFS=$'\t' read -r id url; do
  if [ -f "$DIR/ss/$id.jpg" ]; then
    echo "lewati $id"
    continue
  fi
  echo "$(date '+%H:%M:%S') $id"
  curl -s -X POST "http://127.0.0.1:8790/_test/mark?id=$id" >/dev/null
  xcrun simctl openurl "$SIM" "$url"
  sleep "$WAIT"
  xcrun simctl io "$SIM" screenshot "$DIR/ss/raw.png" >/dev/null 2>&1
  sips -Z 874 -s format jpeg -s formatOptions 82 "$DIR/ss/raw.png" --out "$DIR/ss/$id.jpg" >/dev/null
done < <(node -e '
const only = new Set(process.argv.slice(2));
for (const l of require(process.argv[1])) {
  if (l.resolves && (only.size === 0 || only.has(l.id))) console.log([l.id, l.url].join("\t"));
}' "$DIR/links.json" "$@")
rm -f "$DIR/ss/raw.png"
