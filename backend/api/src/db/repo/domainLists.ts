import type { TransactionSql } from "postgres";

/**
 * True when a not_safe verdict on this domain must never enter the global review queue (SECURITY T5):
 * a subtree row of admin.domain_lists covers the domain or a parent, or an apex row is the domain
 * itself (official banks, e-wallets, popular sites, public suffixes, shared hosting platforms). The
 * same rule as admin.domain_match (protected), on the one list the dashboard edits (ADM-09, W16).
 * Runs in the verdict's transaction, without a cache: a domain the dashboard adds counts at once.
 * A family's own not_safe verdict still applies to that family.
 */
export async function isProtected(tx: TransactionSql, rawDomain: string): Promise<boolean> {
  const domain = rawDomain.toLowerCase(); // as domain_match; /scans already stores lowercase
  const labels = domain.split(".");
  const suffixes = labels.map((_, i) => labels.slice(i).join(".")); // a.b.c.id → a.b.c.id, b.c.id, c.id, id
  const [row] = await tx<{ hit: boolean }[]>`
    select exists (
      select 1 from admin.v_domain_lists_public
      where domain in ${tx(suffixes)} and (protect = 'subtree' or (protect = 'apex' and domain = ${domain}))
    ) as hit`;
  return row!.hit; // exists always returns one row
}
