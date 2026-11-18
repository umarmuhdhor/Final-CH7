#!/usr/bin/env bash
# QA-E2E API scenarios (fase 16, R7 §5 #1, #3, #5–#7, #10–#13, #16, #19 + security) against a LOCAL stack.
# Prerequisites: `supabase start` + `supabase db reset` (backend/db), `pnpm -C backend/api dev` (with .dev.vars),
# jq, docker (psql inside container supabase_db_shoo). Never point this at the cloud: it registers 7 devices and rewrites rows directly.
# Usage: bash plan/alief/qa/api-e2e.sh   (prints one PASS/FAIL line per check, exit 1 if any FAIL)
set -uo pipefail
API=${API:-http://localhost:8787}
case "$API" in http://localhost:*|http://127.0.0.1:*) ;; *) echo "local API only" >&2; exit 2 ;; esac
FIX="$(cd "$(dirname "$0")/../../.." && pwd)/contracts/fixtures/blocked-92.json"
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1 ($2)"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails+1)); fi; }
sql() { docker exec supabase_db_shoo psql -U postgres -qtAX -c "$1"; }
# req METHOD PATH TOKEN [BODY] → sets CODE and BODY_OUT
req() {
  local auth=(); [ -n "$3" ] && auth=(-H "Authorization: Bearer $3")
  local out; out=$(curl -s -w '\n%{http_code}' -X "$1" "$API$2" "${auth[@]}" -H 'Content-Type: application/json' ${4:+-d "$4"})
  CODE=${out##*$'\n'}; BODY_OUT=${out%$'\n'*}
}
err() { jq -r '.error.code // empty' <<<"$BODY_OUT"; }
reg() { # name mode [apnsToken] → "deviceId token avatarId"
  req POST /devices "" "{\"name\":\"$1\",\"mode\":\"$2\"${3:+,\"apnsToken\":\"$3\"}}"
  [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || { echo "FAIL register $1: $CODE $BODY_OUT"; fails=$((fails+1)); }
  jq -r '"\(.deviceId) \(.token) \(.avatarId)"' <<<"$BODY_OUT"
}
scan_body() { # url domain status
  jq -c --arg u "$1" --arg d "$2" --arg s "$3" 'del(.id,.verdict,.screenshotUrl,.pageReplicaUrl) | .url=$u | .domain=$d | .status=$s | .ownerDeviceId="00000000-0000-0000-0000-000000000000" | .ownerName="Spoof"' "$FIX"
}

# #1 onboarding
# Fake 64-hex APNs token: the push is attempted (APNs answers BadDeviceToken) and logged.
read -r G1 G1T G1A < <(reg "QA Guardian" guardian "$(printf 'ab%.0s' {1..32})")
check "#1 POST /devices returns avatar_NN" "$(grep -cE '^avatar_[0-9]{2}$' <<<"$G1A")" 1
read -r P1 P1T _ < <(reg "QA Mum" protected)
read -r P2 P2T _ < <(reg "QA Dad" protected)
read -r P3 P3T _ < <(reg "QA Gran" protected)
read -r P4 P4T _ < <(reg "QA Fourth" protected)
read -r G2 G2T _ < <(reg "QA Other G" guardian)
read -r Q1 Q1T _ < <(reg "QA Other P" protected)

# security: token
req GET /devices/me "not-a-token"; check "sec wrong token → 401" "$CODE" 401
req GET /devices/me "";            check "sec no token → 401" "$CODE" 401
req POST /family/code "$P1T" '{}'; check "sec protected cannot make a code → 403" "$CODE" 403

# #3 pairing by typed code
req POST /family/code "$G1T" '{}'; CODE1=$(jq -r .code <<<"$BODY_OUT")
check "#3 code is 6 digits" "$(grep -cE '^[0-9]{6}$' <<<"$CODE1")" 1
check "#3 inviteUrl is https /j/<code>" "$(jq -r .inviteUrl <<<"$BODY_OUT" | grep -cE "^https?://.+/j/$CODE1$")" 1
req POST /family/join "$P1T" "{\"code\":\"$CODE1\"}"
check "#3 join → guardian name" "$(jq -r .guardian.name <<<"$BODY_OUT")" "QA Guardian"
req GET /devices/me "$P1T"; check "#3 /devices/me shows guardian" "$(jq -r .guardian.deviceId <<<"$BODY_OUT")" "$G1"
req POST /family/join "$P1T" "{\"code\":\"$CODE1\"}"; check "#3 join twice → already_connected" "$(err)" already_connected
req POST /family/join "$G2T" "{\"code\":\"$CODE1\"}"; check "sec guardian cannot join → 403" "$CODE" 403
req POST /family/join "$P2T" "{\"code\":\"$CODE1\"}"; check "#3 second member joins" "$CODE" 200
req POST /family/join "$P3T" "{\"code\":\"$CODE1\"}"; check "#3 third member joins" "$CODE" 200

# #7 family full
req POST /family/join "$P4T" "{\"code\":\"$CODE1\"}"; check "#7 fourth member → family_full" "$(err)" family_full
req GET /family/members "$G1T"; check "#7 members = 3" "$(jq '.members|length' <<<"$BODY_OUT")" 3

# #5 expired code (other guardian, expires_at moved into the past)
req POST /family/code "$G2T" '{}'; CODE2=$(jq -r .code <<<"$BODY_OUT")
sql "update family_codes set expires_at = now() - interval '1 second' where code = '$CODE2'" >/dev/null
req POST /family/join "$Q1T" "{\"code\":\"$CODE2\"}"; check "#5 expired code → code_expired" "$(err)" code_expired
req POST /family/code "$G2T" '{}'; CODE2=$(jq -r .code <<<"$BODY_OUT")
check "#5 guardian gets a fresh code" "$(sql "select count(*) from family_codes where code = '$CODE2' and expires_at > now()")" 1

# #6 brute force: wrong codes until too_many_attempts
last=""; for i in 1 2 3 4 5 6 7 8 9 10; do
  req POST /family/join "$P4T" "{\"code\":\"$(printf '%06d' $((RANDOM % 1000000)))\"}"; last=$(err)
  [ "$last" = too_many_attempts ] && break
done
check "#6 wrong codes → too_many_attempts (after $i tries)" "$last" too_many_attempts
check "#6 429 with Retry-After" "$CODE" 429

# second family for IDOR
req POST /family/join "$Q1T" "{\"code\":\"$CODE2\"}"; check "setup other family joined" "$CODE" 200

# #9 / #19 scan from a subdomain, spoofed owner ignored
req POST /scans "$P1T" "$(scan_body "https://login.bca-verifikasi.site/login" bca-verifikasi.site blocked)"
S1=$(jq -r .id <<<"$BODY_OUT"); check "#19 subdomain scan → 201" "$CODE" 201
req GET "/scans/$S1" "$G1T"
check "#19 stored with registrable domain" "$(jq -r .domain <<<"$BODY_OUT")" bca-verifikasi.site
check "sec spoofed ownerDeviceId ignored" "$(jq -r .ownerDeviceId <<<"$BODY_OUT")" "$P1"
check "sec spoofed ownerName ignored" "$(jq -r .ownerName <<<"$BODY_OUT")" "QA Mum"
for _ in 1 2 3 4 5; do [ "$(sql "select count(*) from push_log where scan_id = '$S1'")" -ge 1 ] && break; sleep 1; done
check "#9 push attempted for guardian (push_log)" "$(sql "select count(*) > 0 from push_log where scan_id = '$S1' and to_device_id = '$G1'")" t

# #12 IDOR
req GET "/scans/$S1" "$G2T"; check "#12 other guardian GET /scans/{id} → 404" "$CODE" 404
req GET "/scans/$S1" "$Q1T"; check "#12 other protected GET /scans/{id} → 404" "$CODE" 404
req GET "/scans?owner=$P1" "$G2T"; check "#12 other guardian ?owner=<id> → 403/404" "$( [ "$CODE" = 403 ] || [ "$CODE" = 404 ] && echo ok || echo "$CODE")" ok
req POST /verdicts "$G2T" "{\"scanId\":\"$S1\",\"value\":\"safe\"}"; check "#12 other guardian verdict → verdict_not_allowed" "$(err)" verdict_not_allowed
req POST /verdicts "$P1T" "{\"scanId\":\"$S1\",\"value\":\"safe\"}"; check "sec protected cannot post a verdict → 403" "$CODE" 403

# #10 It's safe
req POST /verdicts "$G1T" "{\"scanId\":\"$S1\",\"value\":\"safe\"}"; check "#10 safe verdict → 200/201" "$( [ "$CODE" = 200 ] || [ "$CODE" = 201 ] && echo ok || echo "$CODE")" ok
req GET "/verdicts?url=https%3A%2F%2Flogin.bca-verifikasi.site%2Flogin&domain=bca-verifikasi.site" "$P1T"
check "#10 Protected sees verdict safe" "$(jq -r .verdict.value <<<"$BODY_OUT")" safe
req GET "/scans/$S1" "$G1T"; check "#10 scan carries the verdict" "$(jq -r .verdict.value <<<"$BODY_OUT")" safe

# #11 Not safe on a second link of another domain
req POST /scans "$P2T" "$(scan_body "https://mandiri-hadiah.site/claim" mandiri-hadiah.site blocked)"; S2=$(jq -r .id <<<"$BODY_OUT")
req POST /verdicts "$G1T" "{\"scanId\":\"$S2\",\"value\":\"not_safe\",\"notes\":\"QA: fake prize page asks for PIN\"}"
check "#11 not_safe verdict accepted" "$( [ "$CODE" = 200 ] || [ "$CODE" = 201 ] && echo ok || echo "$CODE")" ok
req GET "/verdicts?url=https%3A%2F%2Fmandiri-hadiah.site%2Fother&domain=mandiri-hadiah.site" "$P2T"
check "#11 not_safe covers another link of the domain" "$(jq -r .verdict.value <<<"$BODY_OUT")" not_safe
req GET "/scans/$S2" "$G1T"; check "#11 notes never returned" "$(jq -r '.verdict.notes // "absent"' <<<"$BODY_OUT")" absent
check "#11 domain queued, not yet global" "$(sql "select count(*) from blocklist_entries where domain = 'mandiri-hadiah.site' and approved_at is not null" 2>/dev/null || echo n/a)" 0

# #13 disconnect from both sides
req DELETE "/family/members/$P3" "$G1T"; check "#13 guardian removes a member" "$CODE" 200
req GET /family/members "$G1T"; check "#13 members = 2" "$(jq '.members|length' <<<"$BODY_OUT")" 2
req DELETE /family/guardian "$P2T"; check "#13 protected leaves" "$CODE" 200
req GET /family/members "$G1T"; check "#13 members = 1" "$(jq '.members|length' <<<"$BODY_OUT")" 1
req GET "/scans/$S2" "$G1T"; check "#13 old scan of a left member → 404" "$CODE" 404
req GET /devices/me "$P2T"; check "#13 left member sees no guardian" "$(jq -r .guardian <<<"$BODY_OUT")" null

# #16 retention: scan older than 14 days disappears after the cron
req POST /scans "$P1T" "$(scan_body "https://old-scam.site/x" old-scam.site warning)"; S3=$(jq -r .id <<<"$BODY_OUT")
sql "update scans set created_at = now() - interval '15 days' where id = '$S3'" >/dev/null
curl -s "$API/cdn-cgi/handler/scheduled?cron=0+19+*+*+*" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(sql "select count(*) from scans where id = '$S3'")" = 0 ] && break; sleep 1; done
check "#16 scan > 14 days removed by retention" "$(sql "select count(*) from scans where id = '$S3'")" 0
check "#16 recent scan kept" "$(sql "select count(*) from scans where id = '$S1'")" 1

# PF-01 delete my data
req DELETE /devices/me "$Q1T"; check "PF-01 DELETE /devices/me" "$CODE" 200
req GET /devices/me "$Q1T"; check "PF-01 token stops working → 401" "$CODE" 401

echo "fails=$fails"
[ "$fails" = 0 ]
