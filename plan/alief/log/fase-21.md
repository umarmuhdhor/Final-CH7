# Log fase 21 — Monitoring, alert, dan observability

- **Status:** [r] 21a — PR `feat/B9-ops-status` (lihat PR), reviewer @umarmuhdhor, **pending LANGKAH MANUAL 1–3** (setelah merge). 21b tertahan (workflow `.github/` milik Umar, pertanyaan di PR 21a). [r] 21c — PR `feat/EX-07-ops-replica` (stacked di #211 19a + #209 21a), **pending merge #209 + #211**, lalu LANGKAH MANUAL 1 21a.
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

## 21b — skrip + workflow (`feat/B9-ops-watch`, dari `origin/main` 7dc0caa)

- **Status:** [r] PR (lihat PROGRESS), reviewer @umarmuhdhor. Urutan dibalik atas instruksi Alief 9 Nov 2026: kode + workflow dulu, lalu satu issue ke Umar (K7) yang berisi PR + setup environment `ops`. Workflow tidak jalan sebelum `vars.OPS_WATCH_ENABLED == 'true'`.
- **Model:** Claude Opus 5.5, 9 Nov 2026.

### Checklist langkah

- [x] 1. Merah: `backend/ci/ops-watch.test.mjs` (`node:test`, `fetch`/`gh`/`sleep` palsu) → `ERR_MODULE_NOT_FOUND`.
- [x] 2. Hijau: `backend/ci/ops-watch.mjs` (Node 24, tanpa dependency). `--quick`: `/healthz` 3× jeda 20 s → `healthz_down`; `/ops/status` Bearer → `failing[]` diteruskan (bentuk ketat), non-200/3xx/tanpa token → `ops_status_unreachable`, 429 → `ops_status_limited` (warn, catatan handoff 21a). `--daily`: + `/healthz/db` (`healthz_db_failed`) + GraphQL (`worker_exceeded_cpu`, `worker_errors`, `worker_requests_high`, `r2_class_a_high`, `r2_class_b_high`, `r2_storage_high`, `cf_analytics_unavailable`). R2 per `actionType` saja (tanpa `objectName`). Issue `ops-alert`: buat (assign `aliefauzan`), comment kalau kode berubah, tutup setelah 2 run hijau; `simulate` hanya kode yang dikenal.
- [x] 3. `node --test 'backend/ci/*.test.mjs'` hijau; `backend/ci/README.md` bagian ops-watch, `backend/README.md` baris runbook kode workflow.
- [x] 4. `.github/workflows/ops-watch.yml` (jadwal K1, `concurrency: ops-watch`, `timeout-minutes: 5`, `permissions: contents: read, issues: write`, `environment: ops`, skip sampai variable, action di-pin SHA, input lewat `env:`) + langkah `backend/ci tests` di `backend.yml`.

### Deviasi

- `node --test backend/ci/` (Verifikasi fase) di Node 24 menganggap folder sebagai file → dipakai `node --test 'backend/ci/*.test.mjs'` (workflow + README).
- Kode tambahan di luar K3: `ops_status_limited` (warn, 429) dan `cf_analytics_unavailable`. `ops_status_limited` "buta": run dengan kode ini tidak dihitung hijau dan tetap memegang kode quick lama (review security MEDIUM). `cf_analytics_unavailable` sejak review Umar (PR #340, 9 Nov) jadi `alert` dan mengganti kode daily lama, bukan "buta" lagi.
- Status issue di marker tersembunyi pada komentar bot (bukan label): hanya penulis `github-actions` dipercaya (repo publik).
- Langkah `bundle-size.mjs` di `backend.yml` (K7 pertanyaan 4, fase 22 K11) tidak ikut: di luar 21b.

### Review (berurutan)

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:security-reviewer` | HIGH: workflow terjadwal mati sendiri setelah 60 hari repo sepi, tanpa alert. MEDIUM: kode "buta" dihitung hijau; `issue list` memercayai issue berlabel dari siapa saja; `--assignee` gagal = alert hilang; komentar flapping tiap 15 menit. LOW: host `OPS_API_URL` bebas, redirect diikuti, ringkasan blocklist salah saat `/ops/status` mati, concurrency daily, marker bisa diedit pemilik akses write | HIGH diterima (fase 21 "Risiko & rollback": cron Worker tetap menjaga Supabase; dicatat di README). Semua MEDIUM diperbaiki (`BLIND`, `--author app/github-actions` + filter penulis, retry tanpa assignee, jam tenang 60 menit). LOW host (`*.workers.dev` saja), redirect (`manual`), ringkasan (`unknown`) diperbaiki; concurrency + marker write diterima, dicatat di README |
| @umarmuhdhor (PR #340, 8 Nov 23:42 UTC) | 1. retry tanpa assignee menangkap semua error (`err.message` memuat `--assignee`). 2. lookup issue tidak pernah dicoba ke gh asli. 3. token CF kedaluwarsa mematikan cek harian diam-diam. 4. run daily buta menahan kode daily lama selamanya. 5. kode daily menahan issue ±24 jam. 6. file di luar `backend/`. 7. `environment: ops` = 1 record deployment per run. 8. komentar state ditulis sebelum edit judul | 1: hanya `err.stderr` + pola sempit; sebelum retry, list ulang (create yang timeout tapi jadi tidak dibuka dua kali); fake test melempar error berbentuk execFile. 2: dicek ke gh asli (lihat Verifikasi): perintah lama menemukan issue bot, tetapi `gh issue list --label` lewat search index (bisa tertinggal sesaat setelah create = issue baru tiap 15 menit) → lookup pindah ke REST `/issues?labels=ops-alert&state=open` (bot = `github-actions[bot]`), `issue view` dihapus. 3: `cf_analytics_unavailable` = `alert`; GraphQL transient (0/429/5xx) dicoba 3× jeda 20 s, 401/403 tidak. 4: run daily selalu mengganti set daily; tanpa analytics jadi `cf_analytics_unavailable`; run 429 hanya memegang kode quick lama. 5: run quick bertanya `/healthz/db` lagi kalau `healthz_db_failed` masih di issue; kode analytics (jendela 24 j) tetap menunggu run daily, ditulis di FOOTER + runbook (dispatch `daily` manual). 6: diputuskan lead di PR, tanpa perubahan; berikutnya lewat issue pertanyaan dulu. 7: `environment: { name: ops, deployment: false }` (changelog GitHub Maret 2026; environment tanpa custom protection rule). 8: edit judul dulu baru komentar; run "unchanged" membetulkan judul yang tidak cocok |
| `code-reviewer` (perbaikan review Umar, 9 Nov) | Tidak ada CRITICAL/HIGH. MEDIUM: 200 + `errors[]` dari GraphQL (timeout/budget Cloudflare) tidak di-retry → alert palsu. LOW: run 429 yang `recheckDb`-nya lolos tidak menulis state (recheck berulang). LOW: run 429 di antara dua run hijau tidak mereset hitungan | MEDIUM diperbaiki (hanya 400/401/403 tidak di-retry, test baru). LOW 1: `recheckDb` tidak jalan saat run buta (test). LOW 2 diterima, FOOTER + README: run 429 tidak dihitung dan tidak mereset |
| `ecc:typescript-reviewer` | HIGH: GraphQL 200 dengan `accounts: []` (akun salah) = hijau selamanya. MEDIUM: jam tenang menelan perubahan set daily; status `exceededCpu`/`exceededMemory`; komentar hanya halaman pertama; cron daily dicocokkan dengan string. LOW: jendela 24 jam di batas dataset, judul issue tidak ikut, retry assignee untuk semua error, test kurang | Semua HIGH/MEDIUM diperbaiki (`analyticsUsable`, jam tenang hanya untuk kode quick, `startsWith("exceeded")`, `gh api --paginate --slurp`, komentar di cron). LOW: jendela 24 j − 1 menit, `gh issue edit --title`, retry hanya error assign, test baru (49) |

### Verifikasi (9 Nov 2026)

| Perintah | Hasil |
|---|---|
| `node --test 'backend/ci/*.test.mjs'` | 49/49 (awal); 60/60 setelah review Umar (kode sebelum review: 32 dari 59 gagal; commit 9b84ee0: 2 test review kedua gagal) |
| Review Umar #2, gh asli (9 Nov ±01:05–01:30 UTC, read-only, repo publik dengan 5 issue `ops-alert` open buatan bot) | Perintah lama `gh issue list --label ops-alert --state open --author app/github-actions --json number,author` → 5 issue, `author.login` `app/github-actions`, `is_bot: true`: filternya benar. `GH_DEBUG=api` → `search(type: ISSUE_ADVANCED …)`: lewat search index. Tanpa `--label`, `--author app/github-actions` → 0 (bukan jalur search), `--author github-actions[bot]` → 5. REST `issues?labels=ops-alert&state=open` → 5, `user.login` `github-actions[bot]`. |
| Dry-run cloud setelah review Umar (9 Nov, token dari Keychain, tiap run berjarak > 60 s karena `/healthz/db` 1/menit per IP) | `--quick` dan `--daily` (token asli): `warn tombstones_stuck`, `warn blocklist_queue`, `issue: dry-run`, sama seperti sebelum review. `--daily` dengan token CF palsu: + `alert cf_analytics_unavailable` saja. Catatan: dua run daily < 60 s berturut-turut memberi `healthz_db_failed` (429 rate limit), bukan bug |
| `syncIssue` ke gh asli, tulis diblok (skrip uji di luar repo) | Repo dengan issue bot: baca REST list + komentar issue terlama (#1) → `updated`, tulis yang diblok `issue edit 1`, `issue comment 1` (urutan butir 8). Repo ini (belum ada issue): baca REST list → `opened`, tulis yang diblok `label create`, `issue create` |
| `git grep -n "objectName" backend/ci/ops-watch.mjs` | 0 hasil |
| Dry-run cloud `OPS_DRY_RUN=1 node backend/ci/ops-watch.mjs --quick` (token dari Keychain) | `warn tombstones_stuck`, `warn blocklist_queue`, `issue: dry-run`; tanpa angka/URL/token di output |
| Dry-run cloud `--daily` (token Analytics dari Keychain, akun Shoo) | `warn tombstones_stuck`, `warn blocklist_queue`, `issue: dry-run`: `/healthz/db` 200, GraphQL dua query sah (tanpa `cf_analytics_unavailable`) |

### Privasi (SECURITY §3)

- P6: output publik (stdout, job summary, issue) hanya kode + level + waktu UTC (test `main` memaku: tanpa token, URL, angka respons). R2 tanpa `objectName` (test + `git grep`).
- §1: token hanya di header; error cetak teks tetap; token tidak pernah di argv `gh`. `OPS_STATUS_TOKEN` + `CF_ANALYTICS_TOKEN` di environment `ops` (bukan `production`).

## LANGKAH MANUAL (setelah PR 21a merge dan CI deploy)

- [x] 1. **(Alief)** `openssl rand -base64 32` → simpan di password manager → dari `backend/api/`: `npx wrangler secret put OPS_STATUS_TOKEN` (di luar 18:30–19:30 UTC). Uji: `read -rs OPS_STATUS_TOKEN`, lalu `curl -s -H "Authorization: Bearer $OPS_STATUS_TOKEN" https://shoo-api.afindo-mi01.workers.dev/ops/status` → 200; tanpa header → 404. Catat hasil (tanpa token) di sini. Sebelum run cron pertama, `failing` memuat `retention_stale`/`notifications_stale` (belum ada baris `ops_jobs`): normal.
  - **7 Nov 2026, 17:11 UTC** (`wrangler secret list`, hanya nama): `OPS_STATUS_TOKEN` **sudah ada** di Worker (ada 3 deploy "Secret Change" 6 Nov ±06:24 UTC). Sesi ini tidak membuat atau menimpa token. `GET /ops/status` tanpa header → 404; `Bearer wrong` → 404. **Belum:** uji 200 dengan token asli (sesi tidak memegang nilainya). Alief: pastikan nilai token ada di password manager; kalau tidak, rotasi (`wrangler secret put`, di luar 18:30–19:30 UTC) lalu uji 200.
  - **8 Nov 2026, ±07:25 UTC (Alief):** nilai lama tidak tersimpan di mana pun → token dirotasi: `openssl rand -base64 32`, disimpan di Keychain Mac Alief (item `Shoo OPS_STATUS_TOKEN`), `wrangler secret put OPS_STATUS_TOKEN` → Success. `GET /ops/status` dengan token baru → **200**. Token lama tidak berlaku lagi. Nanti 21b (`ops-watch`) butuh token ini sebagai GitHub secret.
- [x] 2. **(Alief, D10)** Cloudflare → Notifications → Usage Based Billing → R2 Class A ambang 500 000 dan Class B ambang 5 000 000, email pemilik akun. Kalau tidak bisa dipilih: catat di sini.
  - **7 Nov 2026:** tidak bisa lewat API: token OAuth wrangler tanpa scope Notifications (`available_alerts` → `10000 Authentication error`, hanya baca, tidak ada create). Tetap langkah dashboard Alief (atau token API terpisah dengan scope Notifications).
  - **9 Nov 2026, ±03:40 UTC (dicek di dashboard, tidak diubah):** sudah ada dan `Enabled` di Platform Notifications: "R2 Storage Class A Operations usage above 500000", "R2 Storage Class B Operations usage above 5000000" (Usage based billing; konfigurasi Class A dibuka: produk R2 Storage Class A Operations, ambang 500000), plus "Shoo R2 storage above 5 GB". D10 selesai.
- [x] 3. **(Alief)** Catat pemilik email notifikasi Supabase (pause/kuota) dan Cloudflare (billing).
  - **7 Nov 2026:** Supabase `shoo-demo` dan Worker `shoo-api` sama-sama diakses lewat login CLI Alief, jadi pemilik notifikasi = akun Alief. Alamat email sengaja tidak ditulis (repo publik). Alief konfirmasi; mailbox tim K10 = fase 24 LANGKAH MANUAL 1.
  - **9 Nov 2026:** dicek ulang lewat CLI: `shoo-demo` ada di org Supabase "Shoo" yang terlihat dari login CLI Alief; akun Cloudflare Shoo = akun login `wrangler` Alief. Pemilik notifikasi keduanya = Alief (alamat tidak ditulis).
- [x] 4. **(Alief, spike, 9 Nov 2026 ±17:00 UTC)** Token API "shoo ops-watch analytics read (fase 21b)": hanya Account → Account Analytics → Read, akun Afindo.mi01 (Shoo) saja, kedaluwarsa 9 Nov 2027, dibuat dari profil Cloudflare pemilik akun; disimpan di Keychain Mac Alief (`Shoo OPS_CF_ANALYTICS_TOKEN`), `/user/tokens/verify` → active. Hasil (tanpa angka, repo publik):
  - (a) GraphQL Analytics jalan di plan Free: `workersInvocationsAdaptive` (filter `scriptName`, `datetime_geq/lt`, 24 j − 1 menit), `r2OperationsAdaptiveGroups` (`actionType`), `r2StorageAdaptiveGroups` (`max { payloadSize metadataSize }`, `bucketName`) menjawab tanpa error.
  - (b) Nilai `status` `shoo-api` dalam 24 jam: `success`, `clientDisconnected`. Skrip menghitung semua `exceeded*` (`exceededResources`, `exceededCpu`, `exceededMemory`).
  - (c) `workersInvocationsScheduled` ada (field langsung `cron`, `status`, tanpa `dimensions`), tetapi 0 baris untuk `shoo-api` dalam 24 jam walau cron jalan tiap jam: invocation Cron tidak terlihat di sini. Status cron tetap dari `ops_jobs` (`/ops/status`), sesuai K2.
  - (d) 500 dari `onError` di `errors`: **belum terverifikasi** (tidak ada baris dengan `errors > 0` dalam 24 jam). `worker_errors` tetap memakai `errors`; 5xx `onError` dicari di Query Builder (C16).
  - Token yang sempat dibuat dari profil Cloudflare lain di Chrome (nilai tidak tersimpan, belum pernah dipakai) dihapus.
- [ ] 5. Custom alert Workers Observability (C7): **tersedia**, alert uji belum dibuat.
  - **9 Nov 2026, ±03:45 UTC:** Observability → Alerts → **Monitors (Beta)** ada di akun ini (threshold, anomaly detection, SLO; tujuan email/webhook/dll.), dataset termasuk "Workers Logs" (`logs.workersLogs`). Monitor `replica_dropped` tidak dibuat: pemilih kolom filter tidak memuat daftar field untuk Workers Logs, dan nama kolom untuk Custom SQL tidak ada di docs. Tidak dibuat dengan nama kolom tebakan (alert yang tidak pernah menyala lebih buruk dari tidak ada). Monitors tetap kosong. Kuota replica tetap dijaga `replica_full`/`replica_reserve` lewat `/ops/status` + ops-watch.
  - Sisa (Alief): buat monitor lewat Query Builder Workers Observability (filter `event = replica_dropped`, `reason` ∈ `global_quota`, `global_bytes`, ≥ 1 per jam, email Alief) kalau dashboard sudah memuat field-nya.
- [x] 6. **(Umar, setelah issue K7)** Environment `ops` (tanpa custom protection rule, job memakai `deployment: false`) + 3 secret + variable `OPS_WATCH_ENABLED=true`, merge PR 21b, Run workflow `daily` sekali. Lalu alert test `simulate` = `retention_failed` dan perintah REST di `backend/ci/README.md` (review #340 butir 2): tempel output (nomor + `github-actions[bot]`) di sini. Nilai dari Alief lewat jalur privat (Keychain: `Shoo OPS_STATUS_TOKEN`, `Shoo OPS_CF_ANALYTICS_TOKEN`; account id sama dengan secret `CLOUDFLARE_ACCOUNT_ID` di `production`).
  - **9 Nov 2026, ±03:22–03:28 UTC (Umar, #341):** environment `ops` (deployment branches `main` saja, tanpa protection rule) + `OPS_STATUS_TOKEN`, `CF_ANALYTICS_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`; variable `OPS_WATCH_ENABLED` = `true`. PR #340 merged (76aaab0).
  - `daily` (run 42556059739): `issue: none`, warn yang diharapkan saja (`tombstones_stuck`, `blocklist_queue`).
  - `simulate` = `retention_failed` (run 42556198280): `issue: opened` → #345, di-assign `aliefauzan`. Dua run quick berikutnya: "Green run 1 of 2" (03:24 UTC), lalu "2 green runs in a row … closing" (03:25 UTC). Tidak ada issue kedua: label `ops-alert` (state all) hanya punya #345.
  - Lookup REST saat #345 masih open (review #340 butir 2, perintah di `backend/ci/README.md`), output dari Umar:

    ```json
    {"assignees":["aliefauzan"],"login":"github-actions[bot]","number":345,"title":"ops-alert: retention_failed"}
    ```

  - `deployment: false` (review #340 butir 7): `GET /repos/…/deployments?environment=ops` → 0 record setelah run `daily`, `simulate` dan dua run quick.
- [ ] 7–8. Sesuai `fase-21-monitoring.md` LANGKAH MANUAL 7–8 (TestFlight crash, cek Senin).
  - **Cek Senin 9 Nov 2026, ±03:31 UTC (D11, sebagian):**
    - `/ops/status`: `ok: true`; warn `tombstones_stuck`, `blocklist_queue` (antrean 1); DB 16 MB (Free 500 MB); retention umur 8,5 j, `failed: 0`; notifications umur 0,4 j; `healthzAgeHours` 0,1; replica `ok`, 7 upload / ±87 KB dari kuota 3000 / 500 MB, 3 keluarga, 0 di batas.
    - R2 bulan berjalan (GraphQL): Class A 752, Class B 1502 (ambang 500 000 / 5 000 000); `shoo-replicas` 0,43 MB / 30 objek, `shoo-replica-archive` 0,35 MB / 16 objek.
    - Worker 24 jam: `shoo-api` 2381 request, `errors` 0 (`success`, `clientDisconnected`); `shoo-ai` 329, 0; `shoo-admin` 732, 0; seluruh akun < 5 000 (batas Free 100 000/hari).
    - Belum: Supabase Usage (egress, Storage): sesi dashboard Supabase di browser kedaluwarsa, perlu login Alief. Storage kosong sejak fase 20 (C12).
    - Belum (7): TestFlight feedback + Crashes. App Store Connect di browser belum login; akses Xcode Organizer tidak diberikan. Data Organizer lokal (4 Nov, build 4) belum punya folder crash. Langkah Alief: Xcode → Window → Organizer → Crashes (Shoo), dan App Store Connect → TestFlight → Feedback.

Verifikasi cloud setelah butir 1: pagi setelah run 19:00 UTC pertama → `jobs.retention.failed = 0`, `ageHours < 12`; satu jam setelah deploy → `jobs.notifications.ageHours < 1.2`.

- **7 Nov 2026, 17:11 UTC** (SQL baca saja ke `ops_jobs`, setara isi `/ops/status`): `notifications` failed 0, umur 0,1 jam (< 1,2 ✓). `retention` failed 0, umur 22,2 jam (run 6 Nov 19:00; cek `< 12` berlaku pagi setelah run 19:00, belum waktunya).

## Placeholder aktif

Tidak ada.

## 21c — kuota replica di `/ops/status` (`feat/EX-07-ops-replica`)

Dasar: `feat/EX-07-replica-family-quota` (19a, #211) + merge `feat/B9-ops-status` (21a, #209); konflik satu baris daftar `leak` di `log-hygiene.test.ts` (keduanya digabung). Fase 19 belum merge, jadi PR ini stacked; isinya hanya commit 21c setelah #209 dan #211 merge.

### Checklist langkah

- [x] 1. Merah: `test/ops-status.test.ts` — `replica_reserve` (warn) / `replica_full` (alert) dari `level` gauge; `replica_family_cap` 2 → tidak, 3 → warn; `opsSnapshot` membaca `replicaUsage` (60 upload satu keluarga → `familiesAtCap` 1); respons 200 punya `replica` dengan field K5.2 persis; urutan kode tetap.
- [x] 2. Hijau: `opsSnapshot(sql, { quota, maxBytes })` memanggil `replicaUsage` fase 19 (kuota masuk sebagai parameter, repo tidak mengimpor service). `evaluate` + `OPS_THRESHOLDS.replicaFamiliesAtCap = 3`. Runbook README (4 baris: `replica_full`, `replica_reserve`, `replica_family_cap`, `replica_unknown`) + API.md.
- [x] 3. Setelah review security: query gauge gagal → `replica: null`, kode `replica_unknown` (warn), satu baris `ops_replica_usage_failed` (nama + SQLSTATE saja); angka kesehatan lain tetap terjawab.

### Verifikasi

| Perintah | Hasil |
|---|---|
| `pnpm -C backend/api typecheck` | bersih |
| `vitest run test/ops-status.test.ts test/log-hygiene.test.ts` | 27/27 |
| `vitest run` (suite penuh) | 582 lulus, 1 skip |
| pgTAP | tidak dijalankan ulang: tanpa migrasi baru (21a sudah PASS) |

Catatan lokal: migrasi `ops_jobs` dipasang ke DB lokal dengan `psql` (tanpa reset) karena DB lokal terakhir di-reset dari cabang tanpa 21a.

### Review (berurutan)

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:security-reviewer` | Tidak ada CRITICAL/HIGH. Urutan benar (auth → rate limit → query). LOW 1: `topFamily*` saat `families = 1` = pemakaian satu keluarga (hanya pemegang token). LOW 2: query gauge per panggilan (dibatasi 30/jam). LOW 3: gauge gagal → seluruh `/ops/status` 500 | LOW 1: README: angka `replica` tidak pernah ke tempat publik (kode saja). LOW 2: diterima. LOW 3: `replica: null` + `replica_unknown` (`491ce4c`) |
| `ecc:typescript-reviewer` | Tidak ada CRITICAL/HIGH. MEDIUM: jalur gagal gauge tidak dites sampai log. LOW: repo menulis log (`console.error` di repo), dua round trip berurutan, urutan semua kode belum dipaku | MEDIUM: test baru (`sql` palsu gagal di query kedua → `replica` null, satu baris log nama + kode, tanpa teks SQL). LOW urutan: dipaku. LOW log di repo: diterima (satu tempat, `errorInfo`). LOW round trip: diterima (30/jam) |

### Privasi Apple (SECURITY §3)

- Respons hanya angka agregat dari gauge fase 19 (tanpa id/domain/path); test 200 memaku field persis.
- Log baru `ops_replica_usage_failed`: hanya `error.name` + SQLSTATE (test).

## Catatan handoff

- 21b: workflow harus memperlakukan 429 dari `/ops/status` sebagai "tidak diketahui" (bukan sehat, bukan `ops_status_unreachable` palsu), dan tidak pernah mencetak angka (`dbBytes`, antrean) di log Actions (review security LOW 4, 5).
- Kalau `blocklist_entries` lewat ±10k baris: migrasi `create index concurrently blocklist_queue on blocklist_entries(first_seen_at) where approved_at is null and rejected_at is null and removed_at is null and families > 0` (di luar transaksi; review database MEDIUM).
- 21c selesai (stacked). Workflow 21b: kode `replica_*` ikut daftar kode publik; angka `replica` tidak pernah dicetak.
- `R3-catatan-api.md` §7: tambah `OPS_STATUS_TOKEN` (koordinator, PR plan).
- `app.onError` tanpa field `event` tetap (PR kecil terpisah kalau dibutuhkan).
