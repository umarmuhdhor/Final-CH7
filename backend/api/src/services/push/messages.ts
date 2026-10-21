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

export const pushText = (language: Language, status: "blocked" | "warning", ownerName: string, score: number) =>
  TEXT[language][status](ownerName, score);
