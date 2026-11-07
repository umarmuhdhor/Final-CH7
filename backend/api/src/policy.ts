/**
 * Days a flagged page is kept (PRD §10, contracts/api.md "Scans auto-delete after 14 days"): the scan row
 * with its screenshot, site icon and page copy, and the push log. Retention (src/cron/retention.ts) and the
 * overdue check (src/db/repo/ops.ts) use it; the privacy page, the app's copy and the extension's block
 * memory say the same number (checked by test/retention-sync.test.ts).
 */
export const RETENTION_DAYS = 14;
