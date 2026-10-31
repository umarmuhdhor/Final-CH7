# Fase 21 — Monitoring, alert, dan observability (TODO B9, D9, D10 sisa, D11)

| Field | Nilai |
|---|---|
| Track | c (backend + CI; app tanpa kode) |
| Branch | 21a `feat/B9-ops-status` (backend: tabel `ops_jobs`, `GET /ops/status`, runbook; dari `origin/main` saat mulai) · 21b `feat/B9-ops-watch` (skrip `backend/ci/ops-watch.mjs` + usulan `.github/workflows/ops-watch.yml`, setelah issue ke Umar dijawab, pola PR #174) · 21c `feat/EX-07-ops-replica` (cek kuota replica di `/ops/status`, setelah fase 19 merge; boleh digabung ke 21a kalau fase 19 sudah di `main` saat 21a mulai) |
| Prasyarat | 21a: tidak ada (berdiri sendiri). 21b: 21a live + issue "B9: workflow ops-watch terjadwal" dijawab Umar (K7) + secret diisi Umar. 21c: fase 19 (19a) merge, karena `replicaUsage` dan event `replica_quota_usage` belum ada di `main` (`git grep replica_quota_usage backend/api/src` = 0 hasil, 31 Okt) |
| Urutan | Jawaban K1–K8 → issue ke Umar (K7) → 21a (TDD) → review → PR (reviewer @umarmuhdhor) → merge (CI deploy) → LANGKAH MANUAL 1–3 → 21b PR (Umar merge) → LANGKAH MANUAL 4–6 → uji alert (Verifikasi 6) → 21c setelah fase 19 |
| Requirement | TODO B9 (uptime + anti-pause), D9 (antrean blocklist), D10 sisa (alert R2 Class A + billing), D11 (cek pemakaian mingguan); permintaan Alief 31 Okt "kita juga butuh monitoring"; fase 19 K5 (konsumen event), fase 20 (gerbang run retensi `failed: 0`); SECURITY §3 P2, P6, P13; §1 (secret) |
| Model + reviewer ECC | Opus 5.5 · `ecc:security-reviewer` → `ecc:database-reviewer` → `ecc:typescript-reviewer` (berurutan, tidak paralel) |
| Fase berikutnya | Tidak ada yang menunggu fase 21. Fase 20 memakai `/ops/status` sebagai bukti gerbang retensi kalau 21a sudah live; kalau belum, tetap baris log `retention` |

## Tujuan

**Masalah.** Backend hidup di cloud sejak 23 Okt, tetapi tidak ada yang memberi tahu kalau ada yang rusak:

1. **Uptime + anti-pause (B9) ditunda sejak 21 Okt** (`TODO.md:44`). `/healthz` dan `/healthz/db` ada (`routes/health.ts:7,10-16`), tetapi tidak ada yang memanggilnya terjadwal. Supabase Free di-pause kalau aktivitas database kurang dalam 7 hari (ARCHITECTURE §3).
2. **Cron gagal diam-diam.** Retensi menulis satu baris `{"event":"retention",…,"failed":n}` lalu melempar error (`cron/retention.ts:141-142`), notifikasi satu baris `{"event":"notifications",…}` (`cron/notifications.ts:49`). Tidak ada yang membaca log. Kalau retensi gagal, janji "hapus setelah 14 hari" (P13) rusak tanpa ada yang tahu. Fase 20 butuh "satu run retensi `failed: 0`" sebagai gerbang (`fase-20-screenshot-sunset.md:219,264`), dan hari ini satu-satunya bukti adalah membuka log.
3. **Error Worker.** `app.onError` menulis `{"requestId","route","error":{name,code}}` tanpa field `event` (`app.ts:81-87`). Event lain (`replica_read_failed`, `push_config_incomplete`, `replica_clear_failed`, `screenshots_delete_failed`, dst.) tersebar di 20+ titik. CPU sejauh ini aman (`wrangler tail` 31 Okt, belum tercatat di log fase mana pun, `fase-19-replica-quota.md:48`: `POST /scans` 52–186 ms, `POST /devices` 20–60 ms, `GET /scans` 3–40 ms, semua `outcome: ok`), tetapi CPU cron retensi dengan 40 panggilan R2 belum terukur (`retention.ts:17-22`, fase 18 LANGKAH MANUAL 3).
4. **Biaya/kuota.** R2: notifikasi storage > 5 GB sudah ada, alert Class A belum (`log/fase-18.md:26`, `TODO.md:93`). Supabase DB/Storage/egress dicek manual tanpa jadwal (`TODO.md:94`).
5. **Antrean blocklist (D9)** hanya terlihat kalau seseorang membuka SQL editor (`TODO.md:92`).
6. **Fase 19 K5** menetapkan sinyal `replica_dropped` + gauge per jam `replica_quota_usage` untuk dipakai fase 21 (`fase-19-replica-quota.md:98-104`); belum ada yang membacanya.
7. **App:** tidak ada laporan crash yang dicek.

**Hasil akhir.**
1. Satu endpoint internal `GET /ops/status` (token rahasia, angka agregat saja) yang menilai sendiri kesehatan backend dari DB: umur run terakhir retensi + notifikasi, `failed`, backlog, tombstone yang macet, scan > 15 hari, ukuran DB, antrean blocklist, dan (21c) level kuota replica. Logika ambang ada di backend dan dipaku test.
2. Satu workflow GitHub Actions terjadwal (tanpa akun baru) yang memanggil `/healthz`, `/ops/status`, `/healthz/db` (anti-pause harian), dan GraphQL Analytics Cloudflare (error, `exceededResources`, request/hari, R2 Class A/B), lalu membuka/menutup satu issue `ops-alert` yang di-assign ke Alief. Email datang lewat notifikasi GitHub.
3. Notifikasi billing Cloudflare untuk R2 Class A/B (D10 sisa).
4. Runbook di `backend/README.md`: siapa dapat alert, arti tiap kode, langkah per kode.
5. App: crash dari Xcode Organizer / TestFlight, tanpa SDK dan tanpa upload diagnostik dari app.

## Bacaan wajib

- `plan/alief/TODO.md:22,44,92-94` (A12, B9, D9, D10, D11)
- `plan/alief/fase-19-replica-quota.md` K5 (`:98-104`), C10 (`:52`), Catatan handoff (`:184-186`)
- `plan/alief/fase-20-screenshot-sunset.md:11,219,264,326` (gerbang `failed: 0`; `screenshot_dropped`/`screenshot_ignored` jangan diberi alert)
- `plan/alief/ARCHITECTURE.md` §3 (`:58-71`), `plan/alief/SECURITY.md` §1, §3 P2/P6/P13
- `backend/api/src/routes/health.ts`, `src/cron/retention.ts`, `src/cron/notifications.ts`, `src/index.ts`, `src/app.ts:81-87`, `src/http/logError.ts`, `src/http/rateLimit.ts:16,55,77`
- `backend/api/wrangler.jsonc:11,48`; `backend/README.md` bagian Retention, Quota, Rollback, Deploy
- `.github/workflows/public-blocklist.yml` (contoh workflow terjadwal + skip sampai variable diisi), issue #38 (secret diisi Umar), issue #173 + PR #174 (Alief menulis workflow, Umar merge + isi secret)
- `backend/db/supabase/migrations/20261021130000_init.sql:83-101,181-207`, `20261025100000_blocklist_rejected.sql`, `20261022130000_security_review.sql:29-35`; `tests/grants.test.sql`, `tests/schema.test.sql`

## Cek kelayakan (diverifikasi terhadap `main` 2720b13, 31 Okt 2026)

Fakta cloud dari docs dicek 31 Okt 2026; sumber di kolom temuan.

| # | Butir | Bisa? | Temuan (file:baris / docs) | Tindakan |
|---|---|---|---|---|
| C1 | Supabase tetap aktif tanpa monitor eksternal | Ya, kemungkinan besar | Retensi harian menulis `ops_heartbeat('cron')` paling dulu (`retention.ts:90-92`); cron notifikasi tiap jam menjalankan `update family_links …` (`notifications.ts:59-63`) lewat Hyperdrive tanpa cache (`wrangler.jsonc` blok `hyperdrive`). Docs Supabase: "Typically a few user requests to the database each day over the previous week is enough", peringatan email ±1 minggu sebelum pause, restore 1 tahun (per docs, 31 Okt 2026: supabase.com/docs/guides/platform/free-project-pausing). Apakah koneksi Hyperdrive dihitung sebagai "user requests" **belum terverifikasi** di docs | K1: cron tetap jalur utama; workflow harian `/healthz/db` sebagai penulis kedua yang independen; DoD mencatat proyek tidak pernah dapat email peringatan |
| C2 | Self-ping Worker lewat Cron Trigger | Tidak berguna | Cron sudah bisa menulis DB langsung (C1); self-ping tidak bisa memberi tahu kalau Worker/cron sendiri mati. Perilaku `fetch` Worker ke URL `workers.dev`-nya sendiri **belum terverifikasi** dan tidak dibutuhkan | Ditolak (K1) |
| C3 | GitHub Actions terjadwal | Ya | Interval minimum 5 menit; bisa tertunda saat beban tinggi (terutama awal jam); hanya di default branch; repo publik: dinonaktifkan otomatis setelah 60 hari tanpa aktivitas repo; notifikasi dikirim ke "the user who last modified the cron syntax" (per docs, 31 Okt 2026: docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows). Preseden: `public-blocklist.yml:7-8` (cron 6 jam, skip sampai `vars.*` diisi `:21`) | K1, K7. Menit ganjil (bukan `:00`) |
| C4 | Kepemilikan `.github/workflows/` | Usulan ke Umar | `.github/` tidak ada di tabel owner `CLAUDE.md`; workflow pertama dipindah Umar (#38/#48); Alief menulis `testflight.yml` lewat PR #174 yang menunggu review Umar; secret repo/environment hanya bisa diisi admin (Umar, #38) | Issue K7; logika di `backend/ci/ops-watch.mjs` (folder Alief), workflow tipis |
| C5 | Repo publik → log Actions + issue publik | Ya, batasi isi | Repo publik (#173 "Repo publik, jadi menit runner macOS gratis"). Log run, job summary, dan issue terbaca siapa saja | K6: hanya kode cek (mis. `retention_failed`), tanpa angka sensitif, tanpa URL, tanpa body respons |
| C6 | Workers Logs Free | Ya, terbatas | `observability.enabled = true`, `invocation_logs: false` (`wrangler.jsonc:11`). Free: 200 000 event/hari, retensi 3 hari; field JSON diindeks dan bisa difilter (per docs, 31 Okt 2026: developers.cloudflare.com/workers/observability/logs/workers-logs/). Query Builder tersedia untuk semua developer (developers.cloudflare.com/workers/observability/query-builder/). Mulai **1 Des 2026**: Free 0,5 GB/hari, retensi 7 hari (blog Cloudflare 2 Okt 2026, blog.cloudflare.com/one-observability-platform/) | Dipakai untuk investigasi manual; bukan jalur alert utama |
| C7 | Alert berbasis log Cloudflare | Belum terverifikasi | Blog 2 Okt 2026: "custom alerts … now in beta", contoh "Worker errors increase after a deployment", kanal webhook/chat/incident tool; "Webhooks are now available on all plans". Plan yang mendapat custom alert **tidak disebut** | LANGKAH MANUAL 5 (spike dashboard). Kalau tersedia di Free: tambahan opsional untuk `replica_dropped` per alasan (K5) |
| C8 | Notifikasi Cloudflare di Free | Sebagian | Halaman notifikasi: "Usage Based Billing" untuk akun Pay-as-you-go; tidak ada jenis notifikasi khusus Workers/R2/Cron (per docs, 31 Okt 2026: developers.cloudflare.com/notifications/notification-available/). Faktanya notifikasi "Shoo R2 storage above 5 GB" sudah dibuat 29 Okt (`log/fase-18.md:26`): akun sudah PAYG karena langganan R2 | LANGKAH MANUAL 2: tambah Class A dan Class B dengan cara yang sama |
| C9 | Metrik Worker tanpa invocation log | Ya | Dataset GraphQL `workersInvocationsAdaptive`: `sum { requests errors subrequests }`, `quantiles { cpuTimeP50 cpuTimeP99 }`, `dimensions { status scriptName datetime }` (developers.cloudflare.com/analytics/graphql-api/tutorials/querying-workers-metrics/); status `success`, `clientDisconnected`, `scriptThrewException`, `exceededResources`, `internalError`; metrik disimpan ±3 bulan (developers.cloudflare.com/workers/observability/metrics-and-analytics/). Token: Account → Account Analytics → Read (…/graphql-api/getting-started/authentication/api-token-auth/). Ketersediaan GraphQL di Free **tidak disebut** di docs; apakah invocation Cron masuk dataset ini **belum terverifikasi** | LANGKAH MANUAL 4 (spike satu `curl` + introspeksi) sebelum 21b memakai angka ini |
| C10 | Metrik R2 | Ya | `r2OperationsAdaptiveGroups` (`actionType`, `actionStatus`, `bucketName`, **`objectName`**, `sum { requests }`) dan `r2StorageAdaptiveGroups` (`payloadSize`, `objectCount`) (developers.cloudflare.com/r2/platform/metrics-analytics/). Class A = `PutObject`, `ListObjects`, `CopyObject`, `CreateMultipartUpload`, …; Class B = `GetObject`, `HeadObject`, …; `DeleteObject` gratis; Free 10 GB-bulan, 1 jt A, 10 jt B (developers.cloudflare.com/r2/pricing/) | Query **tidak pernah** memilih `objectName` (kunci = `<owner>/<scan>-replica.html.gz`, berisi id device; P6). Kelompokkan per `actionType` saja |
| C11 | Ukuran DB dari Worker | Ya, diverifikasi di test 21a | `pg_database_size(current_database())` cukup dengan hak CONNECT; `shoo_api` sudah login ke DB (`init.sql:177`). README sudah memakainya sebagai cek manual (`backend/README.md` bagian Quota) | Test 21a memanggilnya sebagai `shoo_api` |
| C12 | Supabase Storage + egress dari Worker/CI | Tidak | Egress hanya di dashboard; Management API butuh access token, dan #68 memutuskan CI tanpa access token Supabase (`backend.yml:72-73`). Storage kosong setelah fase 20 | D11: checklist mingguan manual (K4) |
| C13 | Status cron yang bisa dibaca | Perlu tabel baru | `ops_heartbeat.source` hanya boleh `'cron'`/`'healthz'` (`init.sql:98-101`); `'cron'` ditulis **di awal** retensi (`retention.ts:90-92`), jadi tidak membuktikan run sukses. Notifikasi tidak menulis apa pun ke ops | K2: tabel `ops_jobs` |
| C14 | Antrean blocklist (D9) | Ya | Antrean = `approved_at is null and rejected_at is null and removed_at is null and families > 0` (`ref/R2-skema-db.md:187` + `20261025100000_blocklist_rejected.sql:1-15`) | `/ops/status` memberi jumlah + umur tertua (jam), tanpa domain |
| C15 | Janji hapus (P13) terukur | Ya | Retensi menghapus `created_at < now() - 14 days` (`retention.ts:162,229`), index `scans_created` (`init.sql:67`); README: "`select count(*) from scans where created_at < now() - interval '15 days';` should be 0". Tombstone yang gagal dihapus tetap di `storage_tombstones` (`security_review.sql:29-35`) | Cek `retention_overdue` (scan > 15 hari) dan `tombstones_stuck` (tombstone > 2 hari) |
| C16 | Error 500 dari Worker | Ya, lewat GraphQL | `onError` → 500 `internal` (`app.ts:81-87`) tercatat di `errors`/status `scriptThrewException`? **Belum terverifikasi**: 500 dari `onError` adalah respons normal Hono, jadi kemungkinan status `success`. Persentase 5xx per route tidak ada di GraphQL Workers tanpa invocation log | 21b memakai `errors` + `exceededResources` dari GraphQL; 5xx `onError` dicari di Query Builder (`route` + `error.name`) saat investigasi. LANGKAH MANUAL 4 memastikan apa yang dihitung `errors` |
| C17 | `wrangler tail` | Ya | Tail menampilkan `outcome` per invocation (dipakai 31 Okt); output memuat URL lengkap (id scan, signature link) | Hanya ad-hoc di terminal Alief; jangan tempel output ke issue/log/PR (K6) |
| C18 | App: crash/hang | Ya, tanpa kode | `MXDiagnosticPayload` (crash, hang, CPU, disk write, launch) iOS 14+, **deprecated iOS 27.2: "Use DiagnosticReport instead"** (developer.apple.com/tutorials/data/documentation/metrickit/mxdiagnosticpayload.json, 31 Okt 2026). Crash tester TestFlight masuk App Store Connect (TestFlight → Feedback → Crashes, unduh 120 hari) dan Xcode Organizer (developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback/). "Collect" = dikirim keluar device dan bisa diakses developer (developer.apple.com/app-store/app-privacy-details/); data yang dikumpulkan Apple tidak perlu kita deklarasikan. App tanpa MetricKit (`grep -rl MetricKit ios/` = 0) | K8: tidak ada MetricKit/upload; privacy manifest (`ios/ShooApp/PrivacyInfo.xcprivacy`) tidak berubah |
| C19 | Monitor pihak ketiga | Ya, butuh akun baru | UptimeRobot Free: 50 monitor, interval 5 menit, keyword monitor, boleh komersial; header kustom di Free tidak terkonfirmasi (uptimerobot.com/pricing, 31 Okt 2026). Better Stack Free: 10 monitor & heartbeat, email + Slack (betterstack.com/pricing) | Cadangan saja (K1) kalau Umar menolak workflow |
| C20 | Kuota Cron Trigger | Ya | 2 dari 5 dipakai (`wrangler.jsonc:48`, ARCHITECTURE §3) | Fase 21 tidak menambah Cron Trigger |

## Peta dampak (semua sisi)

| Sisi | File / tempat | Jenis | Sub-fase | Catatan |
|---|---|---|---|---|
| DB | `migrations/<ts>_ops_jobs.sql` | Baru | 21a | Tabel `ops_jobs` (K2), grant `select, insert, update` (tanpa `delete`) ke `shoo_api`, revoke dari `anon, authenticated, service_role`, RLS + policy (pola `security_review.sql:36-40`). Add-only: Worker lama tidak menyentuhnya |
| DB test | `tests/ops_jobs.test.sql` baru; `grants.test.sql` (`table_privs_are` sendiri SELECT/INSERT/UPDATE, bukan daftar CRUD `:13-16`; `ops_jobs` di daftar `:23-27`), `schema.test.sql:10` | Baru / Ganti | 21a | Tabel ada, check `job`, grant, RLS, anon/authenticated tanpa hak |
| Backend | `src/cron/retention.ts` | Ganti | 21a | `startJob('retention')` setelah heartbeat; `finishJob` di akhir dengan `failed`, `backlog` (sebelum `throw`, `:141-142`) |
| Backend | `src/cron/notifications.ts` | Ganti | 21a | `finishJob('notifications')` setelah kirim; gagal tulis ops di-log `ops_job_write_failed`, tidak menggagalkan push |
| Backend | `src/db/repo/ops.ts` (baru) | Baru | 21a | `startJob`, `finishJob`, `opsSnapshot` (satu round trip, angka saja) |
| Backend | `src/services/opsStatus.ts` (baru) | Baru | 21a/21c | Ambang (K3) → `{ ok, failing: [{code, level}], numbers }`; fungsi murni, mudah dites |
| Backend | `src/routes/ops.ts` (baru), `src/app.ts:65-77` | Baru / Ganti | 21a | `GET /ops/status`; token `OPS_STATUS_TOKEN` (K6) |
| Backend | `src/env.ts`, `test/env.d.ts`, `src/http/rateLimit.ts` | Ganti | 21a | `OPS_STATUS_TOKEN?: string` (di kedua deklarasi `Env`); limit `opsStatus` key `"all"` 30/jam, dihitung hanya setelah token cocok (K6) |
| Backend | `vitest.config.ts:31-36`, `.dev.vars.example` | Ganti | 21a | Binding test `OPS_STATUS_TOKEN`; contoh lokal kosong |
| Backend | `src/services/opsStatus.ts` + `replicaUsage` fase 19 | Ganti | 21c | `replica_full` / `replica_reserve` / `replica_family_cap` |
| Test | `test/ops-status.test.ts` (baru), `test/retention.test.ts`, `test/log-hygiene.test.ts`, `test/security-headers.test.ts`, `test/cache-headers.test.ts` | Baru / Ganti | 21a | Lihat Langkah kerja |
| CI (Alief) | `backend/ci/ops-watch.mjs`, `backend/ci/ops-watch.test.mjs`, `backend/ci/README.md` | Baru / Ganti | 21b | Node 24, tanpa dependency (`fetch` bawaan), `node --test` |
| CI (Umar) | `.github/workflows/ops-watch.yml` | Usulan (PR Alief, merge Umar) | 21b | Jadwal K1; `permissions: { contents: read, issues: write }`; environment `ops`; skip sampai `vars.OPS_WATCH_ENABLED == 'true'` (pola `public-blocklist.yml:21`) |
| CI (Umar) | `.github/workflows/backend.yml:41-43` | Usulan (opsional) | 21b | Satu step `node --test backend/ci/` di job `test` |
| App | — | Tidak ada kode | — | K8: crash dari Organizer/TestFlight. `PrivacyInfo.xcprivacy` + label P2 tidak berubah |
| Extension / kontrak | — | Tidak ada | — | `/ops/status` bukan endpoint klien, tidak masuk `contracts/` (`/healthz` juga tidak ada di `contracts/api.md`) |
| Privasi | Respons `/ops/status`, issue `ops-alert`, log Actions | — | 21a/21b | Angka agregat + kode cek saja; tanpa id, domain, nama, path, IP, URL (P6). Token tidak pernah di URL |
| Biaya Free | Workers, Hyperdrive, Actions | — | — | 96 run/hari × 1 request `/ops/status` + 96 `/healthz` + 1 `/healthz/db` ≈ 200 request Worker/hari (0,2 % dari 100k). `opsSnapshot` ≈ 1 query gabungan. Actions di repo publik gratis |
| Dokumen | `backend/README.md` (bagian baru "Monitoring and alerts" = runbook), `backend/API.md` (`GET /ops/status`), `plan/alief/ref/R3-catatan-api.md` §7 (env `OPS_STATUS_TOKEN`; README Env merujuk ke sana), `plan/alief/log/fase-21.md` | Baru / Ganti | 21a/21b | TODO/PROGRESS di-update saat eksekusi, bukan di plan ini |

## Keputusan

**K1 — Uptime + keep-alive + kanal alert (rekomendasi: GitHub Actions; butuh jawaban Alief, lalu Umar lewat issue K7).**

| Opsi | Akun baru? | Bisa memberi tahu kalau Worker mati? | Anti-pause | Minus |
|---|---|---|---|---|
| A. Workflow terjadwal `ops-watch.yml` | Tidak | Ya (runner di luar Cloudflare) | Ya, `/healthz/db` harian | `.github/` milik Umar; jadwal bisa telat; mati sendiri setelah 60 hari repo sepi; repo publik (K6) |
| B. Cron Worker self-ping | Tidak | Tidak (yang mati tidak bisa melapor) | Sudah terjadi tanpa self-ping (C1) | Tidak menambah apa pun |
| C. UptimeRobot / Better Stack | Ya (manual) | Ya, email | Ya, kalau memanggil `/healthz/db` | Akun pihak ketiga; header token di Free tidak pasti → hanya `/healthz` publik, tanpa cek cron |

Rekomendasi **A**, jadwal: `7,22,37,52 * * * *` (uptime `/healthz` dengan 3 percobaan berjarak 20 s, lalu `/ops/status`) dan `41 20 * * *` (20:41 UTC = 04:41 WITA, ±1,5 jam setelah retensi 19:00 UTC: `/healthz/db` + GraphQL Cloudflare + ringkasan harian). Kanal: satu issue terbuka berlabel `ops-alert`, di-assign `aliefauzan`; dibuat kalau ada kode level `alert`, di-comment hanya kalau himpunan kode berubah, ditutup otomatis setelah 2 run hijau berturut-turut. Alasan: tanpa akun baru, logika tetap di repo (bisa dites), email lewat notifikasi GitHub ke assignee. C hanya cadangan kalau Umar menolak A. Keep-alive utama tetap cron Worker (C1); A adalah penulis kedua yang independen.

**K2 — Tempat status cron (rekomendasi: tabel baru `ops_jobs`).**
```sql
create table ops_jobs (
  job        text primary key check (job in ('retention', 'notifications')),
  started_at timestamptz,
  ok_at      timestamptz,             -- akhir run terakhir yang failed = 0
  failed     int not null default 0,  -- jumlah langkah gagal di run terakhir
  backlog    boolean not null default false,
  finished_at timestamptz
);
```
`ops_heartbeat` tidak diubah (jalur anti-pause tetap persis seperti sekarang, `retention.ts:90-92`). Alternatif ditolak: memperluas check `ops_heartbeat.source` (tidak bisa menyimpan `failed`/`backlog`); membaca Workers Logs dari CI (butuh token log + retensi 3 hari + tidak ada API stabil yang terverifikasi). Gerbang fase 20 jadi satu query: `select failed, finished_at from ops_jobs where job = 'retention'`.

**K3 — Kode cek dan ambang (dihitung di `services/opsStatus.ts`, dipaku test; butuh jawaban Alief untuk angka).**

| Kode | Level | Kondisi | Sumber |
|---|---|---|---|
| `retention_stale` | alert | `ops_jobs.retention.ok_at` null atau < now − 26 jam | `ops_jobs` |
| `retention_failed` | alert | run terakhir `failed > 0` | `ops_jobs` |
| `retention_backlog` | warn | `backlog = true` | `ops_jobs` |
| `retention_overdue` | alert | ada scan `created_at < now() - interval '15 days 6 hours'` (`exists`, index `scans_created`; margin 6 jam supaya Cron 19:00 yang telat tidak memicu alert palsu) | `scans` |
| `tombstones_stuck` | warn | tombstone `created_at < now() - 2 days` > 0 | `storage_tombstones` |
| `notifications_stale` | alert | `ok_at` < now − 2 jam 15 menit (cron tiap jam `:05`) | `ops_jobs` |
| `db_size_high` | warn ≥ 350 MB, alert ≥ 450 MB | `pg_database_size` (Free 500 MB) | Postgres |
| `blocklist_queue` | warn | antrean > 0 dan tertua > 24 jam (D9) | `blocklist_entries` |
| `replica_reserve` / `replica_full` | warn / alert | gauge fase 19 `level` = `reserve` / `full` (K5.2 fase 19: `full` = replica ukuran maksimal tidak muat lagi di kuota global, `uploads ≥ Q.global` atau `bytes + M > Q.globalBytes`; drop `global_*` mungkin, bukan bukti drop) | `replicaUsage` fase 19 (21c) |
| `replica_family_cap` | warn | `familiesAtCap ≥ 3` dalam 24 jam | `replicaUsage` fase 19 (21c) |

Dicek oleh workflow (GraphQL, 24 jam terakhir, skrip 21b): `worker_exceeded_cpu` alert kalau status `exceededResources` > 0; `worker_errors` alert kalau `errors/requests > 1 %` dengan ≥ 50 request; `worker_requests_high` warn ≥ 80 000/hari (Free 100k); `r2_class_a_high` warn ≥ 500 000 bulan berjalan; `r2_class_b_high` warn ≥ 5 000 000; `r2_storage_high` warn ≥ 5 GB (dobel dengan notifikasi Cloudflare). Uptime: `healthz_down` alert kalau 3 percobaan gagal; `ops_status_unreachable` alert kalau `/ops/status` bukan 200; `healthz_db_failed` alert kalau `/healthz/db` harian bukan 200. `warn` hanya masuk ringkasan harian, tidak membuka issue.

Aturan fase 19 K5.1 "`reserve`/`family_*` > 20 per jam" butuh hitungan log per alasan: hanya bisa lewat alert Cloudflare (C7, belum terverifikasi). Gantinya dari DB: `replica_family_cap` dan `replica_reserve`. `screenshot_dropped`/`screenshot_ignored` sengaja tidak dipakai (`fase-20-screenshot-sunset.md:326`).

**K4 — Biaya/pemakaian (D11): otomatis sebagian, checklist sisanya.** Otomatis harian: DB size (`/ops/status`), request Worker, R2 Class A/B + storage (GraphQL). Manual Senin (log fase aktif): Supabase Usage (Storage, egress ambang 3,5 GB, DB) + Cloudflare R2 Metrics. Notifikasi billing Cloudflare: R2 storage > 5 GB (ada), tambah Class A > 500 000 dan Class B > 5 000 000 (LANGKAH MANUAL 2). Supabase Free tidak menagih overage; lewat kuota → email + masa tenggang, lalu request 402 (docs Billing FAQ, supabase.com/docs/guides/platform/billing-faq, 31 Okt 2026); `db_size_high` memberi tahu lebih dulu.

**K5 — Ringkasan harian (D9 + D11).** Run `41 20 * * *` menulis job summary Actions berisi kode + level saja (K6) dan baris "antrean blocklist: ada/tidak". Angka persis dibaca Alief sendiri: `curl -H "Authorization: Bearer $OPS_STATUS_TOKEN" …/ops/status` dari Mac (token dari password manager). D9 tetap review manual di SQL editor (query `ref/R2-skema-db.md:187` + `rejected_at is null`); fase 21 hanya membuatnya terlihat.

**K6 — Privasi dan akses (rekomendasi: token header, isi minimum; butuh jawaban Alief).**
- `GET /ops/status` hanya dengan `Authorization: Bearer <OPS_STATUS_TOKEN>` (secret Worker ≥ 32 karakter, `wrangler secret put`; dibandingkan constant-time: SHA-256 kedua sisi lalu `crypto.subtle.timingSafeEqual`, karena `src/` belum punya helper). Secret kosong/pendek atau token salah → 404 `not_found` (endpoint tidak terlihat) **tanpa query DB** (klien `sql` lazy, `app.ts:32,44`). Rate limit `"all"` 30/jam baru dihitung setelah token cocok: kalau dihitung dulu, siapa saja bisa menghabiskan 30 slot dan membutakan workflow (429 → `ops_status_unreachable` palsu). Tidak pernah token di query string.
- Respons: angka agregat + `failing[]`; tanpa id, domain, path, nama, IP, URL. `Cache-Control: private, no-store` sudah global (`app.ts:30`).
- Repo publik: skrip tidak mencetak body respons; issue/job summary hanya berisi kode cek, level, dan waktu UTC. Angka (DB size, jumlah antrean, request) tidak ditulis ke issue. Alternatif: tulis angka juga (lebih praktis, membocorkan kondisi operasional ke publik). Rekomendasi: kode saja.
- Token CI: `OPS_STATUS_TOKEN` + `CF_ANALYTICS_TOKEN` (hanya Account Analytics Read, satu akun) di GitHub Environment `ops` yang dikunci ke `main`, bukan `production` (yang memegang `SUPABASE_DB_URL` deploy). Alternatif ditolak: workflow langsung ke DB dengan `SUPABASE_DB_URL` (kredensial owner DB di job terjadwal yang tidak perlu).

**K7 — Issue ke Umar (wajib sebelum 21b).** Judul: `B9: workflow ops-watch terjadwal + environment ops`, template question, assign @umarmuhdhor. Pertanyaan bernomor:
1. Boleh Alief menulis `.github/workflows/ops-watch.yml` lewat PR (pola #174), logika di `backend/ci/ops-watch.mjs`?
2. Umar membuat Environment `ops` (branch `main`) dan mengisi `OPS_STATUS_TOKEN`, `CF_ANALYTICS_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` (nilai dari Alief lewat password manager, seperti #38), plus variable `OPS_WATCH_ENABLED=true`?
3. Issue publik berlabel `ops-alert` (isi kode saja) boleh sebagai kanal alert?
4. Boleh `backend.yml` menjalankan `node --test backend/ci/` di job `test`?
5. Workflow `public-blocklist.yml` (milik Umar) gagal → email ke Umar sendiri (C3). Perlu ikut dicek `ops-watch`, atau cukup notifikasi GitHub ke Umar?
Sampai dijawab: 21a tetap jalan (endpoint berguna dipanggil manual); keep-alive dari cron Worker (C1); Alief menjalankan `curl /ops/status` sendiri tiap pagi dan mencatat di log fase aktif.

**K8 — App: crash/hang (rekomendasi: tanpa kode).** Pakai App Store Connect → TestFlight → Crashes dan Xcode Organizer → Crashes (data dikumpulkan Apple, tester TestFlight). Tidak ada MetricKit: API payload-nya deprecated di iOS 27.2 (C18), dan mengirim diagnostik ke backend = "collect" `NSPrivacyCollectedDataTypeCrashData`/`PerformanceData` → ubah `PrivacyInfo.xcprivacy` + label P2 + data baru di server. Menyimpan payload hanya lokal tidak berguna (tidak ada yang membacanya). Crash extension (milik Umar) diharapkan muncul di Organizer yang sama (**belum terverifikasi**). Ditinjau ulang hanya kalau TestFlight tidak cukup setelah rilis publik.

**K9 — Penerima alert.** Alief (assignee issue `ops-alert`, pemilik backend). Umar: tidak di-assign; di-mention manual di issue hanya kalau runbook bilang penyebabnya di CI/extension/`ai/`. Email Supabase (pause, kuota) dan Cloudflare (billing) ke pemilik akun masing-masing (LANGKAH MANUAL 3 mencatat siapa).

## Output

- Migrasi `backend/db/supabase/migrations/<ts>_ops_jobs.sql` (`set local lock_timeout = '5s'`): tabel K2, `grant select, insert, update on ops_jobs to shoo_api`, RLS + policy `shoo_api_all`, `revoke all … from anon, authenticated, service_role` (pola `security_review.sql:36-40`).
- pgTAP `tests/ops_jobs.test.sql`; `grants.test.sql` + `schema.test.sql` menyebut `ops_jobs` (plan count disesuaikan).
- `src/db/repo/ops.ts`: `startJob(sql, job)`, `finishJob(sql, job, {failed, backlog})`, `opsSnapshot(sql)` → `{ jobs, scansOverdue: boolean, tombstonesStuck: number, dbBytes: number, blocklistQueue: number, blocklistOldestHours: number | null, healthzAgeHours: number | null }` (umur `ops_heartbeat.healthz`, angka saja, bukan alert).
- `src/services/opsStatus.ts`: `evaluate(snapshot, now)` → `{ ok: boolean, failing: {code, level}[] }` (K3).
- `src/routes/ops.ts`: `GET /ops/status` → 200 `{ ok, failing, jobs: {retention:{ageHours, failed, backlog}, notifications:{ageHours}}, dbBytes, blocklistQueue, blocklistOldestHours, tombstonesStuck, healthzAgeHours }`; 404 tanpa/ salah token (tanpa query DB); 429 lewat limit (hanya dengan token benar).
- `src/cron/retention.ts`, `src/cron/notifications.ts`: tulis `ops_jobs`; opsi test `ops?` (penulis palsu) di `RetentionOptions` dan `opts` notifikasi. Retensi: gagal tulis = `retention_step_failed` dengan `step: "ops_start"`/`"ops_finish"`; notifikasi: event baru `ops_job_write_failed` (`{event, job, error: errorInfo}`).
- `env.ts` + `test/env.d.ts` `OPS_STATUS_TOKEN?`; `rateLimit.ts` `opsStatus: { bucket: "ops_status", max: 30, windowSeconds: 3600 }` (dipanggil setelah token cocok); `vitest.config.ts`; `.dev.vars.example`.
- Test: `test/ops-status.test.ts` (baru), perubahan `retention.test.ts`, `log-hygiene.test.ts`, `security-headers.test.ts`, `cache-headers.test.ts`.
- 21b: `backend/ci/ops-watch.mjs` (mode `--quick` dan `--daily`), `backend/ci/ops-watch.test.mjs`, `backend/ci/README.md` (bagian ops-watch); PR usulan `.github/workflows/ops-watch.yml`.
- 21c: `opsStatus.ts` + `ops.ts` memakai `replicaUsage` fase 19; test baru di `ops-status.test.ts`.
- Dokumen: `backend/README.md` "## Monitoring and alerts" (runbook di bawah), `backend/API.md` `GET /ops/status`, `plan/alief/log/fase-21.md`.

Runbook (masuk `backend/README.md`, Inggris seperti file itu; isi inti):

| Kode | Langkah pertama | Langkah berikutnya |
|---|---|---|
| `healthz_down` / `ops_status_unreachable` | Buka `https://shoo-api.afindo-mi01.workers.dev/healthz`; dashboard Workers → Deployments | Deploy terakhir rusak → `npx wrangler rollback`, lalu fix maju lewat PR (bagian Rollback). Cloudflare down → tunggu, catat |
| `retention_failed` / `retention_stale` | Query Builder: `event = retention_step_failed` (field `step`, `error.name`, `error.code`) | Reproduksi lokal (`wrangler dev --test-scheduled` + trigger README bagian Retention), perbaiki lewat PR; jangan jalankan retensi cloud manual dari Mac, run berikutnya 19:00 UTC. Fase 20 menunggu run `failed: 0` |
| `retention_overdue` / `retention_backlog` | SQL editor: `select count(*) from scans where created_at < now() - interval '15 days'` | Backlog lebih dari 2 hari → naikkan chunk/anggaran lewat PR (P13 terlanggar selama ada) |
| `tombstones_stuck` | Query Builder: `screenshots_delete_failed`, `replica_clear_failed` | Cek binding R2 / kunci Supabase (sebelum fase 20) |
| `notifications_stale` | Query Builder: `push_failed`, `push_config_incomplete`; Cron Events di dashboard Worker | Fix lewat PR |
| `worker_exceeded_cpu` / `worker_errors` | Dashboard Workers → Metrics; Query Builder `error.name`, `route` | `wrangler tail --status error` (jangan menyalin URL dari output) |
| `db_size_high` | `select relname, pg_size_pretty(pg_total_relation_size(oid)) from pg_class order by pg_total_relation_size(oid) desc limit 10` | Biasanya `rate_limit_hits`/`scans`: cek retensi dulu |
| `replica_full` / `replica_reserve` / `replica_family_cap` | Query Builder: `event = replica_dropped` per `reason`; gauge `replica_quota_usage` | Serangan → kill-switch `REPLICAS_ENABLED=false` lewat PR (bagian Kill-switch); issue ke Umar soal App Attest (fase 19 K8) |
| `blocklist_queue` | Review di SQL editor (D9) | Catat disetujui/ditolak di log fase aktif |
| `r2_*`, `worker_requests_high` | Dashboard R2 Metrics / Workers | Cari sumber; turunkan kuota lewat PR |

## Langkah kerja

### 21a — backend (`feat/B9-ops-status`)

1. **Merah — DB.** `tests/ops_jobs.test.sql`: `has_table`, check `job` menolak `'x'`, grant `shoo_api` SELECT/INSERT/UPDATE saja, anon/authenticated tanpa hak, RLS aktif. Update `grants.test.sql`, `schema.test.sql`. `supabase test db` → merah.
2. **Hijau — migrasi** `<ts>_ops_jobs.sql` (K2). `supabase db reset && supabase test db` → hijau.
3. **Merah — cron.** `retention.test.ts`: run sukses → `ops_jobs.retention` `failed = 0`, `ok_at` baru, `backlog` sesuai; satu langkah gagal (store palsu melempar) → `failed = 1`, `ok_at` tidak berubah, `finished_at` baru, error tetap dilempar; opsi test `ops` yang melempar (pola `store?`/`r2Store?`, `retention.ts:61-64`; tidak men-drop/mengunci tabel: test jalan sebagai `shoo_api` tanpa DDL, `lock_timeout` 5 s di `hardening.sql:7`) → retensi tetap menjalankan langkah lain dan log `retention_step_failed` `step: "ops_finish"`. Notifikasi: run → `ops_jobs.notifications.ok_at` baru; `opts.ops` melempar → push tetap terkirim, log `ops_job_write_failed`.
4. **Hijau — `db/repo/ops.ts` + panggilan di `retention.ts` (setelah `heartbeat`, dan sebelum `console.log` `:141`, dengan `failed` = `errors.length` sebelum langkah itu) dan `notifications.ts` (sebelum `:49`).** Tulis `ops_jobs` di dalam `step(...)` sendiri supaya gagal tulis = satu langkah gagal biasa (retensi) / try-catch (notifikasi).
5. **Merah — evaluasi.** `ops-status.test.ts` bagian unit `evaluate`: tiap kode K3 di tepi ambang (26 jam − 1 menit vs + 1 menit, 350/450 MB, antrean 24 jam, dst.), `ok = false` hanya kalau ada `alert`.
6. **Hijau — `services/opsStatus.ts`.**
7. **Merah — route.** `ops-status.test.ts` bagian HTTP: tanpa header → 404 bentuk kontrak error; token salah → 404; secret kosong atau < 32 karakter → 404 walau header cocok (env di-override per request: `app.fetch(req, { ...env, OPS_STATUS_TOKEN: "" }, ctx)`, pola `test/replicas.test.ts:243`); token benar → 200 dengan field Output; respons tidak memuat UUID, domain, path (`/[0-9a-f-]{36}/`, `.example`, `replica.html.gz`); `pg_database_size` jalan sebagai `shoo_api` (C11); 31 panggilan dengan token benar → 429; 40 panggilan token salah → tetap 404 dan tidak menambah baris `rate_limit_hits` bucket `ops_status`; header keamanan + `Cache-Control: private, no-store`.
8. **Hijau — `routes/ops.ts`, `app.ts`, `env.ts`, `rateLimit.ts`, `vitest.config.ts`, `.dev.vars.example`.**
9. `log-hygiene.test.ts`: alur penuh + `/ops/status` + retensi → tidak ada token ops, id, domain di log.
10. `EXPLAIN` lokal untuk `opsSnapshot` dengan data `db/scripts/quota-estimate.sql`: `scans_created` dipakai untuk `exists`, tanpa seq scan `scans`. Catat di log.
11. Dokumen: `backend/README.md` (Monitoring and alerts + runbook + `OPS_STATUS_TOKEN` di tabel Env), `backend/API.md`.
12. `pnpm -C backend/api typecheck && pnpm -C backend/api test`, `supabase test db`, review berurutan (Model), PR, reviewer @umarmuhdhor.

### 21b — skrip + workflow (`feat/B9-ops-watch`, setelah K7 dijawab dan LANGKAH MANUAL 4 selesai)

1. **Merah — `ops-watch.test.mjs`** (`node:test`, `fetch` dipalsukan): `--quick` → `healthz_down` setelah 3 gagal, `ops_status_unreachable` untuk non-200, kode dari `failing[]` diteruskan; `--daily` → kode K3 GraphQL di tepi ambang; query R2 **tidak** memuat `objectName` (assert pada string query); output stdout hanya kode/level, tidak ada angka, URL, atau token; logika issue: buat kalau ada `alert` dan tidak ada issue terbuka, comment hanya kalau himpunan kode berubah, tutup setelah 2 run hijau (state = label + comment terakhir, lewat `gh` CLI yang dipalsukan).
2. **Hijau — `ops-watch.mjs`** (Node 24, tanpa dependency; `gh` CLI bawaan runner untuk issue; `gh label create ops-alert --force` sebelum membuat issue; input `simulate` dibaca dari env dan hanya diterima kalau ada di daftar kode K3).
3. `node --test backend/ci/` hijau. `backend/ci/README.md` bagian ops-watch.
4. PR berisi `.github/workflows/ops-watch.yml` (jadwal K1, `concurrency: ops-watch`, `timeout-minutes: 5`, `permissions: contents: read, issues: write`, `environment: ops`, `if: vars.OPS_WATCH_ENABLED == 'true'`, action di-pin SHA seperti `public-blocklist.yml:25-26`; `workflow_dispatch` input `simulate` diteruskan lewat `env:`, tidak pernah `${{ inputs.simulate }}` di dalam `run:`). Reviewer + merge: @umarmuhdhor.

### 21c — kuota replica (`feat/EX-07-ops-replica`, setelah fase 19 merge)

1. Merah: `ops-status.test.ts` — level `reserve`/`full`, `familiesAtCap` 2 vs 3, dari `replicaUsage` fase 19 tanpa id.
2. Hijau: `opsSnapshot` memanggil `replicaUsage(sql, REPLICA_QUOTA)` (tanda tangan fase 19, `fase-19-replica-quota.md:61`); `evaluate` menambah tiga kode K3. Runbook baris replica.

## LANGKAH MANUAL

- [ ] **1. (Alief, setelah 21a live)** Buat token: `openssl rand -base64 32` → simpan di password manager → dari `backend/api/`: `npx wrangler secret put OPS_STATUS_TOKEN` (di luar 18:30–19:30 UTC; perintah ini men-deploy versi baru dengan kode yang sama). Uji (token tidak diketik sebagai argumen, SECURITY §1): `read -rs OPS_STATUS_TOKEN` (tempel dari password manager), lalu `curl -s -H "Authorization: Bearer $OPS_STATUS_TOKEN" https://shoo-api.afindo-mi01.workers.dev/ops/status` → 200; tanpa header → 404. Catat hasil (tanpa token) di `log/fase-21.md`.
- [ ] **2. (Alief, D10 sisa)** Cloudflare dashboard → Notifications → Add → Usage Based Billing → R2 Class A operations, ambang 500 000, email pemilik akun; ulangi untuk Class B, ambang 5 000 000. Kalau produk R2 Class A/B tidak bisa dipilih: catat di log, `r2_class_*` dari 21b jadi satu-satunya penjaga. Centang D10 di TODO setelah ini.
- [ ] **3. (Alief)** Catat siapa pemilik email notifikasi: Supabase (Organization → Members, owner proyek `shoo-demo`; email pause/kuota) dan Cloudflare (billing). Kalau bukan Alief, minta pemiliknya meneruskan email ke Alief (tanpa berbagi login).
- [ ] **4. (Alief, spike sebelum 21b)** Cloudflare → My Profile → API Tokens → Create Custom Token: hanya **Account → Account Analytics → Read**, akun Shoo saja, tanpa izin lain, kedaluwarsa 1 tahun. Dari Mac: satu `curl` POST `https://api.cloudflare.com/client/v4/graphql` dengan query `workersInvocationsAdaptive` (filter `scriptName: "shoo-api"`, 24 jam) dan `r2OperationsAdaptiveGroups` (dimensi `actionType` saja). Catat: (a) GraphQL jalan di Free, (b) nilai `status` yang muncul, (c) apakah invocation Cron ikut terhitung (cari dataset `workersInvocationsScheduled` lewat introspeksi kalau tidak), (d) apakah 500 dari `onError` masuk `errors` (C16). Kirim token ke Umar lewat password manager untuk Environment `ops` (K7).
- [ ] **5. (Alief, spike)** Dashboard Workers → Observability: ada menu Alerts (custom alert beta, C7) di akun Free? Kalau ada, buat satu alert uji untuk `event = replica_dropped` dengan `reason` `global_quota` atau `global_bytes` ≥ 1 per jam ke email Alief. Kalau tidak ada: catat "tidak tersedia di Free per 31 Okt", tidak ada tindakan.
- [ ] **6. (Umar, setelah K7)** Environment `ops` (branch `main`), 3 secret, variable `OPS_WATCH_ENABLED=true`, merge PR 21b. Lalu Actions → ops-watch → Run workflow (manual) sekali.
- [ ] **7. (Alief, TestFlight)** App Store Connect → TestFlight → grup tester → pastikan feedback tester aktif; Xcode → Window → Organizer → Crashes untuk app Shoo. Cek Senin bersama D11.
- [ ] **8. (Alief, setiap Senin, D11)** Supabase → Usage (Storage, egress, DB) + Cloudflare R2 → `shoo-replicas` → Metrics + Organizer Crashes. Catat angka di log fase aktif (repo, bukan issue publik).

## Verifikasi

```bash
pnpm -C backend/api typecheck
pnpm -C backend/api test                                   # termasuk ops-status, retention, log-hygiene
pnpm -C backend/api exec vitest run test/ops-status.test.ts
(cd backend/db && supabase db reset && supabase test db)   # ops_jobs, grants, schema
node --test backend/ci/                                    # 21b
(cd backend/api && npx wrangler deploy --dry-run --outdir /tmp/shoo-worker)
git grep -n "objectName" backend/ci/ops-watch.mjs         # 21b: 0 hasil (file test boleh memuatnya di assert)
```

1. Lokal (Supabase lokal jalan; `backend/api/.dev.vars` dari `.dev.vars.example` dengan `OPS_STATUS_TOKEN=` diisi `openssl rand -base64 32`, kosong = 404): terminal 1 `pnpm -C backend/api dev --test-scheduled`; terminal 2 `curl "http://localhost:8787/cdn-cgi/handler/scheduled?cron=0+19+*+*+*"` lalu `docker exec -i supabase_db_shoo psql -U postgres -c "select job, failed, backlog, ok_at, finished_at from ops_jobs"` → baris `retention` `failed = 0`.
2. Lokal: `export OPS_STATUS_TOKEN=$(sed -n 's/^OPS_STATUS_TOKEN=//p' backend/api/.dev.vars)`; `curl -s -H "Authorization: Bearer $OPS_STATUS_TOKEN" http://localhost:8787/ops/status` → `ok: true`; `docker exec -i supabase_db_shoo psql -U postgres -c "update ops_jobs set ok_at = now() - interval '2 days' where job = 'retention'"` → `curl` yang sama: `failing` memuat `retention_stale`.
3. Cloud (setelah LANGKAH MANUAL 1): `/ops/status` → 200; tanpa token → 404.
4. Cloud, pagi setelah run 19:00 UTC pertama sesudah deploy: `jobs.retention.failed = 0`, `ageHours` < 12.
5. Cloud: `/ops/status` satu jam setelah deploy → `jobs.notifications.ageHours` < 1,2.
6. Uji alert (setelah 21b): `gh workflow run ops-watch.yml -f simulate=retention_failed` (hanya mengubah evaluasi di skrip, tidak menyentuh backend) → issue `ops-alert` terbuka, di-assign Alief, isi hanya kode; dua run normal → issue tertutup. Email GitHub diterima Alief.
7. Log Actions run 6: tidak ada token, URL, angka DB, atau body JSON (baca manual).

## Kriteria selesai (DoD)

- [ ] `ops_jobs` di cloud; pgTAP hijau di CI.
- [ ] Retensi dan notifikasi menulis `ops_jobs`; gagal tulis tidak menggagalkan langkah lain (test).
- [ ] `GET /ops/status` 404 tanpa token yang benar, 200 dengan token; respons tanpa id/domain/path (test + `log-hygiene`).
- [ ] Semua kode K3 sisi backend dipaku test di tepi ambang.
- [ ] Runbook di `backend/README.md`; `backend/API.md` memuat `/ops/status`.
- [ ] Issue K7 dibuat dan dijawab; jawabannya ditautkan di `log/fase-21.md`.
- [ ] 21b merge; satu alert uji membuka dan menutup issue `ops-alert`; Alief menerima email.
- [ ] Notifikasi R2 Class A + Class B ada (atau dicatat tidak tersedia); D10 dicentang.
- [ ] 7 run `--daily` berturut-turut hijau di riwayat Actions (`/healthz/db` 200 tiap run), `healthzAgeHours` < 25 di `/ops/status` pada hari ke-7, dan tidak ada email peringatan pause dari Supabase.
- [ ] Hasil spike LANGKAH MANUAL 4 (GraphQL Free, status Cron, `errors`) dan 5 (custom alert) tercatat.
- [ ] 21c merge setelah fase 19 (atau dicatat ditunda dengan alasan).
- [ ] TODO B9, D9 (kanal terlihat), D11 (otomatis + checklist) diperbarui saat eksekusi.

## Risiko & rollback

- **Workflow terjadwal tidak jalan** (antrean GitHub penuh, repo sepi 60 hari) → alert hilang diam-diam. Mitigasi: cron Worker tetap menjaga Supabase (C1); run harian menulis `ops_heartbeat('healthz')`, jadi umurnya terlihat di `/ops/status` (`healthzAgeHours`, angka, bukan alert). Setelah proyek selesai, kehilangan monitor diterima.
- **Repo publik** memperlihatkan kode alert. Diterima dengan K6 (tanpa angka). Kalau Alief/Umar menolak, ganti kanal ke UptimeRobot/Better Stack (akun baru, keyword monitor pada `/ops/status` tidak bisa tanpa header → hanya `/healthz`), atau hanya email kegagalan workflow.
- **Token ops bocor** → hanya angka agregat yang terbaca; rotasi: `wrangler secret put OPS_STATUS_TOKEN` + update secret Environment `ops`. Tidak ada data pengguna di respons.
- **Tulis `ops_jobs` menambah titik gagal di cron** → dibungkus `step`/try-catch; retensi tetap menghapus data. Rollback: revert PR (tabel dibiarkan; migrasi hanya maju).
- **Ambang terlalu sensitif** (alert palsu) → angka di `opsStatus.ts` diubah lewat PR kecil; issue tertutup otomatis setelah 2 run hijau.
- **GraphQL tidak tersedia di Free / skema beda** (C9) → 21b tanpa bagian GraphQL; `worker_*` dan `r2_*` jatuh ke notifikasi Cloudflare + checklist Senin.
- **Perubahan harga Workers Logs 1 Des 2026** (0,5 GB/hari, 7 hari) → tidak memengaruhi alert (tidak bergantung pada log), hanya investigasi.
- Rollback umum: `npx wrangler rollback` untuk Worker; workflow dimatikan dengan variable `OPS_WATCH_ENABLED=false` (Umar) tanpa PR.

## Catatan handoff

- Fase 19 K5 tetap berlaku: jangan menambah field id ke `replica_dropped`/`replica_quota_usage`. Fase 21 membaca kuota dari DB (`replicaUsage`), bukan dari log, kecuali LANGKAH MANUAL 5 menemukan custom alert di Free.
- Fase 20: gerbang "satu run retensi `failed: 0`" bisa dibaca dari `/ops/status` (`jobs.retention.failed`, `ageHours`) setelah 21a live. Setelah 20b, `screenshots_delete_failed` diganti nama `objects_delete_failed` (fase 20 K5): runbook ikut diganti di PR 20b.
- Fase 24 K8 (`fase-24-privacy-data.md:98`) menulis hitungan `inactive_devices` "ikut `ops_jobs` lewat `RetentionResult`": `ops_jobs` (K2) hanya menyimpan `failed`/`backlog`, tanpa hitungan. Hitungan tetap di log; langkah fase 24 yang gagal masuk `failed` lewat `step`. Kalau fase 24 butuh hitungan di DB, kolom baru = migrasi fase 24.
- `app.onError` (`app.ts:85`) tidak punya field `event`. Kalau nanti dibutuhkan filter mudah, tambahkan `event: "unhandled_error"` di PR kecil terpisah (backend saja, dengan update `log-hygiene.test.ts`).
- `wrangler tail` dan Query Builder dipakai hanya oleh Alief di mesin sendiri. Jangan menempel output yang memuat URL (`/replicas/…?sig=`, `/j/<code>`) ke issue, PR, atau log plan.
- Biaya: tidak ada akun atau SDK baru di rekomendasi. UptimeRobot/Better Stack hanya cadangan dan butuh akun yang dibuat manusia.
- Hal yang belum terverifikasi: Hyperdrive dihitung aktivitas Supabase (C1); GraphQL di Free + status Cron + arti `errors` (C9, C16; LANGKAH MANUAL 4); custom alert di Free (C7; LANGKAH MANUAL 5); siapa penerima notifikasi workflow terjadwal setelah PR di-merge Umar (C3, mungkin Umar, karena itu kanal utama = issue ber-assignee); crash extension di Organizer (K8).

## Riwayat verifikasi

- Ronde 1 (31 Okt 2026): 20 temuan (0 kritis, 0 tinggi, 7 sedang, 13 rendah); diperbaiki: rate limit `/ops/status` dihitung setelah token cocok (sebelumnya siapa saja bisa menghabiskan 30 slot/jam dan membutakan workflow; token salah kini 404 tanpa query DB), grant `ops_jobs` seragam `select, insert, update` + `grants.test.sql` tanpa daftar CRUD, gauge `full` disamakan dengan fase 19 K5.2 (bukan bukti drop), test gagal-tulis `ops_jobs` lewat opsi `ops?` (bukan drop/lock tabel) dengan nama event per cron, `git grep objectName` hanya `ops-watch.mjs`, DoD anti-pause lewat riwayat run + `healthzAgeHours` (field ditambah ke Output), perintah persis Verifikasi 1–2/6; rendah: `test/env.d.ts`, `init.sql:177`, margin `retention_overdue` 15 hari 6 jam, `timingSafeEqual` atas SHA-256, token lewat `read -rs`, label `ops-alert` + `simulate` lewat `env:`, `replicaUsage(sql, REPLICA_QUOTA)`, `healthz_db_failed`, angka `wrangler tail` belum tercatat, runbook `retention_failed`, `R3` §7, catatan fase 24 K8; semua di baris yang sama, jadi rujukan `:19,76,131-132,215` dari fase 19/24 tetap tepat; dicatat tanpa diubah: tidak ada.
- Ronde 2 (31 Okt 2026): bagian yang diubah dibaca ulang; 1 temuan rendah (cara override env di test secret kosong/pendek), diperbaiki; 0 kritis/tinggi/sedang. Belum terverifikasi: Hyperdrive dihitung aktivitas Supabase (C1), GraphQL di Free + dataset Cron + arti `errors` (C9, C16; LANGKAH MANUAL 4), custom alert di Free (C7; LANGKAH MANUAL 5), penerima notifikasi workflow terjadwal setelah merge Umar (C3), crash extension di Organizer (K8).
