import { describe, expect, it } from "vitest";
import contract from "../../../contracts/api.md?raw";
import strings from "../../../ios/ShooApp/Resources/Localizable.xcstrings?raw";
import connectView from "../../../ios/ShooApp/Features/Pairing/ConnectView.swift?raw";
import detailView from "../../../ios/ShooApp/Features/Detail/DetailView.swift?raw";
import blockMemory from "../../../ios/ShooExtension/Resources/block-memory.js?raw";
import { RETENTION_DAYS } from "../src/policy";
import privacy from "../src/routes/privacy.ts?raw";

// Retention is one number in code (src/policy.ts) and prose everywhere a person reads it. When the number
// changes, this fails at every place whose wording still says the old one. Read-only for other folders.
const N = RETENTION_DAYS;

describe(`retention: ${N} days everywhere`, () => {
  it("is the number in contracts/api.md", () => {
    expect(contract).toContain(`Scans auto-delete after ${N} days`);
  });

  it("privacy page says it in both languages", () => {
    expect(privacy).toContain(`deleted automatically after ${N} days`);
    expect(privacy).toContain(`dihapus otomatis setelah ${N} hari`);
  });

  it("app copy says it (English source and Bahasa Indonesia)", () => {
    expect(connectView).toContain(`for ${N} days, so your Guardian can see the evidence`);
    expect(detailView).toContain(`Items are deleted after ${N} days`);
    expect(strings).toContain(`selama ${N} hari supaya Guardian bisa melihat buktinya`);
    expect(strings).toContain(`Item dihapus setelah ${N} hari`);
  });

  it("the extension's block memory forgets a page when the scan is gone", () => {
    expect(blockMemory).toMatch(new RegExp(`TTL_MS = ${N} \\* 24 \\* 60 \\* 60 \\* 1000;`));
  });
});
