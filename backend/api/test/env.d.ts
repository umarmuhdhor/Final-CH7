// Types for `cloudflare:workers` env/exports inside tests.
declare namespace Cloudflare {
  interface Env {
    DB: Hyperdrive;
    INVITE_BASE_URL: string;
    APNS_SPIKE?: string;
    SPIKE_KEY?: string;
  }
  interface GlobalProps {
    mainModule: typeof import("../src/index");
  }
}
