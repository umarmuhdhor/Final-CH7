import { describe, expect, it } from "vitest";
import appConfig from "../../../ios/ShooApp/App/AppConfig.swift?raw";
import entitlements from "../../../ios/ShooApp/Shoo.entitlements?raw";
import { CONTACT } from "../src/routes/privacy";
import wrangler from "../wrangler.jsonc?raw";

// The app and the Worker each write some public values down once. They live in two languages, so a test
// keeps the copies equal: change one, this fails until the other follows.

/** The single string literal assigned to `static let <name>` in AppConfig.swift. */
function swiftConstant(name: string): string {
  const match = appConfig.match(new RegExp(`static let ${name}\\b[^=]*=\\s*(?:URL\\(string:\\s*)?"([^"]+)"`));
  if (!match?.[1]) throw new Error(`AppConfig.${name} is not a string literal any more`);
  return match[1];
}

function wranglerVar(name: string): string {
  const match = wrangler.match(new RegExp(`"${name}":\\s*"([^"]*)"`));
  if (!match?.[1]) throw new Error(`wrangler.jsonc has no ${name}`);
  return match[1];
}

describe("app and backend agree", () => {
  it("support address: AppConfig.supportEmail = privacy.ts CONTACT", () => {
    expect(swiftConstant("supportEmail")).toBe(CONTACT);
  });

  it("public host: AppConfig.publicBaseURL = INVITE_BASE_URL (invite links the app accepts)", () => {
    expect(swiftConstant("publicBaseURL")).toBe(wranglerVar("INVITE_BASE_URL"));
  });

  it("Universal Link: the app's applinks entitlement names the same host", () => {
    const host = new URL(wranglerVar("INVITE_BASE_URL")).host;
    expect(entitlements).toContain(`<string>applinks:${host}</string>`);
  });
});
