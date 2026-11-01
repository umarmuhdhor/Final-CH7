#!/usr/bin/env bash
# Figma parity QA, test 2b/2c: opens the corpus URLs that still resolve in the Protected simulator's Safari
# (extension on, "All Websites: Allow"), one at a time, and keeps a screenshot of each.
# Guardrails (plan/alief/qa/figma-parity-2026-10-31.md): load only, no typing, no taps on the page, no downloads.
# Hosts that don't resolve (corpus-dns.json) are never opened; they are covered by test 2a.
#
#   bash plan/alief/qa/live-visit.sh <protected-udid> [seconds-per-page] [dns json] [output folder]
#   Test 3b (ai/test-layer2 links): ... 15 img/figma-parity/layer2-dataset-dns.json img/figma-parity/live-l2
set -uo pipefail
P=${1:?protected simulator udid}
WAIT=${2:-15}
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
DNS=$REPO/plan/alief/qa/${3:-img/figma-parity/corpus-dns.json}
OUT=$REPO/plan/alief/qa/${4:-img/figma-parity/live}
mkdir -p "$OUT"
node -e '
const r = require(process.argv[1]);
for (const x of r.filter((x) => x.resolves)) console.log([x.id, x.label, x.url].join("\t"));
' "$DNS" > "$OUT/visited.tsv"
while IFS=$'\t' read -r id label url; do
  echo "$(date '+%H:%M:%S') $label $id $url"
  xcrun simctl openurl "$P" "$url"
  sleep "$WAIT"
  xcrun simctl io "$P" screenshot "$OUT/raw.png" >/dev/null 2>&1
  sips -Z 874 -s format jpeg -s formatOptions 82 "$OUT/raw.png" --out "$OUT/safari-$id.jpg" >/dev/null
done < "$OUT/visited.tsv"
rm -f "$OUT/raw.png"
echo "done: $(wc -l < "$OUT/visited.tsv") pages"
