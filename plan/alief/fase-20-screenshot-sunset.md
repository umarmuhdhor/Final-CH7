# Fase 20 — Matikan jalur screenshot lama + cabut kunci Supabase dari Worker (18c, TODO E1, D-alief-C23/C27)

| Field | Nilai |
|---|---|
| Track | c (backend dulu, lalu app; kontrak hanya lewat issue ke Umar) |
| Branch | 20a `fix/EX-07-ignore-screenshot-upload` (backend, kecil) · 20b `feat/EX-07-screenshot-sunset` (backend: route, layanan, retensi, satu store R2, privasi, index baru add-only) · 20c `feat/EX-07-drop-screenshot-columns` (migrasi drop kolom + bucket, **satu deploy setelah** 20b) · 20d `feat/DT-04-screenshot-sunset` (app). Semua dari `origin/main` saat mulai |
| Prasyarat | #178 di `main` (29 Okt 04:05 UTC, extension tidak lagi mengirim screenshot). 18a ter-deploy (#182, 30 Okt 03:25 UTC). 18b merge (#199 → #200 → #201, 31 Okt 08:20 UTC). Gerbang G1–G6 (Cek kelayakan C1–C3, C11) lulus untuk sub-fase yang memerlukannya. Fase 19 sebaiknya merge dulu: 19a dan 20b sama-sama mengubah `db/repo/scans.ts` dan `test/replicas.test.ts` |
| Urutan | Semua device demo di build ≥ #201 (G2) → issue ke Umar (K7, pertanyaan 2 menyangkut 20a) → 20a merge + deploy CI → tunggu G1 (≥ 15 hari setelah baris screenshot terakhir) + G3–G5 nol → 20b merge + deploy CI → satu run retensi `failed: 0` → LANGKAH MANUAL cabut kunci → 20c (G6) → 20d (boleh paralel dengan 20c, setelah G1) → PR Umar: kontrak + `ShooShared` + fixture → PR kecil Alief: buang `screenshotUrl: null` dari respons (K2) |
| Requirement | TODO E1, D-alief-C23, D-alief-C27 (b), D-alief-C24 (e), EX-07, DT-04, SECURITY §2 T6, §3 P2, P3, P6, P9, P13 |
| Model + reviewer ECC | Opus 5.5 · 20a–20c: `ecc:security-reviewer` → `ecc:typescript-reviewer` → `ecc:database-reviewer`; 20d: `ecc:swift-reviewer` → `ecc:security-reviewer` (berurutan, tidak paralel) |
| Fase berikutnya | Fase 21 (monitoring): event `screenshot_dropped` (antarmuka K5.3 fase 19) hilang sejak 20a, diganti `screenshot_ignored` sampai 20b, lalu tidak ada sama sekali |

## Tujuan

**Masalah.** Pengirim screenshot sudah mati: extension di `main` sejak #178 hanya mengirim salinan halaman (`git grep -i screenshot ios/ShooExtension` hanya `CLAUDE.md:14`). Backend masih:
- menerima `screenshotBase64` dan memprosesnya **sinkron sebelum push** (`routes/scans.ts:57,132-139`, `services/scans.ts:54-91`);
- menyajikan `GET /screenshots/:id` lewat Supabase Storage (`routes/screenshots.ts:21-51`);
- memegang secret `SUPABASE_SERVICE_ROLE_KEY` (`env.ts:26-27`) yang hanya dipakai `SupabaseStorageStore` (`services/screenshots.ts:30-90`). Kunci ini melewati RLS seluruh proyek Supabase (D-alief-C27). Grant tabel `public` sudah dicabut (`20261022130000_security_review.sql:6-11`), tetapi Storage dan skema lain tetap terbuka bagi pemegang kunci. Worker terbuka ke internet, jadi kunci yang tidak dibutuhkan = risiko tanpa manfaat.

Retensi, tombstone, dan hapus device masih punya dua store dan dua anggaran (`retention.ts:14-22,94-117`, `services/screenshots.ts:92-179`). Detail di app masih punya fallback screenshot (`DetailView.swift:55-58,391-405`).

**Garis waktu.** #178 merge 29 Okt 04:05 UTC; 18a deploy 30 Okt 03:25 UTC; 18b merge 31 Okt 08:20 UTC. Belum ada build TestFlight dari `main` (PR #174 masih open), device demo dipasang dari Xcode. Build lama terus mengirim screenshot sampai diganti; versi app statis `0.1.0 (1)` (`ios/project.yml:22-23`), jadi build tidak bisa dibedakan dari nomor versi (C2).

**Hasil akhir.**
1. Backend tidak menerima, menyimpan, atau menyajikan screenshot. Bundle Worker tanpa `storage/v1` (tidak ada fetch ke Supabase Storage).
2. Satu store objek (R2 `shoo-replicas`) untuk salinan halaman + favicon. Retensi, tombstone, dan hapus device tanpa cabang Supabase dan tanpa anggaran 50-fetch.
3. Kolom `scans.screenshot_path` + index-nya dihapus, bucket `screenshots` dihapus, var `SUPABASE_URL` + `SCREENSHOT_MAX_BYTES` hilang dari `wrangler.jsonc`, secret `SUPABASE_SERVICE_ROLE_KEY` dihapus dari Worker, dan kunci `shoo-worker` dicabut di Supabase.
4. App: Detail = salinan halaman → placeholder. Helper yang masih dipakai favicon/salinan halaman dipindah, bukan dihapus.
5. Kontrak: `screenshotBase64` + `screenshotUrl` dihapus Umar (issue K7).
6. Halaman privasi, `ARCHITECTURE.md` §2/§3, `SECURITY.md` jujur: Supabase hanya database.

**Perkiraan tanggal.** Paling cepat ±16 Nov 2026, kalau semua device demo sudah di build ≥ #201 pada 1 Nov (baris screenshot terakhir ≤ 1 Nov + 15 hari). Tanggal pasti dari G1, bukan dari tanggal merge #178.

## Bacaan wajib

- `plan/alief/fase-18-page-replica.md` (K9, K23, Peta dampak baris `ScreenshotView.swift`, Catatan handoff 18c), `log/fase-18.md` (LANGKAH MANUAL 1 tabel cloud, bagian 18b "Penyimpangan"), `log/DECISIONS.md` D-alief-C23, C24, C27, C28
- `fase-19-replica-quota.md` (K5.3 `screenshot_dropped`, K7)
- Backend: `src/routes/{scans,screenshots,favicons,replicas,devices,privacy}.ts`, `src/services/{scans,screenshots,screenshotLinks,favicons,replicas,replicaStore,images}.ts`, `src/cron/retention.ts`, `src/db/repo/{scans,tombstones,devices}.ts`, `src/env.ts`, `src/app.ts`, `src/http/rateLimit.ts`, `wrangler.jsonc`, `vitest.config.ts`, `.dev.vars.example`
- DB: `migrations/20261021130000_init.sql:60,209-214`, `20261021170000_screenshot_bucket.sql`, `20261022130000_security_review.sql:42-49`, `20261028120000_favicons.sql`, `20261029100000_page_replicas.sql:26-39`; `tests/{storage,grants,retention_indexes}.test.sql`
- App: `Features/Detail/{ScreenshotView,DetailView,DetailModel,EvidenceCard,PageCopyCaption,ReplicaLoader}.swift`, `Components/SiteIcon.swift`, `Data/MockRepository.swift`, `Tests/{DetailPrivacyTests,DetailScreenshotLinkTests,FaviconLoaderTests,ReplicaLoaderTests,MockRepositoryTests,PageCopyTests,FixtureTests}.swift`, `UITests/DetailUITests.swift`
- Kontrak (read-only): `contracts/api.md:25,47-49,73`, `contracts/scan-result.schema.json:61-69`, `ios/ShooShared/ScanResult.swift:13`; PR #181 (closed)
- `.github/workflows/backend.yml:35-84`, `backend/ci/README.md:18` (migrasi jalan **sebelum** Worker baru)
- `ARCHITECTURE.md` §2 (baris Retensi), §3 (baris Supabase Storage, R2), `SECURITY.md` §2 T6, §3 P2/P3/P9/P13

## Cek kelayakan (diverifikasi terhadap `main` 2720b13, 31 Okt 2026)

| # | Butir | Bisa? | Temuan dari kode | Tindakan |
|---|---|---|---|---|
| C1 | Gerbang tanggal (G1) | Ya | Retensi harian `0 19 * * *` (`wrangler.jsonc:48`) menghapus baris `created_at < now() - 14 days` (`retention.ts:162`); reuse hanya dari upload asli < 24 jam (`db/repo/scans.ts:83,90-98`), jadi objek hidup ≤ 15 hari | Paling cepat = `max(created_at) where screenshot_path is not null` + 15 hari. Setelah tanggal itu G3–G5 harus nol (objek benar-benar terhapus, bukan hanya barisnya) |
| C2 | Semua device demo di build ≥ #201 (G2) | Sebagian | Tidak ada kolom versi app di DB; `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` statis (`project.yml:22-23`), Profile menampilkan `0.1.0 (1)` (`ProfilePages.swift:1309-1310`) | Bukti tidak langsung: scan terakhir tiap device aktif 7 hari terakhir tanpa screenshot (SQL G2) + checklist manual per HP (dipasang dari `main` ≥ 2720b13). Setelah 20a: Workers Logs Query Builder `event = screenshot_ignored` = 0 dalam 48 jam terakhir (Free retensi 3 hari) |
| C3 | Favicon lama `-favicon.` di Supabase (G3) | Kemungkinan besar sudah 0 | Migrasi `20261028120000_favicons` baru sampai cloud bersama deploy 18a (`log/fase-18.md:29`: cloud berhenti di `20261027100000`, deploy `main` gagal sejak 28 Okt). 18a menulis favicon ke R2 `-icon.` (`services/favicons.ts:53`, `storeKind` `services/screenshots.ts:99-102`). Jadi favicon `-favicon.` kemungkinan tidak pernah ada di cloud | **Belum terverifikasi di cloud** → SQL G3. Catatan handoff fase 18 baris 230 sudah mencatat favicon pindah di 18a (K23); syarat sisanya = G3 |
| C4 | Kunci hanya untuk Storage | Ya | `git grep SUPABASE_SERVICE_ROLE_KEY`: kode hanya `services/screenshots.ts:88-89`; test lewat `vitest.config.ts:33-34` + 6 file `storage/v1/object/info` (`scans.test.ts:58`, `retention.test.ts:15`, `devices-me.test.ts:113`, `favicons.test.ts:351`, `log-hygiene.test.ts:62`, `security-review.test.ts:129`). CI hanya memakai `SUPABASE_DB_URL` + `CLOUDFLARE_*` (`backend.yml:77,82-83`). Tidak ada Edge Function di repo (`backend/db/supabase/` tanpa `functions/`). App, extension, `chrome/`, `ai/` tidak memakai kunci Supabase | Cabut setelah 20b live (LANGKAH MANUAL 3–4). Verifikasi di Verifikasi butir 5 |
| C5 | `SCREENSHOT_URL_SECRET` tetap | Ya | Dipakai link favicon (`services/favicons.ts:76`, `routes/favicons.ts:25`) dan salinan halaman (`services/replicas.ts:108`) | **Tidak** dicabut. Nama tetap (K5): ganti nama = secret baru di cloud tanpa manfaat keamanan |
| C6 | Helper backend bersama | Ya, refactor | `services/screenshots.ts` memuat `ScreenshotStore`, `storeKind`, `r2Store`, `removeTombstoned(All)`, `deleteScreenshots`, `abandonUpload`, dipakai `services/replicas.ts:10`, `routes/replicas.ts:11`, `services/favicons.ts:10`, `routes/favicons.ts:11`, `routes/devices.ts:9,173,197`, `retention.ts:5-7`, `replicaStore.ts:1`. `images.ts`: `decodeBase64` dipakai `replicas.ts:8,129`, `sniffImage` dipakai `faviconFetch.ts:1`. `screenshotLinks.ts` dipakai favicon + replica | Hapus hanya bagian Supabase + screenshot; sisanya diganti nama (K5). `images.ts` tetap |
| C7 | Screenshot diproses sebelum push | Ya | `attachScreenshot` di-`await` sebelum lookup push (`routes/scans.ts:132-139` vs `:153-170`) | Hilang di 20a: `POST /scans` dari build lama tidak lagi decode/upload sebelum 201 |
| C8 | Build lama tetap mengirim `screenshotBase64` | Ya | `scanBody` = `z.object` (strip, bukan strict, `routes/scans.ts:47`); body sampai 512 KB tetap diterima | 20a: field jadi `z.unknown().optional()` yang tidak dipakai + log `{"event":"screenshot_ignored"}` tanpa id (K3); 20b: field keluar dari zod (strip). Selalu 201, bukan 422 (extension membuang scan saat 4xx) |
| C9 | Drop kolom vs urutan CI | Ya, **dua deploy** | `backend.yml:74-84` menjalankan `supabase db push` sebelum `wrangler deploy`; `backend/ci/README.md:18` "add first, remove one deploy later". Worker sekarang membaca `screenshot_path` di `selectScans` (`db/repo/scans.ts:298`), retensi (`retention.ts:163,176,229,233`), `dueTombstones` (`tombstones.ts:51`), `deleteDevice` (`devices.ts:166`) | Drop kolom di PR yang sama dengan kode → Worker lama 500 di antara migrasi dan deploy. Jadi 20b (kode berhenti membaca) dulu, 20c (drop) setelah 20b live |
| C10 | Index yang bergantung pada `screenshot_path` | Ya | `scans_plain_created` / `scans_shot_created` (predikat menyebut `screenshot_path`, `20261029100000_page_replicas.sql:32-39`), `scans_owner_shot` (`20261021170000_screenshot_bucket.sql:11`), `scans_original_shot`, `scans_shot_path` (`20261022130000_security_review.sql:45-49`). `DROP COLUMN` ikut menghapus index yang memakai kolom itu, termasuk di predikat | 20b menambah index `scans_plain_created_v3` / `scans_shot_created_v3` dengan predikat tanpa `screenshot_path` (add-only, Worker lama tetap jalan). 20c: `drop index if exists` yang lama, drop kolom, rename `_v3`. pgTAP `retention_indexes.test.sql:13-16` disesuaikan |
| C11 | Hapus bucket lewat SQL (G6) | Ya, dengan izin eksplisit | **Diverifikasi lokal 31 Okt** (Supabase CLI lokal, `docker exec supabase_db_shoo psql`): trigger `protect_buckets_delete` + `protect_objects_delete` → `storage.protect_delete()` melempar 42501 kecuali `storage.allow_delete_query = 'true'`; role `postgres` punya `DELETE` di `storage.buckets` | Migrasi 20c: guard (tidak ada objek di bucket) → `set local storage.allow_delete_query = 'true'` → `delete from storage.buckets where id = 'screenshots'`. Objek **tidak pernah** dihapus lewat SQL (filenya tertinggal di penyimpanan); dikosongkan oleh retensi. Versi Storage cloud **belum terverifikasi** → G6 sebelum merge 20c |
| C12 | pgTAP yang menyebut bucket/kolom | Ya | `storage.test.sql:7-15` (batas bucket, `scans_owner_shot`, juga `scans_favicon_path`), `grants.test.sql:37` (bucket privat), `retention_indexes.test.sql:9,13-16` | 20c: `storage.test.sql` diganti (bucket tidak ada, `scans_favicon_path` tetap ada), `grants.test.sql` cek bucket tidak ada, `retention_indexes.test.sql` regex baru + `hasnt_column('scans','screenshot_path')` |
| C13 | Helper app bersama | Ya, pindah | `URLSessionScreenshotLoader.configuration()` dipakai `SiteIcon.swift:23`, `ReplicaLoader.swift:26`, `FaviconLoaderTests.swift:30,38`, `ReplicaLoaderTests.swift:54,61`, `DetailPrivacyTests.swift:79,90`; `RedirectRefuser` dipakai `SiteIcon.swift:29`, `ReplicaLoader.swift:33`; `ScreenshotDecoder` dipakai `SiteIcon.swift:44-45`; **`ZoomedScreenshot` dipakai salinan halaman** (`DetailView.swift:60`, `pageImage` `:341`) | Fase 18 (Peta dampak baris `ScreenshotView.swift`) hanya menyebut tiga helper pertama: **usang**, karena 18b menggambar salinan halaman menjadi gambar dan memakai layar zoom yang sama (`log/fase-18.md` 18b "Penyimpangan"). Keempatnya dipindah ke `Support/`; yang dihapus hanya loader screenshot, protokol, env, fixture |
| C14 | Mock + UI test bergantung pada `screenshotUrl` | Ya | `MockRepository.swift:304` memberi salinan halaman hanya ke fixture yang punya `screenshotUrl`; `DetailUITests.swift:39,80-90,128-133` menunggu `FixtureScreenshotLoader`; `awaitsCopy` (`DetailModel.swift:109`); `PageCopyCaption.hasScreenshot` (`:23-24,59`). Fixture app = salinan per byte kontrak (`FixtureTests.swift:45-50`), jadi `screenshotUrl` di fixture tetap ada sampai PR Umar | Mock memakai daftar id fixture yang punya bukti (bukan field `screenshotUrl`), UI test Detail diluncurkan dengan `-debug.replicaFixture YES`. App tidak lagi membaca `.screenshotUrl` di mana pun, supaya PR Umar yang menghapus field di `ShooShared` tidak memecah build |
| C15 | Kontrak | Usulan ke Umar | `contracts/api.md:73` sudah menjanjikan penghapusan "in a follow-up PR"; `scan-result.schema.json:61-69` (`deprecated: true`); `ShooShared/ScanResult.swift:13`. `additionalProperties: false` hanya di `LocalizedText` (`schema.json:197`), bukan di ScanResult, dan `screenshotUrl` tidak `required` (`:7-17`). PR #181 `docs/EX-07-screenshot-deprecated` **ditutup Alief 31 Okt** karena isinya sudah ada di `main` sebagai f92d8bf (masuk lewat merge 18a), bukan karena ditolak | Backend boleh mengirim `screenshotUrl: null` (K2). Issue baru ke Umar (K7) |
| C16 | Halaman privasi | Ganti | EN `routes/privacy.ts:28,39,48,68`, ID `:87,98,107,127` menyebut screenshot dan "Supabase … storage of older screenshots and site icons"; test `privacy.test.ts:41-47,57,72` | 20b (setelah G1: tidak ada screenshot lagi, jadi teks baru jujur) |
| C17 | Rate limit + log | Ganti | `viewScreenshot` (`rateLimit.ts:22`); peta bucket `screenshots_view` di `log-hygiene.test.ts:87`; `screenshot_dropped` (`services/scans.ts:47,82`, `routes/scans.ts:137`) | Dihapus di 20b; baris `rate_limit_hits` lama habis sendiri dalam 24 jam (`retention.ts:130-139`) |
| C18 | Anggaran retensi | Ya | Supabase: `MAX_BATCHES = 10`, `TOMBSTONES = 500` (`retention.ts:14-15,37`) demi batas 50 fetch eksternal; R2: `R2_MAX_BATCHES = 40` (`:22`). CPU cron dengan 40 panggilan binding **belum terukur** (fase 18 LANGKAH MANUAL 3 masih terbuka) | Hanya anggaran R2 yang tersisa, tetap 40 × 100 (K6) |
| C19 | CI + test lokal | Ya | `backend.yml:37` menyalakan Storage lokal (dibutuhkan: `init.sql:211-214` insert ke `storage.buckets`). `vitest.config.ts:10-23` `localSupabase()` hanya untuk Storage; Storage lokal tidak stabil di CI (`log/fase-18.md:29`) | 20b menghapus `localSupabase()` + binding `SUPABASE_*` dari vitest: test tidak lagi bergantung pada Storage lokal. `.github/` tidak diubah (bukan folder kita) |

Kesimpulan: semua butir bisa dikerjakan di `backend/`, `ios/ShooApp/`, `plan/alief/`. Di luar folder kita: kontrak + `ShooShared` + `docs/mandates/alief.md:52,56` (Umar, K7).

**Koreksi terhadap teks fase 18 (usang per 31 Okt):**
- Catatan handoff baris 229: rujukan `retention.ts:131` usang (filter 14 hari sekarang `retention.ts:162`); syarat tanggal + build tetap (G1, G2).
- Catatan handoff baris 230: `SUPABASE_URL` yang "dicabut dari Worker" adalah **var** di `wrangler.jsonc:35`, bukan secret. Var itu hilang lewat perubahan kode 20b, bukan lewat `wrangler secret delete`. `storageCalls` dan `retention.ts:7-13,122` tidak ada lagi; anggarannya sekarang `budget.supabase` (`retention.ts:96`). `services/screenshots.ts:87` → `:88-89`.
- Peta dampak baris `ScreenshotView.swift`: daftar helper yang dipindah kurang `ZoomedScreenshot` (C13).
- Output 18b/K10 (kartu `WKWebView` hidup): implementasi akhir menggambar salinan halaman menjadi gambar (`ReplicaSnapshot`), sehingga layar zoom screenshot ikut dipakai.
- Baris 230 "migrasi bucket `screenshots`" tanpa cara: `delete` SQL langsung diblokir trigger Storage (C11), jadi perlu `storage.allow_delete_query` + guard.

## Peta dampak (semua sisi)

**Hapus** = dihapus, **Ganti** = berubah, **Pindah** = dipindah/ganti nama tanpa ubah perilaku, **Tetap** = harus tetap lulus (regresi).

| Sisi | Bagian | Status | Sub-fase | Apa yang berubah / dijaga |
|---|---|---|---|---|
| Backend | `routes/scans.ts:57,132-139` | Ganti | 20a/20b | 20a: `screenshotBase64: z.unknown().optional()`, tidak dipakai, log `screenshot_ignored` kalau truthy (K3, C8). 20b: key keluar dari zod (strip) + log hapus |
| Backend | `routes/scans.ts:16,219,234` | Ganti | 20b | `toScanResult` tanpa argumen screenshot; respons `screenshotUrl: null` tetap (K2) |
| Backend | `services/scans.ts:3-19,45-111` | Hapus/Ganti | 20a/20b | 20a: tidak dipanggil lagi. 20b: `attachScreenshot`, `screenshotUrl`, kuota 50/300, `DEFAULT_MAX_BYTES` hapus; `toScanResult` tetap |
| Backend | `routes/screenshots.ts`, `app.ts:17,51,75` | Hapus | 20b | `GET /screenshots/:id` → 404 (`app.notFound`) |
| Backend | `services/screenshots.ts` | Pindah + Hapus | 20b | `SupabaseStorageStore`, `BUCKET`, `screenshotStore`, `storeKind`/`byStore`/`Stores` hapus; sisanya ke `services/objectStore.ts` (`ObjectStore`, `objectStore(env)`, `removeTombstoned`, `deleteObjects`, `abandonUpload`) (K5) |
| Backend | `services/screenshotLinks.ts:16,35-36,43-44` | Pindah + Ganti | 20b | Kind `screenshot` hapus; file → `services/signedLinks.ts` (K5) |
| Backend | `routes/favicons.ts:11,32-35`, `services/favicons.ts:10,17-20,82-87` | Ganti | 20b | Baca dari R2 saja; `faviconContentType` tetap kenal dua pola (path lama `-favicon.` tidak ada lagi, tetapi aturan ekstensi sama) |
| Backend | `db/repo/scans.ts:34-114,118-121,279,298,345-353` | Hapus/Ganti | 20b | `reserveScreenshot`, `clearScreenshotPath`, `ORIGINAL`, `recentScreenshot`, `screenshotsToday`, `allScreenshotsToday`, `screenshotPathForViewer`, `ScanRow.screenshotPath` hapus; `ORIGINAL_FAVICON` hanya pola `-icon.` |
| Backend | `db/repo/tombstones.ts:36-58` | Ganti | 20b | `R2_PATH`/parameter `store` hapus; cek `screenshot_path` hapus |
| Backend | `db/repo/devices.ts:153-175` | Ganti | 20b | `returning` tanpa `screenshot_path` |
| Backend | `cron/retention.ts:9-22,54-64,94-117,146-238` | Ganti | 20b | Satu store, satu anggaran 40 × 100 (K6); predikat tanpa `screenshot_path` (cocok dengan index `_v3`); `RetentionOptions.store` = R2 |
| Backend | `routes/devices.ts:9,173,197`, `routes/replicas.ts:11`, `services/replicas.ts:9-10`, `services/replicaStore.ts:1` | Pindah | 20b | Impor dari `objectStore.ts` / `signedLinks.ts` |
| Backend | `http/rateLimit.ts:22` | Hapus | 20b | `viewScreenshot` |
| Backend | `env.ts:24-29,32-33`, `wrangler.jsonc:9-10,34-37`, `.dev.vars.example:14-15`, `test/env.d.ts:15-17`, `vitest.config.ts:10-23,33-34` | Ganti | 20b | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SCREENSHOT_MAX_BYTES` hapus; komentar `SCREENSHOT_URL_SECRET` = link favicon + salinan halaman |
| Backend | `routes/privacy.ts:28,39,48,68,87,98,107,127` | Ganti | 20b | Tanpa screenshot; pemroses: Supabase = database saja |
| Backend | `services/images.ts` | Tetap | — | Dipakai replica + favicon (C6) |
| Test | `test/screenshots.test.ts` | Hapus | 20b | — |
| Test | `test/scans.test.ts` (semua hasil `rg -n -i screenshot`, a.l. `:58,128,183-286,429-470`) | Ganti | 20a/20b | 20a: body dengan `screenshotBase64` → 201, tidak ada objek, log `screenshot_ignored`. 20b: kasus screenshot hapus, `screenshotUrl` selalu `null` |
| Test | `test/{retention,security-review,devices-me,log-hygiene,favicons,replicas,privacy,cache-headers}.test.ts` | Ganti | 20b | Store palsu satu (R2); hapus `supabaseHas`/`storage/v1`; `favicons.test.ts:349-352,627-691` (favicon lama di Supabase) hapus; `replicas.test.ts:14,150-157,573-578,650-657,678,730-742` (dua store) disederhanakan; `security-review.test.ts:83-87` pindah ke `replicaUrl`/`faviconUrl` dengan secret pendek |
| DB | Migrasi 20b `<ts>_screenshot_sunset_indexes.sql` | Baru (add-only) | 20b | `scans_plain_created_v3 … where favicon_path is null and replica_path is null`; `scans_shot_created_v3 … where favicon_path is not null or replica_path is not null` |
| DB | Migrasi 20c `<ts>_drop_screenshots.sql` | Baru | 20c | Guard → drop index lama → drop kolom → rename `_v3` → hapus baris bucket (C10, C11) |
| DB | `tests/{storage,grants,retention_indexes}.test.sql` | Ganti | 20b/20c | C12 |
| DB | `db/scripts/quota-estimate.sql:11,33` | Ganti | 20c | Tanpa `screenshot_path` |
| App | `Features/Detail/ScreenshotView.swift` | Pindah + Hapus | 20d | `configuration()` → `Support/EvidenceSession.swift`, `RedirectRefuser` + `ScreenshotDecoder` → `Support/` (nama `ImageDecoder`), `ZoomedScreenshot` → `Features/Detail/ZoomedPage.swift`; `ScreenshotLoadError`, `ScreenshotLoading`, `URLSessionScreenshotLoader` (loader), env `screenshotLoader`, `FixtureScreenshotLoader` hapus |
| App | `DetailView.swift:10,13-15,55-58,341-345,369,386,391-405,414-419,467` | Ganti | 20d | Urutan bukti: salinan halaman → placeholder |
| App | `DetailModel.swift:106-110,118,179-187,248-249` | Ganti | 20d | `awaitsCopy` hanya `pageReplicaUrl`; `refreshScreenshotLink` hapus |
| App | `PageCopyCaption.swift:23-24,48,59`, `EvidenceCard.swift:137,283` | Ganti | 20d | `hasScreenshot` hapus ("No copy of this page" selalu tampil saat tanpa salinan); label VoiceOver (K8) |
| App | `MockRepository.swift:72-74,288-292,304` | Ganti | 20d | Daftar id fixture berbukti; daftar tidak menyentuh `screenshotUrl` |
| App | `SiteIcon.swift:16,23,29,44-45`, `ReplicaLoader.swift:26,33` | Pindah | 20d | Nama helper baru |
| App | `Resources/Localizable.xcstrings:1655,2681,2691,2702` | Hapus/Ganti | 20d | Hapus "Loading screenshot", "Screenshot", "Screenshot isn't available anymore" (tidak dipakai kode; hanya `:2691` bertanda `stale`). "Screenshot of the page" diganti key baru "Copy of the page" EN/ID (K8; yang ada hanya "Copy of the page · %@", `:737`) |
| App | `Tests/DetailScreenshotLinkTests.swift` | Pindah | 20d | Jadi `Tests/DetailReplicaLinkTests.swift`: tiga test yang sama untuk `refreshReplicaLink` (key `pageReplicaUrl`, link `/replicas/`). Tidak ada test lain untuk `refreshReplicaLink` (`rg` hanya `DetailView.swift:384`, `DetailModel.swift:191`) |
| App | `Tests/{DetailPrivacyTests,FaviconLoaderTests,ReplicaLoaderTests}.swift`, `Tests/MockRepositoryTests.swift:18,61`, `Tests/PageCopyTests.swift:28,69,112,141`, `Tests/ActivityNoteTests.swift:12`, `Data/ShooRepository.swift:37` (komentar), `UITests/DetailUITests.swift:39,80-100,128-133` | Ganti | 20d | Test loader screenshot dihapus, test helper yang dipindah tetap; tidak ada `screenshotUrl` di Swift (memberwise init tanpa argumen itu); UI test memakai `-debug.replicaFixture YES` |
| App | `Data/Fixtures/*.json`, `Tests/FixtureTests.swift` | Tetap → PR Umar | — | Salinan per byte kontrak; berubah bersama kontrak (pola 18f) |
| App | `PrivacyInfo.xcprivacy` | Tetap | — | Other User Content tetap (salinan halaman) |
| Kontrak (Umar) | `contracts/api.md:25,47-49,73`, `scan-result.schema.json:61-69`, `contracts/fixtures/*.json`, `ShooShared/ScanResult.swift:13`, `docs/mandates/alief.md:52,56` | Di luar folder kita | setelah 20d | Issue K7 |
| CI | `backend.yml` | Tetap | — | Storage lokal tetap menyala (`init.sql` butuh skema `storage`); `.github/` bukan folder kita |
| Privasi | Halaman privasi, SECURITY T6/P2/P3/P9/P13 | Ganti | 20b | Teks tanpa screenshot; T6 ditutup (data tidak lagi diterima) |
| Biaya Free | Supabase Storage + egress | Turun ke 0 | 20b/20c | Tidak ada fetch eksternal ke Storage di `GET /favicons` lama, retensi, hapus device; R2 tidak berubah |
| Docs | `backend/API.md:18,35,257,260,403,421,432-433,446,483,495-498,585,614-637` (semua hasil `rg -n -i screenshot`), `backend/README.md:5,55,70,77,110-115,125-127,144-147`, `backend/CLAUDE.md:9`, `backend/ci/README.md:18` | Ganti | 20b/20c | Endpoint + env + retensi + anggaran |
| Plan | `ARCHITECTURE.md` §2 baris Retensi, §3 baris Supabase Storage, `SECURITY.md` T6/P2/P3/P9/P13, `ref/R2` (kolom), `ref/R3:107-113` (env), `TODO.md` E1 + D11, `log/DECISIONS.md`, `log/fase-20.md` | Ganti | per sub-fase | Saat implementasi, bukan di file fase ini |

## Keputusan

**K1 — Pecah sub-fase (butuh jawaban Alief).** (a) Satu PR backend setelah G1. (b) **20a dulu** (berhenti menerima screenshot, segera setelah G2), lalu 20b (hapus kode + Storage) setelah G1, lalu 20c (drop kolom + bucket). Rekomendasi **(b)**: 20a menghentikan jam G1 begitu semua device demo sudah diperbarui, jadi tanggal 20b pasti (≤ deploy 20a + 15 hari) dan tidak mundur karena satu HP lama. 20a kecil dan bisa di-revert. 20c terpisah karena C9.

**K2 — `screenshotUrl` di respons (butuh jawaban Umar di issue K7).** (a) **Kirim `screenshotUrl: null` tetap** sampai kontrak menghapusnya, lalu PR kecil membuang key. (b) Buang key di 20b. Rekomendasi **(a)**: sah terhadap skema hari ini dan sesudahnya (`screenshotUrl` tidak `required`, ScanResult tanpa `additionalProperties: false`, C15). App lama men-decode `URL?`, jadi `null` maupun key hilang aman. (a) membuat backend tidak pernah mendahului kontrak.

**K3 — `screenshotBase64` dari build lama.** (a) **Strip diam-diam + log `{"event":"screenshot_ignored"}`** (tanpa id, P6), 201. (b) 422. Rekomendasi **(a)**: 422 membuat extension membuang seluruh scan (`routes/scans.ts:58-59` alasan yang sama untuk replica). Log menjadi bukti G2 di `wrangler tail`. Log dihapus di 20b (zod strip tetap).

**K4 — Bucket `screenshots`.** (a) **Migrasi 20c** dengan guard + `set local storage.allow_delete_query = 'true'` (C11). (b) Hapus manual di dashboard, migrasi tidak menyentuh Storage. Rekomendasi **(a)**: satu sumber kebenaran untuk lokal, CI, dan cloud; guard menolak kalau masih ada objek (P13). Kalau G6 menunjukkan trigger cloud berbeda dari lokal, pakai (b) dan migrasi hanya `delete … where id = 'screenshots'` untuk lokal (catat di DECISIONS).

**K5 — Nama (butuh jawaban Alief).** Rekomendasi: `services/screenshots.ts` → `services/objectStore.ts` (`ScreenshotStore` → `ObjectStore`, `deleteScreenshots` → `deleteObjects`), `services/screenshotLinks.ts` → `services/signedLinks.ts`, log `screenshots_delete_failed` → `objects_delete_failed`, `screenshot_discard_failed` → `object_discard_failed` (fase 21 belum memakainya). **Tetap**: secret `SCREENSHOT_URL_SECRET` (ganti nama = `wrangler secret put` baru + celah konfigurasi tanpa manfaat keamanan), tabel `storage_tombstones`. Alternatif: tidak ganti nama (churn lebih kecil, nama menyesatkan).

**K6 — Anggaran hapus R2.** Tetap 40 batch × 100 = 4000 objek per run (`retention.ts:22`), dipakai bersama langkah scans + tombstone. Tidak dinaikkan: CPU cron belum terukur (C18). Batas 50 fetch eksternal tidak lagi relevan untuk retensi.

**K7 — Jalur kontrak (butuh jawaban Umar).** Issue **baru** (template question, label `question`, assign @umarmuhdhor), judul `EX-07: remove deprecated screenshotBase64 / screenshotUrl (fase 20)`, link ke #176. Alasan issue baru: satu issue = satu topik; #176 membahas desain replica. Pertanyaan bernomor:
1. Hapus `screenshotBase64` (`api.md:47`), `screenshotUrl` (`schema.json:61-69`, `api.md:48-49,73`), kata "screenshots" di `api.md:25`, field di `contracts/fixtures/*.json` dan `ShooShared/ScanResult.swift:13`, setelah PR 20d (app tidak lagi membaca field) merge?
2. Sampai itu, boleh backend mengirim `screenshotUrl: null` (K2a) dan mengabaikan `screenshotBase64` (K3a)?
3. Fixture app (`ios/ShooApp/Data/Fixtures/`, per byte) disalin Alief ke branch kontrak dengan pola 18f, atau Umar sekalian?
4. `docs/mandates/alief.md:52,56` ("upload screenshot", "scan + screenshot") ikut diperbarui?

Sampai dijawab: backend mengirim `null`, app tidak membaca field, fixture tidak disentuh.

**K8 — Teks app (butuh jawaban Alief, UI).** Label VoiceOver gambar halaman "Screenshot of the page" (`EvidenceCard.swift:283`, `ScreenshotView.swift:155`) → "Copy of the page" EN/ID (jujur: gambarnya salinan halaman). Accessibility identifier `detail.screenshot*` **tetap** (hanya UI test, tidak terlihat pengguna). `ZoomedScreenshot` → `ZoomedPage`. PR 20d = PR UI → before/after screenshot simulator wajib.

**K9 — Kunci JWT legacy Supabase (opsional, butuh jawaban Alief).** Worker memakai secret key baru `sb_secret_…` (`backend/README.md:111`). Proyek mungkin masih punya kunci legacy `anon` + `service_role` (JWT). Tidak ada komponen di repo yang memakainya (C4). Rekomendasi: setelah LANGKAH MANUAL 4, cek di dashboard (API Keys → Legacy) dan nonaktifkan kalau tidak ada pemakaian. **Belum terverifikasi**: apakah dashboard menampilkan "last used" per kunci. Kalau ragu, biarkan dan catat di TODO E.

## Output

**20a backend (`fix/EX-07-ignore-screenshot-upload`)**
- `routes/scans.ts`: `screenshotBase64: z.unknown().optional()` di `scanBody` (`:57`; diterima apa pun, tidak pernah dipakai, tanpa `.max()` supaya tidak ada 422); kalau truthy → `console.log(JSON.stringify({ event: "screenshot_ignored" }))` tanpa isi; blok `attachScreenshot` (`:132-139`) hapus. 20b menghapus key dari zod (strip `z.object`) dan log-nya.
- `test/scans.test.ts`: body berisi `screenshotBase64` valid → 201, `screenshot_path` null, tidak ada objek di Storage lokal, satu log `screenshot_ignored` tanpa id; `log-hygiene.test.ts` diperluas.
- `backend/API.md:446,483`: "diabaikan sejak fase 20a". Tanpa migrasi.

**20b backend (`feat/EX-07-screenshot-sunset`)**
- Hapus: `routes/screenshots.ts`, `test/screenshots.test.ts`, bagian screenshot di `services/scans.ts`, `db/repo/scans.ts`, `rateLimit.ts:22`, kind `screenshot` di link, `SupabaseStorageStore` + `screenshotStore`, cabang Supabase di retensi/tombstone/hapus device, `localSupabase()` di vitest.
- Pindah (K5): `services/objectStore.ts`, `services/signedLinks.ts`.
- `toScanResult(row, faviconUrl, pageReplicaUrl)` + `screenshotUrl: null` konstan (K2).
- `env.ts`, `wrangler.jsonc`, `.dev.vars.example`, `test/env.d.ts`, `vitest.config.ts`: tanpa `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SCREENSHOT_MAX_BYTES`.
- Migrasi add-only `<ts>_screenshot_sunset_indexes.sql` (`set local lock_timeout = '5s'`, `statement_timeout = '60s'`): dua index `_v3` (C10). pgTAP `retention_indexes.test.sql`: index `_v3` ada + predikat via `pg_indexes.indexdef`.
- `routes/privacy.ts` EN/ID + `privacy.test.ts`; docs backend (Peta dampak).
- Plan (di PR yang sama): `ARCHITECTURE.md` §2 + §3 (baris Supabase Storage: "tidak dipakai sejak fase 20; bucket dihapus 20c; kunci dicabut"), `SECURITY.md` T6/P2/P3/P9/P13, `ref/R3:107-113`, DECISIONS (K1–K9), `log/fase-20.md`, TODO E1 + D11.

**20c DB (`feat/EX-07-drop-screenshot-columns`)**
- Migrasi `<ts>_drop_screenshots.sql`, satu transaksi:
  ```sql
  set local lock_timeout = '5s';
  set local statement_timeout = '60s';
  do $$ begin
    if exists (select 1 from scans where screenshot_path is not null)
       or exists (select 1 from scans where favicon_path like '%-favicon.%')
       or exists (select 1 from storage_tombstones where not (path like '%-replica.html.gz' or path ~ '-icon\.[a-z]+$'))
       or exists (select 1 from storage.objects where bucket_id = 'screenshots')
    then raise exception 'fase 20c: Supabase Storage still in use (run the G1-G5 checks)';
    end if;
  end $$;
  drop index if exists scans_owner_shot, scans_original_shot, scans_shot_path, scans_plain_created, scans_shot_created;
  alter table scans drop column screenshot_path;
  alter index scans_plain_created_v3 rename to scans_plain_created;
  alter index scans_shot_created_v3 rename to scans_shot_created;
  -- Storage blocks direct deletes (storage.protect_delete); the bucket is empty (guard above).
  set local storage.allow_delete_query = 'true';
  delete from storage.buckets where id = 'screenshots';
  ```
- pgTAP: `storage.test.sql` → `is((select count(*) from storage.buckets where id = 'screenshots'), 0)` + `has_index … scans_favicon_path`; `grants.test.sql:37` → bucket tidak ada; `retention_indexes.test.sql` → regex predikat baru, `hasnt_column('public','scans','screenshot_path')`, `hasnt_index` untuk tiga index screenshot, tidak ada index `scans\_%\_v3` (pola `:21`).
- `db/scripts/quota-estimate.sql`, `backend/README.md:70,77`, `ref/R2` (kolom).

**20d app (`feat/DT-04-screenshot-sunset`)**
- Pindah: `Support/EvidenceSession.swift` (`configuration()`), `Support/RedirectRefuser.swift`, `Support/ImageDecoder.swift` (dari `ScreenshotDecoder`), `Features/Detail/ZoomedPage.swift` (dari `ZoomedScreenshot`), `Tests/DetailReplicaLinkTests.swift` (dari `DetailScreenshotLinkTests`, untuk `refreshReplicaLink`); pemakai di C13 diperbarui.
- Hapus: sisa `ScreenshotView.swift`, test loader screenshot di `DetailPrivacyTests.swift`, 3 key screenshot di string catalog (Peta), `refreshScreenshotLink`, `hasScreenshot`.
- `DetailView`/`DetailModel`/`PageCopyCaption`/`MockRepository` sesuai Peta dampak; tidak ada `.screenshotUrl` di `ios/ShooApp` selain fixture JSON.
- Label VoiceOver K8 EN/ID; before/after screenshot simulator di PR.

## Langkah kerja

### 20a — berhenti menerima screenshot (setelah G2)

1. LANGKAH MANUAL 1 (G2) lulus dulu, issue K7 sudah dibuat (LANGKAH MANUAL 8). 20a tidak menunggu jawaban: field opsional + deprecated, bentuk respons tidak berubah.
2. **Test dulu** (`superpowers:test-driven-development`): kasus di Output 20a → merah.
3. Kode `routes/scans.ts` → hijau; suite `scans`, `log-hygiene`, `favicons`, `replicas` tetap hijau.
4. Review berurutan `ecc:security-reviewer` → `ecc:typescript-reviewer`. PR (reviewer @umarmuhdhor), merge di menit :10–:40, tidak di 18:30–19:30 UTC. Catat jam deploy CI = awal jam G1 maksimum.

### 20b — hapus jalur screenshot + Supabase Storage (setelah G1, G3–G5 nol)

1. LANGKAH MANUAL 2 (G1, G3–G5) lulus, issue K7 sudah ada (dibuat sebelum 20a).
2. **Test dulu**: `GET /screenshots/<id>?…` → 404; `GET /scans/{id}` → `screenshotUrl === null` + ajv; retensi dengan satu store palsu: scan dengan favicon/replica dihapus bersama objeknya, scan tanpa objek masuk jalur plain; `dueTombstones` tanpa parameter store; `DELETE /devices/me` + `POST /devices/me/protected` menghapus objek R2; binding R2 hilang → retensi `failed`, tombstone tetap; tanpa test `env.SUPABASE_*` (bukti = `typecheck` setelah `test/env.d.ts` dibersihkan + `rg` kosong, Verifikasi 3); link favicon tidak membuka `/replicas/` dan sebaliknya (kind `screenshot` hilang). Merah.
3. Migrasi index `_v3` + pgTAP → `supabase test db` hijau.
4. Pindah file (K5) lebih dulu dalam commit terpisah (tanpa ubah perilaku, suite hijau), lalu hapus kode Supabase + screenshot → hijau.
5. `rg -n -i "screenshot|SUPABASE_URL|SERVICE_ROLE|storage/v1" backend/api/src` → hanya `SCREENSHOT_URL_SECRET` + `screenshotUrl: null` (dengan komentar K2).
6. Privasi + docs + plan (Output 20b) → `privacy.test.ts` hijau.
7. `npx wrangler deploy --dry-run --outdir "$TMPDIR/shoo-worker"` lalu `grep -c "storage/v1" "$TMPDIR/shoo-worker/index.js"` = 0.
8. Review berurutan: `ecc:security-reviewer` (P13: tidak ada objek yatim, tombstone R2 saja; P6) → `ecc:typescript-reviewer` → `ecc:database-reviewer` (index `_v3`, predikat sama persis dengan retensi). PR, merge (jam aman), tunggu CI hijau.

### 20c — drop kolom + bucket (satu deploy setelah 20b, setelah G6)

1. 20b sudah live (CI hijau) dan satu run retensi 19:00 UTC dengan `failed: 0`.
2. **Test dulu**: pgTAP C12 → merah. Bukti guard sekali, sebelum file 20c ditaruh di `migrations/` (pgTAP jalan setelah kolom di-drop, jadi tidak bisa): DB lokal di keadaan 20b, `docker exec -i supabase_db_shoo psql -U postgres` dengan `begin; insert into storage_tombstones (path) values ('dev/scan.jpg');` + blok `do $$` Output 20c + `rollback;` → gagal dengan pesan `fase 20c: Supabase Storage still in use`; tanpa insert → lulus. Catat di `log/fase-20.md`.
3. Migrasi (Output 20c) → `supabase db reset && supabase test db` hijau; `pnpm -C backend/api test` hijau (Worker 20b tidak membaca kolom).
4. Review `ecc:database-reviewer` (urutan drop/rename, `set local`, guard) → `ecc:security-reviewer`. PR, merge jam aman. CI menjalankan migrasi; kalau guard melempar, deploy berhenti (aman, tidak ada data hilang) → cek ulang G1–G5.

### 20d — app (setelah G1; paralel dengan 20c)

1. **Test dulu** (tanpa menyebut properti `screenshotUrl` di Swift; scan "lama" = fixture `blocked-92`, yang JSON-nya berisi `screenshotUrl` non-null): `DetailModelTests` (`awaitsCopy` hanya melihat `pageReplicaUrl`, fixture `blocked-92` tanpa salinan → `awaitsCopy` mengikuti umur saja), `PageCopyTests` (tanpa salinan → "No copy of this page", juga untuk `blocked-92`; argumen `screenshotUrl: nil` di `:141` dan `ActivityNoteTests.swift:12` dibuang, default `nil` memberwise init SE-0242), `DetailReplicaLinkTests` (port `DetailScreenshotLinkTests` ke `refreshReplicaLink`), `MockRepositoryTests` (salinan untuk daftar id fixture berbukti), test helper yang dipindah (`FaviconLoaderTests`, `ReplicaLoaderTests`, `DetailPrivacyTests` bagian decoder) → merah/compile error.
2. Pindah helper (commit terpisah, perilaku sama, suite hijau), lalu hapus jalur screenshot → hijau. `xcodegen` setelah file baru.
3. `rg -n "screenshotUrl|ScreenshotLoading|FixtureScreenshotLoader|refreshScreenshotLink" ios/ShooApp --glob '*.swift'` → kosong.
4. UI: `DetailUITests` dengan `-debug.replicaFixture YES`; gerbang UI Detail × {Guardian, Protected} × {EN, ID}, SE + XL; before/after screenshot (blocked-92 Mock: sebelum = screenshot fixture, sesudah = salinan fixture; scan tanpa salinan = placeholder).
5. Review `ecc:swift-reviewer` → `ecc:security-reviewer` (P9: helper URLSession tetap ephemeral, tanpa cache, redirect ditolak). PR.

## LANGKAH MANUAL

Semua SQL di bawah **read-only**, dijalankan Alief di Supabase SQL editor (atau `supabase db query --linked`). Catat **angka saja** di `log/fase-20.md`, tanpa id/nama/path (P6).

- [ ] **1. G2 — sebelum 20a: semua device demo di build ≥ #201.**
  - Checklist per HP demo (Alief, Umar, tester lain): app + extension dipasang ulang dari `main` ≥ 2720b13 (Xcode) atau build TestFlight dari commit itu. Versi di Profile selalu `0.1.0 (1)`, jadi catat tanggal pasang, bukan versi.
  - SQL (harus 0):
    ```sql
    -- Devices whose latest scan in the last 7 days still carried a screenshot (old build).
    select count(*) as devices_on_old_build from (
      select distinct on (owner_id) owner_id, screenshot_path
      from scans where created_at > now() - interval '7 days'
      order by owner_id, created_at desc) last
    where screenshot_path is not null;
    ```
  - Kalau > 0: lihat nama device di SQL editor (jangan disalin ke log/chat), minta pemiliknya update, ulangi.
- [ ] **2. G1 + G3–G5 — sebelum 20b.**
  ```sql
  -- G1: last screenshot row and the earliest date for 20b.
  select count(*) as rows_with_shot, max(created_at) as last_shot,
         max(created_at) + interval '15 days' as earliest_20b
  from scans where screenshot_path is not null;
  -- G3: old favicons in Supabase (expected 0, C3).
  select count(*) as old_favicons from scans where favicon_path like '%-favicon.%';
  -- G4: tombstones that point at Supabase Storage.
  select count(*) as supabase_tombstones from storage_tombstones
  where not (path like '%-replica.html.gz' or path ~ '-icon\.[a-z]+$');
  -- G5: objects left in Supabase Storage.
  select bucket_id, count(*) as objects, coalesce(sum((metadata->>'size')::bigint), 0) as bytes
  from storage.objects group by bucket_id;
  ```
  Lulus = `rows_with_shot = 0` (biasanya tercapai setelah `earliest_20b`; kalau masih > 0, retensi tertinggal: tunggu, karena 20b menghapus baris tanpa `screenshot_path` di predikat dan tanpa tombstone Supabase), G3 = 0, G4 = 0, G5 tanpa baris `screenshots` (atau 0 objek). Setelah 20a, cek juga Workers Logs (dashboard → Workers → `shoo-api` → Observability → Query Builder, `event = screenshot_ignored`, 48 jam terakhir) = 0. Kalau `rows_with_shot = 0` tetapi G5 > 0: objek yatim → tombstone manual (pola runbook takedown `backend/README.md:156`), tunggu satu run retensi, ulangi.
- [ ] **3. Setelah 20b live (CI hijau) + satu run retensi 19:00 UTC dengan `failed: 0` di log `retention`.** Hapus secret dari Worker (dari `backend/api/`, tidak di 18:30–19:30 UTC; perintah ini langsung men-deploy versi baru Worker tanpa secret):
  ```bash
  npx wrangler secret list                          # SUPABASE_SERVICE_ROLE_KEY masih ada
  npx wrangler secret delete SUPABASE_SERVICE_ROLE_KEY
  npx wrangler secret list                          # tidak ada lagi; SCREENSHOT_URL_SECRET, RATE_KEY_SECRET, APNS_* tetap
  ```
- [ ] **4. Cabut kunci di Supabase.** Dashboard → Project Settings → API Keys → Secret keys → kunci Worker (`shoo-worker` di `backend/README.md:111`, `shoo_worker` di TODO B5; cocokkan nama) → hapus/revoke. Tidak dibuat pengganti (tidak ada pemakai, C4). K9 (kunci legacy) diputuskan Alief di langkah ini.
- [ ] **5. Verifikasi cloud tanpa kunci** (Verifikasi butir 5): dengan `wrangler tail` terbuka, buka Activity (favicon) + Detail berisi salinan halaman di HP demo → 200, tanpa `favicon_read_failed`/`replica_read_failed`; `DELETE /devices/me` device uji → tanpa `objects_delete_failed`; run retensi berikutnya `failed: 0`. Supabase dashboard → Storage: tidak ada bucket `screenshots` (setelah 20c), Usage Storage 0.
- [ ] **6. G6 — sebelum merge 20c:** `select tgname from pg_trigger where tgrelid = 'storage.buckets'::regclass and not tgisinternal;` → ada `protect_buckets_delete` (sama dengan lokal) dan `select prosrc from pg_proc where proname = 'protect_delete';` memuat `storage.allow_delete_query`. Berbeda → K4 (b).
- [ ] **7. Setelah 20c:** CI hijau (migrasi + deploy); ulangi G5 → tidak ada baris; `select count(*) from information_schema.columns where table_name = 'scans' and column_name = 'screenshot_path';` = 0.
- [ ] **8. Issue K7** dibuat **sebelum merge 20a** (pertanyaan 2 menyangkut K3a yang live di 20a; `contracts/api.md:73` masih menjanjikan screenshot diterima), nomornya dicatat di TODO + PR 20a/20b/20d. Setelah PR Umar merge: PR kecil Alief buang `screenshotUrl: null` dari `toScanResult` (K2).

## Verifikasi

```bash
# 1. DB
(cd backend/db && supabase start && supabase db reset && supabase test db)
# 2. Backend
pnpm -C backend/api run typecheck
pnpm -C backend/api test                     # suite penuh (scans, retention, favicons, replicas, devices-me, security-review, log-hygiene, privacy)
# 3. Tidak ada sisa Supabase Storage di kode + bundle
rg -n -i "SUPABASE_URL|SERVICE_ROLE|SCREENSHOT_MAX_BYTES|storage/v1|SupabaseStorageStore" backend/api/src backend/api/test backend/api/vitest.config.ts backend/api/wrangler.jsonc backend/api/.dev.vars.example   # kosong
(cd backend/api && npx wrangler deploy --dry-run --outdir "$TMPDIR/shoo-worker") && grep -c "storage/v1" "$TMPDIR/shoo-worker/index.js"   # 0
# 4. Wire lokal tetap
bash plan/alief/qa/replica-e2e.sh
bash plan/alief/qa/push-e2e.sh
# 5. Cloud setelah LANGKAH MANUAL 3-4 (Alief)
SHOO_API=https://shoo-api.afindo-mi01.workers.dev bash plan/alief/qa/replica-e2e.sh --cloud   # wrangler tail terbuka
# 6. App
source plan/alief/ref/sim.sh
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,id=$SIM_ID" -only-testing:ShooAppTests
for SIM_ID in 483B28B6-913A-4C3A-8A4C-0C7219022682 4FBB910B-DA84-4552-B174-28396BD496DB; do xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,id=$SIM_ID" -only-testing:ShooAppUITests/DetailUITests -only-testing:ShooAppUITests/AccessibilityAuditUITests; done   # SE ("Shoo QA SE" iOS 26.5, yang dipertahankan fase 23) + XL (iPhone 17 Pro Max iOS 26.5)
rg -n "screenshotUrl|ScreenshotLoading|FixtureScreenshotLoader|refreshScreenshotLink" ios/ShooApp --glob '*.swift'   # kosong
```

## Kriteria selesai (DoD)

- [ ] G2 lulus dan tercatat (angka saja); 20a live: `screenshotBase64` diabaikan dengan 201, tidak ada objek baru di Supabase (test + Workers Logs Query Builder 48 jam tanpa `screenshot_ignored`).
- [ ] G1, G3, G4, G5 lulus sebelum merge 20b (angka di `log/fase-20.md`).
- [ ] `GET /screenshots/*` → 404; `GET /scans/{id}` dan `GET /scans` selalu `screenshotUrl: null`, valid ajv (test).
- [ ] Retensi, tombstone, `DELETE /devices/me`, `POST /devices/me/protected` hanya memakai R2, anggaran 40 × 100; objek R2 tetap terhapus walau `REPLICAS_ENABLED = "false"` (test lama tetap hijau).
- [ ] Kode, test, vitest, `wrangler.jsonc`, `.dev.vars.example` tanpa `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`/`SCREENSHOT_MAX_BYTES`; bundle tanpa `storage/v1` (Verifikasi butir 3).
- [ ] Secret dihapus dari Worker (`wrangler secret list`) dan kunci dicabut di Supabase; satu run retensi + uji asap cloud sesudahnya tanpa error store (LANGKAH MANUAL 3–5).
- [ ] 20c: kolom `screenshot_path` + lima index screenshot hilang, `_v3` di-rename, bucket `screenshots` hilang; guard terbukti melempar saat masih ada data (bukti `psql` lokal langkah 20c.2 di log); migrasi cloud lewat CI hijau.
- [ ] Halaman privasi EN/ID tanpa screenshot dan Supabase = database saja (test); `ARCHITECTURE.md` §2/§3, `SECURITY.md` T6/P2/P3/P9/P13, `ref/R2`, `ref/R3`, docs backend, DECISIONS, TODO E1 + D11 diperbarui.
- [ ] App: tidak ada `.screenshotUrl` di Swift app; favicon Activity + salinan halaman + zoom tetap jalan (helper dipindah, test hijau); "No copy of this page" saat tanpa salinan; label VoiceOver K8 EN/ID; before/after screenshot di PR.
- [ ] Issue K7 terbuka dan ditautkan; setelah PR Umar: `screenshotUrl` hilang dari respons (PR kecil K2).
- [ ] **Regresi**: pgTAP penuh, vitest penuh, typecheck, `replica-e2e.sh`, `push-e2e.sh`, `xcodebuild test` penuh ShooAppTests + ShooAppUITests hijau; review security tanpa HIGH terbuka.

## Risiko & rollback

- **Masih ada HP demo dengan build lama setelah 20a** → screenshot-nya diabaikan; scan tetap tersimpan, hanya tanpa bukti. Mitigasi: G2 sebelum 20a, log `screenshot_ignored`. Rollback 20a = revert PR (tanpa migrasi).
- **Secret dihapus terlalu cepat** → kalau 20b perlu di-revert, Worker lama tanpa kunci membuang screenshot (`services/screenshots.ts:86-90`) dan retensi Supabase gagal (`storage not configured`), tanpa kehilangan data DB. Mitigasi: hapus secret hanya setelah 20b stabil + satu run retensi `failed: 0`. Kalau perlu lagi: buat kunci Supabase baru (bukan memulihkan yang dicabut) + `wrangler secret put`.
- **Revert 20b** aman sebelum 20c (migrasi 20b add-only). **Setelah 20c tidak ada rollback** (kolom + bucket hilang) → forward-fix. Guard migrasi mencegah drop saat masih ada data Storage (P13).
- **Objek yatim di Supabase** (baris sudah hilang, objek tersisa) → G5 > 0 menahan 20b/20c; dibersihkan lewat tombstone + retensi sebelum kunci dicabut. Setelah kunci dicabut, pembersihan hanya lewat dashboard Storage.
- **Trigger Storage cloud berbeda** (C11) → migrasi 20c gagal di CI, deploy berhenti tanpa kerusakan. Fallback K4 (b).
- **Konflik dengan fase 19** (`db/repo/scans.ts`, `test/replicas.test.ts`) → merge 19 dulu, atau rebase 20b. Fase 21 dan 24 juga mengubah `cron/retention.ts` (`fase-24-privacy-data.md:7,292`): yang merge belakangan rebase.
- **Index retensi**: antara deploy 20b dan 20c, predikat kode = index `_v3` (dibuat di 20b), jadi rencana query tetap memakai index.

## Catatan handoff

- Tanggal 20b ditentukan G1, paling cepat ±16 Nov 2026 (perkiraan). Jalankan LANGKAH MANUAL 1 sesegera mungkin; setiap HP lama menggeser tanggal kalau 20a belum live.
- Fase 19 K5.3 (`screenshot_dropped`) dan fase 21: event itu hilang di 20a; `screenshot_ignored` hidup sampai 20b, lalu hilang. Jangan pasang alert fase 21 pada keduanya. Runbook `tombstones_stuck` fase 21 (`screenshots_delete_failed`) ikut diganti ke `objects_delete_failed` di PR 20b (K5).
- `SCREENSHOT_URL_SECRET` tetap dan tetap wajib (link favicon + salinan halaman). Ganti nama hanya kalau ada rotasi rahasia karena alasan lain.
- Setelah fase ini Supabase = database saja (Hyperdrive). `ARCHITECTURE.md` §3: hapus ambang D11 Storage 700 MB / 3,5 GB; pantau R2 saja.
- `ios/ShooApp/Data/Fixtures/*.json` masih memuat `screenshotUrl` sampai PR kontrak Umar; app sudah mengabaikannya.

## Riwayat verifikasi

- Ronde 1 (31 Okt 2026): 17 temuan (0 kritis, 0 tinggi, 7 sedang, 10 rendah); diperbaiki: waktu issue K7 jadi sebelum merge 20a (Urutan, langkah 20a/20b, LANGKAH MANUAL 8 seragam), test `env.SUPABASE_URL` yang bertentangan dengan `rg` kosong dibuang, test app 20d tanpa properti `screenshotUrl` (fixture `blocked-92`) + memberwise init tanpa `screenshotUrl: nil` (`ActivityNoteTests.swift:12`, `PageCopyTests.swift:141`) + file yang hilang dari Peta, `DetailScreenshotLinkTests` di-port ke `DetailReplicaLinkTests` (klaim "cakupan sudah ada" salah), bukti guard 20c lewat `psql` lokal sebelum migrasi (pgTAP tidak bisa setelah kolom di-drop), "`wrangler tail` 48 jam" diganti Workers Logs Query Builder, baris Peta 20a disamakan dengan C8; rendah: syarat G1 `rows_with_shot = 0`, rujukan fase 18 baris 229–230, string catalog (`stale` hanya satu key, key baru "Copy of the page"), baris `security_review.sql`, UDID simulator SE + XL, `.dev.vars.example` di `rg`, konflik fase 21/24, cek sisa index `_v3`, runbook fase 21, daftar baris docs/test; semua di baris yang sama, jadi rujukan fase 21 (`:11,219,264,326`) tetap tepat.
- Ronde 2 (31 Okt 2026): bagian yang diubah dibaca ulang; 1 temuan rendah (Output 20d belum menyebut `DetailReplicaLinkTests`), diperbaiki; 0 kritis/tinggi/sedang. Belum terverifikasi: trigger `storage.protect_delete` + `storage.allow_delete_query` (C11, Docker lokal mati saat verifikasi; G6 tetap gerbang), FK lain ke `storage.buckets` di Storage cloud (mis. `storage.prefixes`), nama keluaran `wrangler deploy --dry-run` (`index.js`), angka cloud G1–G5, "last used" kunci legacy (K9).
