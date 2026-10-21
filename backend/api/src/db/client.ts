import postgres, { type Sql } from "postgres";
import type { Env } from "../env";

/**
 * One client per request through Hyperdrive. `prepare` stays at its default
 * (Hyperdrive docs: do not set prepare:false). `fetch_types: false` saves a
 * round trip, so never pass JS arrays as parameters (R5 §2).
 */
export function createSql(env: Env): Sql {
  return postgres(env.DB.connectionString, { max: 5, fetch_types: false });
}
