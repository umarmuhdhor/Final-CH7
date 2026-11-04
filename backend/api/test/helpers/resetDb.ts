import { env } from "cloudflare:workers";
import postgres, { type Sql, type TransactionSql } from "postgres";

/** Direct connection for assertions, as role shoo_api (same as the Worker). Not ended: see src/app.ts. */
export function testSql(): Sql {
  return postgres(env.DB.connectionString, { max: 1, fetch_types: false });
}

/** Role postgres: what a reviewer does in the SQL editor (approve/remove blocklist domains). */
export function adminSql(): Sql {
  return postgres(env.DB_ADMIN.connectionString, { max: 1, fetch_types: false });
}

let admin: Sql | undefined;

/**
 * Empties every table. shoo_api has DELETE (not TRUNCATE), which is enough for tests, except on
 * blocklist_entries (its policy lets the Worker delete undecided rows only, D-alief-B12) and ops_jobs.
 */
export async function resetDb(sql: Sql): Promise<void> {
  await sql.begin(async (tx) => {
    for (const t of [
      "push_log", "verdicts", "scans", "join_attempts", "family_codes", "family_links",
      "ops_heartbeat", "rate_limit_hits", "storage_tombstones", "devices",
    ]) {
      await tx`delete from ${tx(t)}`;
    }
  });
  admin ??= adminSql();
  await admin`delete from blocklist_entries`;
  // shoo_api cannot delete ops_jobs rows (fase 21a): nobody but a person does.
  await admin`delete from ops_jobs`;
}

/**
 * Bulk fake rows (quota and retention fillers) as role postgres with session_replication_role =
 * replica, so no per-row trigger runs: the admin triggers (ADM-02 domain intel, ADM-07 scan archive)
 * make thousands of rows take seconds, past the 5 s test timeout on CI. Real scans arrive one at a time.
 */
export async function withoutTriggers(run: (tx: TransactionSql) => Promise<unknown>): Promise<void> {
  admin ??= adminSql();
  await admin.begin(async (tx) => {
    await tx`set local session_replication_role = replica`;
    await run(tx);
  });
}
