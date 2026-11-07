// ADM-09 (shoo-dashboard plan, phase 10a K2): admin.domain_match in JS, over rows shaped like
// admin.domain_lists. The reference the golden file was computed with; no old lists needed here.

/** "a.b.c.id" → ["a.b.c.id", "b.c.id", "c.id", "id"]: the host first, then each parent. */
export const parents = (host) => host.split(".").map((_, i, l) => l.slice(i).join("."));

/** K2 in JS, the reference admin.domain_match is tested against (golden). */
export function match(byDomain, host) {
  const chain = parents(host).map((d, depth) => ({ depth, r: byDomain.get(d) })).filter((x) => x.r);
  const isProtected = chain.some(({ depth, r }) => r.protect === "subtree" || (r.protect === "apex" && depth === 0));
  const isWww = (depth) => depth === 1 && host.startsWith("www.");
  let trusted;
  if (chain.some(({ r }) => r.hosting === "host_path")) trusted = false;
  else if (chain.some(({ depth, r }) => r.hosting === "subdomains" && depth > 0 && !isWww(depth))) trusted = false;
  else trusted = chain.some(({ r }) => r.trusted);
  const hosting = chain.find(({ r }) => r.hosting !== "none")?.r.hosting ?? "none";
  return { protected: isProtected, trusted, hosting };
}

/** The row that makes `host` protected (nearest first), for K12 labels. */
export function protectingRow(byDomain, host) {
  return parents(host).map((d, depth) => ({ depth, r: byDomain.get(d) }))
    .find(({ depth, r }) => r && (r.protect === "subtree" || (r.protect === "apex" && depth === 0)))?.r ?? null;
}
