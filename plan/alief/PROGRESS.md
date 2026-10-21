# Progress — Shoo · Alief (Team App + Backend)

Legenda status: `[ ]` belum · `[~]` sedang dikerjakan · `[m]` berhenti di LANGKAH MANUAL, belum ada PR (log fase berisi checklist) · `[r]` PR terbuka, menunggu review/merge Umar (catatan "pending C3/B6…" boleh di Ringkasan) · `[x]` PR **sudah di-merge** ke `main` (cek `gh pr view <no> --json state`) · `[!]` terblokir (diset agent saat berhenti karena blocker P0 / PR ditutup; dibuka kembali hanya oleh Alief)

Mode auto: kalau ada fase `[r]` track dengan review/komentar Umar yang lebih baru dari komentar PR "Review handled @<sha>" terakhir → tangani dulu (sekali per review baru); kalau ada fase track berstatus `[~]`/`[m]` → lanjutkan fase itu dulu (`[m]`: berhenti lagi kalau checklist LANGKAH MANUAL belum dicentang Alief); kalau tidak ada → fase pertama berstatus `[ ]` (PROMPT langkah 1, D-alief-26). Fase `[r]` tidak dikerjakan ulang; fase berikutnya ditumpuk di atas branch-nya. Gate yang menyebut `[x]` berarti merged; baris gate diperbarui di langkah 1 saat status disegarkan.
Waktu dalam WITA. Setiap track **hanya mengedit baris fasenya sendiri** (supaya PR paralel tidak bentrok).

| Fase | Judul | Track | Branch | Status | Mulai | Selesai | PR | Ringkasan satu kalimat | Log |
|---|---|---|---|---|---|---|---|---|---|
| 00 | Plan + tooling | – | docs/alief-plan | [~] | 21 Okt 2026 | | | Folder plan/alief dibuat dari hasil grilling; menunggu PR | log/fase-00.md |
| 01 | Fondasi app + target test | app | chore/APP-test-targets, feat/APP-foundation | [ ] | | | | | log/fase-01.md |
| 01S | Spike S1/S2 di iPhone Alief | spike | spike/S1-S2-extension | [ ] | | | | | log/fase-01S.md |
| 02 | Onboarding ON-01..05 | app | feat/ON-01-05-onboarding | [ ] | | | | | log/fase-02.md |
| 03 | Detail DT-01..06 | app | feat/DT-detail | [ ] | | | | | log/fase-03.md |
| 04 | Protected PR-04/05 | app | feat/PR-04-05-shield-activity | [ ] | | | | | log/fase-04.md |
| 05 | Guardian & Family GD-01/02/03/05 | app | feat/GD-family-mode | [ ] | | | | | log/fase-05.md |
| 06 | Profile PF-01 | app | feat/PF-01-profile | [ ] | | | | | log/fase-06.md |
| 06Q | QA-A (UI fixtures) | app | fix/QA-A-* | [ ] | | | | | qa/QA-A-*.md |
| 07 | Fondasi backend + auth + blocklist awal | be | feat/BE-devices | [ ] | | | | | log/fase-07.md |
| 08 | Family | be | feat/BE-family | [ ] | | | | | log/fase-08.md |
| 09 | Scans + screenshot | be | feat/BE-scans | [ ] | | | | | log/fase-09.md |
| 10 | Verdicts + blocklist | be | feat/BE-verdicts | [ ] | | | | | log/fase-10.md |
| 11 | Push APNs | be | feat/BE-push | [ ] | | | | | log/fase-11.md |
| 12 | Retensi + hardening + deploy | be | feat/BE-retention-hardening | [ ] | | | | | log/fase-12.md |
| 13 | ApiRepository + sesi App Group | c | feat/APP-api-repository | [ ] | | | | | log/fase-13.md |
| 14 | Pairing GD-04, PR-01/02/03 | c | feat/GD-04-PR-01-03-pairing | [ ] | | | | | log/fase-14.md |
| 15 | Push tap + validasi GD-06/07 | c | feat/GD-06-07-push-validation | [ ] | | | | | log/fase-15.md |
| 16 | QA-E2E + fixbug + retest | c | fix/QA-* | [ ] | | | | | qa/QA-E2E-*.md |
| 17 | Ditahan: Live Activity push | – | – | [!] | | | | Menunggu keputusan Umar (spike Dynamic Island) | – |

## Gate & milestone

| Titik | Syarat | Status | Catatan |
|---|---|---|---|
| G0 · Izin Umar | Jawaban TODO C3 (kamera + push di project.yml), C11 (`extensionLastSeenAt`), C13 (`owner=family`) | [ ] | C3 dibutuhkan sebelum fase 14/15 (butir 4 `UIBackgroundModes` untuk PiP ON-04 di fase 02, ada fallback); C11/C13 sebelum fase 05/08 (ada default kalau belum dijawab) |
| G1 · Plan disetujui | PR `docs/alief-plan` di-merge | [ ] | Umar approve (CODEOWNERS `*`) |
| G2 · Target test ada | PR `chore/APP-test-targets` di-merge | [ ] | Sampai merge, fase app ditumpuk di atas PR ini |
| G3 · Blocklist publik | `GET /blocklist` hidup di cloud, URL dikirim ke Imelda | [ ] | Akhir fase 07 (LANGKAH MANUAL deploy) |
| G4 · Verdict untuk EX-06 | `GET /verdicts?domain=` hidup di cloud, info ke Umar | [ ] | Akhir fase 10 |
| G5 · Track app selesai | 01–06 + 06Q `[x]` (semua PR merged) | [ ] | Syarat track c |
| G6 · Track be selesai | 07–12 `[x]` (semua PR merged) + TODO D8 (deploy ulang dari `main`, uji asap hijau) | [ ] | Syarat track c |
| G7 · TestFlight | Team ID + capability Push + build internal | [ ] | Syarat QA-E2E (TODO B6–B8); uji push sandbox ke satu iPhone sudah di fase 11 |
| G8 · MVP Alief | Definisi selesai README §7 | [ ] | |

## Status requirement P0 (PRD §8)

| ID | Fase | Status | Bukti (test / screenshot / log) |
|---|---|---|---|
| ON-01 Splash 3 slide + Skip | 02 | [ ] | |
| ON-02 Nama 1–20 + avatar acak | 02 (+13 `POST /devices`) | [ ] | |
| ON-03 Pilih mode permanen | 02 (+13) | [ ] | |
| ON-04 Turn on extension | 02 (+01S hasil spike) | [ ] | |
| Spike S1/S2 (mandat) | 01S | [ ] | |
| ON-05 Izin notifikasi + pengingat | 02 (+15 token APNs) | [ ] | |
| PR-01 Connect QR / kode | 14 | [ ] | |
| PR-02 Protected by | 14 | [ ] | |
| PR-03 Link undangan (P0), deferred (P1) | 14 | [ ] | |
| PR-04 Shield Protected | 04 (+13 data asli) | [ ] | |
| PR-05 Activity Protected | 04 (+13) | [ ] | |
| GD-01 Shield Guardian | 05 | [ ] | |
| GD-02 Toggle Family mode | 05 | [ ] | |
| GD-03 Shield Family | 05 (+13) | [ ] | |
| GD-04 Family code | 14 | [ ] | |
| GD-05 Activity Family | 05 (+13) | [ ] | |
| GD-06 Push ke guardian | 11 + 15 | [ ] | |
| GD-07 Validasi tanpa konfirmasi | 03 (tombol) + 10 + 15 | [ ] | |
| DT-01..06 Detail | 03 (+13) | [ ] | |
| PF-01 Profile | 06 (+13, +14 menu Family code) | [ ] | |
| BE Devices | 07 | [ ] | |
| BE Family | 08 | [ ] | |
| BE Scans | 09 | [ ] | |
| BE Verdicts | 10 | [ ] | |
| BE Blocklist | 07 (awal) + 10 | [ ] | |
| BE Push APNs | 11 | [ ] | |
| BE Retensi 14 hari | 12 | [ ] | |
| BE Keamanan (akses Guardian, batas percobaan kode) | 08, 09, 10, 12 (checkbox mandat dicentang di 12) | [ ] | |
| EN + ID semua teks | 01–06, 13–15 | [ ] | |

## QA

| Ronde | Fase | Tanggal | P0 | P1 | P2 | P3 | Kesimpulan | Laporan |
|---|---|---|---|---|---|---|---|---|
| QA-A | 06Q | | | | | | | |
| QA-E2E | 16 | | | | | | | |
