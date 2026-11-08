# Log fase 24 — Privasi dan data (E6, E7, C22)

- **Status:** [m] 24a-1 PR #312 merged 7 Nov 2026 15:37 UTC (deploy lewat CI, mode `dry_run`), **LANGKAH MANUAL 24a-1 butir 1: 7 run dry-run (Alief)** · [r] 24c-1 PR `fix/E6-privacy-contact`, reviewer @umarmuhdhor, **pending LANGKAH MANUAL 1–2 (mailbox K10 belum ada)** · 24a-2 dan 24b belum (24b/24c-2 = app).
- **Model:** Claude Opus 5.5, sesi track be. 1 Nov 2026.
- **Rencana:** `fase-24-privacy-data.md` (PR #207).
- **Keputusan K:** R8 §c (D-alief-C29): K10 (a) mailbox tim gratis (belum dibuat → LANGKAH MANUAL 1), K11 (a) tetap `workers.dev`, K12 isian App Privacy ditanyakan ke Umar (E6). Tidak ada D-alief baru.

## 24c-1 — `fix/E6-privacy-contact` (dari `origin/main` aa976af)

Mailbox K10 belum ada, jadi alamat kontak **tidak** diganti di PR ini. Supaya penggantian nanti satu baris, `CONTACT` di `routes/privacy.ts` diekspor dan dipakai bersama `/privacy` dan `/support`.

### Checklist langkah (Langkah kerja 22–23 file fase, disesuaikan)

- [x] 22. Merah: `test/support.test.ts` — `GET /support` 200, HTML, CSP `default-src 'none'`, `nosniff`, `private, no-store` (sama dengan `/privacy`), EN default + `?lang=id` + `Accept-Language: id`, memuat `CONTACT`, "Profile → Delete account" / "Profil → Hapus akun", cara putus keluarga, link `/privacy` dan `/terms`, tanpa `<script`; `CONTACT` sama di `/privacy`. 3/3 merah.
- [x] 23. Hijau: `routes/support.ts` (memakai `legalPage` + `pageLanguage`), didaftarkan di `app.ts`; `CONTACT` diekspor. `API.md` + `README.md` (tabel endpoint).
- [ ] 22b. Test "kontak = mailbox K10, tanpa 'coming before public release'": menunggu LANGKAH MANUAL 1.

### Verifikasi

| Perintah | Hasil |
|---|---|
| `npx tsc --noEmit` (`backend/api`) | bersih |
| `vitest run test/support.test.ts test/privacy.test.ts` | 8/8 (support tanpa route: 3 merah) |
| `vitest run` (suite penuh) | 538 lulus, 1 skip |

### Review

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:typescript-reviewer` | HIGH: "Guardian atau orang yang dilindungi … ketuk Putuskan koneksi" salah — di app hanya Guardian yang bisa memutus (`ProfilePages.swift:814`, Protected terkunci). MEDIUM: Guardian yang masih punya anggota harus memutus dulu sebelum Hapus akun. LOW: "dihapus seketika" untuk file (R2/Storage dihapus setelah commit, retry cron). Label app cocok (`Localizable.xcstrings`); `legalPage` raw HTML aman (teks statis); header sama dengan `/privacy` | Semua diperbaiki EN + ID: Guardian memutus; Protected minta Guardian atau hapus akun; kalimat "Guardian dengan anggota memutus dulu"; "removed from our server right away". Test memaku kalimat baru |

### Privasi Apple (SECURITY §3)

- Halaman statis, tanpa DB, tanpa log baru, header sama dengan `/privacy` (`private, no-store`, CSP ketat).
- Kontak tetap placeholder (bukan alamat pribadi siapa pun; K10 menolak alamat pribadi).

## 24a-1 — `feat/E7-inactive-devices` (dari `origin/main` ce137f9, 7 Nov 2026)

Keputusan yang dipakai (dari brief, belum tercatat sebagai D-alief): K1 = 90 hari, K3 = (b) keluarga satu unit, K4 = (b) 30 hari, K6 = 50 per run, K7 = cek ulang di transaksi (`lock_timeout` 3 s + kunci baris), K8 = `off` (default kode) | `dry_run` | `delete`, `wrangler.jsonc` = `dry_run`. Nilai env tak dikenal = `off`.

### Checklist langkah (Langkah kerja 1–7 file fase)

- [x] 1. Merah — kandidat: `describe("inactive devices (E7)")` di `test/retention.test.ts`; device dimundurkan lewat SQL (`last_seen_at`/`created_at`). Kasus: tanpa keluarga 91 hari → kandidat, 89 → bukan; registrasi tak terpakai 31 hari → kandidat, 29 → bukan; Guardian 200 hari + Protected aktif → bukan; Guardian + semua Protected 91 hari → semua kandidat; Protected 91 hari dengan Guardian aktif → bukan; tambahan: registrasi tak terpakai 40 hari **dalam** keluarga aktif → bukan (aturan keluarga menang). Batas `limit` memotong daftar, bukan hitungan.
- [x] 2. Hijau: `db/repo/devices.ts` `inactiveDeviceIds(sql, cutoffs, limit)` + `countInactiveDevices(sql, cutoffs)` dari satu fragmen SQL `inactiveCandidates` (sketsa spec, `make_interval(days => $n::int)`).
- [x] 3. Merah — mode: `off` (env tanpa var, `"DELETE"`, `"on"`, `""`, opsi `off`) → hasil 0, tidak ada yang terhapus; `dry_run` → `inactiveCandidates = 5` walau `inactiveMax = 2`, `backlog` false (juga di `ops_jobs`), log hanya hitungan; `delete` → device, link, scan, verdict (dua arah), push_log, join_attempts, family_codes hilang, path ditombstone, `blocklist_entries.families` 2 → 1; batas K6 → `backlog: true` (hasil + `ops_jobs`), sisa terhapus run berikutnya; `INACTIVE_DEVICES: "delete"` dari env bekerja sama. Log hygiene: baris `inactive_devices` ada di alur penuh (`dry_run` dari `wrangler.jsonc`) + test baru `dry_run`/`delete` tanpa id, nama, token, token APNs.
- [x] 4. Hijau: `cron/retention.ts` `step("inactive_devices", …)` setelah `rate_limit_hits` dan **sebelum** `ops_finish` (fase 21a), jadi gagalnya masuk `failed`. `parseInactiveMode` (gagal tertutup), `inactiveMax ?? 50`. `env.ts`, `test/env.d.ts`, `wrangler.jsonc` (`"INACTIVE_DEVICES": "dry_run"`).
- [x] 5. Merah — balapan: device kandidat lalu `touchLastSeen` di antara SELECT dan hapus → `skipped = 1`, scan utuh, device lain tetap terhapus; Guardian keluarga kandidat menjadi aktif → Protected (dan Guardian) dilewati, link utuh; baris device dikunci transaksi lain → `55P03` → dilewati, device berikutnya tetap terhapus; error lain (`57014`, `statement_timeout` < `lock_timeout`) → langkah berhenti di device pertama, `failed: 1` di log + `ops_jobs`, run tetap selesai lalu melempar. `deleteDevice` tanpa opsi tetap menghapus; dengan opsi pada device bukan kandidat / tidak ada → `null`.
- [x] 6. Hijau: `deleteDevice(sql, id, { onlyIfInactive, lockTimeoutMs })` (overload; tanpa opsi kode lama persis sama, `devices-me.test.ts` hijau tanpa diubah): `set_config('lock_timeout', '3000ms', true)`, kunci baris device + Guardian + semua Protected keluarganya `order by id for share`, lalu cek ulang SQL kandidat yang sama untuk id itu; tidak ada baris → `null`. Retensi: `40P01`/`55P03` → `skipped`, lanjut; error lain → lempar.
- [x] 7. Migrasi `20261107100000_inactive_devices.sql` (`create index devices_last_seen on devices(last_seen_at)`, add-only, `set local lock_timeout 5s`) + pgTAP `tests/inactive_devices.test.sql` (`has_index`, tidak parsial, valid). Merah 3/3 sebelum migrasi, hijau sesudah.
- [x] 8. Review `ecc:database-reviewer` → `ecc:typescript-reviewer` → `ecc:security-reviewer` (berurutan, 7 Nov 2026): 0 CRITICAL/HIGH, lihat tabel Review.

### File

| File | Ubah |
|---|---|
| `backend/db/supabase/migrations/20261107100000_inactive_devices.sql` | baru: index `devices_last_seen` |
| `backend/db/supabase/tests/inactive_devices.test.sql` | baru: pgTAP 3 test |
| `backend/api/src/db/repo/devices.ts` | `InactiveCutoffs`, `inactiveCandidates` (privat), `inactiveDeviceIds`, `countInactiveDevices`, `DeleteDeviceOptions`, overload `deleteDevice` |
| `backend/api/src/cron/retention.ts` | `parseInactiveMode`, `RetentionResult.inactiveCandidates/inactiveDevices/inactiveSkipped`, opsi test `inactiveMode`, `inactiveMax`, `afterInactiveSelect`, langkah `inactive_devices` |
| `backend/api/src/env.ts`, `backend/api/test/env.d.ts`, `backend/api/wrangler.jsonc` | var `INACTIVE_DEVICES` (`dry_run`) |
| `backend/api/test/retention.test.ts` | 10 test baru (describe "inactive devices (E7)") |
| `backend/api/test/log-hygiene.test.ts` | cek baris `inactive_devices` di alur penuh + 1 test baru |
| `backend/README.md` | baris env `INACTIVE_DEVICES` + butir retensi |

### Verifikasi

| Perintah | Hasil |
|---|---|
| `supabase test db` (`backend/db`, setelah `supabase migration up --local`) | 766/766 lulus, 24 file (sebelum migrasi: `inactive_devices.test.sql` 3/3 merah) |
| `supabase test db` (ulang, setelah sesi lain me-reset DB bersama ke migrasi `20261107095337_admin_domain_lists` yang tidak ada di branch ini) | `inactive_devices.test.sql` ok; 759/766 — 7 gagal di `admin_analysis`, `admin_archive`, `admin_grants`, `l5_review_data` karena skema/data sesi lain (`admin.shared_hosts`, sisa baris), bukan perubahan ini. Tidak di-`db reset` supaya kerja sesi lain tidak terhapus |
| `pnpm -C backend/api run typecheck` | bersih |
| `vitest run retention log-hygiene` sebelum kode | 12 merah / 14 lulus |
| `vitest run retention devices-me log-hygiene privacy` | 4 file, 40/40 lulus |
| `pnpm -C backend/api test` (suite penuh) | 37 file, 671 lulus, 1 skip (dua run awal rusak karena checkout `Final-CH7-dash` menjalankan vitest + reset di DB yang sama; diulang saat DB sepi) |

### EXPLAIN SQL kandidat (lokal, dalam transaksi yang di-rollback)

Data: 50 000 device (5 % terakhir aktif 100–149 hari lalu, sisanya ≤ 9 hari), 37 497 link keluarga, `analyze`. `count(*)` SQL kandidat (`inactiveDays` 90, `unusedDays` 30):
- Cabang K1: `Bitmap Index Scan on devices_last_seen` (2500 baris) → hash anti join ke Guardian aktif (seq scan `devices g`, 47 500 baris; planner memilih hash karena hampir semua device aktif) → anti join Protected aktif lewat `family_links_guardian` + `devices_pkey`.
- Cabang K4: `Bitmap Index Scan on devices_last_seen` → anti join `family_links` lewat `BitmapOr` `family_links_pkey` + `family_links_guardian`.
- Execution 16 ms, planning 0,6 ms. Index sementara di-drop lagi setelah EXPLAIN (DB bersama).

### Penyimpangan dari spec

- Nama opsi `onlyIfInactiveBefore` → `onlyIfInactive: InactiveCutoffs` (+ `lockTimeoutMs`): cek ulang K7 butuh kedua ambang (K1 dan K4) dan aturan keluarga, bukan satu cutoff.
- Cek ulang K7: bukan `select 1 … and last_seen_at < $cutoff for update` saja, tetapi kunci baris device **dan** seluruh anggota keluarganya (`for share`, urut id) lalu jalankan SQL kandidat yang sama untuk id itu. Alasan: `UNION` tidak bisa `for update`; dengan kunci keluarga, `touchLastSeen` anggota mana pun menunggu sampai commit, jadi tidak ada celah antara cek ulang dan hapus. `for share` tidak bentrok dengan `for key share` dari insert ber-FK.
- Opsi `now` (Peta dampak) tidak dibuat: test memundurkan kolom lewat SQL (Catatan handoff), cukup.
- Opsi test tambahan `afterInactiveSelect` (hook di antara SELECT kandidat dan hapus) untuk test balapan langkah 5.
- Log `{"event":"inactive_devices",…}` juga ditulis di mode `off` (semua hitungan 0) supaya mode yang aktif terlihat di tail; `RetentionResult` juga punya `inactiveSkipped` (masuk baris log `retention`, hanya angka).
- Langkah merah/hijau 1–6 dijalankan dalam dua putaran (semua test merah dulu, lalu semua kode), bukan enam putaran.
- R7: fase 25c (Durable Object) belum ada di `src` (`grep -rn DurableObject` = 0), jadi tidak ada socket yang perlu ditutup.

### Placeholder aktif

Tidak ada.

### Review (langkah 8)

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:database-reviewer` | MEDIUM: index `devices_last_seen` mematikan HOT update `touchLastSeen` (maks 1×/5 menit per device). MEDIUM: kunci keluarga `id = … or … in (subselect)` tidak bisa memakai `devices_pkey` (seq scan per hapus). LOW: cron ringkasan mingguan `notifications.ts` mengunci baris device tanpa urutan, jendela deadlock sempit dengan retensi. LOW: urutan kunci, SQL K3/K4, migrasi aman | Index **tetap** (spec C7; EXPLAIN 50 000 baris memakai index; biaya HOT kecil di volume ini, dicek ulang di LANGKAH MANUAL 1). Kunci keluarga ditulis ulang `id in (… union …)` (6f50456). Deadlock ringkasan: sisi retensi aman (40P01 → skip); catatan handoff |
| `ecc:typescript-reviewer` | MEDIUM: test balapan tidak membuktikan kunci `for share` keluarga. MEDIUM: `statement_timeout` test 57014 berlaku untuk semua langkah retensi (bisa kena langkah lain di CI lambat). LOW: holder transaksi tidak dilepas kalau `runRetention` melempar. LOW: komentar join setelah cek ulang, 40001 sengaja tidak di-skip | Test baru "uncommitted request holds the family lock" (merah tanpa `for share`, dicek mutasi); timeout dipasang lewat `afterInactiveSelect`; `try/finally`; dua komentar (9ef3fea) |
| `ecc:security-reviewer` | MEDIUM (P12): `/privacy` masih "not deleted automatically yet": benar selama `dry_run`, salah begitu `delete`. LOW: query kandidat tanpa `statement_timeout`. LOW: hook test di `RetentionOptions` tidak terjangkau produksi (`index.ts` tanpa opsi). Fail-closed env, injeksi SQL, aturan keluarga: aman | P12 = gerbang 24a-2: teks `/privacy` EN/ID wajib di PR yang sama atau sebelum `INACTIVE_DEVICES = delete` (catatan handoff). LOW lain diterima: kegagalan terisolasi `step`, tidak ada risiko hapus |

Verifikasi setelah review: typecheck bersih; `vitest run retention devices-me log-hygiene` 34/34 lulus.

### Privasi Apple (SECURITY §3)

- P2: tidak ada data baru. P3: jalur hapus pengguna (`DELETE /devices/me`) tidak berubah (`devices-me.test.ts` tanpa perubahan).
- P6: log `inactive_devices` hanya mode + hitungan (`log-hygiene.test.ts`).
- P12: teks `/privacy` belum berubah (benar untuk `dry_run`); 24a-2 wajib menggantinya.
- P13: hapus lewat `deleteDevice` yang sama: cascade 6 tabel, trigger `admin.on_device_delete`, path R2/Storage ditombstone dalam transaksi (objek 404 seketika, dihapus fisik run berikutnya).

### LANGKAH MANUAL 24a-1 (setelah PR merge + deploy CI)

- [~] 1. **(Alief, cloud, baca saja)** = butir 3 file fase: 7 run cron berturut-turut (19:00 UTC), baca `npx wrangler tail shoo-api --format json` atau Workers Logs: `retention` `failed: 0`, `inactive_devices` `mode: dry_run`. Bandingkan `candidates` dengan query kandidat (langkah 2 file fase, 90/30 hari) di SQL editor (`supabase db query --linked`), plus `over_k1` dan `total`; hanya angka, tanpa id. Catat `cpuTime` cron. Setelah 7 run bersih: 24a-2 boleh mulai.
  - **Pembanding SQL, 7 Nov 2026, 17:11 UTC** (baca saja, perkiraan, bukan fragmen `inactiveCandidates` persis): `total` 18, `over_k1` 0, `unused_30` 0 → `candidates` yang diharapkan 0. Index `devices_last_seen` ada di cloud (migrasi 24a-1 terpasang). Run `retention` yang terlihat di `ops_jobs` (6 Nov 19:00) **sebelum** deploy 24a-1, jadi bukan dry run.
  - **Run 1/7, 7 Nov 2026 19:00 UTC** (`wrangler tail`): cron `0 19 * * *` cpu 24 ms, wall 5 828 ms, `ok`.
    - `{"event":"inactive_devices","mode":"dry_run","candidates":0,"deleted":0,"skipped":0,"failed":0}` → sama dengan pembanding SQL (0).
    - `retention`: `failed` 0, `backlog` false, `inactiveCandidates` 0, `inactiveDevices` 0, `tombstones` 1, `rateLimitHits` 415, lainnya 0.
  - Run 2–7 (8–13 Nov 19:00 UTC): Alief, baris sama dari tail atau Workers Logs.

## Catatan handoff 24a

- 24a-2 (ganti var ke `delete`) **wajib** membawa teks `/privacy` EN/ID baru + `privacy.test.ts` di PR yang sama (review security P12).
- Cron ringkasan mingguan (`cron/notifications.ts`, `update devices … from unnest(...)`) mengunci baris tanpa urutan; kalau muncul 40P01 di sisi notifikasi, tambahkan `order by id … for update` (review database LOW).
- Index `devices_last_seen`: kalau tabel `devices` membesar dan bloat terlihat, pertimbangkan `fillfactor` lebih rendah (review database MEDIUM, diterima).

## LANGKAH MANUAL

- [ ] 1. **(Alief)** Buat mailbox tim K10 (a): alamat baru di layanan email gratis, khusus tim, bukan alamat pribadi siapa pun; simpan login di password manager tim. Catat alamatnya di sini.
- [ ] 2. **(Alief, PR kecil setelah 1)** Ganti satu baris `CONTACT` di `backend/api/src/routes/privacy.ts` ke alamat itu (berlaku untuk `/privacy` dan `/support`), hapus `TODO(sync:alief)`, tambah test "kontak = mailbox, tanpa 'coming before public release'" di `privacy.test.ts` + `support.test.ts`, ubah tanggal "Last updated" `/privacy` (test `privacy.test.ts` ikut). 24c-2 (app, `AppConfig.supportEmail`) memakai alamat yang sama.
- [ ] 3. **(Alief, setelah merge + CI deploy)** `curl -s https://shoo-api.afindo-mi01.workers.dev/support | grep -o '<h1>[^<]*'` → "Shoo support"; `?lang=id` → "Bantuan Shoo".
- [ ] 4. **(Umar)** Jawab pertanyaan E6 di PR 24c-1 (`## Questions for Umar`, D-alief-C29).
