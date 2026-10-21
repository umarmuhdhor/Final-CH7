# Fase 16 — QA-E2E + fixbug + retest

| Field | Nilai |
|---|---|
| Track | c |
| Branch | `fix/QA-E2E-<ID>-<slug>` per perbaikan |
| Prasyarat | 15 (boleh `[r]`); G6 + D8 (backend `main`); G7 (TestFlight) untuk skenario perangkat fisik |
| Requirement | Semua P0 Alief (PROGRESS), definisi selesai README §7 |
| Model | Sonnet 5.5 (run QA) · Opus 5.5 (fix keamanan) · `ecc:e2e-testing` |
| Fase berikutnya | selesai (17 hanya kalau Umar memberi kabar) |

## Tujuan

Laporan QA End-to-End berformat Catalyst atas sistem nyata (app TestFlight + Worker + Supabase cloud), semua P0/P1 ditutup dan di-retest.

## Bacaan wajib

- `ref/R7` (seluruhnya), `qa/README.md`, `fixbug.md`, PROGRESS tabel P0

## Langkah kerja

1. Persiapan (LANGKAH MANUAL, tulis di log, berhenti sampai Alief selesai): build TestFlight (B6, B8), **set `APNS_ENV=production` dan `APNS_TOPIC=<bundle ID build TestFlight>` di Edge Function `push` (`supabase secrets set …`) dan var Worker sebelum uji; ganti juga `APNS_KEY_P8_B64`/`APNS_KEY_ID` ke kunci **Production** (dan `APNS_TEAM_ID` kalau tim TestFlight beda dengan tim D7) (B7, `--env-file`)** (TestFlight = APNs production, B7), dua iPhone (D6), data cloud bersih (`truncate` tabel uji lewat SQL editor). Sumber build (D-alief-30): app dari ujung branch fase 15 (stack 13–15, walau masih `[r]`), backend dari `main` setelah D8. Catat commit app + commit backend + nomor build di header laporan.
2. Jalankan matriks QA-E2E `ref/R7` §5 (19 skenario, termasuk ON-04 #17, deep link #18, subdomain #19) + skenario keamanan API (IDOR, brute force, scan palsu, token salah) dengan `curl`.
3. Batasan ditulis jujur di header (mis. extension Umar belum final → scan dikirim lewat `curl` meniru extension).
4. Tulis `qa/QA-E2E-<YYYY-MM-DD>.md`, bukti di `qa/img/QA-E2E/`.
5. Isi `fixbug.md`, perbaiki P0 → P1 → P2 (TDD, satu bug satu commit). Bug di luar folder kita → "Diteruskan".
6. Retest, tambahkan blok Retest, perbarui PROGRESS (tabel QA, P0, G8).

## Verifikasi

```bash
source plan/alief/ref/sim.sh
(cd ios && xcodegen)
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM"
(cd backend/db && supabase start && supabase test db) && pnpm -C backend/api test
```

## Kriteria selesai (DoD)

- [ ] Laporan lengkap; P0 = 0 dan P1 = 0 setelah retest.
- [ ] Semua baris P0 di PROGRESS `[x]` dengan bukti.
- [ ] Checkbox mandat tercentang di PR terakhir. G8 terpenuhi setelah PR fix di-merge dan retest LULUS (diperbarui di PROMPT langkah 1).
