/**
 * Advisory lock classes: the first argument of pg_advisory_xact_lock(class int, key int). Each class
 * is its own key space, so one class per purpose: two purposes on one class wait on each other
 * whenever their keys hash alike, and could close a lock cycle nobody planned (fase 27k F-B12).
 * Always pass a class from here, never a number (test/locks.test.ts checks both).
 *
 * Taken outside the Worker, in the admin SQL functions (migrations): 7 (blocklist decisions, key 1),
 * 8 (API keys), 9 (Worker secrets). The one-argument form pg_advisory_xact_lock(bigint) is a separate
 * key space: the guardian lock (families.ts, trigger family_links_check) and the rate-limit key
 * (http/rateLimit.ts).
 *
 * A changed class only serializes against Workers on the same version: during a deploy an old and a
 * new isolate may briefly take different classes for the same purpose.
 */
export const LOCK = {
  /** Join attempts per device (joinAttempts.ts). Taken before joinIp. */
  joinDevice: 1,
  /** Join attempts per IP hash (joinAttempts.ts). */
  joinIp: 2,
  /** Screenshot reserve per owner (scans.ts reserveScreenshot). */
  screenshot: 3,
  /** Verdicts and the review queue per domain (verdicts.ts). */
  verdictDomain: 4,
  /** A guardian's daily review-queue cap (verdicts.ts decideVerdict). */
  verdictQueue: 5,
  /** Replica reserve per owner, and key 0 for the shared quota count (scans.ts). */
  replica: 6,
  /** Favicon reserve per owner (scans.ts reserveFavicon); was 4, shared with verdictDomain. */
  favicon: 10,
  /** One Activity row per owner + site (scans.ts recordScan); was 7, shared with the admin functions. */
  scanSite: 11,
} as const;
