#!/usr/bin/env bash
# Fase 23c (K7 a): a Guardian sees the page copy (replica) of a real scan, in the app, on one simulator.
# Runs ShooAppUITests/LiveReplicaUITests against wrangler dev (localhost:8787) + local Supabase. The test
# onboards a Guardian through the UI and writes the family code to $W/code.txt; this script registers a
# Protected device with curl, joins, posts a scan with a replica built by the extension's own code
# (replica-input.mjs), waits until the Worker stored the copy and writes the scan id to $W/scan.txt.
# The test then opens shoo://scan/<id>, checks "Copy of the page" and deletes the Guardian from Profile.
#
#   bash plan/alief/qa/replica-ui.sh
#
# Needs: `pnpm -C backend/api dev` (backend/api/.dev.vars) and `supabase start` first, Node 24, xcodegen.
# Env: SHOO_SIM        simulator UDID (default: "Shoo QA SE" of plan/alief/fase-23-ci-reliability.md)
#      SHOO_DD         -derivedDataPath (default: $TMPDIR/shoo-dd-replica-ui)
#      SHOO_SHOT_DIR   where live-replica-se.png goes (default: plan/alief/qa/img/fase-23)
# Every run registers 2 devices (POST /devices: 10 per hour per IP) and deletes both. No token is printed:
# the Guardian's never leaves the app, the Protected's stays in this shell and a chmod 700 temp dir.
# Exit code = the exit code of xcodebuild (1 when the stack is not up or the build fails; 0/65 from the
# log when xcodebuild had to be stopped after the tests ended).
set -uo pipefail

U=http://localhost:8787
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
SIM=${SHOO_SIM:-483B28B6-913A-4C3A-8A4C-0C7219022682}
DD=${SHOO_DD:-${TMPDIR:-/tmp}/shoo-dd-replica-ui}
SHOT_DIR=${SHOO_SHOT_DIR:-$REPO/plan/alief/qa/img/fase-23}
DEST="platform=iOS Simulator,id=$SIM"
# Simulator signing like CI (.github/workflows/ios-app.yml): ad hoc, no team, no profile.
SIGN=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
TEST=ShooAppUITests/LiveReplicaUITests
W=$(mktemp -d); chmod 700 "$W"
LOG="$DD/replica-ui-test.log"
P="" XB=""

say() { echo "$(date '+%H:%M:%S') $*"; }
json() { python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get(sys.argv[1]) or "")' "$1" 2>/dev/null; }
devices() { docker exec supabase_db_shoo psql -U postgres -Atc "select count(*) from devices"; }
# The test fails at once on error.txt instead of waiting for scan.txt.
host_fail() { say "FAIL $*"; echo "$*" > "$W/error.txt"; }
delete_protected() {
  [ -n "$P" ] || return 0
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$U/devices/me" -H "authorization: Bearer $P")
  [ "$code" = 200 ] && say "Protected deleted (DELETE /devices/me 200)" || say "WARN DELETE /devices/me (Protected) answered $code"
  P=""
}
cleanup() {
  delete_protected
  if [ -n "$XB" ] && kill -0 "$XB" 2>/dev/null; then kill "$XB" 2>/dev/null; fi
  rm -rf "$W"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

curl -s -o /dev/null --max-time 5 "$U/healthz" || { echo "$U not reachable: pnpm -C backend/api dev"; exit 1; }
docker inspect supabase_db_shoo >/dev/null 2>&1 || { echo "local Supabase container not running: supabase start"; exit 1; }
if pgrep -f 'vitest|supabase test' >/dev/null; then say "WARN backend tests are running and may reset the shared DB mid-run"; fi
mkdir -p "$DD" "$SHOT_DIR"
BEFORE=$(devices)
T0=$(date +%s)

(cd "$REPO/ios" && xcodegen -q) || { echo "xcodegen failed"; exit 1; }
say "build-for-testing ($SIM) …"
xcodebuild build-for-testing -project "$REPO/ios/Shoo.xcodeproj" -scheme Shoo -destination "$DEST" \
  -derivedDataPath "$DD" "${SIGN[@]}" > "$DD/replica-ui-build.log" 2>&1 \
  || { grep -E ": error: " "$DD/replica-ui-build.log" | head -20; echo "build failed, log: $DD/replica-ui-build.log"; exit 1; }

say "test $TEST …"
TEST_RUNNER_SHOO_LIVE_BACKEND=1 TEST_RUNNER_SHOO_LIVE_REPLICA=1 \
TEST_RUNNER_SHOO_REPLICA_DIR="$W" TEST_RUNNER_SHOO_SHOT_DIR="$SHOT_DIR" \
  xcodebuild test-without-building -project "$REPO/ios/Shoo.xcodeproj" -scheme Shoo -destination "$DEST" \
  -derivedDataPath "$DD" -only-testing:"$TEST" "${SIGN[@]}" > "$LOG" 2>&1 &
XB=$!

# --- the Guardian's code (the app registers and opens the invite sheet) ------------------------------
CODE=""
for ((i = 0; i < 240; i++)); do
  [ -s "$W/code.txt" ] && { CODE=$(tr -dc '0-9' < "$W/code.txt"); break; }
  kill -0 "$XB" 2>/dev/null || break
  sleep 0.5
done

if [ ${#CODE} = 6 ]; then
  say "family code on screen after $(($(date +%s) - T0)) s"
  # --- Protected joins and posts a scan with a replica ---------------------------------------------
  curl -s -X POST "$U/devices" -H 'content-type: application/json' -d '{"name":"Mom","mode":"protected"}' > "$W/dev.json"
  P=$(json token < "$W/dev.json"); rm -f "$W/dev.json"
  if [ -z "$P" ]; then
    host_fail "POST /devices (Protected) refused: rate limit 10/hour per IP?"
  elif [ "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$U/family/join" -H "authorization: Bearer $P" \
          -H 'content-type: application/json' -d "{\"code\":\"$CODE\"}")" != 200 ]; then
    host_fail "POST /family/join did not answer 200"
  elif ! node --no-warnings "$REPO/plan/alief/qa/replica-input.mjs" sample "$W" > /dev/null; then
    host_fail "replica-input.mjs failed"
  else
    DOMAIN="bca-verifikasi-ui-$RANDOM$RANDOM.site"
    python3 - "$REPO/contracts/fixtures/blocked-92.json" "$DOMAIN" "$W/sample.b64" > "$W/scan.json" <<'PY'
import json, sys
f = json.load(open(sys.argv[1]))
for k in ("id", "verdict", "screenshotUrl", "pageReplicaUrl"):
    f.pop(k, None)
f["url"] = "https://" + sys.argv[2] + "/login"
f["domain"] = sys.argv[2]
f["pageReplicaBase64"] = open(sys.argv[3]).read()
print(json.dumps(f))
PY
    ST=$(curl -s -o "$W/scan.resp" -w '%{http_code}' -X POST "$U/scans" -H "authorization: Bearer $P" \
      -H 'content-type: application/json' --data-binary "@$W/scan.json")
    ID=$(json id < "$W/scan.resp")
    if [ "$ST" != 201 ] || [ -z "$ID" ]; then
      host_fail "POST /scans answered $ST"
    else
      # The Worker stores the replica in waitUntil after the 201: wait for it as the owner, so the app's
      # Detail does not depend on its own retry window (DetailModel.copyRetryDelays).
      URL=""
      for ((i = 0; i < 80; i++)); do
        URL=$(curl -s "$U/scans/$ID" -H "authorization: Bearer $P" | json pageReplicaUrl)
        [ -n "$URL" ] && break
        sleep 0.25
      done
      if [ -n "$URL" ]; then
        echo "$ID" > "$W/scan.txt"
        say "scan with a stored copy ready after $(($(date +%s) - T0)) s"
      else
        host_fail "pageReplicaUrl still null 20 s after POST /scans"
      fi
    fi
  fi
else
  say "FAIL the app never wrote a family code (log: $LOG)"
fi

# xcodebuild once hung for hours after the test had ended (simulator gone while it collected results):
# 180 s after the suite ended, or 15 min after the start, stop it and take the result from the log.
ENDED=""
while kill -0 "$XB" 2>/dev/null; do
  if [ -z "$ENDED" ] && grep -qE "^Test Suite 'Selected tests' (passed|failed)" "$LOG"; then ENDED=$(date +%s); fi
  NOW=$(date +%s)
  if { [ -n "$ENDED" ] && [ $((NOW - ENDED)) -gt 180 ]; } || [ $((NOW - T0)) -gt 900 ]; then
    say "WARN xcodebuild did not exit on its own: stopping it"
    kill "$XB" 2>/dev/null; break
  fi
  sleep 2
done
wait "$XB"; STATUS=$?; XB=""
if [ $STATUS -gt 128 ]; then
  if grep -qE "^Test Suite 'Selected tests' passed" "$LOG"; then STATUS=0; else STATUS=65; fi
fi
delete_protected
grep -E "^Test Case .*(passed|failed|skipped)|: error: |XCTAssert|Test Suite .* (passed|failed)" "$LOG" | tail -15
AFTER=$(devices)
say "devices before=$BEFORE after=$AFTER (Guardian is deleted by the test, Protected by this script)"
[ "$BEFORE" = "$AFTER" ] || say "WARN device count changed: a leftover, or another session used the shared DB"
[ -f "$SHOT_DIR/live-replica-se.png" ] && say "screenshot: $SHOT_DIR/live-replica-se.png"
if [ $STATUS = 0 ]; then say "PASS in $(($(date +%s) - T0)) s"; else say "FAIL (xcodebuild exit $STATUS, log: $LOG)"; fi
exit $STATUS
