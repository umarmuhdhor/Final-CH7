import { describe, expect, it } from "vitest";
import { pushText } from "../src/services/push/messages";

describe("pushText (contracts/api.md push payloads, R3 §6)", () => {
  it.each([
    ["en", "blocked", "Mom hit a blocked site · 92%"],
    ["en", "warning", "Mom opened a suspicious site · 41%"],
    ["id", "blocked", "Mom membuka situs yang diblokir · 92%"],
    ["id", "warning", "Mom membuka situs mencurigakan · 41%"],
  ] as const)("%s %s", (lang, status, text) => {
    expect(pushText(lang, status, "Mom", status === "blocked" ? 92 : 41)).toBe(text);
  });
});
