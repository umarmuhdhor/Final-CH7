import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { execSync } from "node:child_process";
import { defineConfig } from "vitest/config";

// Local Supabase started with `supabase start` in backend/db. Dev-only password (seed.sql).
const LOCAL_DB = process.env.SHOO_TEST_DB_URL ?? "postgres://shoo_api:shoo_api_local@127.0.0.1:54322/postgres";

// Local Storage for screenshot tests: URL + secret key of the running local stack (demo values,
// printed by `supabase status`). Env vars win, e.g. in CI.
function localSupabase(): { url: string; key: string } {
  if (process.env.SHOO_TEST_SUPABASE_URL && process.env.SHOO_TEST_SUPABASE_KEY) {
    return { url: process.env.SHOO_TEST_SUPABASE_URL, key: process.env.SHOO_TEST_SUPABASE_KEY };
  }
  try {
    const out = JSON.parse(execSync("supabase status -o json", { cwd: "../db", stdio: ["ignore", "pipe", "ignore"] }).toString());
    return { url: out.API_URL, key: out.SECRET_KEY ?? out.SERVICE_ROLE_KEY };
  } catch {
    return { url: "http://127.0.0.1:54321", key: "" };
  }
}
const storage = localSupabase();

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        hyperdrives: { DB: LOCAL_DB },
        bindings: {
          INVITE_BASE_URL: "http://localhost:8787",
          SUPABASE_URL: storage.url,
          SUPABASE_SERVICE_ROLE_KEY: storage.key,
          SCREENSHOT_URL_SECRET: "test-screenshot-url-secret",
        },
      },
    }),
  ],
  test: {
    // Tests share one local Postgres; run files one at a time.
    fileParallelism: false,
  },
});
