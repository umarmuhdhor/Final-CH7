// Types for `cloudflare:workers` env/exports inside tests.
declare namespace Cloudflare {
  interface Env {
    DB: Hyperdrive;
    INVITE_BASE_URL: string;
    APNS_SPIKE?: string;
    SPIKE_KEY?: string;
    SUPABASE_URL?: string;
    SUPABASE_SERVICE_ROLE_KEY?: string;
    SCREENSHOT_MAX_BYTES?: string;
  }
  interface GlobalProps {
    mainModule: typeof import("../src/index");
  }
}

// vitest.config.ts runs in Node; only this one Node API is used there.
declare module "node:child_process" {
  export function execSync(command: string, options?: { cwd?: string; stdio?: unknown }): { toString(): string };
}
