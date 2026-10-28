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
