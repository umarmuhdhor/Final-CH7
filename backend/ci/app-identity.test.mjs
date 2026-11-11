import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { FILES, mismatches, readIdentity } from "./app-identity.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

const texts = {
  projectYml: [
    "        # `DWTZNGA7Y8.com.umarmuhdhor.shoo`. Moves to our own domain later (TODO E6).",
    "        com.apple.developer.associated-domains:",
    "          - applinks:shoo-api.example.workers.dev",
  ].join("\n"),
  entitlements: "<string>applinks:shoo-api.example.workers.dev</string>",
  appConfig: 'static let publicBaseURL = URL(string: "https://shoo-api.example.workers.dev")!',
  wrangler: [
    '"INVITE_BASE_URL": "https://shoo-api.example.workers.dev",',
    '"APPLINKS_APP_IDS": "DWTZNGA7Y8.com.umarmuhdhor.shoo",',
    '"APNS_TOPIC": "com.umarmuhdhor.shoo",',
  ].join("\n"),
};

test("the repo's own files agree", () => {
  const real = Object.fromEntries(Object.entries(FILES).map(([k, p]) => [k, readFileSync(join(ROOT, p), "utf8")]));
  assert.deepEqual(mismatches(readIdentity(real)), []);
});

test("matching sides: no mismatch", () => {
  assert.deepEqual(mismatches(readIdentity(texts)), []);
});

test("a new Worker host on one side only is caught on every copy", () => {
  const moved = { ...texts, wrangler: texts.wrangler.replace("shoo-api.example.workers.dev", "api.shoo.id") };
  const out = mismatches(readIdentity(moved));
  assert.equal(out.length, 3, out.join("\n"));
  assert.ok(out.every((line) => line.includes("api.shoo.id")));
});

test("a changed bundle ID breaks both the AASA app ID and the APNs topic", () => {
  const renamed = { ...texts, projectYml: texts.projectYml.replace("com.umarmuhdhor.shoo", "id.shoo.app") };
  const out = mismatches(readIdentity(renamed));
  assert.equal(out.length, 2, out.join("\n"));
  assert.match(out[0], /APPLINKS_APP_IDS/);
  assert.match(out[1], /APNS_TOPIC/);
});

test("a changed team ID is caught; a second app ID in the list is fine", () => {
  const otherTeam = { ...texts, projectYml: texts.projectYml.replace("DWTZNGA7Y8", "ABCDE12345") };
  assert.match(mismatches(readIdentity(otherTeam)).join("\n"), /does not list ABCDE12345\.com\.umarmuhdhor\.shoo/);
  const twoApps = {
    ...texts,
    wrangler: texts.wrangler.replace('"DWTZNGA7Y8.com.umarmuhdhor.shoo"', '"ABCDE12345.id.dev, DWTZNGA7Y8.com.umarmuhdhor.shoo"'),
  };
  assert.deepEqual(mismatches(readIdentity(twoApps)), []);
});

test("a missing app ID comment or URL is an error, not a silent pass", () => {
  const noComment = { ...texts, projectYml: texts.projectYml.split("\n").slice(1).join("\n") };
  assert.match(mismatches(readIdentity(noComment)).join("\n"), /no `<Team ID>\.<bundle ID>`/);
  const noUrl = { ...texts, wrangler: texts.wrangler.replace(/"INVITE_BASE_URL"[^\n]*\n/, "") };
  assert.match(mismatches(readIdentity(noUrl)).join("\n"), /INVITE_BASE_URL is missing/);
});
