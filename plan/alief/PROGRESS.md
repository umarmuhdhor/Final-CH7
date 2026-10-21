# Progress — Shoo · Alief (Team App + Backend)

Legenda status: `[ ]` belum · `[~]` sedang dikerjakan · `[m]` berhenti di LANGKAH MANUAL, belum ada PR (log fase berisi checklist) · `[r]` PR terbuka, menunggu review/merge Umar (catatan "pending C3/B6…" boleh di Ringkasan) · `[x]` PR **sudah di-merge** ke `main` (cek `gh pr view <no> --json state`) · `[!]` terblokir (diset agent saat berhenti karena blocker P0 / PR ditutup; dibuka kembali hanya oleh Alief)

Mode auto: kalau ada fase `[r]` track dengan review/komentar Umar yang lebih baru dari komentar PR "Review handled @<sha>" terakhir → tangani dulu (sekali per review baru); kalau ada fase track berstatus `[~]`/`[m]` → lanjutkan fase itu dulu (`[m]`: berhenti lagi kalau checklist LANGKAH MANUAL belum dicentang Alief); kalau tidak ada → fase pertama berstatus `[ ]` (PROMPT langkah 1, D-alief-26). Fase `[r]` tidak dikerjakan ulang; fase berikutnya ditumpuk di atas branch-nya. Gate yang menyebut `[x]` berarti merged; baris gate diperbarui di langkah 1 saat status disegarkan.
Waktu dalam WITA. Setiap track **hanya mengedit baris fasenya sendiri** (supaya PR paralel tidak bentrok).

| Fase | Judul | Track | Branch | Status | Mulai | Selesai | PR | Ringkasan satu kalimat | Log |
|---|---|---|---|---|---|---|---|---|---|
| 00 | Plan + tooling | – | docs/alief-plan | [x] | 21 Okt 2026 | 21 Okt 2026 | #2 | Plan merged; disinkronkan dengan kontrak PR #1/#3/#4/#6 | log/fase-00.md |
| 01 | Fondasi app + target test | app | chore/APP-test-targets, feat/APP-foundation | [x] | 21 Okt 2026 | 22 Okt 2026 | #8, #14 (merged) | Tab Shield/Activity, ShooRepository + MockRepository, EN/ID, komponen, privacy manifest; 53 unit + 3 UI test hijau | log/fase-01.md |
| 01S | Spike S1/S2 di iPhone Alief | spike | spike/S1-S2-extension | [ ] | | | | | log/fase-01S.md |
| 02 | Onboarding ON-01..05 | app | feat/ON-01-05-onboarding | [x] | 22 Okt 2026 | 22 Okt 2026 | #16 (merged) | ON-01..05 di Mock: splash, nama, mode permanen + avatar, ON-04 + video PiP, ON-05 + banner; 78 unit + 10 UI test hijau; pending C3/C15, ON-04 di iPhone | log/fase-02.md |
| 03 | Detail DT-01..06 | app | feat/DT-detail | [r] | 22 Okt 2026 | 22 Okt 2026 | #18 | Detail semua mode: ring, label, link salin-saja, 3 bukti (labelSimple untuk Protected), screenshot tanpa cache + zoom, verdict optimistic + rollback, catatan "by"; 116 unit + 16 UI test hijau (di atas main setelah #14/#16) | log/fase-03.md |
| 04 | Protected PR-04/05 | app | feat/PR-04-05-shield-activity | [x] | 22 Okt 2026 | 22 Okt 2026 | #19 (merged) | Shield Active/Off + guardian + kartu blokir, Activity filter/paging/refresh; 140 unit + 20 UI lulus di atas main (#14/#16/#18). Sheet panduan "Turn on" menyusul di #21 (D-alief-A23) | log/fase-04.md |
| 05 | Guardian & Family GD-01/02/03/05 | app | feat/GD-family-mode | [x] | 22 Okt 2026 | 22 Okt 2026 | #21 (merged) | Shield Guardian sendiri, Family mode On/Off diingat, kartu keluarga (maks 3, Not connected), Family Activity filter orang; resolusi A18 fase 04 (sheet "Turn on", satu sumber status extension, D-alief-A23); di atas main: 152 unit + 25 UI lulus | log/fase-05.md |
| 06 | Profile PF-01 | app | feat/PF-01-profile | [r] | 22 Okt 2026 | 22 Okt 2026 | #22 | Profile kedua mode: nama, bahasa langsung, status extension, Disconnect → Connect, keluarga x/3, Delete my data selalu tampil (D-alief-A40); di atas main: 165 unit + 30 UI lulus | log/fase-06.md |
| 06Q | QA-A (UI fixtures) | app | fix/QA-A-report, fix/QA-A-P2-layout | [~] | 22 Okt 2026 | | | QA-A: P0 0 · P1 0 · P2 7 (6 diperbaiki + retest lulus, P2-6 ke QA-E2E) · P3 2; 167 unit + 32 UI lulus | qa/QA-A-2026-10-22.md |
| 07 | Fondasi backend + auth + blocklist awal | be | feat/BE-devices | [r] | 21 Okt 2026 | 21 Okt 2026 | #9 | Worker + skema hidup di cloud, spike APNs lulus (D-alief-B01), review diperbaiki (pgTAP 61, vitest 48); di-rebase ke main setelah #7 merge; pending C7/B9 | log/fase-07.md |
| 08 | Family | be | feat/BE-family | [r] | 21 Okt 2026 | 21 Okt 2026 | #11 | Family code/join/members/disconnect, `/join`, `GET`+`DELETE /devices/me`; cloud deploy + smoke hijau (Worker a9807b02); pgTAP 67, vitest 100; stacked on #9; usulan C19 + `code_unavailable` di PR; pending C7/B9 | log/fase-08.md |
| 09 | Scans + screenshot | be | feat/BE-scans | [r] | 21 Okt 2026 | 21 Okt 2026 | #13 | `POST/GET /scans`, `GET /scans/{id}`, screenshot privat hanya lewat Worker `/screenshots/{id}` (link HMAC 1 jam, cek akses DB tiap request, D-alief-B08); default `private, no-store` + log tanpa id (D-alief-B09, P13); 4 review + cek P1–P13; pgTAP 71, vitest 184; cloud Worker c6ba8556, smoke (c) hijau (after delete/disconnect 404); stacked on #11; catatan kontrak C20 di PR | log/fase-09.md |
| 10 | Verdicts + blocklist | be | feat/BE-verdicts | [r] | 21 Okt 2026 | 22 Okt 2026 | #15 | `POST/GET /verdicts`, antrean blocklist dari verdict layak (snapshot, allowlist, sufiks publik, maks 10/24 jam per Guardian), review manual tetap; verdict Guardian lama terhapus saat putus hubungan (P13, D-alief-B10); 3 review + cek P1–P13; pgTAP 77, vitest 242; cloud Worker 781cf277, smoke hijau (verdict di GET pertama, antrean → disetujui → `/blocklist` → dihapus); deviasi p95 (1547 ms dari ID) → fase 12 (D-alief-B10 g); stacked on #13; C8 dikirim Alief | log/fase-10.md |
| 11 | Push APNs | be | feat/BE-push | [r] | 22 Okt 2026 | 22 Okt 2026 | #17 | `ApnsSender` langsung dari Worker (D-alief-B01/B11): JWT ES256 di-cache, 410 → token dikosongkan, maks 10 push / 10 menit per Guardian, `push_log` tanpa teks (privasi), route spike dihapus; 3 review + cek P1–P13; pgTAP 92, vitest 274; cloud Worker ac2025ec, `push_log` `logged` lewat waitUntil; stacked on #15; pending B6/B7/C3 (kunci APNs + D7 di fase 15 / G7) | log/fase-11.md |
| 12 | Retensi + hardening + deploy | be | feat/BE-retention-hardening | [r] | 22 Okt 2026 | 22 Okt 2026 | #20 | Cron retensi 14 hari (objek dulu, scan tanpa screenshot chunk besar), hardening (timeout role, header, 413 awal, batas 401/IP, HMAC `RATE_KEY_SECRET` wajib, Worker tidak bisa menyetujui blocklist), `service_role` dicabut, tombstone Storage (P13), batas global, `GET /privacy`; 3 review + cek P1–P13; pgTAP 113, vitest 310; cloud Worker `bdc661e8` (cron `0 19 * * *`), smoke hijau, `/verdicts` p95 317 ms (deviasi kecil diterima, D-alief-B12 k); stacked on #17; run cron pertama terbukti 22 Okt 03:00 WITA (ops_heartbeat, tombstone 0); screenshot Triggers + log retensi (`failed: 0`) tercatat; pending toggle Data API (opsional, Alief) | log/fase-12.md |
| 13 | ApiRepository + sesi App Group | c | feat/APP-api-repository | [ ] | | | | | log/fase-13.md |
| 14 | Pairing GD-04, PR-01/02/03 | c | feat/GD-04-PR-01-03-pairing | [ ] | | | | | log/fase-14.md |
| 15 | Push tap + validasi GD-06/07 | c | feat/GD-06-07-push-validation | [ ] | | | | | log/fase-15.md |
| 16 | QA-E2E + fixbug + retest | c | fix/QA-* | [ ] | | | | | qa/QA-E2E-*.md |
| 17 | Ditahan: Live Activity push | – | – | [!] | | | | Menunggu keputusan Umar (spike Dynamic Island) | – |

## Gate & milestone

| Titik | Syarat | Status | Catatan |
|---|---|---|---|
| G0 · Izin Umar | Jawaban TODO C3 (kamera + push di project.yml), C11 (`extensionLastSeenAt`), C13 (`owner=family`) — C11/C13 (+ C4–C6, C9, C10, C12) diterima lewat kontrak PR #1/#3/#4 (21 Okt); tinggal C3 | [ ] | C3 dibutuhkan sebelum fase 14/15 (butir 4 `UIBackgroundModes` untuk PiP ON-04 di fase 02, ada fallback); C11/C13 sebelum fase 05/08 (ada default kalau belum dijawab) |
| G1 · Plan disetujui | PR `docs/alief-plan` di-merge | [x] | Umar approve (CODEOWNERS `*`) |
| G2 · Target test ada | PR `chore/APP-test-targets` di-merge | [ ] | Sampai merge, fase app ditumpuk di atas PR ini |
| G3 · Blocklist publik | `GET /blocklist` hidup di cloud, URL dikirim ke Imelda | [ ] | Akhir fase 07 (LANGKAH MANUAL deploy) |
| G4 · Verdict untuk EX-06 | `GET /verdicts?domain=` hidup di cloud, info ke Umar | [ ] | Hidup di cloud sejak 22 Okt (Worker 781cf277); tinggal Alief mengirim C8 ke Umar |
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
| BE Devices | 07 | [r] | `backend/api/test/devices.test.ts`, PR #9 |
| BE Family | 08 | [r] | `backend/api/test/family.test.ts`, `join-page.test.ts`, `devices-me.test.ts`; PR #11 |
| BE Scans | 09 | [r] | `backend/api/test/scans.test.ts`, `screenshots.test.ts`, `cache-headers.test.ts`, `images.test.ts`, `push-notify.test.ts`; PR #13 |
| BE Verdicts | 10 | [r] | `backend/api/test/verdicts.test.ts`, `allowlist.test.ts`; cloud smoke 22 Okt; PR #15 |
| BE Blocklist | 07 (awal) + 10 | [r] | `blocklist.test.ts` (07), antrean dari verdict di `verdicts.test.ts` (10); cloud smoke 22 Okt; PR #9 + #15 |
| BE Push APNs | 11 | [r] | `backend/api/test/push-apns.test.ts`, `push-deliver.test.ts`, `push-notify.test.ts`; cloud `logged` 22 Okt; PR #17; pending B6/B7/C3 (D7) |
| BE Retensi 14 hari | 12 | [r] | `backend/api/test/retention.test.ts`, `security-review.test.ts`; cron cloud `bdc661e8`; PR #20 |
| BE Keamanan (akses Guardian, batas percobaan kode) | 08, 09, 10, 12 (checkbox mandat dicentang di 12) | [r] | `family.test.ts`, `scans.test.ts`, `security-headers.test.ts`, `security-review.test.ts`, pgTAP `grants`/`hardening`/`security_review`; PR #9–#20 |
| EN + ID semua teks | 01–06, 13–15 | [ ] | |

## QA

| Ronde | Fase | Tanggal | P0 | P1 | P2 | P3 | Kesimpulan | Laporan |
|---|---|---|---|---|---|---|---|---|
| QA-A | 06Q | 22 Okt 2026 | 0 | 0 | 7 (6 ditutup) | 2 | Siap | qa/QA-A-2026-10-22.md |
| QA-E2E | 16 | | | | | | | |
