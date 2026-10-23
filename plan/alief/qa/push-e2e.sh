#!/bin/zsh
# Fase 15 step 4: host side of LivePushUITests against wrangler dev (localhost:8787) + local Supabase.
# Needs a prior `xcodebuild build-for-testing` into $SP/dd. Usage: SP=<work dir> GUARD_UDID=<udid> zsh plan/alief/qa/push-e2e.sh
set -u
SP=${SP:?set SP to a work dir holding dd/ (derivedData)}
case "$SP" in /|"$HOME"|"$HOME"/) echo "refusing SP=$SP"; exit 1;; esac
G=${GUARD_UDID:?set GUARD_UDID}
U=http://localhost:8787
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
# Local only: wrangler dev answers and the DB container is the local Supabase.
curl -s -o /dev/null --max-time 3 "$U/" || { echo "wrangler dev not running on $U"; exit 1; }
docker inspect supabase_db_shoo >/dev/null 2>&1 || { echo "local Supabase container not running"; exit 1; }
D=$SP/push; SHOTS=$SP/pushshots; LOG=$SP/push-host.log
rm -rf "$D" "$SHOTS" "$SP/push.xcresult"; mkdir -p "$D" "$SHOTS"; : > "$LOG"
say() { echo "$(date '+%H:%M:%S') $*" | tee -a $LOG; }
now() { python3 -c 'import time;print(int(time.time()*1000))'; }
waitf() { for i in {1..240}; do [ -s $D/$1 ] && return 0; sleep 0.5; done; say "timeout $1"; return 1; }
psql1() { docker exec supabase_db_shoo psql -U postgres -tAc "$1"; }

cd $REPO/ios
TEST_RUNNER_SHOO_LIVE_BACKEND=1 TEST_RUNNER_SHOO_PUSH_DIR=$D TEST_RUNNER_SHOO_SHOT_DIR=$SHOTS \
  xcodebuild test-without-building -project Shoo.xcodeproj -scheme Shoo -destination "id=$G" -derivedDataPath $SP/dd \
  -resultBundlePath $SP/push.xcresult -only-testing:ShooAppUITests/LivePushUITests > $SP/push-ui.log 2>&1 &
UI=$!

waitf code.txt || exit 1
CODE=$(cat $D/code.txt); say "code shown"
GUARD_ID=$(psql1 "select id from devices where mode='guardian' and name='Rina' order by created_at desc limit 1")
TOK=$(psql1 "select length(apns_token) from devices where id='$GUARD_ID'")
say "guardian apns_token length: ${TOK:-null}"
# The simulator's apsd hands out no token (log fase 15): a dummy one in the local DB lets the backend log the push.
[ -z "$TOK" ] && psql1 "update devices set apns_token=repeat('0',64) where id='$GUARD_ID'" >/dev/null && say "dummy apns_token set (local DB)"
PT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Mom","mode":"protected"}' | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))')
# POST /devices is rate limited per IP: many runs in a row get 429 for a while.
[ -n "$PT" ] || { say "POST /devices refused (rate limit?), try again later"; kill $UI; exit 1; }
say "join $(curl -s -o /dev/null -w '%{http_code}' -X POST $U/family/join -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "{\"code\":\"$CODE\"}")"
echo 1 > $D/joined

for S in foreground background terminated; do
  waitf ready-$S || break
  DOMAIN="bca-verifikasi-$S.site"
  BODY=$(python3 -c 'import json,sys;f=json.load(open(sys.argv[1]));[f.pop(k) for k in ("id","verdict","screenshotUrl")];f["url"]="https://"+sys.argv[2]+"/login";f["domain"]=sys.argv[2];print(json.dumps(f))' "$REPO/contracts/fixtures/blocked-92.json" "$DOMAIN")
  T0=$(now)
  ID=$(curl -s -X POST $U/scans -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "$BODY" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
  [[ "$ID" =~ '^[0-9a-f-]{36}$' ]] || { say "$S: unexpected scan id"; break; }
  for i in {1..20}; do R=$(psql1 "select result from push_log where scan_id='$ID'"); [ -n "$R" ] && break; sleep 0.5; done
  say "$S: scan $ID push_log=${R:-none} after $(( $(now) - T0 )) ms"
  python3 -c 'import json,sys;json.dump({"aps":{"alert":{"body":"Mom hit a blocked site · 92%"},"sound":"default"},"scanId":sys.argv[1]},open(sys.argv[2],"w"),ensure_ascii=False)' "$ID" "$D/$S.apns"
  T1=$(now); xcrun simctl push $G com.shoo.app $D/$S.apns >> $LOG 2>&1
  echo $ID > $D/pushed-$S
  waitf detail-$S || break
  say "$S: push to Detail $(( $(cut -d' ' -f1 $D/detail-$S) - T1 )) ms (tap included)"
  waitf safe-$S || break
  TS=$(cat $D/safe-$S)
  for i in {1..40}; do
    V=$(curl -s "$U/verdicts?domain=$DOMAIN" -H "authorization: Bearer $PT")
    echo $V | grep -q '"safe"' && break; sleep 0.1
  done
  say "$S: GET /verdicts as Protected -> $V ($(( $(now) - TS )) ms after the tap)"
  echo 1 > $D/checked-$S
done
wait $UI; say "ui exit $?"
grep -E "Test Case .* (passed|failed)|error:" $SP/push-ui.log | tee -a $LOG
curl -s -o /dev/null -w "cleanup %{http_code}\n" -X DELETE $U/devices/me -H "authorization: Bearer $PT" | tee -a $LOG
