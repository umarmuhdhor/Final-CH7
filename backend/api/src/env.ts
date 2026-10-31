import type { Sql } from "postgres";

export interface Env {
  DB: Hyperdrive;
  /** R2 bucket `shoo-replicas`: page replicas (EX-07) and new favicons (PR-05, D-alief-C27). */
  REPLICAS?: R2Bucket;
  /** Kill-switch (D-alief-C25 d): only "true" stores and serves replicas. Deletes ignore it. */
  REPLICAS_ENABLED?: string;
  INVITE_BASE_URL: string;
  /** TestFlight or App Store link on the invite page (PR-03). Unset → apps.apple.com. */
  APP_STORE_URL?: string;
  /** Comma-separated `<Team ID>.<bundle ID>` for the Universal Link (issue #129). Unset → no app. */
  APPLINKS_APP_IDS?: string;
  /** Secret: APNs .p8 key (PEM) as one line of base64 (fase 11, D-alief-B01). */
  APNS_KEY_P8_B64?: string;
  /** Secret: APNs key id (10 chars). */
  APNS_KEY_ID?: string;
  /** Secret: Apple Developer team id. */
  APNS_TEAM_ID?: string;
  /** Bundle ID of the build that receives pushes. Empty → LogSender. */
  APNS_TOPIC?: string;
  /** "sandbox" (Debug builds) | "production" (TestFlight). */
  APNS_ENV?: string;
  /** Supabase project URL, for Storage only (fase 09). */
  SUPABASE_URL?: string;
  /** Secret: Supabase secret/service key, for Storage only. */
  SUPABASE_SERVICE_ROLE_KEY?: string;
  /** Largest accepted screenshot in bytes (contract: 150 KB). */
  SCREENSHOT_MAX_BYTES?: string;
  /** Secret: HMAC key for rate-limit keys and join attempt IPs (D-alief-B12). Unset → sha256. */
  RATE_KEY_SECRET?: string;
  /** Secret: HMAC key for screenshot links (D-alief-B08). Unset → screenshotUrl null. */
  SCREENSHOT_URL_SECRET?: string;
}

export type DeviceMode = "guardian" | "protected";
export type Language = "en" | "id";

export interface Principal {
  deviceId: string;
  mode: DeviceMode;
  name: string;
  language: Language;
}

export interface AppEnv {
  Bindings: Env;
  Variables: {
    requestId: string;
    sql: Sql;
    principal: Principal;
  };
}
