# Verifikasi plan Alief — run 01

- **Tanggal:** 21 Okt 2026 (WITA)
- **Reviewer:** Claude Opus 5.5, sesi independen, read-only (satu-satunya file yang dibuat: file ini)
- **Branch/commit yang dibaca:** `docs/alief-plan` @ `a52de19`
- **Prompt:** `plan/alief/VERIFY_PROMPT.md` (cek A–H, format 1–6) + tambahan I (dokumentasi resmi) dan J (wiring)
- **Bacaan:** semua file di daftar `<bacaan>` sudah dibaca lengkap: CLAUDE.md (root, ios, ios/ShooApp, backend), CODEOWNERS, docs/README, mandat Alief, 3 spike, seluruh `contracts/` + fixtures, `ios/ShooShared/*.swift`, `ios/project.yml`, `ios/ShooApp/*.swift`, semua file `plan/alief/` (README, PROMPT, PROGRESS, TODO, ARCHITECTURE, SECURITY, fixbug, DECISIONS, log/fase-00, fase-00…17, R1–R7, qa/README).
- **PRD v1.5:** berhasil dibaca dari Google Drive (`Shoo-PRD-v1.5.docx`, id `1n_1vngw5fFizP9YHWg0kT3VnqGhgXlbV`). Gambar wireframe §6–§7 tidak ikut terbaca (hanya teks), jadi perbandingan dengan wireframe tidak bisa diverifikasi.
- **Laporan QA Catalyst:** dibaca dari Drive (`QA_Catalyst_DeepSeek_26Sep2026.docx`) untuk cek H.

---

## 1. Ringkasan pemahaman

1. Shoo = Safari Web Extension iPhone + app SwiftUI yang memberi skor 0–100 per halaman: 30–79 Warning (popup), ≥ 80 Blocked (layar blokir tanpa bypass). Skor dan sinyal dibuat Imelda, extension dan layar blokir milik Umar, app + backend milik Alief.
2. Dua mode permanen per perangkat, tanpa login: **Guardian** ("Protect myself and my family", bisa memantau ≤ 3 orang lewat Family mode) dan **Protected** ("Protected by others", orang tua, tidak pernah melihat tombol validasi).
3. App (iOS 17, `@Observable`, String Catalog EN/ID) memakai satu protocol `ShooRepository`: `MockRepository` dari `contracts/fixtures` di fase 01–06, lalu `ApiRepository` di fase 13 tanpa mengubah view.
4. Backend = Cloudflare Worker `shoo-api` (Hono + zod + postgres.js lewat Hyperdrive) sebagai satu-satunya pintu. Data di Supabase Postgres (role `shoo_api`, PostgREST tidak dipakai) dan screenshot di Supabase Storage (bucket private, signed URL 1 jam).
5. Push APNs token-based (JWT ES256) dari Worker; kalau `fetch` Worker tidak bisa HTTP/2 ke APNs, fallback Edge Function Supabase (Deno) yang dipanggil Worker dengan shared secret (spike fase 07, D-alief-16).
6. Retensi 14 hari lewat Cron Trigger Worker harian (scan + objek Storage, kode, percobaan join, push_log). Verdict tidak dihapus (D-alief-14).
7. Auth per device: token `shoo_` + 32 byte, hanya hash SHA-256 di DB. App menulis sesi ke App Group (`device.*`, `guardian.name`, `api.baseURL`, `ai.baseURL`) supaya extension bisa memanggil API.
8. Pairing: Guardian membuat kode 4 digit (60 s, multi-pakai, maks 3 Protected), QR + `inviteUrl` https yang membuka `shoo://join?code=`. Join dibatasi 5 gagal/10 menit per device dan per IP.
9. Alur inti: Protected membuka situs → extension `POST /scans` (skor ≥ 30, + screenshot) → Worker simpan + push ke Guardian (bahasa Guardian) → tap → Detail (`GET /scans/{id}`) → It's safe → `POST /verdicts` (per pemilik+domain) → extension Protected polling `GET /verdicts?domain=` tiap 5 s → layar blokir terbuka. Not safe → domain masuk `GET /blocklist` (layer 1 Imelda).
10. Track **app** (01→06→06Q) dan **be** (07→12) paralel di worktree terpisah; track **c** (13→16) setelah 06Q dan 12 selesai; fase 17 (ON-04, Live Activity push) ditahan sampai spike Umar.
11. Eksekusi otomatis lewat `PROMPT.md` (ECC + Superpowers): rencana → TDD → eksekusi → gerbang UI → review → verifikasi → log → PR ke main (reviewer Umar, stacked, agent tidak merge). Semua aksi cloud = LANGKAH MANUAL.
12. QA dua ronde format Catalyst: QA-A (simulator + fixtures) di 06Q dan QA-E2E (2 iPhone TestFlight + cloud) di 16, dengan fixbug "satu bug = satu test gagal = satu commit" dan blok Retest.

## 2. Verdict

**BELUM SIAP** — satu temuan KRITIS (cache Hyperdrive default membuat verdict, otorisasi, dan cek DB basi sampai ±75 detik di cloud, dan tidak terdeteksi oleh test lokal) dan enam TINGGI (konfigurasi postgres.js/Hyperdrive, file Info.plist/entitlements yang ditulis ulang XcodeGen, migrasi role yang tidak bisa jalan, sumber `extensionActive`, peracunan blocklist, definisi `[x]`/gate track c) harus ditutup di teks plan sebelum fase 01/07; semuanya bisa diperbaiki dengan edit dokumen kecil.

## 3. Tabel temuan

| # | Tingkat | File § bagian | Masalah | Usulan perbaikan |
|---|---|---|---|---|
| 1 | KRITIS | ARCHITECTURE.md §2–§3, TODO.md B4, fase-07 §Langkah 12, R3 §4 (`GET /verdicts`, `/healthz/db`) | Hyperdrive **meng-cache query baca secara default** (`max_age` 60 s + `stale_while_revalidate` 15 s, docs Cloudflare). Plan tidak menyebut cache sama sekali. Akibat di cloud: `GET /verdicts?domain=` bisa mengembalikan `null` sampai ±75 s setelah It's safe (melanggar "halaman langsung terbuka", DoD fase 15 "≤ 1 s", R7 #10 "≤ 10 s"); cek otorisasi `family_links` basi setelah disconnect (SECURITY T12); hitungan rate limit join basi kalau waktu dikirim sebagai parameter (fase 08 memakai "jam disuntik"); `select 1` monitor B9 bisa dilayani dari cache sehingga tidak dihitung aktivitas Supabase. Mode lokal (`localConnectionString`) **tidak** memakai cache, jadi semua test hijau tapi cloud salah. | Tambah keputusan baru (D-alief-17): buat Hyperdrive dengan `--caching-disabled` (B4: `npx wrangler hyperdrive create shoo-db --connection-string=... --caching-disabled`), atau minimal pakai dua binding (`DB` tanpa cache untuk semua query, cache hanya untuk `/blocklist`). Tambah langkah uji cloud di LANGKAH MANUAL fase 10: verdict → `GET /verdicts` ≤ 1 s melalui Worker deploy (bukan lokal). `/healthz/db` sebaiknya menulis (mis. `update heartbeat set at = now()`), bukan `select 1`. |
| 2 | TINGGI | R1 §1 (`db/client.ts`), fase-07 §Langkah 3, TODO.md B4 | R1 menulis `prepare: false` dan fase 07 "`prepare: false` bila memakai pooler transaksi"; TODO B4 menyarankan pooler Supabase 5432 atau 6543. Docs Cloudflare: postgres.js ≥ 3.4.5, **jangan** `prepare: false` (Hyperdrive tidak andal mendukungnya, query bisa hang), dan untuk Supabase pakai **Direct connection**, bukan string pooled, karena Hyperdrive sudah melakukan pooling. | R1: `postgres(env.DB.connectionString, { max: 5, fetch_types: false })` (prepare default `true`), versi `postgres@^3.4.5`. B4: pakai Direct connection Supabase. Karena host direct Supabase IPv6 secara default dan dukungan IPv6 Hyperdrive belum terdokumentasi, tulis fallback: session pooler port 5432 (user `shoo_api.<project_ref>`), bukan transaction pooler 6543. Hapus kalimat "prepare: false" di fase 07. |
| 3 | TINGGI | fase-14 §Bacaan wajib (`NSCameraUsageDescription` di `ShooApp/Info.plist` "file kita"), fase-15 §Output (`aps-environment` di `Shoo.entitlements` "file kita"), TODO C3, R5 §6 (`ShooAPIBaseURL` di Info.plist) | `ios/project.yml` mendefinisikan `info: path + properties` dan `entitlements: path + properties` untuk target Shoo. Docs XcodeGen: plist "dibuat di disk pada setiap generate" dan untuk entitlements "semua properties harus diberikan". Edit manual di `Info.plist`/`Shoo.entitlements` akan **hilang** di `xcodegen` berikutnya. ios/CLAUDE.md juga menyatakan Info.plist keys dan capability lewat lead. Jadi kamera (PR-01 Scan QR), push (ON-05/GD-06), dan base URL tidak bisa diselesaikan di folder Team App. | Ubah fase 14/15, R5 §6, TODO C3: semua key Info.plist (`NSCameraUsageDescription`) dan entitlement (`aps-environment`) adalah **permintaan ke Umar via project.yml**, dikirim sekarang (sebelum fase 02) bersama C1. `api.baseURL`: pakai konstanta Swift `#if DEBUG` di `ios/ShooApp/` (bukan Info.plist). Tambah gate "capability kamera + push ada di project.yml" sebelum fase 14/15. |
| 4 | TINGGI | R2 §3 (baris `create role shoo_api login password :'shoo_api_password' noinherit;`) vs R2 baris 117 dan fase-07 §Langkah 2 | Migrasi memakai variabel psql `:'shoo_api_password'`. `supabase db reset`/`db push` tidak menjalankan migrasi lewat psql dengan variabel, jadi migrasi gagal. Teks R2 sendiri bertentangan (password "tidak pernah ada di migrasi", diset di `seed.sql`/SQL editor). | Migrasi: `create role shoo_api login noinherit;` tanpa password. `seed.sql` (lokal): `alter role shoo_api password 'shoo_api_local';`. Cloud: `alter role ... password` lewat SQL editor (LANGKAH MANUAL, sudah ada). Tambah pgTAP `has_role('shoo_api')`. |
| 5 | TINGGI | R3 §4 (`GET /family/members` → `extensionActive`), D-alief-15, fase-05 §3, fase-08 §3 | Fallback "`extensionActive = true` kalau ada scan dalam 24 jam" membuat hampir semua orang tua sehat tampil **"Not connected"**, karena scan hanya dikirim untuk skor ≥ 30 (browsing normal tidak menghasilkan scan). Ini salah informasi di GD-03 (P0) dan R7 P0 ("memberi informasi salah"). Usulan D-alief-15 (app Protected mengirim `extensionLastSeenAt` saat dibuka) juga lemah: orang tua jarang membuka app. | Kirim usulan kontrak ke Umar **sebelum fase 08**: field opsional `extensionLastSeenAt` di `PATCH /devices/me` yang dikirim **oleh extension** (sudah punya token dari App Group) maksimal 1×/jam saat heartbeat, plus oleh app saat foreground. Sampai disetujui: tampilkan status "Unknown/–" alih-alih "Not connected", dan catat sebagai deviasi PRD di DECISIONS. |
| 6 | TINGGI | SECURITY.md T5, D-alief-06, TODO C6, R2 §5 | Mitigasi usulan C6 ("hanya domain dari scan `blocked`") tidak menahan serangan: siapa pun bisa `POST /devices` sebagai Guardian tanpa login, `POST /scans` skor 100 untuk `google.com` dari device-nya sendiri (T4 hanya memvalidasi bentuk), lalu `POST /verdicts not_safe` → domain masuk blocklist global → layer 1 Imelda memblokir semua pengguna. | Ubah C6 menjadi: (a) blocklist hanya dari verdict `not_safe` atas scan milik **Protected** yang terhubung (bukan scan Guardian sendiri), (b) minimal 2 keluarga berbeda atau review manual sebelum masuk global, (c) allowlist domain populer (mis. daftar top domain + domain resmi brand), (d) endpoint/cara hapus entri. Tambah test "Guardian baru + scan palsu + not_safe → tidak masuk /blocklist". Tetap butuh keputusan Umar + Imelda sebelum fase 10. |
| 7 | TINGGI | PROMPT.md §langkah 1, 10, 13; README §3 Gate; PROGRESS.md legenda; fase-13 §Prasyarat | Tidak ada definisi kapan baris PROGRESS jadi `[x]`: saat PR dibuka atau saat PR di-merge Umar? Track c "mulai setelah 06Q dan 12 `[x]`" lalu membuat branch dari `origin/main` di repo utama. Kalau `[x]` = PR dibuka (agent tidak boleh merge), track c mulai di atas main yang belum berisi kode app/be. Kalau `[x]` = merge, legenda `[~]` "menunggu langkah manual" juga dipakai untuk "menunggu review". Ambigu untuk mode auto. | Definisikan di PROGRESS legenda + PROMPT langkah 10: `[~]` = sedang/PR terbuka, `[x]` = PR **di-merge** ke main (dicek `gh pr view --json state`). Gate track c: `gh pr list --state merged` memuat semua PR fase 01–06Q dan 07–12. Kalau belum: berhenti dan laporkan PR yang menunggu review. |
| 8 | SEDANG | R3 §3 (`GET /scans?owner=family` = "protected aktif saya"), fase-09 DoD, fase-05 §4 | `contracts/fixtures/activity-family.json` (respons resmi `owner=family`) berisi `warning-63.json` milik `dev_me`/"Adhella" = Guardian sendiri. R3 mengecualikan scan Guardian sendiri. DoD fase 09 "cocok dengan bentuk `activity-family.json`" lolos bentuk tapi isi berbeda; GD-05 di fase 05 (mock) akan menampilkan scan sendiri, backend tidak. | Tanya Umar: apakah `owner=family` mencakup Guardian sendiri. Samakan R3 §3, fase-05, fase-09, dan MockRepository dengan jawabannya; catat D-alief. |
| 9 | SEDANG | R3 §4 `POST /scans` ("body = ScanResult tanpa `id`/`verdict`/`ownerDeviceId`/`ownerName`") | Kontrak: body = "ScanResult without `id`/`verdict`", jadi extension Umar boleh (bahkan wajar) mengirim `ownerDeviceId` dan `ownerName`. Kalau zod dibuat `.strict()` sesuai R3, request extension ditolak 422. | R3: field `ownerDeviceId`/`ownerName` **diterima tapi diabaikan** (server selalu memakai principal); tambah test "body berisi ownerDeviceId device lain → disimpan sebagai milik principal, bukan 422". |
| 10 | SEDANG | fase-04 §Langkah 2 ("Active = `extensionLastSeenAt` dalam 10 menit") | Bertentangan dengan `AppGroup.extensionActiveWindow` (24 jam) di `ios/ShooShared/AppGroup.swift`, R3 §4 (24 jam), dan ios/ShooApp/CLAUDE.md ("Do not invent another way"). Heartbeat hanya terjadi saat halaman dimuat, jadi 10 menit membuat status "Off" setiap orang tua berhenti browsing 10 menit. | Pakai `AppGroup.extensionActiveWindow` langsung (tanpa konstanta sendiri). Kalau ingin nilai lain, itu usulan ke Umar (ShooShared milik lead), tunggu spike #2. |
| 11 | SEDANG | fase-13 §Output (SessionStore), fase-06 §5, fase-14 §2, contracts/api.md (tidak ada endpoint status Protected) | (a) Protected tidak punya endpoint untuk mengetahui guardian-nya atau bahwa Guardian sudah menghapusnya (`DELETE /family/members/{id}`), jadi PR-04/PF-01 tetap "Protected by Adhella" dan extension tetap "Waiting for Adhella". (b) Plan tidak menyebut menghapus `guardian.name` dari App Group saat disconnect, atau memperbarui `device.name` di App Group setelah ganti nama di PF-01. (c) Avatar guardian (PR-04) hanya ada di respons join; tidak ada tempat simpan yang disebut. | Usulan kontrak ke Umar: `GET /devices/me` → `{ deviceId, name, avatarId, mode, language, guardian: {deviceId,name,avatarId} \| null }`. Fase 13: SessionStore menyimpan `guardian` (nama + avatar), menghapus `guardian.name` saat `leaveGuardian()`/404/`guardian == null`, dan menulis ulang `device.name` setelah `updateMe(name:)`. Tambah test untuk ketiganya. |
| 12 | SEDANG | fase-02 §Langkah 2 vs §Langkah 3 | ON-02 menampilkan avatar "dari `registerDevice` → `avatarId`", tapi `registerDevice(name:mode:)` baru dipanggil di ON-03 (butuh mode). Dengan API asli (fase 13), avatar tidak ada saat ON-02. | Pilih satu: tampilkan avatar setelah ON-03 (layar "Hai Adhella" + avatar), atau app memilih `avatarId` lokal dan mengirimnya (butuh usulan kontrak). Paling sederhana: pindahkan tampilan avatar ke setelah registrasi; catat D-alief. |
| 13 | SEDANG | fase-01 §Verifikasi (`SIM=...`), fase-02…06, 06Q, 13–16 §Verifikasi, fase-08 §Verifikasi, fase-12 §Verifikasi, fase-00 §Verifikasi | (a) Regex `grep -m1 -o 'iPhone [0-9a-zA-Z ]*'` menghasilkan `"iPhone 17 Pro "` dengan **spasi di akhir** (diuji pada baris contoh `simctl`), sehingga `-destination name=` tidak cocok. (b) `$SIM` hanya didefinisikan di fase 01; sesi baru di fase 02+ tidak punya variabel itu. (c) fase-08 dan fase-12: baris pertama `cd backend/db && ...`, baris berikut `pnpm -C backend/api ...` dan `gitleaks --source .` relatif terhadap root → path salah kalau dijalankan berurutan. (d) fase-00: `grep -rn "TODO(sync" plan/alief` "harus kosong", padahal PROMPT.md dan R5 memuat string itu (9 hasil saat ini). | (a) `SIM=$(xcrun simctl list devices available \| grep -oE 'iPhone [0-9]+( Pro( Max)?\| Plus\| mini)?' \| head -1)` atau pakai `-destination 'platform=iOS Simulator,OS=latest,name=...'` dengan UDID (`id=`). (b) Taruh definisi SIM di awal setiap blok Verifikasi atau di R5 sebagai satu baris yang wajib disalin. (c) Pakai subshell `(cd backend/db && supabase db reset && supabase test db)` seperti fase 16. (d) Ganti dengan `grep -rn "TODO(sync" ios/ShooApp backend \|\| true` atau kecualikan PROMPT.md/R5. |
| 14 | SEDANG | ARCHITECTURE.md §1 (panah "HTTP/2 + JWT ES256" dari Worker), fase-07 §Langkah 9, fase-11 §3 | Tidak ada dokumen resmi Cloudflare bahwa `fetch()` Worker bisa HTTP/2 ke origin; laporan komunitas (termasuk staf Cloudflare, lama) menyatakan HTTP/1.1, sedangkan APNs hanya HTTP/2. Spike di `wrangler dev` lokal (workerd di Mac) tidak mewakili jaringan edge produksi. Kemungkinan besar fallback Edge Function yang dipakai, tapi fallback baru dirinci di fase 11. | Jadikan relay Edge Function sebagai **jalur utama yang direncanakan** sampai spike di Worker **yang sudah di-deploy** membuktikan sebaliknya. Pindahkan spike ke LANGKAH MANUAL deploy pertama fase 07 (endpoint debug sementara di Worker cloud yang mengembalikan status APNs). Tambah ke ARCHITECTURE: "HTTP/2 dari Worker BELUM DIVERIFIKASI". Edge Function Free: 500.000 invocation/bulan (cukup). |
| 15 | SEDANG | R3 §6, fase-11 §Langkah 2 ("410/`BadDeviceToken` → kosongkan token") | `400 BadDeviceToken` juga muncul saat **environment salah** (token sandbox dikirim ke host production atau sebaliknya). Build TestFlight memakai APNs production; kalau `APNS_ENV` masih `sandbox`, semua token Guardian akan dihapus. | Kosongkan token hanya untuk `410 Unregistered`. Untuk `400 BadDeviceToken`: catat di `push_log` dan jangan hapus; tambah LANGKAH MANUAL fase 16 "set `APNS_ENV=production` sebelum TestFlight". |
| 16 | SEDANG | log/DECISIONS.md (ID `D-alief-NN`), PROMPT.md §6g/§6j, README §4 | Track app dan be berjalan paralel di worktree berbeda dan keduanya menambah entri `D-alief-NN` ke file yang sama. Keduanya akan memilih nomor berikutnya yang sama (mis. D-alief-17) → konflik merge dan ID dobel. | Bagi rentang ID per track (app: `D-alief-A01…`, be: `D-alief-B01…`, c: `D-alief-C01…`) atau satu file keputusan per fase (`log/decisions/fase-XX.md`) yang digabung saat track c. |
| 17 | SEDANG | R3 §4 (`GET /join?code=`, "Tidak memvalidasi kode"), fase-08 §Langkah 5 | Halaman HTML tanpa auth menampilkan `code` dari query string dan menaruhnya di link `shoo://join?code=`. Tanpa validasi format, ini celah reflected XSS / injeksi link di domain Worker (domain yang sama dengan API). CSP saja tidak cukup kalau nilai dimasukkan ke atribut. | Validasi `^\d{4}$` (selain itu tampilkan halaman tanpa kode), escape HTML, test XSS (`?code=<script>`), header `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'`. |
| 18 | SEDANG | R2 §5, R4 §4 (`NotSafe --> Safe`), contracts/api.md Blocklist | `GET /blocklist?since=` hanya mengirim penambahan. Kalau Guardian berubah pikiran (not_safe → safe) atau entri peracunan dibersihkan, detector yang sudah mengunduh daftar tetap memblokir domain itu selamanya. Query juga `max(decided_at)` per domain lintas keluarga, jadi satu keluarga safe tidak menghapus not_safe keluarga lain. | Usulan kontrak ke Umar + Imelda: tambahkan `removed: [{domain, removedAt}]` atau field `status` per entri, atau `since` kosong secara periodik (full refresh). Tulis test "not_safe lalu safe → domain keluar dari blocklist" begitu kontrak disetujui. |
| 19 | SEDANG | CLAUDE.md hard rule 1–2 vs README §4/§6.3, D-alief-02, fase-01 §Langkah 1 | (a) `plan/alief/` berada di luar folder Team App (hard rule 1) dan tidak tercatat sebagai pengecualian di DECISIONS. (b) Hard rule 2 berbunyi "NEVER edit `ios/project.yml` … write the proposal in the PR description and ask the lead"; D-alief-02 membiarkan agent mengedit langsung di mode auto dan C1 dikirim **setelah** PR dibuka. Batasnya hanya kalimat, tanpa diff yang diizinkan. | (a) Tambah D-alief entri pengecualian `plan/alief/` (CODEOWNERS `*` → Umar approve di G1). (b) D-alief-02: kirim C1 dan dapatkan "OK" Umar **sebelum** agent mengedit; tulis diff persis yang diizinkan (dua target, scheme test, `excludes` target Shoo) dan larangan menyentuh kunci lain; fase 01 berhenti (LANGKAH MANUAL) kalau OK belum ada. |
| 20 | RENDAH | R2 §2 (`verdicts` join per owner+domain), R4 §4, R3 §4 `GET /scans` | Karena verdict di-join per (pemilik, domain), scan **warning** di domain yang sama ikut menampilkan "Verified scam"/"Marked safe", padahal skema menyatakan "Only blocked items can get a verdict in MVP". | Di `toScanResult`, isi `verdict` hanya untuk `status = 'blocked'` (warning → `null`), atau minta keputusan Umar; tambah test. |
| 21 | RENDAH | R2 §2 (`page_title` nullable, `verdicts.by_device_id ... on delete set null`) | Skema kontrak: `pageTitle` bertipe `string` (bukan nullable) dan `Verdict.byDeviceId` wajib string. Kolom nullable bisa menghasilkan `null` yang melanggar JSON schema (Swift tetap bisa decode, tapi test schema extension/AI bisa gagal). | Mapper: hilangkan `pageTitle` kalau null; `by_device_id` `not null` (device tidak pernah dihapus di MVP) atau fallback string. Tambah test validasi respons dengan `scan-result.schema.json` (ajv) di vitest. |
| 22 | RENDAH | R1 §1, R5 §4, fase-07 §Langkah 3 (`vitest@^4`, `@cloudflare/vitest-plugin`) | Docs Cloudflare: `@cloudflare/vitest-plugin` butuh **Vitest 4.1+** (`vitest@^4.1.0`) dan dikonfigurasi dengan plugin `cloudflareTest()` di `vitest.config.ts`; binding Hyperdrive di test diatur lewat `miniflare.hyperdrives` (pola `provide`/`inject`), bukan otomatis dari `localConnectionString`. Fallback "`unstable_dev`" di fase 07 sudah usang. | Tulis versi `vitest@^4.1.0`, contoh config `cloudflareTest({ wrangler: { configPath: "./wrangler.jsonc" }, miniflare: { hyperdrives: { DB: "postgres://shoo_api:shoo_api_local@127.0.0.1:54322/postgres" } } })` (BELUM DIVERIFIKASI bentuk persisnya, cek recipe Hyperdrive), dan ganti fallback ke `wrangler dev` + vitest Node biasa. |
| 23 | RENDAH | fase-15 §DoD ("UI test dengan `simctl push`"), R7 §5 #10, fase-15 DoD "≤ 1 s" | XCUITest tidak bisa menjalankan `xcrun simctl push` dari dalam test runner (tidak ada API bawaan yang terdokumentasi untuk memicu push dari test; BELUM DIVERIFIKASI untuk Xcode terbaru). Target latensi juga tidak konsisten: ≤ 1 s (fase 15) vs ≤ 10 s (R7 #10) vs "langsung" (PRD). | DoD: test unit untuk routing payload (`NotificationRouter`), plus bukti manual `simctl push` + screenshot untuk tiga kondisi app. Satukan target: "≤ 10 s end-to-end (polling 5 s), `GET /verdicts` ≤ 1 s setelah POST". |
| 24 | RENDAH | SECURITY §1, fase-12 §Verifikasi, TODO D1; fase-08/09/10 `pnpm -C backend/api test -- family`; fase-07 `pnpm dev &` | `gitleaks` dipakai tapi tidak ada di D1. `pnpm test -- family` meneruskan `--` ke vitest sehingga filter bisa diabaikan (BELUM DIVERIFIKASI per versi pnpm). `pnpm dev &` lalu `curl` langsung = race. | D1: `brew install gitleaks`. Pakai `pnpm -C backend/api exec vitest run family`. Tambah `npx wait-on tcp:8787` atau `sleep` loop sebelum `curl`. |
| 25 | RENDAH | R4 §5 (retensi "ulangi sampai 20 batch"), fase-12 §Langkah 1 | Workers Free: Cron Trigger juga 10 ms CPU dan 50 subrequest per invocation. 20 batch × (select + DELETE Storage + delete) bisa mendekati batas subrequest. Uji lokal cron lewat `/cdn-cgi/local/scheduled` belum disebut. | Batas eksplisit: maks 10 batch per run, satu `DELETE /storage/v1/object/screenshots` dengan `prefixes` per batch; test lokal `curl "localhost:8787/cdn-cgi/local/scheduled?cron=0+19+*+*+*"`. |

Jumlah: **KRITIS 1 · TINGGI 6 · SEDANG 12 · RENDAH 6**.

## 4. Kontradiksi antar-dokumen

- **fase-04 §2 ↔ `ios/ShooShared/AppGroup.swift` + ios/ShooApp/CLAUDE.md + R3 §4:** ambang Active 10 menit vs `extensionActiveWindow` 24 jam dan larangan "invent another way".
- **fase-02 §2 ↔ fase-02 §3:** avatar ON-02 berasal dari `registerDevice`, padahal `registerDevice` dipanggil di ON-03.
- **R2 §3 (SQL) ↔ R2 §3 teks bawah + fase-07 §2:** password lewat variabel psql di migrasi vs "password tidak pernah ada di migrasi, diset di seed.sql/SQL editor".
- **R1 §1 + fase-07 §3 + TODO B4 ↔ docs Cloudflare Hyperdrive:** `prepare: false` + pooler 6543 vs `prepare` default + Direct connection.
- **fase-14 / fase-15 / R5 §6 / TODO C3 ↔ `ios/project.yml` + ios/CLAUDE.md:** Info.plist dan entitlements disebut "file kita", padahal di-generate dari `project.yml` milik lead.
- **R3 §3 (`owner=family`) ↔ `contracts/fixtures/activity-family.json`:** fixture memuat scan Guardian sendiri (`dev_me`).
- **R3 §4 (`POST /scans` body) ↔ contracts/api.md:** owner fields dikeluarkan dari body vs "ScanResult without id/verdict".
- **R4 §4 / R2 join verdict ↔ `scan-result.schema.json` (`verdict` description):** verdict ikut tampil di scan warning vs "Only blocked items can get a verdict".
- **fase-00 §Verifikasi ↔ PROMPT.md + R5 §7:** "grep TODO(sync harus kosong" padahal dua file itu memuat string tersebut.
- **fase-15 DoD (≤ 1 s) ↔ R7 §5 #10 (≤ 10 s) ↔ PRD §5 ("langsung terbuka"):** target latensi unblock berbeda.
- **fase-11 DoD ("payload persis kontrak + `sound`") ↔ contracts/api.md Push payloads:** kontrak tidak memuat `sound`; aditif dan aman, tapi kata "persis" salah. Sebutkan sebagai tambahan di C9.
- **ARCHITECTURE §1 (panah HTTP/2 Worker → APNs) ↔ fase-07 §9 + D-alief-16:** digambar sebagai fakta, padahal masih spike.
- **ARCHITECTURE §3 ("Hyperdrive kuota BELUM DIVERIFIKASI") ↔ docs Cloudflare:** sudah terverifikasi: Free 100.000 query/hari, ±20 koneksi origin per konfigurasi.
- **R5 §4 (`name=iPhone 16`) ↔ R5 §4 paragraf berikut + fase-01 (`$SIM`):** destination hardcode vs variabel.
- **README §7 butir 1 ↔ mandat "Definisi sukses MVP" butir 1:** plan mengecualikan ON-04 (P0), mandat tidak. Konsisten dengan "Ditahan dulu" di mandat, tapi perlu kalimat eksplisit dari Umar bahwa MVP Alief boleh selesai tanpa ON-04.
- **PRD §5 Validasi ("masuk whitelist keluarga") ↔ D-alief-09 (per pemilik):** sudah dicatat sebagai deviasi; tetap perlu konfirmasi Umar.
- **backend/CLAUDE.md ("document schema + RPCs here") ↔ R2 di `plan/alief/ref/`:** skema didokumentasikan di plan, bukan di `backend/`. Fase 07 sebaiknya menyalin ringkasan skema ke `backend/README.md`.

## 5. Lima risiko terbesar untuk MVP + mitigasi

1. **Push APNs dari Worker tidak bisa HTTP/2.** GD-06 (P0) dan definisi sukses butir 2 bergantung padanya. Mitigasi: rencanakan relay Edge Function sebagai jalur utama, uji di Worker cloud saat deploy pertama fase 07, simpan `PushSender` sebagai interface (sudah ada).
2. **Perilaku cloud berbeda dari lokal (cache Hyperdrive, koneksi Supabase direct/IPv6, CPU 10 ms).** Semua test lokal hijau tapi EX-06/GD-07 gagal di cloud. Mitigasi: `--caching-disabled`, smoke test cloud per fase be (LANGKAH MANUAL berisi pengukuran `GET /verdicts` setelah POST), `wrangler dev --remote` untuk satu skenario sebelum QA-E2E.
3. **Ketergantungan ke Umar** (project.yml: test target, kamera, push, Team ID; kontrak: `extensionLastSeenAt`, `inviteUrl`, screenshot, `owner=family`, status Protected; extension: polling verdict dan `POST /scans`). Mitigasi: kirim C1, C3, C5, D-alief-15, temuan #8/#11 dalam satu paket minggu ini; placeholder `TODO(sync:umar)` dan curl peniru extension untuk QA.
4. **TestFlight + dua iPhone fisik baru dibutuhkan di fase 16.** Team ID, App Store Connect, capability push, dan sertifikat bisa memakan hari. Mitigasi: majukan B6/B8 dan uji push sandbox ke satu iPhone di fase 11 (bukan 16).
5. **Penyalahgunaan endpoint anonim** (peracunan blocklist global, scan palsu → push spam, brute force kode dengan banyak device/IP) dan **kuota Supabase Free** (pause 7 hari, 1 GB Storage, 5 GB egress). Mitigasi: temuan #6, rate limit + batas device per IP, retensi + monitor menulis ke DB, ambang pindah ke R2 (E1) yang sudah ada.

## 6. Pertanyaan yang harus dijawab sebelum fase 01 dan 07

1. **Umar:** Apakah agent boleh mengedit `ios/project.yml` untuk target test (D-alief-02), dengan diff persis apa? Dan bisakah Umar sekalian menambah `NSCameraUsageDescription`, entitlement `aps-environment` (capability Push), dan Team ID, karena Info.plist/entitlements di-generate XcodeGen?
2. **Umar:** Apakah `GET /scans?owner=family` mencakup scan Guardian sendiri (fixture `activity-family.json` berkata ya)?
3. **Umar:** Setujukah field opsional `extensionLastSeenAt` di `PATCH /devices/me`, dan apakah **extension** (bukan hanya app) yang mengirimnya saat heartbeat?
4. **Umar:** Bolehkah endpoint baru `GET /devices/me` (atau `GET /family/guardian`) supaya Protected tahu guardian-nya dan tahu kalau sudah diputus?
5. **Umar + Imelda:** Aturan blocklist global: sumber verdict yang dihitung (hanya scan Protected?), minimal berapa keluarga, allowlist, dan cara menghapus entri (`removed` di `GET /blocklist`)?
6. **Umar:** Body `POST /scans` dari extension memuat `ownerDeviceId`/`ownerName` atau tidak? Server mengabaikannya, setuju?
7. **Umar:** Untuk Guardian yang membuka situs blocked sendiri (PRD §5 "User Guardian untuk dirinya → It's safe → halaman terbuka"), apakah extension Guardian juga polling `GET /verdicts?domain=`? Kontrak saat ini hanya menyebut Protected.
8. **Alief:** Setuju Hyperdrive dibuat dengan `--caching-disabled` dan memakai Direct connection Supabase (fallback session pooler 5432, bukan 6543)?

---

## I. Cek dokumentasi resmi

| # | Klaim di plan | Status | Sumber / koreksi |
|---|---|---|---|
| I1 | Workers Free: 100k request/hari, CPU 10 ms/request, 50 subrequest/request (ARCHITECTURE §3) | **VERIFIED** | https://developers.cloudflare.com/workers/platform/limits/ — 100.000/hari (reset 00:00 UTC), CPU 10 ms per HTTP request **dan per Cron Trigger**, 50 subrequest (1.000 ke layanan internal), 5 Cron Trigger per akun, 6 koneksi keluar simultan, memori 128 MB. |
| I2 | Hyperdrive tersedia di Workers Free, kuota "BELUM DIVERIFIKASI" | **VERIFIED** (kuota sekarang diketahui) | https://developers.cloudflare.com/hyperdrive/platform/pricing/ — termasuk Free dan Paid; Free 100.000 query/hari. https://developers.cloudflare.com/hyperdrive/platform/limits/ — Free: 10 konfigurasi, ±20 koneksi origin per konfigurasi, query maks 60 s. |
| I3 | Hyperdrive lokal lewat `localConnectionString` ke `supabase start` :54322 | **VERIFIED** | https://developers.cloudflare.com/hyperdrive/configuration/local-development/ — key `localConnectionString` di entry `hyperdrive`, atau env `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_<BINDING>` (menang kalau dua-duanya ada, disarankan agar password tidak di file). Mode lokal **tidak** memakai cache/pooling Hyperdrive. Port 54322: https://supabase.com/docs/reference/cli/supabase-start |
| I4 | (tidak disebut di plan) Cache query Hyperdrive | **WRONG (terlewat)** | https://developers.cloudflare.com/hyperdrive/concepts/query-caching/ — cache **aktif default**, `max_age` 60 s, `stale_while_revalidate` 15 s, hanya query baca; matikan dengan `--caching-disabled`. Lihat temuan #1. |
| I5 | postgres.js di Workers butuh `nodejs_compat`; `prepare: false` untuk pooler transaksi (fase 07, R1) | **Sebagian WRONG** | https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-drivers-and-libraries/postgres-js/ — `nodejs_compat` wajib (VERIFIED), postgres.js ≥ 3.4.5, `max: 5`, `fetch_types: false` (VERIFIED), client per request disarankan (VERIFIED); **jangan** `prepare: false` (WRONG). |
| I6 | Hyperdrive ke pooler Supabase 5432/6543 (TODO B4) | **WRONG** | https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-database-providers/supabase/ — pakai Direct connection, bukan string pooled. Catatan: host direct Supabase IPv6 secara default (https://supabase.com/docs/guides/troubleshooting/supabase--your-network-ipv4-and-ipv6-compatibility-cHe3BP); dukungan IPv6 Hyperdrive **UNVERIFIABLE** dari docs. |
| I7 | `vitest@^4` + `@cloudflare/vitest-plugin` | **Sebagian WRONG** | https://developers.cloudflare.com/workers/testing/vitest-integration/write-your-first-test/ — nama paket benar (`@cloudflare/vitest-plugin`, pengganti `@cloudflare/vitest-pool-workers`), tapi butuh **Vitest 4.1+** (`vitest@^4.1.0`), plugin `cloudflareTest()`. |
| I8 | Test bisa menjangkau Postgres lokal lewat Hyperdrive | **VERIFIED (pola), detail UNVERIFIABLE** | https://developers.cloudflare.com/workers/testing/vitest-integration/configuration/ — binding Hyperdrive di test dikonfigurasi lewat `miniflare.hyperdrives` (pola `provide`/`inject`, ada recipe Hyperdrive). Apakah `localConnectionString` dibaca otomatis oleh plugin tidak tertulis. |
| I9 | Workers Cron Triggers (`triggers.crons`, `0 19 * * *` UTC) | **VERIFIED** | https://developers.cloudflare.com/workers/configuration/cron-triggers/ — 5 field, UTC, uji lokal `/cdn-cgi/local/scheduled?cron=...`, propagasi ≤ 15 menit; Free 5 cron/akun dan 10 ms CPU per cron (I1). |
| I10 | `fetch()` Worker bisa HTTP/2 ke APNs (spike) | **UNVERIFIABLE** (indikasi negatif) | Tidak ada docs resmi. Forum Cloudflare: https://community.cloudflare.com/t/http-2-fetch-to-origin-from-workers/413317 (outbound terlihat HTTP/1.1). APNs hanya HTTP/2 (I15). Plan sudah punya spike + fallback; lihat temuan #14. |
| I11 | Fallback Edge Function Supabase (Deno) bisa HTTP/2 ke APNs | **UNVERIFIABLE** | Tidak ada docs Supabase yang menyebut APNs/HTTP/2. Edge Function Free 500.000 invocation: https://supabase.com/pricing |
| I12 | Supabase Free: 500 MB DB, 1 GB Storage, 5 GB egress, pause 7 hari | **VERIFIED** | https://supabase.com/pricing — 500 MB DB, 1 GB file storage, 5 GB egress (+ 5 GB cached egress terpisah), upload maks 50 MB, 2 proyek aktif, pause setelah 1 minggu tidak aktif. |
| I13 | Apa yang dihitung "aktivitas" (ARCHITECTURE §3, fase 12 §4) | **VERIFIED sebagian** | https://supabase.com/docs/guides/platform/project-pausing — "user database activity" dalam 7 hari; beberapa request DB per hari biasanya cukup; definisi persis tidak dijelaskan. Cron retensi harian yang menulis ke DB kemungkinan cukup; `select 1` lewat Hyperdrive bisa ter-cache (I4). |
| I14 | Storage REST: `POST /storage/v1/object/screenshots/<path>`, `POST /storage/v1/object/sign/screenshots/<path>`, `DELETE /storage/v1/object/screenshots` + `prefixes` | **VERIFIED** | Kode klien resmi https://github.com/supabase/storage-js/blob/main/src/packages/StorageFileApi.ts — upload `POST {url}/object/{bucket}/{path}`, sign `POST {url}/object/sign/{bucket}/{path}` body `{ expiresIn }` → `signedURL` relatif (URL penuh = `${SUPABASE_URL}/storage/v1` + `signedURL`), remove `{url}/object/{bucket}` body `{ prefixes }` (helper `remove` = DELETE). Bucket lewat `insert into storage.buckets` di migrasi: tidak dicek di docs (umum dipakai, risiko rendah). |
| I15 | APNs token auth: JWT ES256, `kid`, `iss`, `iat`, refresh, header | **VERIFIED** (halaman Apple dirender JS; isi diambil lewat ringkasan) | https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns dan https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns — HTTP/2 wajib, `api.push.apple.com` / `api.sandbox.push.apple.com`, `POST /3/device/<token>`, `authorization: bearer <JWT>`, `apns-push-type`, `apns-topic`, `apns-priority`; token JWT diperbarui tidak lebih sering dari 20 menit dan tidak lebih tua dari 60 menit (cache 50 menit di plan = OK); 400 `BadDeviceToken` (juga environment salah), 403 `InvalidProviderToken`, 410 `Unregistered`. |
| I16 | Supabase CLI `init`, `start` (`-x studio,imgproxy,edge-runtime,logflare,vector`), `test db` + pgTAP | **VERIFIED** | https://supabase.com/docs/reference/cli/supabase-start (daftar container yang bisa di-exclude memuat kelima nama itu), https://supabase.com/docs/reference/cli/supabase-test-db (menjalankan `pg_prove` atas `supabase/tests`, butuh `supabase start`), https://supabase.com/docs/guides/local-development/testing/overview (contoh test memakai `create extension if not exists pgtap with schema extensions;` — sertakan baris ini di setiap file test). |
| I17 | Perubahan grant Supabase 30 Okt 2026 (R2 §1) | **VERIFIED** | https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically — tabel baru di `public` tidak lagi otomatis diberi grant untuk Data API mulai 30 Okt 2026 untuk proyek lama; tabel yang sudah ada tidak berubah. Plan yang mencabut grant `anon`/`authenticated` dan tidak memakai PostgREST aman terhadap perubahan ini. |
| I18 | `.environment(\.locale)` mengubah teks String Catalog di iOS 17 | **UNVERIFIABLE** (tidak ada docs Apple yang eksplisit) | Plan sudah menandai BELUM DIVERIFIKASI + fallback (R5 §1, fase 01 §5). Sumber komunitas: `Text("literal")` (LocalizedStringKey) mengikuti locale environment, tetapi `String(localized:)` dan string dari variabel tidak: https://justdoswift.substack.com/p/switching-app-language-at-runtime. Tambahkan ke test fase 01: kasus `Text(stringVariable)` dan `String(localized:)` di view model. |
| I19 | XcodeGen: `bundle.unit-test`, `bundle.ui-testing`, `excludes` | **VERIFIED**, dengan koreksi Info.plist/entitlements | https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md — tipe `bundle.unit-test` dan `bundle.ui-testing` ada; `excludes` relatif ke `path` source, glob Bash 4 + `**`; `TEST_HOST` diset otomatis untuk unit test yang menarget app; **plist (Info.plist, entitlements) ditulis ulang setiap generate** → temuan #3. |
| I20 | WhatsApp tidak membuat `shoo://` bisa diklik (D-alief-03) | **UNVERIFIABLE** | Tidak ada dokumentasi resmi WhatsApp tentang skema kustom. Desain halaman https `/join` aman di kedua kemungkinan, jadi keputusan tetap masuk akal; uji di QA-E2E #4. |

## J. Cek wiring ujung ke ujung

### J1. `ShooRepository` (fase-01 §2) → `contracts/api.md` → fase backend

| Method app | Endpoint kontrak | Diimplementasi di | Catatan |
|---|---|---|---|
| `registerDevice(name:mode:)` | `POST /devices` | fase 07 §5 | `apnsToken?` dikirim belakangan lewat `PATCH` (fase 15). `language` tidak ada di `POST`, jadi app ID harus langsung `PATCH language` setelah registrasi (belum tertulis di fase 13). |
| `updateMe(name:language:apnsToken:)` | `PATCH /devices/me` | fase 07 §6 | OK. |
| `createFamilyCode()` | `POST /family/code` | fase 08 §1 | OK. |
| `joinFamily(code:)` | `POST /family/join` | fase 08 §2 | OK + `already_connected` (kode tambahan, dilaporkan ke Umar). |
| `familyMembers()` | `GET /family/members` | fase 08 §3 | `extensionActive` bermasalah (temuan #5). |
| `removeMember(_:)` | `DELETE /family/members/{id}` | fase 08 §4 | OK. |
| `leaveGuardian()` | `DELETE /family/guardian` | fase 08 §4 | OK; App Group `guardian.name` tidak dihapus (temuan #11). |
| `scans(owner:status:cursor:)` | `GET /scans` | fase 09 §2 | `limit` tambahan di backend, tidak di protocol (boleh). Semantik `family` (temuan #8). |
| `scan(id:)` | `GET /scans/{id}` | fase 09 §3 | OK. |
| `setVerdict(scanId:value:)` | `POST /verdicts` | fase 10 §1 | OK. |
| — (tidak ada) | status Protected / guardian saya | tidak ada | **Celah**: tidak ada endpoint; lihat temuan #11. |

Endpoint yang tidak dipakai app tapi dipakai tim lain: `POST /scans` (extension, fase 09), `GET /verdicts?domain=` (extension, fase 10), `GET /blocklist` (detector, fase 07 + 10). Semua punya fase. **Semua 10 method protocol terpetakan.**

### J2. Key App Group (`contracts/app-group-keys.md`) → fase yang menulis

| Key | Ditulis oleh | Status |
|---|---|---|
| `device.id`, `device.token`, `device.mode` | fase 13 `SessionStore` | OK |
| `device.name` | fase 13 | Ditulis saat onboarding; **tidak** diperbarui setelah ganti nama di PF-01 (temuan #11) |
| `guardian.name` | fase 14 §2 | Ditulis saat join; **tidak** dihapus saat disconnect (temuan #11) |
| `api.baseURL` | fase 13 | OK, tapi sumber nilainya (R5 §6 Info.plist) harus diganti `#if DEBUG` (temuan #3) |
| `ai.baseURL` | fase 13 | Placeholder `TODO(sync:imelda)` |
| `extension.lastSeenAt` | Extension (Umar) | Dibaca fase 01 `ExtensionStatus`, fase 04/05/06 |

**Semua key yang ditulis App punya fase.** Native message `getSession` dibaca extension dari key-key ini; tidak ada pekerjaan Alief tambahan.

### J3. Output/handoff → dipakai fase berikutnya

| Dari | Output | Dipakai di | Status |
|---|---|---|---|
| 01 | protocol, `MockRepository`, `AppSettings`, `Router`, komponen, target test | 02–06, 13 | OK |
| 02 | `NotificationReminderBanner`, placeholder ON-04 + Connect, registrasi APNs disiapkan | 04/05, 17, 14, 15 | OK |
| 03 | `DetailView` + `VerdictButtons` | 15 | OK |
| 04 | `ActivityModel` | 05 | OK |
| 05 | placeholder "Invite your family" | 14 | OK |
| 06 | menu Family code placeholder, `leaveGuardian` | 14, 13 | OK |
| 06Q | laporan QA-A, G5 | gate 13 | OK (definisi `[x]` ambigu, temuan #7) |
| 07 | `auth`, `ApiError`, repo pattern, `resetDb()`, D-alief-16, URL Worker | 08–12, 11, Imelda (C7) | `resetDb()` tidak ada di daftar Output fase 07 (R1 hanya `helpers/seed.ts`); tambahkan |
| 08 | `/join` page, `inviteUrl` | 14 | OK |
| 09 | `PushSender` + `LogSender`, `ScreenshotStore` | 11, 12 | OK |
| 10 | verdict asli, G4 | 15, Umar (C8) | OK |
| 11 | `ApnsSender`/`RelaySender`, `push_log` | 15 | OK |
| 12 | cron retensi, deploy final, G6 | 13, QA-E2E #16 | OK |
| 13 | `ApiRepository`, `SessionStore` | 14, 15 | OK |
| 14 | pairing, `guardian.name` | 15, 16 | OK |
| 15 | `push-blocked.apns`, tap → Detail | 16 | OK |

Tidak ada output yang menggantung, kecuali `resetDb()`.

### J4. Checkbox mandat (`docs/mandates/alief.md`) → fase

| Checkbox | Fase | Status |
|---|---|---|
| Fondasi (`feat/APP-foundation`) | 01 | OK |
| ON-01 | 02 | OK |
| ON-02 | 02 (+13) | OK (temuan #12) |
| ON-03 | 02 (+13) | OK |
| ON-05 | 02 (+15) | OK |
| DT-01 s.d. DT-06 | 03 | OK |
| PR-04, PR-05 | 04 | OK |
| GD-01, GD-02, GD-03, GD-05 | 05 | OK |
| PF-01 | 06 | OK |
| Devices | 07 | OK |
| Family | 08 | OK |
| Scans | 09 | OK |
| Verdicts | 10 | OK |
| Blocklist | 07 (awal) + 10 | Dobel disengaja (mandat: "kerjakan lebih awal"), jelas |
| Push (APNs) | 11 | OK |
| Retensi | 12 | OK |
| Keamanan | 08, 09, 10, 12 | Tersebar; boleh, tapi tentukan fase mana yang mencentang (usul: 12) |
| `ApiRepository` | 13 | OK |
| Key sesi App Group | 13 | OK |
| GD-04 | 14 | OK |
| PR-01, PR-02 | 14 | OK |
| PR-03 | 14 | OK (P1 deferred → TODO E4) |
| GD-06 | 15 (+11) | OK |
| GD-07 | 15 (+03, +10) | OK |
| Ditahan: ON-04, Live Activity push | 17 | OK |

**Tidak ada checkbox yang hilang.** Tidak ada pekerjaan di luar `ios/ShooApp/` dan `backend/` selain `plan/alief/`, `docs/mandates/alief.md` (dibolehkan CODEOWNERS) dan `ios/project.yml` (D-alief-02, temuan #19). Temuan #3 menunjukkan tiga perubahan lagi yang sebenarnya jatuh ke `project.yml`.

### J5. Skema R2 → field respons kontrak dan fixture

| Field kontrak | Kolom R2 | Status |
|---|---|---|
| ScanResult `id` (uuid) | `scans.id text default gen_random_uuid()` | OK (fixture memakai UUID valid) |
| `url`, `domain`, `score`, `status`, `signals`, `detectedAt` | kolom sama nama | OK (check constraint cocok ambang) |
| `pageTitle` (string, tidak nullable) | `page_title` nullable | Mapper harus menghilangkan null (temuan #21) |
| `faviconUrl` (nullable) | `favicon_url` | OK |
| `screenshotUrl` | `screenshot_path` → signed URL | OK (null di daftar, D-alief-04) |
| `ownerDeviceId`, `ownerName` (≤ 20) | `owner_id` + join `devices.name` (1–20) | OK |
| `verdict` {value, byDeviceId, byName, decidedAt} | `verdicts` (owner, domain) | `by_device_id` bisa null (temuan #21); verdict ikut ke scan warning (temuan #20) |
| family member {deviceId, name, avatarId, extensionActive, lastScan{status,score,url,detectedAt}} | `devices`, `family_links`, `ext_last_seen_at`, scan terbaru | Bentuk OK; sumber `extensionActive` (temuan #5) |
| `POST /family/code` {code, expiresAt, inviteUrl} | `family_codes` + env `INVITE_BASE_URL` | OK |
| join {guardian{deviceId,name,avatarId}} | `devices` | OK |
| `POST /devices` {deviceId, token, avatarId} | `devices` + `token_hash` | OK |
| blocklist {domains[{domain, addedAt}], nextSince} | `verdicts` | OK; tidak ada cara mengirim penghapusan (temuan #18) |
| ID fixture `dev_mom`, `dev_dad`, `dev_me` | `devices.id text` | OK (keputusan R2 §1) |
| bahasa push | `devices.language` | OK |

### J6. Perintah di bagian Verifikasi bisa dijalankan apa adanya?

| Fase | Masalah |
|---|---|
| 00 | `grep -rn "TODO(sync" plan/alief` tidak akan kosong (9 hasil) |
| 01 | `SIM` berakhiran spasi (diuji); `cd ios` lalu path relatif OK |
| 02–06, 06Q, 13–16 | `$SIM` tidak didefinisikan di sesi baru; selain itu flag `xcodebuild test -only-testing:<Target>/<Suite>` valid |
| 07 | `cd backend/db` lalu `cd ../api` OK; `pnpm dev &` lalu `curl` langsung = race; `pnpm typecheck` harus ada di `package.json` (tidak disebut di Output) |
| 08 | `cd backend/db && ...` lalu `pnpm -C backend/api ...` → path salah dari `backend/db` |
| 09, 10, 11 | `pnpm -C backend/api test -- <filter>`: filter bisa diabaikan (temuan #24); urutan cd di 09 aman karena `cd` di baris terakhir |
| 12 | Sama dengan 08 (cd lalu path root); `gitleaks` tidak ada di D1 |
| 14 | `xcrun simctl openurl booted "shoo://join?code=1234"` valid |
| 15 | `xcrun simctl push booted com.shoo.app plan/alief/qa/push-blocked.apns` valid (dijalankan dari root; file dibuat di fase itu) |
| 16 | Memakai subshell, OK |

---

## Catatan untuk run berikutnya

- Fokus ulang: temuan #1–#7, lalu jawaban Umar atas pertanyaan §6 (khususnya #1, #2, #3, #5).
- Yang tidak bisa diverifikasi di run ini: wireframe PRD §7 (gambar), perilaku HTTP/2 Worker → APNs, HTTP/2 Edge Function Supabase, IPv6 Hyperdrive, locale environment + String Catalog iOS 17, perilaku link WhatsApp. Semuanya butuh uji nyata, bukan docs.
