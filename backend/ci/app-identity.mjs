// #326: the app's identity is written on both sides by hand. A missed copy silently breaks Universal Links
// (the AASA lists the wrong app) or pushes (APNs rejects the topic). This check fails CI when they drift.
//
// iOS side (read-only, lead's files): `ios/project.yml` (applinks host, and the `<Team ID>.<bundle ID>` the
// Worker must serve, written in the comment above it) and `ios/ShooApp/Shoo.entitlements`.
// App side: `ios/ShooApp/App/AppConfig.swift` `publicBaseURL`, and `cloudAPIURL`: the Worker's workers.dev host, where
// invite links handed out before PR-03 moved them to `publicBaseURL` still point. It may stay in applinks beside the
// invite host, so those links keep opening the app; no other host may.
// Backend side: `backend/api/wrangler.jsonc` `INVITE_BASE_URL`, `APPLINKS_APP_IDS`, `APNS_TOPIC`.
//
//   node backend/ci/app-identity.mjs   (from the repo root; exit 1 with one line per mismatch)
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const FILES = {
  projectYml: "ios/project.yml",
  entitlements: "ios/ShooApp/Shoo.entitlements",
  appConfig: "ios/ShooApp/App/AppConfig.swift",
  wrangler: "backend/api/wrangler.jsonc",
};

/** `"KEY": "value"` from wrangler.jsonc. Regex, not a JSONC parser: the values are plain strings. */
function wranglerVar(text, key) {
  const match = text.match(new RegExp(`"${key}"\\s*:\\s*"([^"]*)"`));
  return match ? match[1] : undefined;
}

const hostOf = (url) => {
  try {
    return new URL(url).hostname;
  } catch {
    return undefined;
  }
};

/** Every value the check compares, read from the file texts (`{ projectYml, entitlements, appConfig, wrangler }`). */
export function readIdentity(texts) {
  const appIdInComment = texts.projectYml.match(/`([A-Z0-9]{10})\.([A-Za-z0-9.-]+)`/);
  const appConfigBase = texts.appConfig.match(/publicBaseURL\s*=\s*URL\(string:\s*"([^"]+)"/);
  const appConfigCloud = texts.appConfig.match(/cloudAPIURL\s*=\s*URL\(string:\s*"([^"]+)"/);
  return {
    ios: {
      teamId: appIdInComment?.[1],
      bundleId: appIdInComment?.[2],
      applinksHosts: [...texts.projectYml.matchAll(/applinks:([A-Za-z0-9.-]+)/g)].map((m) => m[1]),
      entitlementHosts: [...texts.entitlements.matchAll(/applinks:([A-Za-z0-9.-]+)/g)].map((m) => m[1]),
      appBaseHost: appConfigBase ? hostOf(appConfigBase[1]) : undefined,
      legacyInviteHost: appConfigCloud ? hostOf(appConfigCloud[1]) : undefined,
    },
    backend: {
      inviteHost: hostOf(wranglerVar(texts.wrangler, "INVITE_BASE_URL") ?? ""),
      appIds: (wranglerVar(texts.wrangler, "APPLINKS_APP_IDS") ?? "").split(",").map((s) => s.trim()).filter(Boolean),
      apnsTopic: wranglerVar(texts.wrangler, "APNS_TOPIC"),
    },
  };
}

/** One readable line per mismatch; empty when both sides agree. */
export function mismatches({ ios, backend }) {
  const out = [];
  if (!ios.teamId || !ios.bundleId) {
    out.push(`${FILES.projectYml}: no \`<Team ID>.<bundle ID>\` above the associated-domains entry`);
  }
  if (!backend.inviteHost) out.push(`${FILES.wrangler}: INVITE_BASE_URL is missing or not a URL`);
  if (ios.applinksHosts.length === 0) out.push(`${FILES.projectYml}: no applinks: host`);
  if (backend.inviteHost) {
    // The invite host, plus the old workers.dev host of links handed out before PR-03.
    const allowed = [backend.inviteHost, ios.legacyInviteHost].filter(Boolean);
    for (const [file, hosts] of [[FILES.projectYml, ios.applinksHosts], [FILES.entitlements, ios.entitlementHosts]]) {
      const stray = hosts.filter((host) => !allowed.includes(host));
      for (const host of stray) out.push(`${file}: applinks:${host} but INVITE_BASE_URL host is ${backend.inviteHost}`);
      // Only the old host left: new invite links would open Safari instead of the app.
      if (!stray.length && hosts.length && !hosts.includes(backend.inviteHost)) {
        out.push(`${file}: no applinks:${backend.inviteHost} (INVITE_BASE_URL host)`);
      }
    }
  }
  if (backend.inviteHost && ios.appBaseHost !== backend.inviteHost) {
    out.push(`${FILES.appConfig}: publicBaseURL host ${ios.appBaseHost} but INVITE_BASE_URL host is ${backend.inviteHost}`);
  }
  if (ios.teamId && ios.bundleId) {
    const appId = `${ios.teamId}.${ios.bundleId}`;
    if (!backend.appIds.includes(appId)) {
      out.push(`${FILES.wrangler}: APPLINKS_APP_IDS "${backend.appIds.join(",")}" does not list ${appId}`);
    }
    if (backend.apnsTopic !== ios.bundleId) {
      out.push(`${FILES.wrangler}: APNS_TOPIC "${backend.apnsTopic}" is not the bundle ID ${ios.bundleId}`);
    }
  }
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const texts = Object.fromEntries(Object.entries(FILES).map(([k, path]) => [k, readFileSync(join(ROOT, path), "utf8")]));
  const problems = mismatches(readIdentity(texts));
  if (problems.length) {
    for (const p of problems) console.error(`::error::${p}`);
    process.exit(1);
  }
  console.log("App identity matches: bundle ID, team ID and applinks host agree on both sides.");
}
