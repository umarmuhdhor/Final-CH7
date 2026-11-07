# Log fase 20 — Pensiun screenshot (EX-07)

- **Status:** [x] 20a **kode selesai, review pending** (8 Nov 2026, G2 lulus) · pertanyaan K7 belum diajukan (wajib sebelum merge 20a) · 20b/20c belum · 20d milik track app.
- **Model:** Claude Opus 5.5, sesi track be. 1 Nov 2026.
- **Rencana:** `fase-20-screenshot-sunset.md` (PR #207).
- **Keputusan:** brief koordinator: 20a hanya kalau G2 dicentang; kalau tidak, tulis LANGKAH MANUAL dan lewati. Tidak ada kode di PR ini.

## Cek gerbang (1 Nov 2026)

- `log/fase-20.md` belum ada di `origin/main` maupun `docs/alief-plan-19-26` → LANGKAH MANUAL 1 (G2) belum dicentang.
- G2 butuh SQL produksi (read-only) dan pengecekan HP demo: aksi cloud/device, tidak dijalankan sesi ini.

## LANGKAH MANUAL

- [x] **1. G2 — sebelum 20a (Alief): semua device demo di build ≥ #201.** Lulus 8 Nov 2026: `devices_on_old_build` = 0 (cloud, read-only).
  - Checklist per HP demo (Alief, Umar, tester lain): app + extension dipasang ulang dari `main` ≥ 2720b13 (Xcode) atau build TestFlight dari commit itu. Versi di Profile selalu `0.1.0 (1)`, jadi catat tanggal pasang, bukan versi.
  - SQL read-only di Supabase SQL editor (harus 0):
    ```sql
    -- Devices whose latest scan in the last 7 days still carried a screenshot (old build).
    select count(*) as devices_on_old_build from (
      select distinct on (owner_id) owner_id, screenshot_path
      from scans where created_at > now() - interval '7 days'
      order by owner_id, created_at desc) last
    where screenshot_path is not null;
    ```
  - Kalau > 0: lihat nama device di SQL editor (jangan disalin ke log/chat), minta pemiliknya update, ulangi.
  - Catat di sini: tanggal, angka (0), tanpa id/nama.
- [ ] **2. Pertanyaan K7 ke Umar** (R8 §b #1, wajib sebelum merge 20a): diajukan di PR ini (`## Questions for Umar`, D-alief-C29), bukan issue.
- [ ] **3. Setelah 1 + 2:** sesi berikut menjalankan 20a (`fix/EX-07-ignore-screenshot-upload`) sesuai Langkah kerja 20a di file fase (TDD, review security → TypeScript, merge di menit :10–:40, tidak di 18:30–19:30 UTC; jam deploy CI = awal jam G1).

## Catatan handoff

- 20a tidak menunggu jawaban K7 untuk mulai coding (field opsional + deprecated), tetapi pertanyaan harus sudah diajukan sebelum merge.

## 20a — `fix/EX-07-ignore-screenshot-upload` (8 Nov 2026)

- **Gerbang:** G2 lulus 8 Nov 2026, SQL `devices_on_old_build` = 0 di cloud (read-only, dijalankan Alief). Pertanyaan K7 (LANGKAH MANUAL 2) belum diajukan: wajib sebelum merge.
- **Model:** Claude Opus 5.5. Review (`ecc:security-reviewer` → `ecc:typescript-reviewer`) dilakukan Alief, belum.

### Checklist

- [x] Test dulu (merah), lalu kode (hijau).
- [x] `routes/scans.ts`: `screenshotBase64: z.unknown().optional()` (nilai apa pun diterima, tanpa `.max()`, tanpa 422); nilai truthy → `console.log(JSON.stringify({ event: "screenshot_ignored" }))` tanpa id, domain, atau isi (P6); panggilan `attachScreenshot` dihapus dari POST /scans. Respons tidak berubah; `GET /scans/{id}` tetap mengirim `screenshotUrl` untuk scan lama yang punya screenshot.
- [x] `services/scans.ts` (`attachScreenshot`) tetap ada; dihapus di 20b.
- [x] `backend/API.md`: `screenshotBase64` "ignored since fase 20a (7 Nov 2026)" di tabel body, Screenshot rules, dan dua catatan Deprecated; rujukan "fase 18c" → "fase 20b".
- [x] Test lama yang membuat screenshot lewat POST /scans sekarang men-seed lewat `attachScreenshot` (helper `test/helpers/screenshots.ts` `seedScreenshot`), cakupan serving / 404 setelah hapus atau disconnect / cache header / tombstone / kuota tetap.
- [x] Tanpa migrasi.
- [ ] Review security → TypeScript (Alief).
- [ ] Pertanyaan K7 ke Umar sebelum merge; PR, merge di menit :10–:40 (tidak di 18:30–19:30 UTC); jam deploy CI = awal jam G1.

### File

- `backend/api/src/routes/scans.ts`
- `backend/api/test/helpers/screenshots.ts` (baru)
- `backend/api/test/scans.test.ts`, `log-hygiene.test.ts`, `screenshots.test.ts`, `devices-me.test.ts`, `security-review.test.ts`
- `backend/API.md`

### Test

- `pnpm -C backend/api run typecheck`: bersih.
- **Merah (sebelum kode):** `vitest run scans screenshots devices-me security-review log-hygiene` → 6 gagal / 114 lulus (120). Yang gagal: 5 kasus baru di `scans.test.ts` (screenshot valid tersimpan; 4 nilai non-string → 422) dan `log-hygiene` (tidak ada `screenshot_ignored`).
- **Hijau (sesudah kode):** `vitest run scans screenshots devices-me security-review log-hygiene favicons replicas` → 291 lulus / 1 gagal (292). Yang gagal: `replicas` "the Guardian's push goes out before the replica is inflated", juga gagal dengan `routes/scans.ts` dari `main`: penyebabnya `backend/api/.dev.vars` lokal (kunci APNs asli → bukan `LogSender`), bukan 20a.
- **Suite penuh:** `pnpm -C backend/api test` dengan `.dev.vars` lokal → 7 gagal / 672 lulus / 1 skip; semua 7 karena `.dev.vars` (APNs, `APPLINKS_APP_IDS`). Tanpa `.dev.vars` (seperti CI) → 38 file, 679 lulus / 1 skip.

### Adaptasi test lama

- `scans.test.ts`: blok "POST /scans screenshot" dipecah. "POST /scans screenshotBase64 (ignored since fase 20a)": screenshot valid → 201, `screenshot_path` null, tidak ada objek di Storage lokal, tidak ada tombstone, tepat satu log `{"event":"screenshot_ignored"}` tanpa id/device/domain; nilai number/object/array/`true` → 201; `""`/`null` → tanpa log; kunjungan ulang mempertahankan screenshot lama. "attachScreenshot (until fase 20b)": JPEG/PNG tersimpan, 6 alasan drop, dedupe 24 jam, kuota paralel, kuota 50/24 jam, lewat service. List dan detail `GET /scans` men-seed screenshot lewat service.
- `screenshots.test.ts`: `postShot` membuat scan tanpa screenshot lalu `seedScreenshot`; semua test serving, 404, `Cache-Control`, rate limit tetap.
- `devices-me.test.ts`: hapus objek Storage saat `DELETE /devices/me` memakai seed.
- `security-review.test.ts`: tombstone sebelum upload, `DELETE /devices/me` menghapus objek, dan kuota global memakai seed.
- `log-hygiene.test.ts`: alur penuh mengirim `screenshotBase64` → tepat satu `screenshot_ignored`, ikut cek kebocoran; screenshot scan di-seed supaya link screenshot (sekarang wajib 200) dan penghapusannya tetap ada di alur.

### Deviasi

- Log `screenshot_ignored` ditulis setelah validasi dan anggaran global, sebelum `recordScan`, jadi kunjungan ulang situs yang sama juga tercatat (bukti build lama, tetap tanpa id).
- Selain `API.md:446,483` dari rencana: dua catatan Deprecated dan daftar isi juga diperbarui (rujukan "fase 18c" sudah usang).
- Test tambahan di luar Output: nilai non-string, `""`/`null` tanpa log, kunjungan ulang.
- Local Supabase mati saat sesi mulai (Docker Desktop tidak jalan); Docker dinyalakan, container `supabase_*_shoo` jalan lagi tanpa reset.
