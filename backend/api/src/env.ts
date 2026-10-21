import type { Sql } from "postgres";

export interface Env {
  DB: Hyperdrive;
  INVITE_BASE_URL: string;
  /** "1" enables POST /debug/apns-spike (fase 07 only). */
  APNS_SPIKE?: string;
  /** Secret: header x-spike-key for /debug/apns-spike. */
  SPIKE_KEY?: string;
  /** Supabase project URL, for Storage only (fase 09). */
  SUPABASE_URL?: string;
  /** Secret: Supabase secret/service key, for Storage only. */
  SUPABASE_SERVICE_ROLE_KEY?: string;
  /** Largest accepted screenshot in bytes (contract: 150 KB). */
  SCREENSHOT_MAX_BYTES?: string;
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
