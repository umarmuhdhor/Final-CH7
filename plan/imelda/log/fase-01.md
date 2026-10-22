# Log fase 01 — Layer 1 sisi detector: `db_match` (M5-B)

**Status:** `[~]` kode selesai dan ter-commit di `feat/AI-M5-detector`. Belum push, belum PR (menunggu izin Imelda, D-imelda-03).
**Tanggal:** 22 Okt 2026 · **Commit:** `598656a` (fitur), `b23cf61` (validasi + test tambahan)

## Rencana singkat
1. Test dulu (a–h dari prompt) di `detector/test/detector.test.mjs`, lihat gagal.
2. `analyzeLocal`: ambil hostname lewat `hostOf` (aman untuk URL rusak), lewati host kosong/IP, `await globalThis.ShooLists?.match(host)` di dalam try/catch.
3. Hit valid → satu sinyal `db_match` (layer 1, weight 100, `evidence` = `hit.source`) dan berhenti. `null`, helper tidak ada, atau error → lanjut layer 2.
4. `signal()` diberi parameter `layer` (sebelumnya selalu 2). Teks EN + ID.
5. Sync ke extension, commit `src/` dan `detector.js` bersamaan.

## File diubah
- `detector/src/detector.js` (`matchLists`, `T.dbMatch`, parameter `layer`)
- `detector/test/detector.test.mjs` (12 test layer 1 baru; `ctx` vm diekspos supaya `ShooLists` bisa di-mock)
- `ios/ShooExtension/Resources/detector.js` (hasil sync)
- `plan/imelda/**` disalin dari `docs/imelda-plan` (belum ada di `main`; PR #29 masih terbuka), `docs/mandates/imelda.md` (centang M5-B)

## Hasil verifikasi
- `node --test detector/test ai/eval/test ios/ShooExtension/Tests` → tests 141, pass 141, fail 0 (baseline 129).
- `grep -nE "fetch|XMLHttpRequest|WebSocket|sendBeacon" detector/src/detector.js` → kosong (exit 1).
- Waktu `analyzeLocal` dengan mock `ShooLists`: 10.000 panggilan, rata-rata 0,113 ms, terburuk 0,753 ms (target < 50 ms).

## DoD
- [x] `db_match` muncul untuk domain yang di-mock cocok (test "Shoo list hit", "public list hit")
- [x] `ShooLists` tidak ada / `match` error → tetap jalan (test "missing", "throws or rejects")
- [x] Tanpa request jaringan di detector (grep kosong)
- [x] `label` dan `labelSimple` EN + ID, `labelSimple` tanpa istilah teknis (test bilingual)
- [x] Baseline hijau: 129 → 141 lolos

## Temuan review (`ecc:code-reviewer`)
CRITICAL 0 · HIGH 0 · MEDIUM 2 · LOW 3. Verdict: approve.
- MEDIUM 1: `match` yang tidak pernah selesai membuat `analyzeLocal` menggantung → **belum diperbaiki**, lihat Deviasi/usulan.
- MEDIUM 2 (celah test: domain resmi + hit, bentuk `hit` buruk, argumen ekstra) → ditutup di `b23cf61`.
- LOW 3 (hit truthy apa pun dianggap cocok) → diperbaiki: hanya `source` `shoo`/`public`.
- LOW 4 (guard IP duplikat), LOW 5 (`!DATA` memblokir layer 1) → dibiarkan; kecil, di luar scope.

## Deviasi / keputusan
- Hostname diambil lewat `hostOf` (jatuh ke `snapshot.domain` kalau URL rusak), bukan `new URL(snapshot.url)` mentah, agar tidak melempar.
- Host IP/IPv6 tidak dikirim ke `match` (daftar berisi domain).
- Hit pada domain resmi tetap `db_match` (sesuai kontrak "hit → 100"); server fase 05 yang wajib membuang domain resmi dari daftar (A7).
- **Usulan, menunggu Imelda:** timeout sekitar 500 ms–1 s di sekitar `match` supaya layer 2 selalu jalan. Perlu cek apakah `pipeline.js` (Umar) sudah punya timeout sendiri.

## Catatan handoff
- Fase 05 membuat daftar yang dikonsumsi `ShooLists`; fase ini hanya memakai helper-nya.
