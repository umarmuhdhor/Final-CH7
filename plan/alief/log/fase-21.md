# Log fase 21 — Monitoring, alert, dan observability

- **Status:** [r] 21a — PR `feat/B9-ops-status` (lihat PR), reviewer @umarmuhdhor, **pending LANGKAH MANUAL 1–3** (setelah merge). 21b tertahan (workflow `.github/` milik Umar, pertanyaan di PR 21a). 21c: lihat bagian 21c di bawah.
- **Model:** Claude Opus 5.5, sesi track be. 1 Nov 2026.
- **Rencana:** `fase-21-monitoring.md` (sudah diverifikasi 2 ronde + cek lintas fase R8). Tidak ada `fase-21-plan.md` terpisah: Langkah kerja 21a di file fase sudah per langkah TDD, dipakai langsung.
- **Keputusan K:** semua dari R8 §c (D-alief-C29): K1 A (workflow `ops-watch`), K3 angka tabel, K6 token header + 404 + issue kode saja. Lihat D-alief-B13 di bawah.

## 21a — backend (`feat/B9-ops-status`, dari `origin/main` aa976af)

### Checklist langkah

- [x] 1. pgTAP merah: `tests/ops_jobs.test.sql` (tabel, PK, check `job`, `failed >= 0`, grant SELECT/INSERT/UPDATE, anon/authenticated/service_role tanpa hak, policy per perintah, RLS); `grants.test.sql` (+3), `schema.test.sql` (+1).
- [x] 2. Migrasi `20261101100000_ops_jobs.sql` (K2 + `check (failed >= 0)`, `set local lock_timeout`). `supabase db reset && supabase test db` hijau.
- [x] 3–4. Retensi: `ops_start` setelah heartbeat, `ops_finish` sebelum log `retention` dengan `failed = errors.length`; keduanya `step(...)` biasa. Notifikasi: `finish` sebelum log, gagal → `ops_job_write_failed` (`{event, job, error: errorInfo}`), push tetap terkirim. Opsi test `ops?: OpsWriter`.
- [x] 5–6. `services/opsStatus.ts` `evaluate(snapshot)`: semua kode K3 sisi backend di tepi ambang (26 jam ± 1 menit, 2 j 15 m ± 1 menit, 350/450 MB ± 1 byte, antrean 24 jam ± 1 menit).
- [x] 7–8. `GET /ops/status`: 404 tanpa header / token salah / skema bukan Bearer / HEAD / secret kosong atau < 32 karakter; 200 dengan token; 30/jam key `"all"` dihitung setelah token cocok (40 token salah → 0 baris `ops_status`); respons tanpa UUID, domain, path.
- [x] 9. `log-hygiene.test.ts`: `/ops/status` dengan token benar dan salah → token tidak ada di log; bucket `ops_status` masuk daftar limit yang direview.
- [x] 10. `EXPLAIN` (20 000 scans lokal, `analyze`): `exists (… created_at < now() - '15 days 06:00:00')` → `Index Only Scan using scans_created`.
- [x] 11. `backend/README.md` (tabel endpoint, `ops_jobs`, Env `OPS_STATUS_TOKEN`, bagian "Monitoring and alerts" = runbook), `backend/API.md` (`GET /ops/status`).
- [x] 12. Typecheck, vitest, pgTAP, review berurutan (security → database → TypeScript).

### File dibuat/diubah

Baru: `backend/db/supabase/migrations/20261101100000_ops_jobs.sql`, `backend/db/supabase/tests/ops_jobs.test.sql`, `backend/api/src/db/repo/ops.ts`, `backend/api/src/services/opsStatus.ts`, `backend/api/src/routes/ops.ts`, `backend/api/test/ops-status.test.ts`.
Diubah: `src/app.ts`, `src/env.ts`, `src/http/rateLimit.ts`, `src/cron/retention.ts`, `src/cron/notifications.ts`, `test/env.d.ts`, `test/helpers/resetDb.ts` (hapus `ops_jobs` lewat role postgres: `shoo_api` tidak punya DELETE), `test/retention.test.ts`, `test/settings.test.ts`, `test/log-hygiene.test.ts`, `vitest.config.ts`, `.dev.vars.example`, `db/supabase/tests/grants.test.sql`, `schema.test.sql`, `backend/README.md`, `backend/API.md`.

### Deviasi dari file fase (kecil)

- `evaluate(snapshot)` tanpa argumen `now`: umur dihitung di query dengan jam DB (`now()`), jadi tidak ada beda jam Worker vs DB. Test tepi ambang memakai angka umur langsung.
- Respons menambah `okAgeHours` per job di samping `ageHours` (umur run terakhir). Gerbang fase 20 membaca `jobs.retention.failed` + `ageHours`; `retention_stale` memakai `okAgeHours`.
- `notifications`: `failed` = push yang melempar + hasil `failed:config` (konfigurasi APNs rusak). Penolakan APNs per device (token salah/kedaluwarsa) normal, hanya di `push_log`. Run yang melempar sebelum `finish` → `notifications_stale` (review TypeScript MEDIUM 1).
- Policy per perintah (select/insert/update) alih-alih `shoo_api_all` (review security LOW 2).
- Index `blocklist_queue` ditunda (review database MEDIUM): tabel kecil.
- `plan/alief/ref/R3-catatan-api.md` §7 (env `OPS_STATUS_TOKEN`) **tidak** diubah: sesi ini hanya boleh `backend/**` dan `plan/alief/log/**`. Koordinator menambahkannya di PR plan.

### Verifikasi (1 Nov 2026, lokal, Docker + Supabase CLI)

| Perintah | Hasil |
|---|---|
| `supabase db reset && supabase test db` | 13 file, 173 test, PASS |
| `pnpm -C backend/api typecheck` | bersih |
| `pnpm -C backend/api exec vitest run test/ops-status.test.ts` | 20/20 |
| `pnpm -C backend/api exec vitest run test/ops-status.test.ts test/retention.test.ts test/settings.test.ts` | 53/53 |
| `pnpm -C backend/api exec vitest run` (suite penuh, setelah semua review) | 560 lulus, 1 skip, **1 gagal di luar fase ini**: `allowlist.test.ts` "covers every official domain in detector/data/brands.json" (`agoda.com`, `agoda.co.id`, `dhl.com`, `dhl.co.id`). Penyebab: commit Umar `71fd461` (29 Okt, `detector/`) menambah brand, `backend.yml` tidak terpicu karena filter path `backend/**`. Perbaikan di PR kecil terpisah `fix/BE-allowlist-brands` (lihat laporan akhir) |

Catatan lokal: dua run penuh sebelumnya gagal `53300 too_many_connections` di `security-headers.test.ts` karena 15 koneksi `shoo_api` idle tersisa dari run vitest yang dihentikan. Setelah `select pg_terminate_backend(pid) from pg_stat_activity where usename = 'shoo_api'` suite hijau (selain `allowlist`). Test rate limit `/ops/status` mengisi 29 baris `rate_limit_hits` langsung (bukan 30 request) supaya tidak menambah koneksi.

Verifikasi 1–2 file fase (`wrangler dev --test-scheduled` + curl lokal) belum dijalankan: perilaku yang sama dipaku test (`retention.test.ts`, `ops-status.test.ts` lewat `app.fetch`). Verifikasi 3–7 butuh cloud (LANGKAH MANUAL).

### Review (berurutan)

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:security-reviewer` | Tidak ada CRITICAL/HIGH. LOW 1: secret kosong keluar sebelum hash (beda waktu kecil). LOW 2: policy `for all` juga mengizinkan DELETE di level policy. LOW 3: token salah tanpa batas per IP (hanya biaya CPU; WAF Cloudflare kalau perlu). LOW 4: pemegang token bisa menghabiskan 30/jam → ops-watch harus menganggap 429 "tidak diketahui". LOW 5: `dbBytes` hanya untuk pemegang token, jangan dicetak di Actions | LOW 1 + 2 diperbaiki (`d314aea`), HEAD tanpa token ikut dites. LOW 3: tidak diubah (tebak token 256-bit mustahil; limiter DB akan membocorkan route). LOW 4 + 5: catatan untuk 21b |
| `ecc:database-reviewer` | Tidak ada CRITICAL/HIGH. MEDIUM: antrean blocklist tanpa index parsial → seq scan `blocklist_entries` tiap panggilan. LOW: hitungan tombstone tidak bisa memakai `storage_tombstones_due` (tabel kecil, dikuras cron); konsumen harus menganggap `okAgeHours: null` = basi | MEDIUM diterima: tabel ratusan baris, 30 panggilan/jam paling banyak; index `blocklist_queue` (`create index concurrently`, di luar transaksi migrasi) kalau tabel lewat ±10k baris (handoff). `null` sudah = `*_stale` di `evaluate` |
| `ecc:typescript-reviewer` | Tidak ada CRITICAL/HIGH. MEDIUM 1: notifikasi selalu `failed: 0`, jadi APNs rusak total tidak pernah membuat alert. MEDIUM 2: `started_at` tidak dibaca; notifikasi tanpa `start`. LOW: assertion `r!` berulang, tipe kembali, test 404 tidak membandingkan path tak dikenal, `"Bearer "` kosong dobel, urutan kode perlu komentar | MEDIUM 1: run gagal kalau push melempar atau hasil `failed:config` (token device ditolak tetap normal), test baru. MEDIUM 2: notifikasi kini `start` juga; `started_at` dibaca manual (runbook: run mati di tengah). LOW diperbaiki |

### Privasi Apple (SECURITY §3, D-alief-40)

- P2/P3: tidak ada data pengguna baru; `ops_jobs` hanya status job (2 baris).
- P6: respons dan log hanya angka agregat + kode; test memastikan tanpa UUID/domain/path/token (`ops-status.test.ts`, `log-hygiene.test.ts`).
- P13: `Cache-Control: private, no-store` (global, dites). Cek `retention_overdue` membuat janji 14 hari terukur.
- §1 secret: `OPS_STATUS_TOKEN` hanya lewat `wrangler secret put`; dibandingkan constant-time; tidak pernah di URL.

## D-alief-B13 · 1 Nov 2026 · fase 21a · Status cron di `ops_jobs`, `GET /ops/status` dengan token

- Keputusan: fase 21 K2 (tabel `ops_jobs`), K3 (ambang di `services/opsStatus.ts`), K6 (Bearer `OPS_STATUS_TOKEN` ≥ 32 karakter, 404 tanpa token tanpa query DB, limit 30/jam dihitung setelah token cocok, respons angka saja), memakai rekomendasi R8 §c (D-alief-C29). Umur dari jam DB; `okAgeHours` + `ageHours` per job. Notifikasi tanpa `failed`.
- Alasan: rekomendasi file fase; satu query; logika ambang dites.
- Catatan untuk koordinator: entri ini dipindah ke `log/DECISIONS.md` di PR plan (#207) supaya PR fase tidak bentrok di file yang sama.

## LANGKAH MANUAL (setelah PR 21a merge dan CI deploy)

- [ ] 1. **(Alief)** `openssl rand -base64 32` → simpan di password manager → dari `backend/api/`: `npx wrangler secret put OPS_STATUS_TOKEN` (di luar 18:30–19:30 UTC). Uji: `read -rs OPS_STATUS_TOKEN`, lalu `curl -s -H "Authorization: Bearer $OPS_STATUS_TOKEN" https://shoo-api.afindo-mi01.workers.dev/ops/status` → 200; tanpa header → 404. Catat hasil (tanpa token) di sini. Sebelum run cron pertama, `failing` memuat `retention_stale`/`notifications_stale` (belum ada baris `ops_jobs`): normal.
- [ ] 2. **(Alief, D10)** Cloudflare → Notifications → Usage Based Billing → R2 Class A ambang 500 000 dan Class B ambang 5 000 000, email pemilik akun. Kalau tidak bisa dipilih: catat di sini.
- [ ] 3. **(Alief)** Catat pemilik email notifikasi Supabase (pause/kuota) dan Cloudflare (billing).
- [ ] 4–8. Sesuai `fase-21-monitoring.md` LANGKAH MANUAL 4–8 (spike GraphQL, custom alert, Environment `ops` oleh Umar, TestFlight crash, cek Senin). 4–6 baru perlu sebelum 21b.

Verifikasi cloud setelah butir 1: pagi setelah run 19:00 UTC pertama → `jobs.retention.failed = 0`, `ageHours < 12`; satu jam setelah deploy → `jobs.notifications.ageHours < 1.2`.

## Placeholder aktif

Tidak ada.

## Catatan handoff

- 21b: workflow harus memperlakukan 429 dari `/ops/status` sebagai "tidak diketahui" (bukan sehat, bukan `ops_status_unreachable` palsu), dan tidak pernah mencetak angka (`dbBytes`, antrean) di log Actions (review security LOW 4, 5).
- Kalau `blocklist_entries` lewat ±10k baris: migrasi `create index concurrently blocklist_queue on blocklist_entries(first_seen_at) where approved_at is null and rejected_at is null and removed_at is null and families > 0` (di luar transaksi; review database MEDIUM).
- 21c (`feat/EX-07-ops-replica`) menambah `replica_reserve`/`replica_full`/`replica_family_cap` dari `replicaUsage` fase 19, stacked di atas 19a.
- `R3-catatan-api.md` §7: tambah `OPS_STATUS_TOKEN` (koordinator, PR plan).
- `app.onError` tanpa field `event` tetap (PR kecil terpisah kalau dibutuhkan).
