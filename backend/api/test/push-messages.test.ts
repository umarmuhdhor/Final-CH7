import { describe, expect, it } from "vitest";
import { familyPushText, pushLevel, pushText } from "../src/services/push/messages";

describe("pushText (contracts/api.md push payloads, push-copy proposal option A)", () => {
  it.each([
    ["en", "warning", 30, "Be careful: Mom opened a suspicious site. Remind Mom not to enter personal details. Tap to see why."],
    ["en", "warning", 50, "High risk: Mom opened a site that may be a scam. Call Mom and ask them not to enter a PIN or OTP. Tap for details."],
    ["en", "blocked", 92, "Blocked: Shoo closed a dangerous site Mom opened. Mom is safe. Tap to check it and decide if it's safe."],
    ["id", "warning", 49, "Waspada: Mom membuka situs mencurigakan. Ingatkan Mom jangan isi data pribadi. Ketuk untuk lihat alasannya."],
    ["id", "warning", 79, "Risiko tinggi: Mom membuka situs yang mungkin penipuan. Telepon Mom, minta jangan isi PIN atau OTP. Ketuk untuk detail."],
    ["id", "blocked", 50, "Diblokir: Shoo menutup situs berbahaya yang dibuka Mom. Mom aman. Ketuk untuk cek dan putuskan apakah situs ini aman."],
  ] as const)("%s %s %i", (lang, status, score, text) => {
    expect(pushText(lang, status, "Mom", score)).toBe(text);
  });

  it("never shows the score", () => {
    for (const lang of ["en", "id"] as const)
      for (const status of ["warning", "blocked"] as const)
        for (const score of [30, 41, 64, 92]) expect(pushText(lang, status, "Mom", score)).not.toMatch(/\d|%/);
  });

  it("level: Waspada below 50, Risiko tinggi from 50, Diblokir whatever the score", () => {
    expect(pushLevel("warning", 49)).toBe("warning1");
    expect(pushLevel("warning", 50)).toBe("warning2");
    expect(pushLevel("blocked", 50)).toBe("blocked");
  });
});

describe("familyPushText (PF-01, QA 2026-11-10 #6)", () => {
  it.each([
    ["en", "disconnected", "Adhella", "Adhella stopped protecting you"],
    ["id", "disconnected", "Adhella", "Adhella berhenti melindungimu"],
    ["en", "memberLeft", "Maria", "Maria deleted their Shoo account. You no longer protect them"],
    ["id", "memberLeft", "Maria", "Maria menghapus akun Shoo-nya. Kamu tidak lagi melindunginya"],
  ] as const)("%s %s", (lang, kind, name, text) => {
    expect(familyPushText(lang, kind, name)).toBe(text);
  });
});
