#!/usr/bin/env bash
# ADM-02 (dashboard plan 02a): the checks pgTAP cannot do in one session, plus trigger overhead (C5).
#   I10  a scan insert is not slowed by a running analysis (target < 50 ms)
#   I11  device delete while an analysis holds the label rows → label_forget, hidden, then deleted
#   SA012 a second run while one holds the advisory lock → analysis_running
#   C5   per-insert cost of admin_scan_intel, sequential (p50/p95) and 10 parallel writers on one domain
#
# Local Supabase only (it writes fixtures prefixed cc_ and removes them at the end):
#   bash backend/db/scripts/admin_intel_concurrency.sh
#   PSQL="psql postgresql://postgres:postgres@127.0.0.1:54322/postgres" bash …   # psql on the host
# Default runs psql inside the Supabase db container.
set -euo pipefail

# Deletes fixtures and empties label_forget: never against anything but local Supabase.
if [ -n "${PSQL:-}" ] && ! [[ "$PSQL" =~ @(127\.0\.0\.1|localhost):54322/ ]]; then
  echo "PSQL must point at local Supabase (127.0.0.1:54322)" >&2; exit 2
fi
if [ -z "${PSQL:-}" ]; then
  C="$(docker ps --format '{{.Names}}' | grep -m1 '^supabase_db_')"
  PSQL="docker exec -i $C psql -U postgres -d postgres"
fi
q() { $PSQL -X -q -t -A -v ON_ERROR_STOP=1 -c "$1"; }

cleanup() {
  q "delete from devices where id like 'cc\_%';
     delete from admin.domain_intel where domain like 'cc-%';
     delete from admin.domain_intel_label where domain like 'cc-%';
     delete from admin.domain_labels where domain like 'cc-%';
     delete from admin.label_forget;" >/dev/null
}
trap cleanup EXIT
cleanup

q "insert into devices (id, name, mode, avatar_id, token_hash) values
     ('cc_g', 'G', 'guardian', 'avatar_01', '\xcc01'), ('cc_p', 'P', 'protected', 'avatar_02', '\xcc02'),
     ('cc_q', 'Q', 'protected', 'avatar_03', '\xcc03');
   insert into family_links (protected_id, guardian_id) values ('cc_p', 'cc_g'), ('cc_q', 'cc_g');
   insert into scans (id, owner_id, url, domain, score, status, detected_at) values
     ('cc_s1', 'cc_p', 'https://cc-run.test/', 'cc-run.test', 90, 'blocked', now()),
     ('cc_s2', 'cc_q', 'https://cc-forget.test/', 'cc-forget.test', 90, 'blocked', now());
   insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
     ('cc_p', 'cc-run.test', 'not_safe', 'cc_s1', 'cc_g', 'G'),
     ('cc_q', 'cc-forget.test', 'not_safe', 'cc_s2', 'cc_g', 'G');" >/dev/null

# Insert duration in ms, measured inside the database.
insert_ms() {
  q "do \$\$ declare t timestamptz := clock_timestamp(); begin
       insert into scans (owner_id, url, domain, score, status, detected_at)
       values ('cc_p', 'https://$1/', '$1', 85, 'blocked', now());
       raise notice '%', round(extract(epoch from clock_timestamp() - t) * 1000, 1);
     end \$\$;" 2>&1 | sed -n 's/.*NOTICE: *//p'
}

echo "== I10: scan insert during a running analysis"
$PSQL -X -q -c "begin; select admin.run_analysis('manual', 'cc@local'); select pg_sleep(3); commit;" >/dev/null &
A=$!
sleep 1
ms="$(insert_ms cc-run.test)"
wait $A
echo "insert while run holds its locks: ${ms} ms (target < 50)"
awk -v m="$ms" 'BEGIN { exit !(m < 50) }' && echo "PASS I10" || { echo "FAIL I10"; exit 1; }

echo "== SA012: second run while the lock is held"
$PSQL -X -q -c "begin; select pg_advisory_xact_lock(7, 0); select pg_sleep(2); commit;" >/dev/null &
A=$!
sleep 0.5
out="$(q "select admin.run_analysis('manual', 'cc@local')" 2>&1 || true)"
wait $A
echo "$out" | grep -q "analysis_running" && echo "PASS SA012" || { echo "FAIL SA012: $out"; exit 1; }

echo "== I11: device delete while the analysis holds the label row"
$PSQL -X -q -c "begin; select id from admin.domain_labels where domain = 'cc-forget.test' for update; select pg_sleep(3); commit;" >/dev/null &
A=$!
sleep 1
del="$(q "do \$\$ declare t timestamptz := clock_timestamp(); begin
            delete from devices where id = 'cc_q';
            raise notice '%', round(extract(epoch from clock_timestamp() - t) * 1000, 1);
          end \$\$;" 2>&1 | sed -n 's/.*NOTICE: *//p')"
wait $A
# The cascade to family_links fires the unlink trigger too: two queue rows.
echo "device delete took ${del} ms (SKIP LOCKED: no wait, held rows go to label_forget)"
queued="$(q "select count(*) from admin.label_forget where owner_ref = admin.owner_ref('cc_q')")"
hidden="$(q "set role shoo_admin; select count(*) from admin.v_labels where domain = 'cc-forget.test'")"
physical="$(q "select count(*) from admin.domain_labels where domain = 'cc-forget.test'")"
q "select admin.snapshot_daily()" >/dev/null
after="$(q "select count(*) from admin.domain_labels where domain = 'cc-forget.test'")"
echo "label_forget=$queued v_labels=$hidden table_before=$physical table_after_snapshot=$after"
awk -v m="$del" 'BEGIN { exit !(m < 100) }' && [ "$queued" -ge 1 ] && [ "$hidden" = 0 ] && [ "$physical" = 1 ] && [ "$after" = 0 ] && echo "PASS I11" || { echo "FAIL I11"; exit 1; }

echo "== K5: one full run (5000 labels over 5000 domains, rolled back) against the role's 5 s default"
run_ms="$(q "begin;
  insert into admin.domain_labels (domain, is_scam, source, connected, owner_ref, by_ref)
  select 'cc-k5-' || g || '.test', g % 3 = 0, 'guardian', true,
         left(md5('o' || g), 16), left(md5('b' || (g % 700)), 16) from generate_series(1, 5000) g;
  do \$\$ declare t timestamptz := clock_timestamp(); begin
    perform admin.run_analysis('manual', 'cc@local');
    raise notice '%', round(extract(epoch from clock_timestamp() - t) * 1000);
  end \$\$;
  rollback;" 2>&1 | sed -n 's/.*NOTICE: *//p')"
echo "run_analysis 5000 labels: ${run_ms} ms (role default statement_timeout 5000 ms; 02b sets 50 s)"
awk -v m="$run_ms" 'BEGIN { exit !(m < 5000) }' && echo "PASS K5 under 5 s" || echo "WARN K5 over 5 s: 02b must set statement_timeout"

echo "== C5: trigger overhead per insert (2000 sequential inserts over 50 domains, rolled back)"
c5() {
  q "begin;
     $1
     do \$\$ declare t timestamptz; d double precision[] := '{}'; begin
       for i in 1..2000 loop
         t := clock_timestamp();
         insert into scans (owner_id, url, domain, score, status, signals, detected_at)
         values ('cc_p', 'https://cc-' || (i % 50) || '.test/', 'cc-' || (i % 50) || '.test', 85, 'blocked',
                 '[{\"id\": \"brand_mismatch\"}, {\"id\": \"otp_form\"}, {\"id\": \"new_domain\"}]', now());
         d := d || extract(epoch from clock_timestamp() - t) * 1000;
       end loop;
       raise notice '% %',
         round((select percentile_cont(0.5) within group (order by x) from unnest(d) x)::numeric, 3),
         round((select percentile_cont(0.95) within group (order by x) from unnest(d) x)::numeric, 3);
     end \$\$;
     rollback;" 2>&1 | sed -n 's/.*NOTICE: *//p'
}
read -r off50 off95 <<<"$(c5 'alter table public.scans disable trigger admin_scan_intel;')"
read -r on50 on95 <<<"$(c5 '')"
echo "without trigger p50=${off50} p95=${off95} ms · with trigger p50=${on50} p95=${on95} ms"
extra="$(awk -v a="$on95" -v b="$off95" 'BEGIN { printf "%.3f", a - b }')"
echo "extra p95 = ${extra} ms (target < 2)"
awk -v e="$extra" 'BEGIN { exit !(e < 2) }' && echo "PASS C5 sequential" || echo "WARN C5 sequential above target"

echo "== C5: 10 parallel writers × 100 inserts on one domain"
par() {
  local start end
  start=$(python3 -c "import time;print(time.time())")
  for w in $(seq 1 10); do
    $PSQL -X -q -c "insert into scans (owner_id, url, domain, score, status, detected_at)
                    select 'cc_p', 'https://cc-hot.test/', 'cc-hot.test', 85, 'blocked', now() from generate_series(1, 100)" >/dev/null &
  done
  wait
  end=$(python3 -c "import time;print(time.time())")
  python3 -c "print(round(($end - $start) * 1000))"
}
t_on="$(par)"
n="$(q "select scans from admin.domain_intel where domain = 'cc-hot.test'")"
echo "10×100 inserts with trigger: ${t_on} ms wall, domain_intel.scans=${n} (expected 1000, fewer = lost counts under lock_timeout)"
