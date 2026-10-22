# Rencana fase 06 — Profile: PF-01

> Ditulis agent track app (22 Okt 2026). Branch `feat/PF-01-profile`, stacked on #21 (fase 05) + merge fase 02 (#16) di awal fase (D-alief-A18).

| # | Langkah | Test dulu |
|---|---|---|
| 1 | `ProfileModel`: `me()` (+ `familyMembers()` untuk Guardian), ganti nama (NameRule ON-02 → `updateMe(name:)`), bahasa (`AppSettings.language` langsung + `updateMe(language:)`), Disconnect Protected (`leaveGuardian()` → onboarding lanjut di Connect), Delete my data di belakang `AppConfig.dataDeletionEnabled` (`deleteMe()`, usulan C19) | `ProfileModelTests` |
| 2 | `ProfileView` (sheet dari ikon kanan atas): avatar + nama (edit), bahasa, status extension Active/Off + Turn on (sheet ON-04), Protected: guardian + Disconnect (dialog konfirmasi standar), Guardian: Family code (placeholder fase 14) + terhubung x/3 | `ProfileUITests`: ganti bahasa EN↔ID langsung berlaku, Disconnect → Connect, Family code hanya Guardian |
| 3 | Langkah 7 (refine ON-04): **dilewati** — `origin/main` belum punya `docs/spikes/open-extension-settings.md` dengan `## Recommendation for ON-04` (dicek 22 Okt 2026) | – |
| 4 | Gerbang UI `qa/img/ui-06/` (Guardian, Protected, edit nama, Disconnect, EN/ID, light/dark, AX-XL), review, log, PR | – |
