// Types for `cloudflare:workers` env/exports inside tests.
declare namespace Cloudflare {
  interface Env {
    DB: Hyperdrive;
    /** Tests only: role postgres, for what a person does in the SQL editor (approve blocklist domains). */
    DB_ADMIN: Hyperdrive;
    INVITE_BASE_URL: string;
    APP_STORE_URL?: string;
    APPLINKS_APP_IDS?: string;
    APNS_KEY_P8_B64?: string;
    APNS_KEY_ID?: string;
    APNS_TEAM_ID?: string;
    APNS_TOPIC?: string;
    APNS_ENV?: string;
    SUPABASE_URL?: string;
    SUPABASE_SERVICE_ROLE_KEY?: string;
    SCREENSHOT_MAX_BYTES?: string;
    REPLICAS: R2Bucket;
    REPLICA_ARCHIVE: R2Bucket;
    REPLICAS_ENABLED?: string;
    SCREENSHOT_URL_SECRET?: string;
    RATE_KEY_SECRET?: string;
    OPS_STATUS_TOKEN?: string;
    INACTIVE_DEVICES?: string;
    /** Tests only: "1" runs the slow opt-in cases (vitest.config.ts). */
    SHOO_SLOW_TESTS?: string;
  }
  interface GlobalProps {
    mainModule: typeof import("../src/index");
  }
}

// vitest.config.ts runs in Node; only this one Node API is used there.
declare module "node:child_process" {
  export function execSync(command: string, options?: { cwd?: string; stdio?: unknown }): { toString(): string };
}

// Vite `?raw` imports: a file's text, for tests that check other folders stay in sync (app-config-sync.test.ts).
declare module "*?raw" {
  const text: string;
  export default text;
}
