// ADM-09 (shoo-dashboard plan, phase 10a/10c): a snapshot of admin.v_domain_lists_public from the local
// database, for the fallback copy readers bundle in phase 10c (they never fall back to an empty list,
// D-dash-21 #4). The response shape of GET /lists/domains waits for the contract (X11), so this writes
// the view as it is, plus the version: { version, domains: [{ domain, protect, trusted, hosting }] }.
//   node backend/db/scripts/export-domain-lists.mjs > domain-lists.snapshot.json
// Reads through `docker exec` on the local Supabase container (no client library in backend/db).
import { execFileSync } from "node:child_process";

const CONTAINER = process.env.SHOO_DB_CONTAINER ?? "supabase_db_shoo";
const query = `select json_build_object(
  'version', (select version from admin.domain_lists_meta),
  'domains', coalesce((select json_agg(json_build_object('domain', domain, 'protect', protect, 'trusted', trusted,
                                                         'hosting', hosting) order by domain)
                       from admin.v_domain_lists_public), '[]'))`;
const out = execFileSync("docker", ["exec", CONTAINER, "psql", "-U", "postgres", "-At", "-c", query], { encoding: "utf8" });
const snapshot = JSON.parse(out);
if (!Array.isArray(snapshot.domains) || snapshot.domains.length === 0) throw new Error("empty domain list: refusing to write");
process.stdout.write(JSON.stringify(snapshot, null, 1) + "\n");
