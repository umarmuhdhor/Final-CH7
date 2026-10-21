import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Local Supabase started with `supabase start` in backend/db. Dev-only password (seed.sql).
const LOCAL_DB = process.env.SHOO_TEST_DB_URL ?? "postgres://shoo_api:shoo_api_local@127.0.0.1:54322/postgres";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        hyperdrives: { DB: LOCAL_DB },
        bindings: {
          INVITE_BASE_URL: "http://localhost:8787",
          APNS_SPIKE: "0",
          SPIKE_KEY: "test-spike-key",
        },
      },
    }),
  ],
  test: {
    // Tests share one local Postgres; run files one at a time.
    fileParallelism: false,
  },
});
