# Log fase 13 — ApiRepository + sesi App Group (Alief, track c)

- **Status:** [~] — branch `feat/APP-api-repository` dari `origin/main` `b91f2a1` (semua PR #1–#28 MERGED, G5 + G6 [x]).
- **Model:** Claude Opus 5.5, mode auto. Mulai 22 Okt 2026 10:20 WITA.
- **Rencana:** `log/fase-13-plan.md` (ditulis langsung oleh agent dari "Langkah kerja" file fase; tidak memakai agent planner terpisah karena aturan Alief: subagent satu per satu, dan review keamanan wajib lebih penting di slot itu).

## Ringkasan rencana

1. `APIClient` (URLSession ephemeral tanpa cache/cookie, Bearer, error kontrak, 401 → sesi rusak).
2. `KeychainItem` + `SessionStore` (token `AfterFirstUnlockThisDeviceOnly`, key kontrak App Group).
3. `ApiRepository` untuk semua operasi `ShooRepository` + efek sesi.
4. `AppEnvironment`: pemilihan repository, registrasi → sesi → mode → bahasa, sinkron foreground, sesi kedaluwarsa.
5. Layar "Session expired".
6. Screenshot: link baru sekali sebelum "tidak tersedia".
7. `AppConfig` Release = Worker cloud; `ai.baseURL` placeholder.
8. UI test lama + `-UITestMock YES`; uji manual melawan `wrangler dev`; gerbang UI; review; PR.

## Checklist langkah (file fase "Langkah kerja")

- [x] 1. `APIClient` + test stub untuk setiap endpoint (`Tests/APIClientTests.swift`, `Tests/ApiRepositoryTests.swift`).
- [x] 2. `ApiRepository` memenuhi protocol; `MockRepository` tetap untuk preview + UI test (`-UITestMock YES`, D-alief-C01).
- [x] 3. Onboarding → `registerDevice` asli → `SessionStore.save` → App Group; bahasa ID → `PATCH language=id` (D-alief-C06).
- [x] 4. 401 → layar "Session expired" + mulai ulang onboarding (D-alief-C03).
- [ ] 5. Uji manual melawan `wrangler dev` lokal dari simulator.
- [ ] 6. `ecc:security-reviewer` fokus T3.
- [x] 7. `updateMe(extensionLastSeenAt:)` saat `scenePhase == .active`; `me()` mengisi ulang `SessionStore` (D-alief-C06).
