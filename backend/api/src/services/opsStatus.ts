import type { OpsSnapshot } from "../db/repo/ops";

export type OpsLevel = "warn" | "alert";
export interface OpsFailure {
  code: string;
  level: OpsLevel;
}

const MB = 1024 * 1024;
/**
 * Fase 21 K3 (D-alief-B13). Retention runs daily at 19:00 UTC: 26 h leaves 2 h for a late Cron.
 * Notifications run hourly at :05: 2 h 15 min = one missed run plus slack.
 */
export const OPS_THRESHOLDS = {
  retentionStaleHours: 26,
  notificationsStaleHours: 2.25,
  dbWarnBytes: 350 * MB,
  /** Supabase Free has 500 MB. */
  dbAlertBytes: 450 * MB,
  blocklistQueueHours: 24,
} as const;

/**
 * Health of the backend from one snapshot (fase 21 K3): a pure function, so every threshold is
 * pinned by a unit test. `ok` is false only when an `alert` fails; `warn` goes to the daily summary.
 * Codes come in a fixed order, so a caller can compare sets run to run.
 */
export function evaluate(s: OpsSnapshot): { ok: boolean; failing: OpsFailure[] } {
  const t = OPS_THRESHOLDS;
  const failing: OpsFailure[] = [];
  const add = (when: boolean, code: string, level: OpsLevel) => {
    if (when) failing.push({ code, level });
  };
  add(s.retention.okAgeHours === null || s.retention.okAgeHours > t.retentionStaleHours, "retention_stale", "alert");
  add(s.retention.failed > 0, "retention_failed", "alert");
  add(s.retention.backlog, "retention_backlog", "warn");
  add(s.scansOverdue, "retention_overdue", "alert");
  add(s.tombstonesStuck > 0, "tombstones_stuck", "warn");
  add(s.notifications.okAgeHours === null || s.notifications.okAgeHours > t.notificationsStaleHours, "notifications_stale", "alert");
  if (s.dbBytes >= t.dbAlertBytes) add(true, "db_size_high", "alert");
  else add(s.dbBytes >= t.dbWarnBytes, "db_size_high", "warn");
  add(s.blocklistQueue > 0 && (s.blocklistOldestHours ?? 0) > t.blocklistQueueHours, "blocklist_queue", "warn");
  return { ok: !failing.some((f) => f.level === "alert"), failing };
}
