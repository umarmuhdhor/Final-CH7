# Verifikasi plan Alief — run 02

- **Tanggal:** 21 Okt 2026 (WITA)
- **Reviewer:** Claude Opus 5.5, sesi independen, read-only (satu-satunya file yang dibuat: file ini)
- **Branch/commit yang dibaca:** `docs/alief-plan` @ `60de56b` (perbaikan run 01; diff `a52de19..60de56b` juga dibaca)
- **Prompt:** `plan/alief/VERIFY_PROMPT.md` (cek A–H, format 1–6) + tambahan I (dokumentasi resmi), J (wiring), dan §2a (status temuan run 01)
- **Bacaan:** semua file di daftar `<bacaan>` dibaca lengkap: CLAUDE.md (root, ios, ios/ShooApp, backend), CODEOWNERS, docs/README, mandat Alief, 3 spike, seluruh `contracts/` + fixtures, `ios/ShooShared/*.swift`, `ios/project.yml`, `ios/ShooApp/*.swift` (+ Info.plist, entitlements, `SafariWebExtensionHandler.swift`, `background.js` sebagai konteks), semua file `plan/alief/` termasuk `ref/sim.sh`, `log/DECISIONS.md`, `log/fase-00.md`, dan `log/verify/run-01.md`.
- **PRD v1.5:** berhasil dibaca dari Google Drive (`Shoo-PRD-v1.5.docx`, id `1n_1vngw5fFizP9YHWg0kT3VnqGhgXlbV`). Gambar wireframe §6–§7 tidak ikut terbaca (hanya teks), jadi perbandingan dengan wireframe tidak bisa diverifikasi.
- **Laporan QA Catalyst:** dibaca dari Drive (`QA_Catalyst_DeepSeek_26Sep2026.docx`, id `1ZHVIvha4RxRS1Bgp1dK20VUIByez9mwT`) untuk cek H.
- **Perintah read-only yang dijalankan:** `bash -n` + `source plan/alief/ref/sim.sh` (bash dan zsh), grep Verifikasi fase 00, `git diff --stat origin/main -- . ':!plan/alief'`, `xcrun simctl help push|get_app_container`, `xcrun simctl list devices available`, `gitleaks version`/`detect --help`. Tidak ada build, `supabase start`, atau deploy.

---

## 1. Ringkasan pemahaman

1. Shoo = Safari Web Extension iPhone + app SwiftUI. Skor 0–100 per halaman: 30–79 Warning (popup), ≥ 80 Blocked (layar blokir tanpa bypass). Skor/sinyal milik Imelda, extension + layar blokir milik Umar, app + backend milik Alief.
2. Dua mode permanen tanpa login: **Guardian** (melindungi diri + Family mode ≤ 3 orang) dan **Protected** (orang tua; tidak pernah melihat tombol validasi).
3. App iOS 17 (`@Observable`, String Catalog EN/ID) memakai protocol `ShooRepository`: `MockRepository` (fixtures) di fase 01–06, `ApiRepository` di fase 13 tanpa mengubah view.
4. Backend = Worker Cloudflare `shoo-api` (Hono + zod + postgres.js) → Hyperdrive **tanpa cache** (`--caching-disabled`, D-alief-17) → Supabase Postgres (role `shoo_api`, PostgREST tidak dipakai) + Storage private (signed URL 1 jam).
5. Push: jalur utama **relay** Worker → Edge Function Supabase `push` (Deno, shared secret) → APNs HTTP/2 JWT ES256. Push langsung dari Worker hanya kalau spike di Worker yang sudah di-deploy lulus (D-alief-16).
6. Auth per device: token `shoo_` + 32 byte, hanya hash SHA-256 di DB; app menulis `device.*`, `guardian.name`, `api.baseURL`, `ai.baseURL` ke App Group untuk extension.
7. Pairing: kode 4 digit 60 s multi-pakai, maks 3 Protected, 5 gagal/10 menit per device dan per IP; `inviteUrl` https `/join?code=` yang membuka `shoo://join?code=` (usulan C5).
8. Alur inti: Protected membuka situs → extension `POST /scans` (≥ 30, + screenshot) → Worker simpan + push (bahasa Guardian) → tap → Detail → It's safe → `POST /verdicts` (per pemilik+domain) → extension polling `GET /verdicts?domain=` 5 s → layar blokir terbuka (target ≤ 10 s ujung ke ujung). Not safe → domain masuk `/blocklist` (dengan filter bawaan R2 §5).
9. Retensi 14 hari lewat Cron Worker harian (maks 10 batch), `ops_heartbeat` ditulis cron + `/healthz/db` supaya Supabase Free tidak pause.
10. Track **app** (01→06→06Q) dan **be** (07→12) paralel di worktree; track **c** (13→16) setelah semua PR 01–06Q dan 07–12 **merged**; fase 17 (ON-04, Live Activity push) ditahan.
11. Eksekusi otomatis lewat `PROMPT.md`: status `[ ]/[~]/[r]/[x]/[!]`, branch stacked, PR ke main (Umar merge), semua aksi cloud = LANGKAH MANUAL, ID keputusan per track (`D-alief-A/B/C…`).
12. QA dua ronde format Catalyst (QA-A di 06Q, QA-E2E di 16) dengan fixbug "satu bug = satu test gagal = satu commit" dan blok Retest.

## 2. Verdict

**BELUM SIAP** — tidak ada KRITIS lagi dan semua KRITIS/TINGGI run 01 kecuali #6 sudah tertutup, tetapi ada dua TINGGI: (a) **regresi** dari perbaikan #7: mode auto sekarang hanya mengambil fase `[ ]`, sehingga fase yang berhenti di LANGKAH MANUAL (`[~]`) dilewati saat Alief mengetik ulang kalimat yang sama, dan (b) filter blocklist bawaan (#6) masih bisa dilewati dengan dua device anonim. Keduanya cukup diperbaiki dengan edit teks kecil.

## 2a. Status temuan run 01

| run-01 # | Tingkat | Status | Bukti (file:baris di `60de56b`) |
|---|---|---|---|
| 1 | KRITIS | **FIXED** | `TODO.md:39` (`--caching-disabled`), `ARCHITECTURE.md:48,60`, `log/DECISIONS.md:133-138` (D-alief-17), `fase-07-be-fondasi.md:46,67`, `fase-10-be-verdicts.md:28,41` (uji cloud), `SECURITY.md:35,37` (T12, T14), `ref/R3-catatan-api.md:67` (`/healthz/db` menulis) |
| 2 | TINGGI | **FIXED** | `ref/R1-struktur-repo.md:14,24`, `fase-07-be-fondasi.md:34,75`, `TODO.md:39`, D-alief-17. Format user pooler `shoo_api.<ref>` sesuai docs Supabase (I5) |
| 3 | TINGGI | **FIXED** (catatan baru #N8) | `PROMPT.md:144-146` (6k), `ref/R5-konvensi.md:46`, `ref/R1-struktur-repo.md:64`, `fase-14-pairing.md:20`, `fase-15-push-validasi.md:24`, `TODO.md:52` (C3), `SECURITY.md:51`. Kalimat baru di `fase-15:24` ("tanpa itu registrasi APNs di simulator tetap jalan") salah → #N8 |
| 4 | TINGGI | **FIXED** | `ref/R2-skema-db.md:111,122` (role tanpa password, `seed.sql`, `has_role`), `fase-07-be-fondasi.md:25,33,45` |
| 5 | TINGGI | **FIXED** (dampak baru #N5) | `ref/R3-catatan-api.md:59` (tanpa data → `true`), `log/DECISIONS.md:181` (D-alief-24), `fase-08-be-family.md:31`, `fase-05-guardian-family.md:32`, `TODO.md:60` (C11 dikirim extension). Matriks QA-E2E `R7:64` masih mengharapkan "Not connected" → #N5 |
| 6 | TINGGI | **PARTIALLY** | Filter bawaan ditambahkan (`ref/R2-skema-db.md:140-156`, `fase-10-be-verdicts.md:25,36`, `SECURITY.md:28`), tetapi bisa dilewati dengan dua device anonim; default `BLOCKLIST_MIN_FAMILIES = 1` (`R3:105`) → tetap TINGGI sebagai #N2 |
| 7 | TINGGI | **FIXED + REGRESSION** | Definisi `[r]`/`[x]` = merged dan gate track c via `gh pr view` sudah ada (`PROGRESS.md:3-5`, `PROMPT.md:84-91,170`, `README.md:80`, `fase-13-api-repository.md:7`). Regresi: `PROMPT.md:87` hanya memilih `[ ]` → fase `[~]` (LANGKAH MANUAL) tidak pernah dilanjutkan → #N1 |
| 8 | SEDANG | **FIXED** | D-alief-19 (`DECISIONS.md:147-151`), `R3:47`, `fase-05:33`, `fase-09:30,45`, `TODO.md:62` (C13) |
| 9 | SEDANG | **FIXED** | `R3:60`, `fase-09-be-scans.md:29,46`, `TODO.md:59` (C10) |
| 10 | SEDANG | **FIXED** | `fase-04-protected.md:30`, D-alief-23 (`DECISIONS.md:171-175`) |
| 11 | SEDANG | **FIXED** (celah tercatat) | `fase-13-api-repository.md:25,27,53`, D-alief-21 (`DECISIONS.md:159-163`), `TODO.md:61` (C12). Pemutusan oleh Guardian tetap tidak terdeteksi Protected sampai C12 — dicatat jujur |
| 12 | SEDANG | **FIXED** | `fase-02-onboarding.md:30-31,49`, D-alief-22 |
| 13 | SEDANG | **FIXED** (sisa kecil #N11) | `ref/sim.sh` (diuji: `SIM=iPhone 17 Pro`, tanpa spasi, bash + zsh), semua blok iOS diawali `source plan/alief/ref/sim.sh`, subshell di `fase-08:40`, `fase-12:33`, grep `fase-00:39` (diuji: kosong) |
| 14 | SEDANG | **FIXED** | `ARCHITECTURE.md:34-36,51`, D-alief-16 (`DECISIONS.md:126-131`), `fase-07-be-fondasi.md:40,49,68` |
| 15 | SEDANG | **FIXED** | `R3:92`, `fase-11-be-push.md:29,36`, `fase-16-qa-e2e.md:22`, `TODO.md:42` (B7) |
| 16 | SEDANG | **FIXED** (sisa teks #N12) | `PROMPT.md:136-137`, `README.md:90-92`. `PROMPT.md:62` dan `README.md:47` masih menulis "ID D-alief-NN" |
| 17 | SEDANG | **FIXED** | `R3:58`, `fase-08-be-family.md:33,44`, `SECURITY.md:36` (T13) |
| 18 | SEDANG | **FIXED** (usulan) | D-alief-18, `R2:158`, `TODO.md:55` (C6 butir d) |
| 19 | SEDANG | **PARTIALLY** | D-alief-20 (pengecualian `plan/alief/`) dan diff persis D-alief-24 (`DECISIONS.md:179`) ditambahkan. Alief sengaja memilih "tidak perlu menunggu izin" (`TODO.md:23`), yang sah sebagai keputusan pemilik dan tetap di-gate CODEOWNERS. Tapi diff "PERSIS" itu kemungkinan kurang satu setting agar target test bisa di-build → #N3 |
| 20 | RENDAH | **FIXED** | `R3:62`, `R4:58`, `fase-09:30`, `fase-10:36` |
| 21 | RENDAH | **FIXED** | `R2:86` (`by_device_id not null`), `R3:62` (`pageTitle` null dihilangkan), `fase-09:30` (ajv + schema), `R1:45` |
| 22 | RENDAH | **FIXED** | `R1:14`, `R5:34`, `fase-07-be-fondasi.md:20,26,41` (`vitest@^4.1.0`, `cloudflareTest()`, `miniflare.hyperdrives`; fallback bukan `unstable_dev`) |
| 23 | RENDAH | **FIXED** | `fase-15-push-validasi.md:35,51-52`, target ≤ 1 s / ≤ 10 s seragam di `ARCHITECTURE.md:74`, `R4:59`, `fase-10:41` |
| 24 | RENDAH | **FIXED** | `TODO.md:69` (gitleaks, jq), `pnpm -C backend/api exec vitest run …` di fase 08–11, `npx wait-on tcp:8787` di `fase-07:57`, `fase-12:35`, `fase-13:45` |
| 25 | RENDAH | **FIXED** | `R2:170`, `R4:66-68,73`, `fase-12-be-retensi-hardening.md:22,35-36` |

Kontradiksi run 01 yang lain juga tertutup: payload push "kontrak + `sound` aditif" (`fase-11:53`), kuota Hyperdrive (`ARCHITECTURE.md:60`), ringkasan skema di `backend/README.md` (`fase-07:24`), `resetDb` di Output fase 07 (`fase-07:26`), destination hardcode `iPhone 16` (hilang dari R5), ON-04 vs MVP (C14, `README.md:135`).

Ringkas: **23 FIXED, 2 PARTIALLY (#6, #19), 1 REGRESSION (dari #7)**.

## 3. Tabel temuan

| # | Tingkat | File § bagian | Masalah | Usulan perbaikan |
|---|---|---|---|---|
| N1 | TINGGI | `PROMPT.md:87` (langkah 1 "FASE = auto") vs `PROMPT.md:20,24`, `README.md:18`, `PROGRESS.md:3,5`, `PROMPT.md:138-140` (6h) | **Regresi perbaikan #7.** Aturan baru: "ambil fase pertama … yang berstatus [ ] (bukan [r]/[x])". Fase yang berhenti di LANGKAH MANUAL berstatus `[~]` dan belum punya PR (langkah 6h berhenti sebelum review/verifikasi/PR di langkah 7–11). Saat Alief selesai dan "ketik lagi kalimat yang sama" (`README.md:18`, `PROMPT.md:24`), agent melewati fase `[~]` dan mulai fase berikutnya. Contoh: fase 07 berhenti di deploy pertama (`fase-07:43`) → sesi berikut mengerjakan 08; fase 07 tidak pernah diverifikasi, di-log, atau dibuka PR-nya, dan langkah 3c tidak tahu harus menumpuk di atas apa. Berlaku untuk semua fase dengan LANGKAH MANUAL (07–12, 16) dan status `[~]` yang disengaja (`fase-11:56`, `fase-14:20`). `PROMPT.md:20` ("belum [x]") bertentangan dengan baris 87. | Langkah 1: "FASE = auto: (1) kalau ada fase TRACK berstatus `[~]` → mode LANJUT fase itu: tanya/cek apakah LANGKAH MANUAL di log sudah dicentang Alief; kalau belum, berhenti dan tampilkan daftarnya; (2) kalau tidak ada, ambil fase pertama `[ ]`". Pisahkan status "selesai kecuali menunggu Umar" (fase 11 tanpa iPhone, fase 14 tanpa C3) sebagai `[r]` + catatan "pending C3/B6" di kolom Ringkasan, supaya tidak memblokir fase berikutnya. Samakan `PROMPT.md:20` dan legenda `PROGRESS.md:5`. |
| N2 | TINGGI | `ref/R2-skema-db.md:140-156` (§5), `ref/R3-catatan-api.md:56,105`, `SECURITY.md:28` (T5), `fase-10-be-verdicts.md:25,36`, `TODO.md:55` (C6) | **Sisa run 01 #6.** Filter "hanya verdict atas scan milik Protected yang terhubung" dilewati dengan dua panggilan anonim: `POST /devices` mode guardian + `POST /devices` mode protected (rate limit hanya 10/jam per IP), join keluarga sendiri, `POST /scans` skor 100 dari device Protected, lalu `POST /verdicts not_safe` → lolos semua join di query R2 §5. Dengan `BLOCKLIST_MIN_FAMILIES = 1` domain sah apa pun yang tidak ada di allowlist statis (toko kecil, subdomain bank, situs pemerintah daerah) langsung terblokir untuk semua pengguna lewat layer 1 Imelda, dan tidak ada cara mengirim penghapusan (`removed` baru usulan). Menaikkan ke 2 hanya butuh 4 device. Test "Guardian baru + scan palsu miliknya sendiri" (`fase-10:36`) lulus, tapi T5 memberi kesan risiko sudah ditutup. | Default aman sampai C6 dijawab: entri global butuh **persetujuan manual** (kolom `blocklist_approved_at` / tabel `blocklist_review`, diisi Alief/Umar lewat SQL editor sebagai LANGKAH MANUAL), atau minimal `BLOCKLIST_MIN_FAMILIES = 2` + umur `family_links` ≥ 72 jam + umur device ≥ 7 hari. Tambah test "Guardian + Protected milik penyerang yang sama → tidak masuk /blocklist". Ubah T5 menjadi "risiko sisa, menunggu C6". |
| N3 | SEDANG | `log/DECISIONS.md:179` (D-alief-24 diff "PERSIS"), `fase-01-app-fondasi.md:24-27,38` | Diff yang diizinkan untuk `ShooAppTests` / `ShooAppUITests` tidak menyertakan Info.plist. Preset XcodeGen untuk `bundle.unit-test`/`bundle.ui-testing` hanya `BUNDLE_LOADER` + `LD_RUNPATH_SEARCH_PATHS` (I20). XcodeGen hanya mencari `Info.plist` di sources (folder Tests tidak punya), dan default Xcode `GENERATE_INFOPLIST_FILE = NO`. Akibat yang mungkin: build test gagal ("target does not have an Info.plist file"), sementara D-alief-24 melarang menyentuh kunci lain. Fase 01 langkah 1 = pintu G2 untuk seluruh track app. BELUM DIBUKTIKAN dengan build (dilarang di run ini). | Tambah ke diff D-alief-24: `settings: { base: { GENERATE_INFOPLIST_FILE: YES } }` di kedua target test (dan pesan C1). Atau tulis "kalau `xcodebuild test` gagal karena Info.plist, tambahan satu setting ini diizinkan". |
| N4 | SEDANG | `fase-11-be-push.md:40` (langkah 7) vs `:35` (langkah 2) | Uji lokal: `supabase functions serve push --env-file …` tanpa `--no-verify-jwt`. Docs CLI: verifikasi JWT aktif kecuali flag itu diberikan (I13). `RelaySender` hanya mengirim `x-push-secret`, tanpa JWT Supabase → gateway lokal menolak (401) sebelum fungsi jalan. DoD "push_log mencatat respons APNs asli dari relay lokal" (`fase-11:54`) tidak bisa tercapai, dan 401 bisa salah dibaca sebagai bug di relay. | Pakai `[functions.push] verify_jwt = false` di `backend/db/supabase/config.toml` (berlaku untuk serve dan deploy), atau tambah `--no-verify-jwt` di perintah serve. Tambah test Worker: relay 401 → `push_log` `failed:401`. |
| N5 | SEDANG | `ref/R7-protokol-qa.md:64` (#15) vs `R3:59`, D-alief-24, `fase-05:32` | QA-E2E #15 "Extension Off → Shield 'Off'/'Not connected' di Family" tidak bisa lulus dengan default plan (`extensionActive: true` tanpa data) sampai C11 disetujui **dan** extension Umar mengirim `extensionLastSeenAt`. Laporan QA akan mencatat P0 ("informasi salah") yang sebenarnya deviasi yang sudah diputuskan, atau tester melewatinya diam-diam. | Pecah #15: (a) Shield Protected sendiri "Off" (App Group, selalu bisa diuji); (b) GD-03 "Not connected" hanya kalau C11 sudah jalan; selain itu tulis di "Batasan" header laporan + rujuk D-alief-15/24. |
| N6 | SEDANG | `ref/R2-skema-db.md:146-154` (query blocklist) | (a) `having count(distinct v.by_device_id) >= $minFamilies` dihitung **setelah** `where v.decided_at > $since`. Dengan `minFamilies ≥ 2` (yang diusulkan C6 b), domain yang verdict pertamanya sebelum `since` dan verdict kedua sesudahnya tidak pernah muncul di refresh inkremental. (b) Filter `family_links` dievaluasi saat query, bukan saat keputusan: kalau Protected disconnect, domain diam-diam keluar dari hasil penuh tapi detector yang sudah mengunduhnya tidak tahu (tidak ada `removed`). | Hitung kelayakan atas semua verdict, filter waktu di `having max(v.decided_at) > $since`. Simpan "layak blocklist" saat `POST /verdicts` (kolom `eligible_global boolean` atau tabel `blocklist_entries`) supaya disconnect tidak mengubah isi diam-diam. Test untuk kedua kasus. |
| N7 | RENDAH | `fase-06Q-qa-a.md:41` (DoD "G5 `[x]`"), `fase-12-be-retensi-hardening.md:44` ("G6 `[x]`"), `fase-16-qa-e2e.md:42` ("G8 `[x]`"); `PROMPT.md:85-86` | G5/G6 butuh merge oleh Umar, padahal agent tidak boleh merge dan DoD diperiksa sebelum PR dibuka (langkah 9 → 11). DoD itu tidak pernah bisa dicentang di fasenya sendiri. Juga tidak ada langkah yang memperbarui baris G di PROGRESS (langkah 1 hanya mengubah baris fase `[r]` → `[x]`). | DoD: "PR dibuka; G5 terpenuhi setelah semua PR merged (dicek gate track c)". Langkah 1: setelah menyegarkan `[r]` → `[x]`, perbarui G5/G6 kalau syaratnya terpenuhi. |
| N8 | RENDAH | `fase-15-push-validasi.md:24` vs `fase-02-onboarding.md:58` | fase 15: "tanpa `aps-environment` registrasi APNs di simulator tetap jalan". Apple TN2265: entitlement hilang → callback gagal (I23). Fase 02 sendiri menulis "register APNs gagal → log saja". Agent fase 15 bisa menghabiskan waktu men-debug token yang tidak pernah datang. | Ganti: "tanpa `aps-environment`, `registerForRemoteNotifications` gagal (log); `simctl push` tetap bisa diuji karena tidak butuh token. Uji `PATCH apnsToken` setelah C3". |
| N9 | RENDAH | `ref/R1-struktur-repo.md:24`, `fase-07-be-fondasi.md:34` (`fetch_types: false`), `R4:66-68` (retensi per batch) | Docs Cloudflare: `fetch_types: false` hanya kalau skema tidak memakai tipe array (I6). Plan tidak memakai kolom array, tapi retensi/dedupe kemungkinan mengirim daftar ID sebagai parameter array (`= any(${ids})`), yang butuh info tipe array di postgres.js. | Tulis di R5 §2: daftar ID memakai `in ${sql(ids)}` (ekspansi list), bukan parameter array; atau `fetch_types` default di client cron. |
| N10 | RENDAH | `ref/R3-catatan-api.md:94-107` (§7) vs `fase-07:47`, `fase-11:41` | (a) Secret `SPIKE_KEY` (dipakai fase 07) tidak ada di tabel env R3 §7. (b) `INVITE_BASE_URL`, `BLOCKLIST_MIN_FAMILIES`, `SCREENSHOT_MAX_BYTES`, `APNS_ENV` adalah var, tapi tidak disebut bahwa var ditulis di `vars` `wrangler.jsonc` (fase 07 manual mencampur `INVITE_BASE_URL` dengan `secret put`). (c) Nilai lokal untuk test Storage (`SUPABASE_URL=http://127.0.0.1:54321`, service key dari `supabase status`) tidak disebut di `.dev.vars.example` / `miniflare.bindings`. | Tambah `SPIKE_KEY` (secret, fase 07–11). Kolom "Di mana diset": `wrangler.jsonc vars` / `wrangler secret put` / `.dev.vars` lokal / `supabase secrets set`. Isi contoh lokal dari `supabase status`. |
| N11 | RENDAH | `fase-08-be-family.md:40`, `fase-09-be-scans.md:40`, `fase-12-be-retensi-hardening.md:33`; `fase-07:57`, `fase-12:35`, `fase-13:45` | (a) `supabase db reset` / `supabase test db` butuh stack lokal yang sudah jalan (docs CLI), tapi blok fase 08, 09, 12 tidak memanggil `supabase start` (fase 07, 13, 16 memanggilnya). Sesi baru setelah Mac restart → gagal. (b) `wrangler dev` di background tidak pernah dihentikan; blok berikutnya di sesi yang sama bentrok di port 8787. (c) `npx wait-on` tidak ada di devDependencies (npx mengunduh tiap kali). | Awali blok be dengan `(cd backend/db && supabase start)` (idempoten). Akhiri blok yang menyalakan server dengan `pkill -f "wrangler dev" || true`. Tambah `wait-on` ke devDependencies. |
| N12 | RENDAH | `ref/R2-skema-db.md:162`, `ref/R4-state-machine.md:16`, `PROMPT.md:62`, `README.md:47` | Rujukan/teks kecil: R2 §6 merujuk "R4 §4" (retensi ada di R4 §5); R4 §1 "503 `rate_limited`" tidak ada di tabel error R3 §1 (`rate_limited` = 429); PROMPT/README masih menulis "ID D-alief-NN" padahal per track `D-alief-A/B/C…`. | Perbaiki rujukan; pilih 503 `code_unavailable` atau 429 dan tambahkan ke R3 §1; samakan teks ID. |
| N13 | RENDAH | `fase-07-be-fondasi.md:40,47` (spike APNs) vs `TODO.md:42` (B7 di fase 11) | `jwt.ts` "dari `.p8`", tapi `.p8` asli baru ada di fase 11, dan LANGKAH MANUAL fase 07 hanya men-set `SPIKE_KEY`. Agent bisa berhenti menunggu kunci, atau tidak jelas JWT apa yang dipakai spike. | Tulis eksplisit: spike memakai kunci P-256 yang dibuat sekali pakai (bukan rahasia); respons `403 InvalidProviderToken` sudah membuktikan HTTP/2. `.p8` asli tidak dibutuhkan di fase 07. |
| N14 | RENDAH | `fase-11-be-push.md:41`, `fase-16-qa-e2e.md:22` vs `SECURITY.md:8` | `supabase secrets set APNS_KEY_P8=…` menaruh kunci privat di argumen (riwayat shell), padahal SECURITY §1 meminta nilai diketik di prompt. Cara memasukkan PEM multi-baris juga tidak didokumentasikan di CLI (I13). | Pakai `supabase secrets set --env-file <file sementara gitignored>` lalu hapus file, dan simpan P8 sebagai base64 satu baris (`APNS_KEY_P8_B64`) yang di-decode di Edge Function. |
| N15 | RENDAH | `fase-12-be-retensi-hardening.md:42` (DoD "cron terdaftar di cloud (`wrangler triggers`/dashboard)"); `fase-13-api-repository.md:47` | (a) `wrangler triggers` hanya punya subperintah eksperimental `deploy`, tidak menampilkan daftar cron (I10) → bukti harus dari dashboard / `wrangler deployments`. (b) `get_app_container … groups \| awk '{print $2}'` rapuh kalau path memuat spasi; simctl mendukung ID grup langsung (I22). | (a) Bukti: screenshot dashboard Triggers + baris `ops_heartbeat` cloud. (b) `plutil -p "$(xcrun simctl get_app_container booted com.shoo.app group.com.shoo.app)/Library/Preferences/group.com.shoo.app.plist"`. |

Jumlah: **KRITIS 0 · TINGGI 2 · SEDANG 4 · RENDAH 9**.

## 4. Kontradiksi antar-dokumen

- **`PROMPT.md:20` ("belum [x]") ↔ `PROMPT.md:87` ("berstatus [ ] (bukan [r]/[x])"):** dua aturan pemilihan fase berbeda; versi baris 87 melewati fase `[~]` (#N1).
- **`README.md:18` + `PROMPT.md:24` ("ketik lagi kalimat yang sama" untuk melanjutkan) ↔ `PROMPT.md:87`:** kalimat yang sama tidak melanjutkan fase yang berhenti (#N1).
- **`SECURITY.md:28` (T5 "Mitigasi … Test …") ↔ `R2:142-154` + `R3:56`:** filter bisa dilewati dengan dua device anonim; T5 tampak tertutup (#N2).
- **`log/DECISIONS.md:179` (D-alief-24 "PERSIS … kunci lain tidak disentuh") ↔ preset XcodeGen test bundle:** tidak ada Info.plist untuk target test (#N3).
- **`fase-11:35` (deploy `--no-verify-jwt`) ↔ `fase-11:40` (serve lokal tanpa flag):** perilaku JWT lokal dan cloud berbeda (#N4).
- **`R7:64` (#15 "Not connected") ↔ `R3:59` + D-alief-24 (tanpa data → `true`):** skenario QA tidak bisa lulus dengan default (#N5).
- **`fase-15:24` ↔ `fase-02:58`:** registrasi APNs tanpa entitlement "tetap jalan" vs "gagal → log saja" (#N8).
- **`fase-06Q:41`, `fase-12:44`, `fase-16:42` (DoD G5/G6/G8 `[x]`) ↔ `PROMPT.md:178` + `PROGRESS.md:3` (agent tidak merge, `[x]` = merged):** DoD tidak bisa dipenuhi di fasenya (#N7).
- **`R3 §7` ↔ `fase-07:47`:** `SPIKE_KEY` dipakai tapi tidak terdaftar (#N10).
- **`R2:162` ("R4 §4") ↔ `R4:63` (retensi di §5); `R4:16` (503 `rate_limited`) ↔ `R3:24` (429):** rujukan dan status HTTP (#N12).
- **`TODO.md:23` (A13 "tidak perlu menunggu izin") ↔ `CLAUDE.md` hard rule 2 ("write the proposal … ask the lead"):** pengecualian sudah tertulis (D-alief-02/24) dan tetap lewat approve CODEOWNERS; bukan temuan, tapi Umar sebaiknya mengetahuinya lewat C1 sebelum PR dibuka.
- **PRD §5 Validasi ("masuk whitelist keluarga") ↔ D-alief-09 (per pemilik):** deviasi tercatat sejak run 01, masih menunggu konfirmasi Umar.

## 5. Lima risiko terbesar untuk MVP + mitigasi

1. **Alur otomatis macet atau melompati fase** (#N1): fase backend dengan deploy manual tidak pernah selesai/PR, track c tertahan karena PR 07–12 tidak lengkap. Mitigasi: perbaiki aturan langkah 1, tambah status "pending eksternal", uji kering aturan itu pada PROGRESS contoh sebelum mode auto.
2. **Push APNs**: HTTP/2 dari Edge Function Supabase ke APNs belum terdokumentasi (I12), GD-06 P0 bergantung padanya. Mitigasi: uji lokal fase 11 (setelah #N4) membuktikan jalur Deno, uji sandbox ke iPhone Alief di fase 11 (D7), `PushSender` tetap interface sehingga bisa diganti (mis. layanan push pihak ketiga) tanpa mengubah route.
3. **Ketergantungan pada Umar**: C3 (kamera, push, Team ID), C6 (blocklist), C11 (`extensionLastSeenAt`), C12 (`GET /devices/me`), C13, C14, plus extension yang benar-benar memanggil `POST /scans` dan polling verdict. Mitigasi: kirim paket C1/C3/C6/C11/C12/C13/C14 sekarang (fase-00 langkah 4 sudah meminta ini), placeholder `TODO(sync:umar)`, curl peniru extension untuk QA.
4. **Perilaku cloud berbeda dari lokal**: Direct connection Supabase IPv6-only di Free (I5) dan dukungan IPv6 Hyperdrive tidak terdokumentasi; Workers Free 10 ms CPU per request/cron. Mitigasi sudah ada (fallback session pooler 5432 `shoo_api.<ref>`, uji cloud fase 07 dan 10); tambahkan pengukuran CPU (`wrangler tail`) pada uji asap fase 12.
5. **Penyalahgunaan endpoint anonim + kuota Free**: peracunan blocklist (#N2), spam scan/push (120 scan/jam/device × device tak terbatas), pause Supabase 7 hari. Mitigasi: default blocklist dengan review manual, batas device per IP per hari, monitor B9 ke `/healthz/db` yang menulis, ambang pindah ke R2 (E1).

## 6. Pertanyaan yang harus dijawab sebelum fase 01 dan 07

1. **Umar + Imelda (C6):** sampai aturan final ada, bolehkah blocklist global memakai review manual (entri baru tidak terkirim sebelum disetujui), atau cukup `MIN_FAMILIES = 2` + umur link/device? Ini menentukan fase 10.
2. **Umar (C1):** setuju diff D-alief-24 ditambah `GENERATE_INFOPLIST_FILE: YES` di dua target test?
3. **Umar (C3):** kapan `NSCameraUsageDescription`, `aps-environment`, dan Team ID masuk `project.yml`? Tanpa itu PR-01 Scan QR dan uji push perangkat (fase 11/15) tertunda.
4. **Umar (C11):** apakah extension akan memanggil `PATCH /devices/me {extensionLastSeenAt}` saat heartbeat? Kalau tidak, GD-03 "Not connected" tidak pernah tampil di MVP dan QA-E2E #15 harus diubah.
5. **Umar (C13, C12):** `owner=family` memuat scan Guardian sendiri? Boleh endpoint `GET /devices/me`?
6. **Umar (C14):** MVP Alief boleh selesai tanpa ON-04?
7. **Alief:** deploy cloud di akhir setiap fase be dilakukan dari branch yang belum di-review Umar. Diterima untuk demo, atau deploy hanya dari `main` setelah merge (menggeser G3/G4)?
8. **Alief:** setuju status baru (mis. `[m]` menunggu LANGKAH MANUAL, `[r]` + "pending C3/B6") untuk memperbaiki #N1?

---

## I. Cek dokumentasi resmi

| # | Klaim di plan | Status | Sumber / koreksi |
|---|---|---|---|
| I1 | Workers Free: 100k request/hari, CPU 10 ms per request dan per Cron, 50 subrequest, 5 Cron/akun (ARCHITECTURE §3, R2 §6) | **VERIFIED** | https://developers.cloudflare.com/workers/platform/limits/ — juga 6 koneksi keluar simultan per invocation |
| I2 | Cache Hyperdrive aktif default 60 s + 15 s; `--caching-disabled` di `hyperdrive create` (TODO B4, D-alief-17) | **VERIFIED** | https://developers.cloudflare.com/hyperdrive/concepts/query-caching/ — flag yang sama juga ada di `hyperdrive update <id>` (berguna kalau config lama sudah terlanjur dibuat dengan cache) |
| I3 | Lokal: `localConnectionString` / `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_DB`, tanpa cache lokal | **VERIFIED** | https://developers.cloudflare.com/hyperdrive/configuration/local-development/ — env var menang atas config; cache/pooling hanya berlaku dengan `wrangler dev --remote` |
| I4 | Hyperdrive + Supabase: Direct connection, boleh role khusus | **VERIFIED**; dukungan IPv6 Hyperdrive **NOT YET VERIFIED** | https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-database-providers/supabase/ (tidak menyebut IPv6). Fallback plan (session pooler) tetap perlu |
| I5 | Fallback session pooler port 5432, user `shoo_api.<project_ref>`; Direct IPv6 | **VERIFIED** | https://supabase.com/docs/guides/database/connecting-to-postgres — Direct = IPv6 di Free (IPv4 hanya dengan add-on), shared pooler IPv4-only, session mode 5432, role kustom `[ROLE].[PROJECT-REF]`, host `aws-[INDEX]-[REGION].pooler.supabase.com` disalin dari dialog Connect |
| I6 | postgres.js ≥ 3.4.5, `nodejs_compat`, `max: 5`, `fetch_types: false`, `prepare` default, client per request | **VERIFIED** (catatan) | https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-drivers-and-libraries/postgres-js/ — `fetch_types: false` hanya "if your schema doesn't use array types" → #N9 |
| I7 | `vitest@^4.1.0` + `@cloudflare/vitest-plugin` + `cloudflareTest({ wrangler: { configPath } })` | **VERIFIED** | https://developers.cloudflare.com/workers/testing/vitest-integration/write-your-first-test/ dan …/configuration/ |
| I8 | `miniflare.hyperdrives` untuk binding DB di test | **VERIFIED sebagian** | https://developers.cloudflare.com/workers/testing/vitest-integration/configuration/ — hanya muncul di contoh (record nama binding → URL, diteruskan ke Miniflare `WorkerOptions`); plan sudah punya fallback |
| I9 | Uji handler `scheduled()` dari vitest (fase 12 §1) | **NOT YET VERIFIED** | Halaman vitest yang dibaca hanya membahas `fetch`. Fallback `curl /cdn-cgi/local/scheduled` sudah ada di plan |
| I10 | Cron lokal `wrangler dev --test-scheduled` + `/cdn-cgi/local/scheduled?cron=…`; cek cron cloud lewat `wrangler triggers` | **VERIFIED** (route + flag); `wrangler triggers` **VERIFIED sebagian** | https://developers.cloudflare.com/workers/wrangler/commands/workers/ (flag menyebut route itu persis) dan https://developers.cloudflare.com/workers/configuration/cron-triggers/. `wrangler triggers` hanya punya `deploy` (eksperimental), tidak menampilkan daftar → #N15 |
| I11 | `fetch()` Worker bisa HTTP/2 ke APNs | **NOT YET VERIFIED** (tidak ada docs) | Plan sudah menjadikan relay jalur utama dan spike di Worker cloud (D-alief-16) |
| I12 | Edge Function Supabase (Deno) bisa HTTP/2 ke APNs | **NOT YET VERIFIED** | Tidak ada docs Supabase tentang APNs/HTTP/2. Dibuktikan oleh uji lokal fase 11 langkah 7 (setelah #N4) dan uji perangkat D7 |
| I13 | `supabase functions serve --env-file`, `functions deploy --no-verify-jwt`, `secrets set NAME=VALUE` | **VERIFIED** | https://supabase.com/docs/reference/cli/supabase-functions-serve (serve juga punya `--no-verify-jwt`; tanpa flag JWT diverifikasi → #N4), https://supabase.com/docs/reference/cli/supabase-functions-deploy, https://supabase.com/docs/reference/cli/supabase-secrets-set (juga `--env-file`; nilai multi-baris tidak dijelaskan → #N14) |
| I14 | `supabase start -x …`, `supabase test db` + pgTAP (`create extension if not exists pgtap with schema extensions`) | **VERIFIED** (tidak berubah sejak run 01) | https://supabase.com/docs/reference/cli/supabase-start, https://supabase.com/docs/reference/cli/supabase-test-db, https://supabase.com/docs/guides/local-development/testing/overview |
| I15 | Storage REST: upload `POST /object/{bucket}/{path}`, sign `POST /object/sign/{bucket}/{path}`, hapus `/object/{bucket}` + `prefixes` | **VERIFIED** | https://github.com/supabase/storage-js/blob/main/src/packages/StorageFileApi.ts (baris 135, 445, 680–681 saat dibaca) |
| I16 | Supabase Free: 500 MB DB, 1 GB Storage, 5 GB egress, 500k invocation Edge Function, pause setelah 7 hari aktivitas rendah | **VERIFIED** | https://supabase.com/docs/guides/platform/billing-on-supabase dan https://supabase.com/docs/guides/platform/project-pausing ("sufficient user database activity over the past week"; beberapa request DB per hari biasanya cukup) |
| I17 | APNs: HTTP/2 + TLS 1.2, `api.push.apple.com` / `api.sandbox.push.apple.com`, header `apns-push-type`/`apns-topic`/`apns-priority`, JWT diperbarui antara 20 dan 60 menit (cache ±50 menit di plan) | **VERIFIED** | https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns, https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns (dibaca lewat JSON docs Apple) |
| I18 | `410 Unregistered` → hapus token; `400 BadDeviceToken` juga untuk environment salah → jangan hapus | **VERIFIED** | https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns — "Verify that the request contains a valid token and that the token matches the environment" |
| I19 | XcodeGen menulis ulang Info.plist/entitlements setiap generate (dasar PROMPT 6k, R5 §6) | **VERIFIED** | https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md — "Plists are created on disk on every generation"; entitlements "All properties must be provided" |
| I20 | Target test XcodeGen cukup dengan diff D-alief-24 | **WRONG (kemungkinan besar, belum dibuktikan dengan build)** | ProjectSpec: `TEST_HOST`/`TEST_TARGET_NAME` otomatis (VERIFIED); `INFOPLIST_FILE` hanya dicari di sources. Preset https://github.com/yonaskolb/XcodeGen/blob/master/SettingPresets/Products/bundle.unit-test.yml tidak memuat `GENERATE_INFOPLIST_FILE` → #N3 |
| I21 | `xcrun simctl push booted com.shoo.app <file.apns>` | **VERIFIED** | `xcrun simctl help push` (Xcode 27.1 lokal): bundle id opsional kalau payload punya `Simulator Target Bundle`, payload wajib `aps`, ≤ 4096 byte |
| I22 | `xcrun simctl get_app_container booted com.shoo.app groups` | **VERIFIED** | `xcrun simctl help get_app_container`: container `groups` atau `<group identifier>` langsung → #N15 (b) |
| I23 | Registrasi APNs di simulator jalan tanpa `aps-environment` (fase 15) | **WRONG** | Apple TN2265 https://developer.apple.com/library/archive/technotes/tn2265/_index.html — entitlement `aps-environment` hilang → callback error → #N8 |
| I24 | `xcodebuild test -only-testing:ShooAppTests/<Suite>` untuk Swift Testing | **VERIFIED sebagian** | Tidak ada docs Apple yang ditemukan; isu Tuist menyebut `-only-testing` memfilter Swift Testing per suite (https://hive.tuist.dev/forage/items/github-issue/fde4d966-d361-4530-b81c-35c9924e74bf). Pastikan nama suite = nama tipe `@Suite`, atau fallback `-only-testing:ShooAppTests` |
| I25 | `.environment(\.locale)` mengubah String Catalog | **NOT YET VERIFIED** (tidak berubah) | Plan menguji tiga kasus di fase 01 §5 dan punya fallback `L10n` |
| I26 | WhatsApp tidak membuat `shoo://` bisa diklik (D-alief-03) | **NOT YET VERIFIED** (tidak berubah) | Desain `/join` https aman di kedua kemungkinan; diuji di QA-E2E #4 |
| I27 | `gitleaks detect --source . --no-banner` | **VERIFIED** (lokal) | gitleaks 8.30.1: `detect` masih jalan (tersembunyi, pengganti resminya `gitleaks git` / `gitleaks dir`) |

## J. Cek wiring ujung ke ujung

### J1. `ShooRepository` (fase-01 §2) → `contracts/api.md` → fase backend

| Method app | Endpoint kontrak | Backend | Catatan |
|---|---|---|---|
| `registerDevice(name:mode:)` | `POST /devices` | 07 §5 | Bahasa ID langsung `PATCH` setelahnya (`fase-13:33`) — tertutup sejak run 01 |
| `updateMe(name:language:apnsToken:)` | `PATCH /devices/me` | 07 §6 | Kalau C11 disetujui, app juga harus mengirim `extensionLastSeenAt` saat foreground (`TODO.md:60`) → protocol perlu parameter baru; belum tertulis di fase 13 |
| `createFamilyCode()` | `POST /family/code` | 08 §1 | OK |
| `joinFamily(code:)` | `POST /family/join` | 08 §2 | OK (+ `already_connected`) |
| `familyMembers()` | `GET /family/members` | 08 §3 | OK (default `extensionActive: true`) |
| `removeMember(_:)` | `DELETE /family/members/{id}` | 08 §4 | OK |
| `leaveGuardian()` | `DELETE /family/guardian` | 08 §4 | OK; `guardian.name` dihapus (`fase-13:25`, `fase-14:33`) |
| `scans(owner:status:cursor:)` | `GET /scans` | 09 §2 | OK (`family` termasuk diri sendiri, D-alief-19) |
| `scan(id:)` | `GET /scans/{id}` | 09 §3 | OK |
| `setVerdict(scanId:value:)` | `POST /verdicts` | 10 §1 | OK |
| — | `GET /devices/me` (usulan C12) | — | Belum ada di kontrak; tercatat sebagai celah (D-alief-21) |

Endpoint tim lain: `POST /scans` (extension, 09), `GET /verdicts?domain=` (extension, 10), `GET /blocklist` (detector, 07 + 10), `GET /join` (browser, 08). **Semua 10 operasi protocol terpetakan ke endpoint dan fase.**

### J2. Key App Group: penulis dan pembaca

| Key | Penulis | Pembaca | Status |
|---|---|---|---|
| `device.id`, `device.token`, `device.mode` | App, fase 13 `SessionStore` | Extension `getSession` (`SafariWebExtensionHandler.swift:35-37`, wajib) | OK |
| `device.name` | App fase 13 + tulis ulang setelah `updateMe(name:)` | Extension `getSession` | OK |
| `guardian.name` | App fase 14 (join), dihapus saat `leaveGuardian()` | Extension `getSession` ("Waiting for [nama]") | OK; pemutusan dari sisi Guardian tidak terdeteksi (D-alief-21) |
| `api.baseURL` | App fase 13 (`AppConfig` `#if DEBUG`) | Extension `getSession` | OK |
| `ai.baseURL` | App fase 13, placeholder `TODO(sync:imelda)` | Extension `getSession` | Bergantung Imelda; sampai ada, extension menerima `null` dan melewati layer 3–4 (sesuai kontrak "server down") |
| `extension.lastSeenAt` | Extension (heartbeat, sudah ada) | App `ExtensionStatus` fase 01 (dipakai 04, 05, 06) | OK, jendela `AppGroup.extensionActiveWindow` (D-alief-23) |

**Setiap key punya penulis dan pembaca.** Tidak ada key App Group baru di plan.

### J3. Env R3 §7 → di mana diset

| Variabel | Diset di | Status |
|---|---|---|
| `DB` (Hyperdrive) | fase 07 LANGKAH MANUAL 3 (B4) | OK |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | fase 09 DoD "LANGKAH MANUAL deploy fase 09 + secret" (B5) | OK (hanya di DoD, bukan di Langkah kerja; nilai lokal tidak disebut → #N10) |
| `INVITE_BASE_URL` | fase 07 LANGKAH MANUAL 4 | OK; jenis var/secret ambigu → #N10 |
| `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` | fase 11 LANGKAH MANUAL 8 (Edge Function) | OK (Worker tidak butuh kalau relay); cara aman → #N14 |
| `APNS_ENV` | fase 11 (`sandbox`), fase 16 (`production`) | OK |
| `PUSH_RELAY_URL`, `PUSH_RELAY_SECRET` | fase 11 LANGKAH MANUAL 8 (Worker + Edge Function) | OK |
| `BLOCKLIST_MIN_FAMILIES`, `SCREENSHOT_MAX_BYTES` | tidak ada langkah; harus di `vars` `wrangler.jsonc` | RENDAH (#N10) |
| `APNS_SPIKE` + `SPIKE_KEY` | fase 07 LANGKAH MANUAL 4, dihapus fase 11 | `SPIKE_KEY` tidak ada di R3 §7 (#N10) |
| Secret CI (5) | C2 ke Umar (fase 12) | OK |

### J4. Gate PROGRESS bisa dicapai?

| Gate | Cara tercapai | Status |
|---|---|---|
| G0 | Jawaban Umar di TODO §C | Manual, OK |
| G1 | Merge PR `docs/alief-plan` | OK |
| G2 | Merge `chore/APP-test-targets` | Bergantung #N3 (build target test) |
| G3 | Fase 07 LANGKAH MANUAL | Tercapai manual, tapi fase 07 sendiri tidak dilanjutkan agent (#N1) |
| G4 | Fase 10 uji cloud | Sama (#N1) |
| G5, G6 | Semua PR merged | Tercapai lewat Umar; DoD 06Q/12 yang mewajibkan `[x]` tidak bisa dipenuhi di fasenya, dan baris G tidak pernah diperbarui (#N7). Gate track c sendiri memeriksa PR langsung (`PROMPT.md:89-91`), jadi tidak macet |
| G7 | B6–B8 | Manual, OK |
| G8 | README §7 | Butuh C14 + QA-E2E #15 yang realistis (#N5) |

### J5. Perintah Verifikasi dari root repo

| Fase | Hasil |
|---|---|
| 00 | Diuji: grep kosong, `git diff --stat origin/main -- . ':!plan/alief'` kosong |
| 01–06, 06Q, 13–16 | `source plan/alief/ref/sim.sh` diuji (bash + zsh): `SIM=iPhone 17 Pro`, regex juga benar untuk `iPhone 17 Pro Max`, `iPhone 16e`; nama ada di beberapa runtime (iOS 26.3–26.5) → xcodebuild memilih salah satu, aman. `-only-testing:<Target>/<Suite>` → I24 |
| 07 | Subshell benar; `wait-on` diunduh npx; server background tidak dihentikan (#N11) |
| 08, 09, 12 | Path benar; tidak memanggil `supabase start` (#N11) |
| 10, 11 | Benar; fase 11 serve lokal butuh `--no-verify-jwt` (#N4) |
| 12 | `wrangler dev --test-scheduled` + `/cdn-cgi/local/scheduled` sesuai docs (I10); `gitleaks detect` jalan (I27) |
| 13 | `get_app_container … groups \| awk` jalan di path tanpa spasi (I22, #N15) |
| 14, 15 | `simctl openurl`, `simctl push` valid (I21); `git diff … Info.plist` benar asal Umar ikut meng-commit plist hasil `xcodegen` setelah C3 |

---

## Catatan untuk run berikutnya

- Fokus ulang: #N1 (aturan pemilihan fase + status `[~]`), #N2 (default blocklist), lalu #N3 dan #N4.
- Uji kering #N1: ambil PROGRESS contoh dengan fase 07 `[~]`, 08 `[ ]` dan pastikan aturan baru memilih 07 (LANJUT), bukan 08.
- Yang tetap tidak bisa diverifikasi dari docs: HTTP/2 Worker/Edge Function → APNs, IPv6 Hyperdrive, locale environment + String Catalog, link WhatsApp, kebutuhan Info.plist target test (butuh `xcodegen` + build), wireframe PRD §7 (gambar).
