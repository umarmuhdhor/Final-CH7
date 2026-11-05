#!/usr/bin/env bash
# Seeds the LOCAL Supabase database with dummy data (see dummy.mjs), runs check-dummy.sql, and can
# export admin.ai_dataset as JSON lines (as shoo_ai, the role Team AI really uses).
#
#   ai/eval/dataset/seed-dummy.sh [--seed N] [--export out.jsonl]
#
# Env: DB_URL (default local postgres on 54322), AI_DB_URL (default shoo_ai on 54322).
# Refuses to run unless the host is 127.0.0.1 or localhost; it stops before any query is sent.
set -euo pipefail
cd "$(dirname "$0")"

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
AI_DB_URL="${AI_DB_URL:-postgresql://shoo_ai:shoo_ai_local@127.0.0.1:54322/postgres}"

assert_local() {
  local url=$1 host
  host=$(printf '%s' "$url" | sed -E 's#^[a-z]+://([^@/]*@)?(\[[^]]*\]|[^:/?]*).*#\2#')
  case "$host" in
    127.0.0.1|localhost) ;;
    *) echo "refusing: not a local database (host: ${host:-none})" >&2; exit 1 ;;
  esac
  # A libpq query parameter can override the host in the URL.
  case "$url" in
    *\?*host*|*\&*host*) echo "refusing: not a local database (host parameter in URL)" >&2; exit 1 ;;
  esac
}
assert_local "$DB_URL"
assert_local "$AI_DB_URL"

seed=1
export_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) seed=$2; shift 2 ;;
    --export) export_file=$2; shift 2 ;;
    *) echo "usage: seed-dummy.sh [--seed N] [--export out.jsonl]" >&2; exit 2 ;;
  esac
done

PSQL=$(command -v psql || true)
[ -n "$PSQL" ] || PSQL=/opt/homebrew/opt/libpq/bin/psql
[ -x "$PSQL" ] || { echo "psql not found (brew install libpq)" >&2; exit 1; }

node dummy.mjs --seed "$seed" | "$PSQL" "$DB_URL" -v ON_ERROR_STOP=1 -q -f -
"$PSQL" "$DB_URL" -v ON_ERROR_STOP=1 -q -f check-dummy.sql

if [ -n "$export_file" ]; then
  "$PSQL" "$AI_DB_URL" -v ON_ERROR_STOP=1 -At -c "select row_to_json(d) from admin.ai_dataset d order by d.id" > "$export_file"
  echo "exported $(wc -l < "$export_file" | tr -d ' ') rows to $export_file"
fi
