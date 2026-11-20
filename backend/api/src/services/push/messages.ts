import type { Language } from "../../env";

/**
 * The push level, the same words as the in-page popup (contracts/README.md thresholds): Waspada below
 * 50, Risiko tinggi from 50, Diblokir for a blocked scan. Usability test 20 Nov 2026: no percentage,
 * it meant nothing to the tester (plan/alief/proposal/push-copy.md, option A).
 */
export type PushLevel = "warning1" | "warning2" | "blocked";

/** Second popup tier (contracts/README.md): the backend only knows warnAt/blockAt, so it uses the default 50. */
export const SECOND_WARNING = 50;

export const pushLevel = (status: "blocked" | "warning", score: number): PushLevel =>
  status === "blocked" ? "blocked" : score >= SECOND_WARNING ? "warning2" : "warning1";

// Push text in the guardian's language (contracts/api.md "Push payloads", R3 §6): level word first,
// what happened, one action. Never the URL or domain (SECURITY T9/P10).
const TEXT: Record<Language, Record<PushLevel, (name: string) => string>> = {
  en: {
    warning1: (n) => `Be careful: ${n} opened a suspicious site. Remind ${n} not to enter personal details. Tap to see why.`,
    warning2: (n) => `High risk: ${n} opened a site that may be a scam. Call ${n} and ask them not to enter a PIN or OTP. Tap for details.`,
    blocked: (n) => `Blocked: Shoo closed a dangerous site ${n} opened. ${n} is safe. Tap to check it and decide if it's safe.`,
  },
  id: {
    warning1: (n) => `Waspada: ${n} membuka situs mencurigakan. Ingatkan ${n} jangan isi data pribadi. Ketuk untuk lihat alasannya.`,
    warning2: (n) => `Risiko tinggi: ${n} membuka situs yang mungkin penipuan. Telepon ${n}, minta jangan isi PIN atau OTP. Ketuk untuk detail.`,
    blocked: (n) => `Diblokir: Shoo menutup situs berbahaya yang dibuka ${n}. ${n} aman. Ketuk untuk cek dan putuskan apakah situs ini aman.`,
  },
};

// Family pushes, in the receiver's own language (PF-01, proposed contract addition). `remind` and
// `disconnected` go to the protected device and name the guardian; `memberLeft` goes to the guardian when a
// member deleted their account (QA 2026-11-10 #6) and names that member.
type FamilyKind = "remind" | "disconnected" | "memberLeft";
const FAMILY: Record<Language, Record<FamilyKind, (name: string) => string>> = {
  en: {
    remind: (g) => `${g} reminds you: turn on Shoo in Safari`,
    disconnected: (g) => `${g} stopped protecting you`,
    memberLeft: (m) => `${m} deleted their Shoo account. You no longer protect them`,
  },
  id: {
    remind: (g) => `${g} mengingatkan: nyalakan Shoo di Safari`,
    disconnected: (g) => `${g} berhenti melindungimu`,
    memberLeft: (m) => `${m} menghapus akun Shoo-nya. Kamu tidak lagi melindunginya`,
  },
};

export const familyPushText = (language: Language, kind: FamilyKind, name: string) => FAMILY[language][kind](name);

export const pushText = (language: Language, status: "blocked" | "warning", ownerName: string, score: number) =>
  TEXT[language][pushLevel(status, score)](ownerName);

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
