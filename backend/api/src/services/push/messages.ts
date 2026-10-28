import type { Language } from "../../env";

// Push text in the guardian's language (contracts/api.md "Push payloads", R3 §6).
const TEXT: Record<Language, Record<"blocked" | "warning", (name: string, score: number) => string>> = {
  en: {
    blocked: (n, s) => `${n} hit a blocked site · ${s}%`,
    warning: (n, s) => `${n} opened a suspicious site · ${s}%`,
  },
  id: {
    blocked: (n, s) => `${n} membuka situs yang diblokir · ${s}%`,
    warning: (n, s) => `${n} membuka situs mencurigakan · ${s}%`,
  },
};

// Family pushes to the protected device, in its own language (PF-01, proposed contract addition).
const FAMILY: Record<Language, Record<"remind" | "disconnected", (guardian: string) => string>> = {
  en: {
    remind: (g) => `${g} reminds you: turn on Shoo in Safari`,
    disconnected: (g) => `${g} stopped protecting you`,
  },
  id: {
    remind: (g) => `${g} mengingatkan: nyalakan Shoo di Safari`,
    disconnected: (g) => `${g} berhenti melindungimu`,
  },
};

export const familyPushText = (language: Language, kind: "remind" | "disconnected", guardianName: string) =>
  FAMILY[language][kind](guardianName);

export const pushText = (language: Language, status: "blocked" | "warning", ownerName: string, score: number) =>
  TEXT[language][status](ownerName, score);

// PF-01 settings pushes (proposed contract addition), in the receiving device's language.
// Own scans carry no domain: the lock screen may be seen by others.
const OWN: Record<Language, Record<"blocked" | "warning", (score: number) => string>> = {
  en: {
    blocked: (s) => `Shoo blocked a dangerous site · ${s}%`,
    warning: (s) => `Shoo warned you about a risky site · ${s}%`,
  },
  id: {
    blocked: (s) => `Shoo memblokir situs berbahaya · ${s}%`,
    warning: (s) => `Shoo memperingatkanmu soal situs berisiko · ${s}%`,
  },
};

export const ownPushText = (language: Language, status: "blocked" | "warning", score: number) =>
  OWN[language][status](score);

const PROTECTION_OFF: Record<Language, (member: string) => string> = {
  en: (m) => `${m}'s protection is off: Shoo has not run in Safari for a day`,
  id: (m) => `Perlindungan ${m} mati: Shoo tidak berjalan di Safari sejak sehari`,
};

export const protectionOffText = (language: Language, memberName: string) => PROTECTION_OFF[language](memberName);

/** Weekly summary: the last 7 days of the device and, for a guardian, its members. */
export function summaryText(language: Language, s: { blocked: number; warnings: number; family: boolean }): string {
  if (language === "id") {
    const who = s.family ? "kamu dan keluargamu" : "kamu";
    return s.blocked + s.warnings === 0
      ? `Ringkasan minggu ini: tidak ada situs berbahaya untuk ${who}.`
      : `Ringkasan minggu ini untuk ${who}: ${s.blocked} situs diblokir, ${s.warnings} peringatan.`;
  }
  const who = s.family ? "you and your family" : "you";
  const sites = (n: number) => `${n} ${n === 1 ? "site" : "sites"}`;
  const warnings = (n: number) => `${n} ${n === 1 ? "warning" : "warnings"}`;
  return s.blocked + s.warnings === 0
    ? `Your week: no dangerous sites for ${who}.`
    : `Your week for ${who}: ${sites(s.blocked)} blocked, ${warnings(s.warnings)}.`;
}
