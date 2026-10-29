#!/usr/bin/env bash
# Fase 18a step 13 (+ step 12 with --bench): the page replica wire, extension → backend → app.
# Builds pageReplicaBase64 with the extension's own replica.js + replica-build.js (replica-input.mjs),
# POST /scans as a Protected device, GET /scans/{id} as its Guardian, then fetches pageReplicaUrl with
# curl without --compressed: the stored gzip bytes must come back as is, with the exact headers
# (proves encodeBody "manual"; vitest's app.fetch cannot), and inflate to the HTML the extension sent.
#
#   bash plan/alief/qa/replica-e2e.sh            # against wrangler dev (localhost:8787) + local Supabase
#   bash plan/alief/qa/replica-e2e.sh --bench    # also the worst-case replica and the zero gzip bomb
#   SHOO_API=https://… bash plan/alief/qa/replica-e2e.sh --cloud [--bench]   # LANGKAH MANUAL 3
#
# Local: `pnpm -C backend/api dev` (needs backend/api/.dev.vars) and `supabase start` first. Set
# WRANGLER_LOG=<file with wrangler dev's output> to also check the replica_dropped log line of the bomb.
# Every run registers 2 devices (POST /devices: 10 per hour per IP) and deletes them at the end.
set -uo pipefail

CLOUD=0 BENCH=0
for a in "$@"; do
  case "$a" in
    --cloud) CLOUD=1 ;;
    --bench) BENCH=1 ;;
    *) echo "unknown option $a"; exit 2 ;;
  esac
done
if [ $CLOUD = 1 ]; then U=${SHOO_API:?set SHOO_API to the cloud API origin}; else U=http://localhost:8787; fi
U=${U%/}
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
W=$(mktemp -d); chmod 700 "$W"
FAILS=0 G="" P=""

say() { echo "$(date '+%H:%M:%S') $*"; }
pass() { say "PASS $*"; }
fail() { say "FAIL $*"; FAILS=$((FAILS + 1)); }
check() { if [ "$1" = "$2" ]; then pass "$3 ($1)"; else fail "$3: got '$1', want '$2'"; fi; }
psql1() { docker exec supabase_db_shoo psql -U postgres -tAc "$1"; }
ms() { python3 -c 'import time;print(int(time.time()*1000))'; }
json() { python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get(sys.argv[1]) or "")' "$1"; }
cleanup() {
  for t in "$P" "$G"; do [ -n "$t" ] && curl -s -o /dev/null -X DELETE "$U/devices/me" -H "authorization: Bearer $t"; done
  rm -rf "$W"
}
trap cleanup EXIT

curl -s -o /dev/null --max-time 5 "$U/healthz" || { echo "$U not reachable"; exit 1; }
if [ $CLOUD = 0 ]; then
  docker inspect supabase_db_shoo >/dev/null 2>&1 || { echo "local Supabase container not running"; exit 1; }
fi

# --- family: Guardian + Protected --------------------------------------------------------------
register() {
  curl -s -X POST "$U/devices" -H 'content-type: application/json' -d "{\"name\":\"$1\",\"mode\":\"$2\"}" > "$W/dev.json"
  json token < "$W/dev.json"
}
G=$(register "Rina" guardian); P=$(register "Mom" protected)
[ -n "$G" ] && [ -n "$P" ] || { echo "POST /devices refused (rate limit 10/hour per IP?), try again later"; exit 1; }
CODE=$(curl -s -X POST "$U/family/code" -H "authorization: Bearer $G" | json code)
check "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$U/family/join" -H "authorization: Bearer $P" -H 'content-type: application/json' -d "{\"code\":\"$CODE\"}")" 200 "Protected joins the Guardian"

# --- helpers -------------------------------------------------------------------------------------
# post_scan <kind>: POST /scans with <kind>.b64 as pageReplicaBase64, a fresh domain each time (no 24-hour
# reuse). Prints "<status> <scan id> <ms>".
post_scan() {
  local domain="bca-verifikasi-$1-$RANDOM$RANDOM.site"
  python3 - "$REPO/contracts/fixtures/blocked-92.json" "$domain" "$W/$1.b64" > "$W/$1.json" <<'PY'
import json, sys
f = json.load(open(sys.argv[1]))
for k in ("id", "verdict", "screenshotUrl", "pageReplicaUrl"):
    f.pop(k, None)
f["url"] = "https://" + sys.argv[2] + "/login"
f["domain"] = sys.argv[2]
f["pageReplicaBase64"] = open(sys.argv[3]).read()
print(json.dumps(f))
PY
  local t0 t1 code
  t0=$(ms)
  code=$(curl -s -o "$W/$1.resp" -w '%{http_code}' -X POST "$U/scans" -H "authorization: Bearer $P" -H 'content-type: application/json' --data-binary "@$W/$1.json")
  t1=$(ms)
  echo "$code $(json id < "$W/$1.resp") $((t1 - t0))"
}
# replica_url <scan id> <seconds>: pageReplicaUrl as the Guardian sees it, polled (the replica is stored in
# waitUntil after the push). Prints "<ms waited> <url or empty>".
replica_url() {
  local t0 url="" i
  t0=$(ms)
  for ((i = 0; i < $2 * 4; i++)); do
    url=$(curl -s "$U/scans/$1" -H "authorization: Bearer $G" | json pageReplicaUrl)
    [ -n "$url" ] && break
    sleep 0.25
  done
  echo "$(($(ms) - t0)) $url"
}
# fetch <url> <name> [curl args]: status code; headers in <name>.h, body in <name>.body exactly as the
# Worker sent it. curl only decodes Content-Encoding with --compressed, so gzip stays gzip here (the
# app's URLSession does inflate it once). Not --raw: that would also keep the chunked framing.
fetch() {
  local url=$1 name=$2; shift 2
  curl -s -D "$W/$name.h" -o "$W/$name.body" -w '%{http_code}' "$@" "$url"
}
header() { grep -i "^$1:" "$W/$2.h" | head -1 | cut -d: -f2- | sed 's/^ *//' | tr -d '\r'; }

# --- the wire: sample page ---------------------------------------------------------------------
node --no-warnings "$REPO/plan/alief/qa/replica-input.mjs" sample "$W" > /dev/null || { echo "replica-input.mjs failed"; exit 1; }
read -r ST ID POST_MS <<< "$(post_scan sample)"
check "$ST" 201 "POST /scans with a replica"
read -r WAIT_MS URL <<< "$(replica_url "$ID" 20)"
[ -n "$URL" ] && pass "GET /scans/{id} has pageReplicaUrl after ${WAIT_MS} ms" || fail "pageReplicaUrl still null after 20 s"
LIST=$(curl -s "$U/scans?owner=family" -H "authorization: Bearer $G" | python3 -c 'import sys,json;l=json.load(sys.stdin)["items"];print(len(l)>0 and all("pageReplicaUrl" in s and s["pageReplicaUrl"] is None for s in l))' 2>/dev/null)
check "$LIST" True "GET /scans: every item has pageReplicaUrl = null"
case "$URL" in "$U/replicas/$ID?"*) pass "link points at $U/replicas/{id}" ;; *) fail "unexpected link origin/path" ;; esac

if [ -n "$URL" ]; then
  check "$(fetch "$URL" plain)" 200 "GET pageReplicaUrl without Sec-Fetch-*"
  check "$(header content-type plain)" "text/html; charset=utf-8" "Content-Type"
  check "$(header content-encoding plain)" "gzip" "Content-Encoding"
  check "$(header content-disposition plain)" 'attachment; filename="replica.html"' "Content-Disposition"
  check "$(header content-security-policy plain)" "sandbox; default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; form-action 'none'; base-uri 'none'; frame-ancestors 'none'" "Content-Security-Policy"
  check "$(header x-content-type-options plain)" "nosniff" "X-Content-Type-Options"
  check "$(header cache-control plain)" "private, no-store" "Cache-Control"
  check "$(header referrer-policy plain)" "no-referrer" "Referrer-Policy"
  check "$(head -c 2 "$W/plain.body" | xxd -p)" "1f8b" "body starts with the gzip magic (sent once, not re-encoded)"
  SAME=$(python3 - "$W/sample.b64" "$W/plain.body" <<'PY'
import base64, gzip, sys
sent = base64.b64decode(open(sys.argv[1]).read())
got = open(sys.argv[2], "rb").read()
print("bytes" if got == sent else ("html" if gzip.decompress(got) == gzip.decompress(sent) else "differs"))
PY
)
  check "$SAME" bytes "stored gzip = sent gzip, so the HTML the app reads = the HTML the extension sent"
  check "$(fetch "$URL" nav -H 'Sec-Fetch-Mode: navigate' -H 'Sec-Fetch-Dest: document')" 404 "browser navigation (Sec-Fetch-Mode: navigate)"
  check "$(fetch "$URL" frame -H 'Sec-Fetch-Dest: iframe')" 404 "Sec-Fetch-Dest: iframe"
  check "$(fetch "$URL" doc -H 'Sec-Fetch-Dest: document')" 404 "Sec-Fetch-Dest: document without Sec-Fetch-Mode"
  check "$(fetch "$URL" fetchapi -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Dest: empty')" 200 "Sec-Fetch-Dest: empty (fetch from code)"
fi

# --- step 12: worst case + zero gzip bomb ------------------------------------------------------
if [ $BENCH = 1 ]; then
  node --no-warnings "$REPO/plan/alief/qa/replica-input.mjs" worst "$W" || exit 1
  read -r ST WID POST_MS <<< "$(post_scan worst)"
  check "$ST" 201 "worst case (409 600 chars, 3 145 728 bytes inflated): POST /scans"
  read -r WAIT_MS WURL <<< "$(replica_url "$WID" 30)"
  say "BENCH worst: POST /scans answered in ${POST_MS} ms, replica visible ${WAIT_MS} ms after the 201 (wall time, local indication)"
  if [ -n "$WURL" ]; then
    check "$(fetch "$WURL" worst)" 200 "worst case: GET pageReplicaUrl"
    check "$(python3 -c 'import gzip,sys;print(len(gzip.decompress(open(sys.argv[1],"rb").read())))' "$W/worst.body")" 3145728 "worst case inflates to 3 145 728 bytes"
  else
    fail "worst case: pageReplicaUrl still null after 30 s"
  fi

  node --no-warnings "$REPO/plan/alief/qa/replica-input.mjs" bomb "$W" || exit 1
  LOGSTART=$( [ -n "${WRANGLER_LOG:-}" ] && wc -l < "$WRANGLER_LOG" || echo 0)
  read -r ST BID POST_MS <<< "$(post_scan bomb)"
  check "$ST" 201 "zero gzip bomb: POST /scans still 201"
  sleep 5
  read -r WAIT_MS BURL <<< "$(replica_url "$BID" 5)"
  check "${BURL:-null}" null "zero gzip bomb: no replica stored"
  say "BENCH bomb: POST /scans answered in ${POST_MS} ms"
  [ $CLOUD = 0 ] && check "$(psql1 "select coalesce(replica_path, 'null') from scans where id = '$BID'")" null "zero gzip bomb: replica_path null in the DB"
  if [ -n "${WRANGLER_LOG:-}" ]; then
    DROP=$(tail -n +"$((LOGSTART + 1))" "$WRANGLER_LOG" | grep -o '"event":"replica_dropped","reason":"[a-z_]*"' | head -1)
    check "$DROP" '"event":"replica_dropped","reason":"too_large"' "zero gzip bomb: dropped as too_large in the Worker log"
    tail -n +"$((LOGSTART + 1))" "$WRANGLER_LOG" | grep -qiE 'exceeded (cpu|memory)|1102|out of memory' && fail "Worker log shows a CPU/memory limit" || pass "no CPU/memory limit error in the Worker log"
  fi
fi

# --- delete = gone immediately (P13) -----------------------------------------------------------
if [ -n "$URL" ]; then
  if [ $CLOUD = 1 ] && [ -t 0 ]; then
    OWNER=$(curl -s "$U/scans/$ID" -H "authorization: Bearer $G" | json ownerDeviceId)
    say "Positive control before the delete (another terminal):"
    say "  npx wrangler r2 object get shoo-replicas/$OWNER/$ID-replica.html.gz --remote --file /dev/null"
    read -r -p "Press Enter to DELETE /devices/me and repeat it (it must fail then) "
  fi
  check "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$U/devices/me" -H "authorization: Bearer $P")" 200 "DELETE /devices/me (Protected)"
  P=""
  check "$(fetch "$URL" gone)" 404 "the same link after DELETE /devices/me"
  [ $CLOUD = 0 ] && check "$(psql1 "select count(*) from scans where id = '$ID'")" 0 "scan row gone"
fi

echo
if [ $FAILS = 0 ]; then say "ALL PASS"; else say "$FAILS FAILED"; exit 1; fi
