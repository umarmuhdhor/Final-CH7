import { adminSql } from "./resetDb";

let admin: ReturnType<typeof adminSql> | undefined;

/** What the dashboard's set_config / set_thresholds store (dashboard phase 04b), written directly. */
export async function setThresholds(t: { live: boolean; warnAt: number; blockAt: number; version: number }) {
  admin ??= adminSql();
  await admin`update admin.admin_config set value = case key
      when 'thresholds_live' then to_jsonb(${t.live}::boolean)
      when 'threshold_warn_at' then to_jsonb(${t.warnAt}::int)
      when 'threshold_block_at' then to_jsonb(${t.blockAt}::int)
      when 'thresholds_version' then to_jsonb(${t.version}::int) end
    where key in ('thresholds_live', 'threshold_warn_at', 'threshold_block_at', 'thresholds_version')`;
}

/** The migration defaults (admin_learning): 30/80 stored, version 1, not live. */
export const DEFAULT_THRESHOLDS = { live: false, warnAt: 30, blockAt: 80, version: 1 };
