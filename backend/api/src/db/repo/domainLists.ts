import type { TransactionSql } from "postgres";

/**
 * True when a domain has no registrable domain, so the extension sent the full host (contracts/api.md
 * Scans "`domain`" case 4, #487): an IPv4 or bracketed IPv6 literal, a single label (`router`), or
 * `www.<public suffix>` (`www.co.id`). A registrable domain never starts with `www.`: the extension strips
 * it, also from a shared host_path host. A bare public suffix (`co.id`) is caught by its apex row instead;
 * the backend keeps no Public Suffix List.
 */
export function lacksRegistrableDomain(rawDomain: string): boolean {
  const domain = rawDomain.toLowerCase();
  return (
    domain.startsWith("[") || !domain.includes(".") || domain.startsWith("www.") || /^\d{1,3}(\.\d{1,3}){3}$/.test(domain)
  );
}

/**
 * True when a not_safe verdict on this domain must never enter the global review queue (SECURITY T5):
 * a subtree row of admin.domain_lists covers the domain or a parent, or an apex row is the domain
 * itself (official banks, e-wallets, popular sites, public suffixes, shared hosting platforms). The
 * same rule as admin.domain_match (protected), on the one list the dashboard edits (ADM-09, W16).
 * Also never queued (#495, contracts/api.md Blocklist 1): a domain on or under a `host_path` row
 * (`sites.google.com`, `sway.cloud.microsoft`: on the global list it would block every page of the
 * platform; the same rows public.verdict_shared reads), and a domain with no registrable domain.
 * Runs in the verdict's transaction, without a cache: a domain the dashboard adds counts at once.
 * A family's own not_safe verdict still applies to that family.
 */
export async function isProtected(tx: TransactionSql, rawDomain: string): Promise<boolean> {
  if (lacksRegistrableDomain(rawDomain)) return true;
  const domain = rawDomain.toLowerCase(); // as domain_match; /scans already stores lowercase
  const labels = domain.split(".");
  const suffixes = labels.map((_, i) => labels.slice(i).join(".")); // a.b.c.id → a.b.c.id, b.c.id, c.id, id
  const [row] = await tx<{ hit: boolean }[]>`
    select exists (
      select 1 from admin.v_domain_lists_public
      where domain in ${tx(suffixes)}
        and (protect = 'subtree' or (protect = 'apex' and domain = ${domain}) or hosting = 'host_path')
    ) as hit`;
  return row!.hit; // exists always returns one row
}
