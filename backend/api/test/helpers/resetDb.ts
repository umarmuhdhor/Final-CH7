import { env } from "cloudflare:workers";
import postgres, { type Sql } from "postgres";

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
 * blocklist_entries: its policy lets the Worker delete undecided rows only (D-alief-B12).
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
}
