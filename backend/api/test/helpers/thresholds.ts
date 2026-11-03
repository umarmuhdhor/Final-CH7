import type { Sql } from "postgres";
import { adminSql } from "./resetDb";

export type Thresholds = { live: boolean; warnAt: number; blockAt: number; version: number };

let admin: Sql | undefined;
const db = () => (admin ??= adminSql());

/** What the dashboard's set_config / set_thresholds store (dashboard phase 04b), written directly. */
export async function setThresholds(t: Thresholds): Promise<void> {
  await db()`update admin.admin_config set value = case key
      when 'thresholds_live' then to_jsonb(${t.live}::boolean)
      when 'threshold_warn_at' then to_jsonb(${t.warnAt}::int)
      when 'threshold_block_at' then to_jsonb(${t.blockAt}::int)
      when 'thresholds_version' then to_jsonb(${t.version}::int) end
    where key in ('thresholds_live', 'threshold_warn_at', 'threshold_block_at', 'thresholds_version')`;
}

/**
 * The stored thresholds before a test file runs. The local DB is shared with the admin dashboard, so
 * tests restore what was there instead of the migration defaults.
 */
export async function readThresholds(): Promise<Thresholds> {
  const rows = await db()<{ key: string; value: boolean | number }[]>`
    select key, value from admin.admin_config
    where key in ('thresholds_live', 'threshold_warn_at', 'threshold_block_at', 'thresholds_version')`;
  const v = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  return { live: v.thresholds_live === true, warnAt: Number(v.threshold_warn_at), blockAt: Number(v.threshold_block_at),
    version: Number(v.thresholds_version) };
}

/** Not live, 30/80: what a fresh database publishes (version 0 on /config/public). */
export const NOT_LIVE = { live: false, warnAt: 30, blockAt: 80, version: 1 };
