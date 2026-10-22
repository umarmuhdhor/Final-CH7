# Log fase 16 — QA-E2E + fixbug + retest

- **Status:** [m] — berhenti di langkah 1 (persiapan: TestFlight, kunci APNs Production, dua iPhone). Branch `fix/QA-E2E-00-setup` (log saja), dari ujung `feat/GD-06-07-push-validation` (fase 15, PR #54).
- **Model:** Claude Opus 5.5, mode auto. 22 Okt 2026.
- **Prasyarat:** 15 `[r]` (#54) ✓ · G6 + D8 ✓ (Worker `8f3df4ed` dari `main`) · G7 TestFlight ✗ (B6, B7, B8, D6 belum).

## Checklist langkah (file fase "Langkah kerja")

- [ ] 1. Persiapan → LANGKAH MANUAL di bawah.
- [ ] 2. Matriks QA-E2E `ref/R7` §5 (19 skenario) + skenario keamanan API (curl).
- [ ] 3. Batasan di header laporan.
- [ ] 4. `qa/QA-E2E-<YYYY-MM-DD>.md` + bukti `qa/img/QA-E2E/`.
- [ ] 5. `fixbug.md`, perbaikan P0 → P1 → P2.
- [ ] 6. Retest, PROGRESS (tabel QA, P0, G8).

## Koreksi file fase

File fase menyebut Edge Function `push` + `supabase secrets set`. Sejak D-alief-B01 push dikirim langsung dari **Worker** (`ApnsSender`), jadi semua nilai APNs diset di Worker (`wrangler secret put` + var `wrangler.jsonc`), bukan di Supabase.

## LANGKAH MANUAL

Tim Apple berbayar = **"umar muhdhor"** (koordinator, 22 Okt). Umar: B7 (kunci APNs) + B8 (App Store Connect/TestFlight). Alief: B6, D6 (+ D7 kalau sempat dulu, log fase 15).

- [ ] 1. **Umar (B7, Production):** buat kunci APNs `.p8` **Production** di tim "umar muhdhor" (developer.apple.com → Keys → Apple Push Notifications service; kunci lama yang berlaku untuk Sandbox + Production juga boleh). Bagikan ke Alief lewat password manager (bukan chat): file `.p8`, Key ID, Team ID, bundle ID + App Group yang terdaftar di tim itu. Draf pesan: TODO C23 (Alief yang mengirim).
- [ ] 2. **Umar (B8):** App Store Connect → My Apps → record untuk bundle ID itu; TestFlight → grup tester **internal**, tambahkan Apple ID Alief (dan pemegang iPhone kedua).
- [ ] 3. **Alief (B6):** `cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig`, isi `DEVELOPMENT_TEAM` = Team ID "umar muhdhor", `SHOO_BUNDLE_ID`, `SHOO_APP_GROUP` = nilai dari butir 1; lalu `(cd ios && xcodegen)`. File ini gitignored, jangan di-commit.
- [ ] 4. **Alief — Worker cloud ke APNs Production** (nilai ditempel di prompt, tidak pernah sebagai argumen):
  ```bash
  cd backend/api
  base64 < ~/Downloads/AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | npx wrangler secret put APNS_KEY_P8_B64
  npx wrangler secret put APNS_KEY_ID
  npx wrangler secret put APNS_TEAM_ID
  ```
  Di `backend/api/wrangler.jsonc`: `"APNS_TOPIC": "<bundle ID butir 1>"`, `"APNS_ENV": "production"`. Deploy dari `main` + perubahan var itu (`npx wrangler deploy`), catat Version ID. Hapus `.p8` dari Downloads setelah tersimpan di password manager. Perubahan var bisa dijadikan PR backend kecil oleh agent kalau diminta.
- [ ] 5. **Build TestFlight** (Umar, atau Alief kalau sudah ditambahkan ke tim dengan peran App Manager): checkout `feat/GD-06-07-push-validation` (ujung stack 13–15, D-alief-30), `(cd ios && xcodegen)`, Xcode → Product → Archive (skema Shoo, Release) → Distribute App → TestFlight & App Store → Upload. Setelah processing: tambahkan build ke grup internal. Catat **commit app** (`git rev-parse HEAD`) + **nomor build**.
- [ ] 6. **Alief (D6):** dua iPhone (Guardian + Protected) instal build itu dari app TestFlight. iPhone Protected: aktifkan extension Shoo di Settings → Safari → Extensions (build extension Umar dari commit yang sama).
- [ ] 7. **Alief — data cloud bersih** (tidak bisa dibatalkan; menghapus semua device, keluarga, scan, verdict dan log push di cloud; daftar blokir publik tetap). Supabase Dashboard → SQL Editor:
  ```sql
  truncate devices, family_codes, family_links, join_attempts, push_log, rate_limit_hits, scans, verdicts cascade;
  ```
  Screenshot lama di Storage terhapus oleh retensi 14 hari (fase 12); atau hapus isi bucket screenshot lewat Dashboard → Storage.
- [ ] 8. Tempel di sini: commit app, nomor build TestFlight, Version ID Worker, model + versi iOS kedua iPhone.
- [ ] 9. Ketik lagi: `Saya Alief, track c. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).` Agent lalu menjalankan langkah 2–6 (Alief memegang dua iPhone untuk skenario yang butuh tap fisik; agent memandu dan menjalankan bagian curl/API).

## Yang sudah siap untuk QA-E2E (dari fase 13–15, simulator)

- App ↔ API asli (`ApiRepository`), pairing kode/QR/link (dua simulator), push tap → Detail di tiga kondisi, verdict `safe` terbaca Protected ≤ 551 ms (backend lokal). Script: `qa/push-e2e.sh` (lokal saja).
- Belum terbukti: token APNs asli dari app (simulator tidak menerima token), push APNs nyata, layar blokir extension terbuka setelah It's safe (EX-06, extension Umar).
