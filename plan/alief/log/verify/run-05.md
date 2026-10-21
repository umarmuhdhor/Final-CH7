# Verifikasi plan Alief — run 05

- **Tanggal:** 21 Okt 2026 (WITA)
- **Reviewer:** Claude Opus 5.5, sesi independen, read-only (satu-satunya file yang dibuat: file ini)
- **Branch/commit yang dibaca:** `docs/alief-plan` @ `5d07d11` (perbaikan run 04 `60b7435` + merge `origin/main` `4b165e6`). Diff `1aa9d87..5d07d11` dibaca (49 file, termasuk EX-02 Umar).
- **Prompt:** `plan/alief/VERIFY_PROMPT.md` (cek A–H, format 1–6) + tambahan I (dokumentasi resmi), J (wiring), dan §2a (status temuan run 04)
- **Bacaan:** semua file di daftar `<bacaan>` dibaca lengkap: CLAUDE.md (root, `ios/`, `ios/ShooApp/`, `ios/ShooExtension/`, `backend/`), CODEOWNERS, `docs/README.md`, `docs/mandates/alief.md`, kedua file spike S1/S2, seluruh `contracts/` + fixtures, `ios/ShooShared/AppGroup.swift`, `ios/project.yml`, `ios/Config/Shoo.xcconfig` + `Local.xcconfig.example`, `ios/ShooApp/*`, `ios/ShooExtension/` (`SafariWebExtensionHandler.swift`, `Resources/background.js`, `content.js`, `pipeline.js`; read-only), semua file `plan/alief/` termasuk `ref/sim.sh`, `log/DECISIONS.md`, `log/fase-00.md`, `log/verify/run-04.md` (run 01–03 lewat ringkasan di run 04 dan `log/fase-00.md`).
- **PRD v1.5:** berhasil dibaca dari Google Drive (`Shoo-PRD-v1.5.docx`, id `1n_1vngw5fFizP9YHWg0kT3VnqGhgXlbV`). Gambar wireframe §6–§7 tidak ikut terbaca (hanya teks), jadi perbandingan wireframe tidak bisa diverifikasi.
- **Laporan QA Catalyst:** dibaca dari Drive (`QA_Catalyst_DeepSeek_26Sep2026.docx`, id `1ZHVIvha4RxRS1Bgp1dK20VUIByez9mwT`) untuk cek H.
- **Penting — `main` maju lagi setelah commit perbaikan:** `git ls-remote origin main` → `597a6d1` ("EX-04: warning popup at 30% and 50%", Umar, 16:44 WITA, dua menit setelah `5d07d11` 16:42). Ada juga **PR #1 terbuka** `contract/deep-links` (Umar, 16:46 WITA) yang menambah bagian "Deep links" ke `contracts/app-group-keys.md`: `shoo://scan/{scanId}`, **`shoo://activity`**, `shoo://join?code=`, dan "unknown or malformed link opens Shield". Keduanya dibaca read-only lewat `gh api …/compare/4b165e6...597a6d1`, `gh api …/contents/…?ref=597a6d1`, `gh pr view 1`, `gh pr diff 1` (tanpa `git fetch`). Dampaknya → #S4.
- **Perintah read-only yang dijalankan:** `git ls-remote`, `git log/diff/show`, `bash -n plan/alief/ref/sim.sh` (lulus), `source plan/alief/ref/sim.sh` di bash dan zsh (`SIM=iPhone 17 Pro`; `BUNDLE_ID`/`APP_GROUP` **kosong** karena `ios/Shoo.xcodeproj` belum ada di checkout ini), Verifikasi fase 00 (`ls` OK, grep `TODO(sync` kosong, `git diff --stat origin/main...HEAD -- . ':!plan/alief'` kosong), cek 01S `git diff --name-only origin/main...HEAD -- ios/project.yml ios/ShooShared ios/ShooExtension` (kosong), grep `com.shoo.app` / `getStateOf` / `Local.xcconfig` / `www.` di plan, `gh api repos/umarmuhdhor/Final-CH7/branches/main --jq .protected` (**`false`**), `gh pr list` (satu PR: #1), `gh pr view --help`, `gh pr edit --help`, `xcrun simctl help push`, `man xcodebuild`. Docs Apple dibaca lewat endpoint JSON `developer.apple.com/tutorials/data/documentation/…json`. Tidak ada build, `xcodegen`, `supabase start`, atau deploy.

---

## 1. Ringkasan pemahaman

1. Shoo = Safari Web Extension iPhone + app SwiftUI. Skor 0–100 per halaman: 30–79 Warning (popup, push ke Guardian kalau pemiliknya Protected), ≥ 80 Blocked (layar blokir tanpa bypass). Skor/sinyal milik Imelda, extension + layar blokir + kontrak + `project.yml` milik Umar, app + backend milik Alief.
2. Dua mode permanen tanpa login: **Guardian** (melindungi diri + Family mode ≤ 3 orang) dan **Protected** (orang tua; tidak pernah melihat tombol validasi).
3. App iOS 17 (`@Observable`, String Catalog EN/ID) memakai protocol `ShooRepository`: `MockRepository` (fixtures) di fase 01–06, `ApiRepository` di fase 13 tanpa mengubah view.
4. Backend = Worker Cloudflare `shoo-api` (Hono + zod + postgres.js `fetch_types: false`) → Hyperdrive `--caching-disabled` → Supabase Postgres (role `shoo_api`, PostgREST ditutup) + Storage private (signed URL 1 jam).
5. Push: relay Worker → Edge Function Supabase `push` (Deno, `x-push-secret`, `verify_jwt = false`) → APNs HTTP/2 JWT ES256, dengan `APNS_TOPIC` = bundle ID build yang diuji (baru, D-alief-34); langsung dari Worker hanya kalau spike cloud fase 07 lulus.
6. Signing per developer lewat L0 (`ios/Config/Local.xcconfig`): bundle ID dan App Group tidak di-hardcode; perintah `simctl` memakai `$BUNDLE_ID`/`$APP_GROUP` dari `ref/sim.sh`, kode memakai `AppGroup.id` / `Bundle.main.bundleIdentifier`.
7. Auth per device: token `shoo_` + 32 byte, hash SHA-256 di DB. App menulis `device.*`, `guardian.name`, `api.baseURL`, `ai.baseURL` ke App Group; extension menulis `extension.lastSeenAt` (heartbeat `content.js` → `background.js` throttle 60 s → `SafariWebExtensionHandler`).
8. Pairing: kode 4 digit 60 s multi-pakai, maks 3 Protected, 5 gagal/10 menit per device dan per IP; `inviteUrl` https `/join?code=` yang membuka `shoo://join?code=`.
9. Alur inti: Protected membuka situs → extension `POST /scans` → Worker simpan + push (bahasa Guardian) → tap → Detail → It's safe → `POST /verdicts` (per pemilik + domain) → extension `GET /verdicts?domain=` (polling 5 s) → layar blokir terbuka (target ≤ 10 s). Not safe hanya masuk antrean `blocklist_entries`; `GET /blocklist` mengirim entri yang disetujui manual.
10. ON-04 di fase 02: tombol Turn on memakai `SFSafariSettings.openExtensionsSettings(forIdentifiers:)` di iOS 26.2+, fallback `openSettingsURLString` + ilustrasi per versi iOS; status dari heartbeat; video PiP (audio session `.playback`, full screen, delegate restore). Spike 01S (track `spike`, `[m]` sampai Alief menempel hasil) menguji API iOS 26.2 dan menyerahkan "Refine ON-04" ke fase 02 atau 06.
11. Track **app** (01→06→06Q) dan **be** (07→12) paralel; track **c** (13→16) setelah semua PR 01–06Q dan 07–12 merged (D8 hanya untuk fase 16). Status `[ ] [~] [m] [r] [x] [!]`; mode REVIEW (pilihan 0) sekarang punya syarat keluar: catatan "review ditangani @<sha>" + `gh pr edit --add-reviewer`.
12. QA dua ronde format Catalyst (QA-A di 06Q, QA-E2E di 16, 17 skenario) dengan fixbug "satu bug = satu test gagal = satu commit", blok Retest, kolom Waktu.

## 2. Verdict

**SIAP DENGAN CATATAN** — tidak ada KRITIS/TINGGI: ketiga TINGGI run 04 sudah ditangani (T2 sebagian, sisanya turun ke SEDANG), tetapi ada 5 SEDANG yang sebaiknya ditutup sebelum fase 01S/09/15/16 dimulai, terutama validasi `domain` di `POST /scans` yang bertentangan dengan kontrak (registrable domain) dan nama API status iOS 26.2 yang salah (`getStateOfSafariExtension` hanya macOS).

## 2a. Status temuan run 04

| run-04 # | Tingkat | Status | Bukti (file:baris di `5d07d11`) |
|---|---|---|---|
| T1 | TINGGI | **FIXED** (sisa kecil #R1, #R7) | Path L0 benar: `fase-01S-spike-extension.md:7,21,33`, `README.md:97`, `TODO.md:41` (B6), `PROMPT.md:178-181` (6k); fallback edit `project.yml`/`AppGroup.id` dihapus; `APNS_TOPIC` di `ref/R3-catatan-api.md:93,105`, `fase-11-be-push.md:41`, `fase-16-qa-e2e.md:22`; `$BUNDLE_ID`/`$APP_GROUP` di `ref/sim.sh:8-14`, `fase-13-api-repository.md:47-48`, `fase-15-push-validasi.md:26,45`; `ARCHITECTURE.md:13` (`AppGroup.id`, default). Grep: `com.shoo.app` hanya tersisa di teks yang melarang hardcode. D-alief-34(a) `log/DECISIONS.md:240` |
| T2 | TINGGI | **PARTIALLY** | `openExtensionsSettings(forIdentifiers:)` benar di `fase-02-onboarding.md:35`, `fase-01S:26,40`. Tetapi API status ditulis `SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier:)` di `fase-01S:22,26,39`, `TODO.md:65` (C17), D-alief-34(b) `DECISIONS.md:240`: menurut docs Apple method itu **macOS 10.12 saja**; versi iOS 26.2 bernama `getStateOfExtension(withIdentifier:completionHandler:)` → #S2. `TODO.md:63` (C14) masih "tanpa link langsung publik" → #R5 |
| T3 | TINGGI | **FIXED** (sisa kecil #R2) | `PROMPT.md:93-97,104-108` (pemicu = review `CHANGES_REQUESTED`/komentar `umarmuhdhor` lebih baru dari "review ditangani @<sha>"; setelah ditangani `gh pr edit --add-reviewer`, fase tidak dipilih lagi), `PROGRESS.md:5`, `TODO.md:66` (C18), D-alief-35 `DECISIONS.md:244-248`. Proteksi branch `main` masih `false` |
| S1 | SEDANG | **FIXED** | `PROMPT.md:172` (pengecualian 01S memakai `[m]`), `fase-01S:35` |
| S2 | SEDANG | **PARTIALLY** | Prasyarat `fase-01S:7` (PR 01 merged atau stacked), PR di langkah 11 `fase-01S:46`, prefix `D-alief-S…` `PROMPT.md:163`, `README.md:95`, `fase-01S:44`; handoff `fase-01S:45`, `fase-06-profile.md:34`. Sisa: `PROGRESS.md:12` dan `fase-02-onboarding.md:74` masih menyebut `feat/ON-04-refine`; jalur handoff bisa hilang → #S5; daftar prefix di `PROMPT.md:66`, `README.md:48` tanpa S → #R6 |
| S3 | SEDANG | **FIXED** | `fase-02-onboarding.md:37` (`.playback` + `.moviePlayback`, full screen, delegate restore, uji di iPhone), cocok dengan docs Apple (I5) |
| S4 | SEDANG | **FIXED** (temuan baru terkait #S3) | `TODO.md:42` (B7: kunci + `APNS_TEAM_ID` + `APNS_TOPIC` dari tim yang sama), `:52` (C3 keputusan tim), `fase-16-qa-e2e.md:22`, `fase-11-be-push.md:41`. Docs APNs sekarang: kunci team-scoped dibatasi ke **Sandbox atau Production** → #S3 |
| R1 | RENDAH | **FIXED** | `PROMPT.md:98-99` (G0–G8, baris fase 00), `PROGRESS.md:35` (G0 di atas) |
| R2 | RENDAH | **FIXED** | `PROMPT.md:115` (track c = PR merged; D8 untuk fase 16) |
| R3 | RENDAH | **FIXED** (catatan #R3) | `ref/R2-skema-db.md:107,182` (`ops_heartbeat.source`), `fase-12-be-retensi-hardening.md:43` |
| R4 | RENDAH | **FIXED** | `ARCHITECTURE.md:74` (antrean + review manual, D-alief-25) |
| R5 | RENDAH | **FIXED** | `SECURITY.md:38` (T15 lima kolom) |
| R6 | RENDAH | **PARTIALLY** | `fase-15-push-validasi.md:46` memakai id `blocked-92.json`, tetapi pemilik seed-nya `dev_mom`; Guardian simulator yang baru onboarding tidak terhubung ke `dev_mom`, jadi `GET /scans/{id}` tetap 404 → #R4 |
| R7 | RENDAH | **FIXED** | `log/fase-00.md:23` (langkah 5), `fase-00-plan-tooling.md:32` (worktree spike) |
| R8 | RENDAH | **FIXED** | `fase-02-onboarding.md:34`, `fase-01S:41` (jalur iOS 17 vs 18+, BELUM DIVERIFIKASI, dipastikan S2) |
| R9 | RENDAH | **FIXED** (catatan #R10) | `ref/R2-skema-db.md:160` ("satu domain per statement, autocommit (tanpa begin)") |
| R10 | RENDAH | **FIXED** | `README.md:19` (sisa Langkah kerja, lalu review, verifikasi, PR) |

Ringkas: **14 FIXED (4 dengan sisa kecil), 3 PARTIALLY (T2, S2, R6), 0 NOT FIXED, 0 REGRESSION**. Satu kesalahan baru dibawa oleh perbaikan T2 (nama method macOS, #S2), bukan regresi perilaku yang sebelumnya benar.

## 3. Tabel temuan

| # | Tingkat | File § bagian | Masalah | Usulan perbaikan |
|---|---|---|---|---|
| S1 | SEDANG | `ref/R3-catatan-api.md:61` (`POST /scans` validasi), `SECURITY.md:27` (T4), `fase-09-be-scans.md:29` vs `contracts/scan-result.schema.json:28-30` + `ios/ShooExtension/Resources/background.js` (`domainFor` → `registrableDomain` PSL), `content.js:48` | **Validasi `domain` bertentangan dengan kontrak.** R3 mewajibkan "`domain` = host `url` lowercase tanpa `www.`". Skema kontrak: `domain` = "**Registrable domain**, lowercase, no www. Verdicts apply per domain (PRD §5)", dan EX-02 Umar (sudah di `main`) menghitungnya dengan Public Suffix List (`login.bca-verifikasi.site` → `bca-verifikasi.site`; `a.b.co.id` → `b.co.id`). Akibat: setiap scan dari halaman subdomain ditolak `422 invalid_body` (atau, kalau server menimpa `domain` dengan host, verdict tersimpan per host sedangkan extension memanggil `GET /verdicts?domain=` dengan registrable domain → layar blokir tidak pernah terbuka). Test fase 09 akan mengunci perilaku yang salah; QA-E2E bisa lolos kalau `curl` memakai domain tanpa subdomain, lalu gagal saat EX-07 asli jalan. | R3 §4: "`domain` sesuai skema = registrable domain yang dikirim extension (PSL, EX-02); server hanya memeriksa lowercase, tanpa `www.`, dan host `url` sama dengan `domain` atau berakhiran `.`+`domain`; server tidak menghitung ulang PSL". Tambah test fase 09: `url` `https://login.example.co.id/x` + `domain` `example.co.id` → 201; `domain` yang bukan sufiks host → 422. Samakan T4. QA-E2E (R7 §5) tambah satu skenario subdomain (#R9). |
| S2 | SEDANG | `fase-01S-spike-extension.md:22,26,39`, `TODO.md:65` (C17), D-alief-34(b) `log/DECISIONS.md:240` | **Nama API status salah untuk iOS.** Docs Apple: `getStateOfSafariExtension(withIdentifier:completionHandler:)` tersedia **hanya macOS 10.12+**. Yang tersedia di iOS/iPadOS/visionOS 26.2 adalah `SFSafariExtensionManager.getStateOfExtension(withIdentifier:completionHandler:)` (atau `stateOfExtension(withIdentifier:) async throws`) → `SFSafariExtensionState.isEnabled`. Output 01S yang ditulis apa adanya tidak terkompilasi untuk target iOS (simbol unavailable), checklist S1 butir 4 tidak bisa dijalankan sesuai teks, dan usulan C17 ke Umar menyebut method yang salah. | Ganti di 01S (Bacaan wajib, Output, LANGKAH MANUAL S1), C17, dan catat entri DECISIONS baru (revisi D-alief-34(b)): `if #available(iOS 26.2, *) { let state = try await SFSafariExtensionManager.stateOfExtension(withIdentifier: Bundle.main.bundleIdentifier! + ".extension"); state.isEnabled }`. |
| S3 | SEDANG | `TODO.md:42` (B7 "environment sandbox dulu; `APNS_ENV=production` sebelum build TestFlight"), `fase-11-be-push.md:41`, `fase-16-qa-e2e.md:22`, `ref/R3-catatan-api.md:93,106` | **Kunci APNs sekarang per environment.** Docs Apple "Establishing a token-based connection to APNs": kunci team-scoped "restrict usage to either Sandbox or Production"; kunci lama yang berlaku di keduanya tetap didukung, tetapi kunci baru dibuat per environment (maks 2 per environment). Plan memakai satu `.p8` sandbox untuk D7 lalu hanya mengganti `APNS_ENV=production` di fase 16; kunci yang diganti hanya kalau timnya berbeda. Dengan kunci Sandbox-only, semua push QA-E2E (TestFlight = production) ditolak APNs, dan skenario #8–#10 (GD-06, P0) gagal di LANGKAH MANUAL fase 16. | B7: "buat kunci Sandbox untuk D7 dan kunci Production untuk TestFlight (atau satu kunci yang mencakup keduanya kalau portal masih menawarkannya; catat jenisnya)". Fase 16 langkah 1: selalu set `APNS_KEY_P8_B64` + `APNS_KEY_ID` milik kunci Production bersama `APNS_ENV=production` dan `APNS_TOPIC` (lewat `--env-file`). R3 §6: tambah `403 InvalidProviderToken` = kunci/environment/tim salah. |
| S4 | SEDANG | `fase-15-push-validasi.md:25,28,33`, `TODO.md:67` (C16), D-alief-32 vs `origin/main` `597a6d1` (`ios/ShooExtension/Resources/popup.js` `detailUrl`) + PR #1 `contract/deep-links` (`contracts/app-group-keys.md` bagian "Deep links") | **Plan tertinggal lagi dari `main` dan kontrak deep link yang sedang diusulkan.** EX-04 (sudah `[x]` di mandat Umar) membuka `shoo://scan/{recordId}` dan, sebelum EX-07 memberi id, **`shoo://activity`**. PR #1 Umar menjadikannya kontrak: `shoo://activity` → tab Activity (terbaru di atas), dan "unknown or malformed link opens Shield". Fase 15 hanya menangani `shoo://scan/<id>` (dan `shoo://join` di fase 14); tidak ada rute Activity dan tidak ada perilaku default. C16 meminta Umar melakukan sesuatu yang sekarang sudah ia kerjakan. Selain itu tombol popup sudah aktif di extension sejak sekarang, sedangkan app baru menanganinya di fase 15 (track c). Pola ini sama dengan T1 run 03/04: `main` bergerak dua menit setelah commit perbaikan. | Merge `origin/main` lagi dan baca PR #1. Fase 15: `NotificationRouter.route(url:)` mengembalikan `.detail(id)`, `.activity`, `.join(code)`, atau `.shield` (default untuk URL tak dikenal/rusak), dengan test untuk keempatnya. Ubah C16 menjadi "review PR #1 dari sisi app" dan tulis entri DECISIONS. Pertimbangkan memindahkan `route(url:)` + `onOpenURL` untuk `scan`/`activity` ke fase app (mis. 03 atau 04, memakai `MockRepository`) supaya tombol popup tidak membuka app tanpa reaksi sampai track c. |
| S5 | SEDANG | `fase-01S-spike-extension.md:10,45`, `fase-06-profile.md:34`, `fase-02-onboarding.md:19,33,74`, `PROGRESS.md:12`, mandat ON-04 ("sempurnakan dari hasil S1 + S2") | **Handoff "Refine ON-04" bisa hilang.** Handoff hanya ditulis di `log/fase-01S.md` di branch spike. Fase 02 membaca bagian Result di `docs/spikes/` dan fase 06 membaca log 01S, tetapi keduanya hanya terlihat di worktree app kalau PR spike sudah merged **dan** branch app dibuat/rebase setelahnya. Kalau 01S selesai setelah fase 06 dimulai (atau PR spike masih `[r]`), tidak ada fase lain (06Q, 13–16) yang menerapkannya, padahal checkbox mandat ON-04 mensyaratkannya. Sisa teks lama: `PROGRESS.md:12` "(+ feat/ON-04-refine)" dan `fase-02:74` "Fase 01S / `feat/ON-04-refine` menyempurnakan…" bertentangan dengan `fase-01S:45` ("tidak mengubah `TurnOnExtensionView`"). | Fase 02/06 membaca handoff dengan `git show origin/spike/S1-S2-extension:plan/alief/log/fase-01S.md` (tidak perlu menunggu merge). Tambah butir di 06Q (atau fase 13 kalau 06Q sudah lewat): "kalau handoff Refine ON-04 belum ditandai diterapkan → kerjakan di sini". Hapus `feat/ON-04-refine` dari PROGRESS dan fase 02. |
| R1 | RENDAH | `fase-13-api-repository.md:42-48`, `fase-15-push-validasi.md:42-45`, `ref/sim.sh:8-14` | `source plan/alief/ref/sim.sh` dijalankan **sebelum** `(cd ios && xcodegen)`. `Shoo.xcodeproj` di-gitignore, jadi di checkout yang belum pernah menjalankan `xcodegen` (track c memakai repo utama; fase 00 tidak menjalankannya) `BUNDLE_ID`/`APP_GROUP` kosong tanpa pesan, dan `simctl get_app_container booted "" ""` / `simctl push … "" …` gagal. Diuji: `source` di checkout ini mencetak `SIM=…` saja. | Urutan Verifikasi: `xcodegen` dulu, baru `source`. Di `sim.sh`, kalau `ios/Shoo.xcodeproj` tidak ada: `echo "BUNDLE_ID kosong: jalankan (cd ios && xcodegen) dulu" >&2`. |
| R2 | RENDAH | `PROMPT.md:93-97,104-108` | Mode REVIEW: (a) catatan "review ditangani @<sha>" ditulis di log fase pada branch fase itu, padahal langkah 1 berjalan di worktree yang mungkin ada di branch lain (fase stacked yang dibuat sebelum catatan); tidak tertulis log mana yang dibaca. (b) `--json comments` hanya memuat komentar percakapan; komentar baris (inline) masuk review berstatus `COMMENTED`, yang tidak memicu pilihan 0. (c) Catatan memakai `<tanggal>`, bukan cap waktu, jadi review di hari yang sama ambigu. (d) Docs GitHub: setelah memberi review, Umar "no longer considered a requested reviewer"; ada endpoint khusus `…/requested_reviewers/rerequest`. | Pakai penanda di PR itu sendiri: balasan agent "Review handled @<sha> <ISO time>" sebagai komentar PR, lalu pemicu = review apa pun (termasuk `COMMENTED`) atau komentar Umar dengan `submittedAt`/`createdAt` lebih baru dari komentar penanda terakhir. Fallback re-request: `gh api -X POST repos/umarmuhdhor/Final-CH7/pulls/<no>/requested_reviewers/rerequest -f 'reviewers[]=umarmuhdhor'` kalau `gh pr edit --add-reviewer` tidak mengubah status. |
| R3 | RENDAH | `ref/R2-skema-db.md:104-108,182`, `fase-12-be-retensi-hardening.md:43`, `TODO.md:44` (B9) | `ops_heartbeat` hanya satu baris (`id = 1`); upsert cron dan `/healthz/db` saling menimpa `source`. Monitor B9 memanggil `/healthz/db` setiap hari, jadi bukti `source = 'cron'` hanya terlihat di jendela antara cron 03:00 WITA dan panggilan monitor berikutnya. | Primary key = `source` (dua baris: `cron`, `healthz`), atau kolom `last_cron_at`. Query DoD: `select at from ops_heartbeat where source = 'cron'`. |
| R4 | RENDAH | `fase-15-push-validasi.md:46` | Id `6f1c2a4e-…-0a1b2c3d4e03` dimiliki `dev_mom` di seed. Guardian simulator di langkah 4 adalah device baru yang dipasangkan dengan Protected simulator baru, jadi `GET /scans/{id}` → 404 dan perintah ini tetap menguji jalur error, bukan Detail. | Pakai id dari respons `POST /scans` (curl sebagai Protected simulator) di langkah 4, mis. `SCAN_ID=$(curl … | jq -r .id)` lalu `openurl … "shoo://scan/$SCAN_ID"`. |
| R5 | RENDAH | `TODO.md:63` (C14) | C14 masih menulis "Settings: <n> tap dari `openSettingsURLString`, tanpa link langsung publik", bertentangan dengan `openExtensionsSettings` iOS 26.2 (fase 02, 01S, C17). | Ubah menjadi "Link langsung `openExtensionsSettings` (iOS 26.2+) = <hasil>; iOS < 26.2: <n> tap dari `openSettingsURLString`". |
| R6 | RENDAH | `PROMPT.md:66`, `README.md:48` | Daftar prefix keputusan masih "D-alief-A/B/C…", tanpa S; langkah 6g dan README §4 sudah memakai S. | Tulis "A/B/C/S". |
| R7 | RENDAH | `fase-15-push-validasi.md:7` ("Team ID di `project.yml`"), `ARCHITECTURE.md:65` ("Butuh Team ID (B6)"), `README.md:82` ("QA-E2E butuh TestFlight (TODO B6)") | Rujukan lama: sejak L0 Team ID ada di `Local.xcconfig`, dan B6 sekarang berarti signing lokal; TestFlight = B8. | Ganti ke "C3 (`aps-environment` + capability Push)", "B8", dan "TODO B6–B8". |
| R8 | RENDAH | `ref/R3-catatan-api.md:66,81`, `SECURITY.md:33` (T10) vs `ios/ShooExtension/Resources/pipeline.js:87-104`, `background.js` (`verdict()` menangkap error → `verdict: null`) | Rate limit `GET /verdicts` 1 req/2 s per device. EX-02 memanggil `GET /verdicts` sekali per halaman yang mencapai skor 30 (cache 60 s per domain), ditambah polling 5 s EX-06 di tab lain. Dua lookup dalam 2 s → 429 → extension menganggap tidak ada verdict, sehingga halaman yang sudah ditandai safe bisa tetap discan/diblokir sampai lookup berikutnya. | Batas per (device, domain) 1 req/2 s, atau token bucket 5 req / 10 s per device. Kirim `Retry-After`. Sampaikan perilaku 429 ke Umar di C8. |
| R9 | RENDAH | `ref/R7-protokol-qa.md` §5 (matriks QA-E2E) | Belum ada skenario deep link dari extension ("See detail" popup EX-04, "Review in Shoo" EX-06, `shoo://activity`) dan skenario scan di subdomain (#S1). | Tambah #18 "popup See detail / Review in Shoo membuka Detail yang benar; tanpa id → Activity; link rusak → Shield" dan #19 "scan dari `https://login.<domain>/…` tersimpan dan verdict berlaku per registrable domain". |
| R10 | RENDAH | `ref/R2-skema-db.md:158-163` (§5 butir 4) | "Autocommit (tanpa begin)" belum cukup: docs Postgres, satu pesan Query berisi beberapa statement dijalankan "as a single transaction" (blok implisit). SQL editor Supabase mengirim seluruh isi editor sekaligus, jadi beberapa `update` yang di-paste bersama tetap satu transaksi. Dampaknya kecil (jeda milidetik). | Tulis "jalankan satu statement per eksekusi (pilih satu baris lalu Run)". |

Jumlah: **KRITIS 0 · TINGGI 0 · SEDANG 5 · RENDAH 10**.

## 4. Kontradiksi antar-dokumen

- **`ref/R3:61` + `SECURITY.md:27` (`domain` = host `url` tanpa `www.`) ↔ `contracts/scan-result.schema.json:30` (registrable domain) + EX-02 `background.js` (PSL):** (#S1).
- **`fase-01S:22,26,39`, `TODO.md:65`, D-alief-34 (`getStateOfSafariExtension` di iOS) ↔ docs Apple (method itu macOS saja; iOS = `getStateOfExtension`):** (#S2).
- **`TODO.md:42` + `fase-16:22` (satu kunci, ganti `APNS_ENV` saja) ↔ docs APNs (kunci per environment Sandbox/Production):** (#S3).
- **`fase-15:25,28` (hanya `shoo://scan/<id>`) + `TODO.md:67` (C16 meminta Umar) ↔ `origin/main:ios/ShooExtension/Resources/popup.js` (`shoo://activity`) + PR #1 (`shoo://activity`, link tak dikenal → Shield):** (#S4).
- **`PROGRESS.md:12` + `fase-02:74` (`feat/ON-04-refine`) ↔ `fase-01S:45` + D-alief-34(c) (spike tidak mengubah `TurnOnExtensionView`, refine di fase 02/06):** (#S5).
- **`TODO.md:63` (C14 "tanpa link langsung publik") ↔ `fase-02:35`, `fase-01S:40`, `TODO.md:65` (`openExtensionsSettings` iOS 26.2):** (#R5).
- **`PROMPT.md:66`, `README.md:48` (A/B/C) ↔ `PROMPT.md:163`, `README.md:95` (A/B/C/S):** (#R6).
- **`fase-15:7` ("Team ID di `project.yml`") ↔ `ios/project.yml` + `ios/Config/` (Team ID di `Local.xcconfig`, L0):** (#R7).
- **`ref/R3:66,81` (1 req/2 s) ↔ EX-02 `pipeline.js` (lookup verdict per halaman ≥ 30) + EX-06 polling 5 s:** (#R8).
- **`contracts/api.md` Blocklist ("all domains with a `not_safe` verdict from any family") ↔ D-alief-25:** deviasi yang sudah diusulkan ke Umar + Imelda (C6). Bukan temuan baru.
- **PRD §5 Validasi ("masuk whitelist keluarga") ↔ D-alief-09 (per pemilik):** deviasi tercatat sejak run 01, masih menunggu konfirmasi Umar.

## 5. Lima risiko terbesar untuk MVP + mitigasi

1. **Scan dari subdomain ditolak atau verdict tidak cocok** (#S1): alur inti push → It's safe → buka blokir putus untuk banyak situs phishing nyata, dan baru terlihat saat EX-07 Umar tersambung. Mitigasi: validasi sufiks host, test subdomain di fase 09, skenario QA-E2E #19.
2. **Push production gagal di QA-E2E** (#S3, sisa S4 run 04): kunci Sandbox-only, tim berbeda, atau topic salah membuat GD-06 (P0) gagal tepat saat demo. Mitigasi: dua kunci (Sandbox untuk D7, Production untuk TestFlight) dari tim yang sama dengan build, diset bersama `APNS_ENV`/`APNS_TOPIC` di fase 16 langkah 1, uji satu push production sebelum menjalankan matriks.
3. **`main` terus bergerak** (#S4; T1 run 03 dan 04): EX-04 dan kontrak deep link muncul dua menit setelah commit perbaikan. Mitigasi: sebelum setiap commit plan dan setiap run verifikasi, `git fetch origin && git log --oneline HEAD..origin/main` + `gh pr list --state open`; PROMPT langkah 3a sudah fetch, tambahkan "baca PR kontrak terbuka milik Umar".
4. **Spike 01S tidak terkompilasi atau hasilnya tidak sampai ke ON-04** (#S2, #S5): method macOS di target iOS, handoff hanya di branch spike. Mitigasi: nama API iOS yang benar, baca handoff lewat `git show origin/spike/…`, butir cadangan di 06Q/13.
5. **Mode auto macet atau melewatkan review** (#R2, proteksi branch masih mati): komentar inline atau review di hari yang sama tidak terdeteksi. Mitigasi: penanda berupa komentar PR dengan cap waktu, semua jenis review memicu pilihan 0, minta Umar mengaktifkan proteksi branch (C18).

## 6. Pertanyaan yang harus dijawab sebelum fase 01 dan 07

1. **Umar:** `domain` di `POST /scans` = registrable domain dari PSL extension; boleh server hanya memeriksa sufiks host tanpa PSL sendiri (#S1)? Imelda juga memakai registrable domain untuk blocklist?
2. **Umar:** PR #1 deep links: app menampilkan Shield untuk link tak dikenal, dan `shoo://activity` membuka tab Activity mode saat ini (Guardian dengan Family mode → Activity Family)? Boleh rute deep link dikerjakan di fase app (mock) sebelum track c (#S4)?
3. **Umar:** setuju `SFSafariExtensionManager.stateOfExtension(withIdentifier:)` (iOS 26.2+) sebagai sumber status tambahan (C17, nama method diperbaiki, #S2)?
4. **Alief/Umar:** tim berbayar mana untuk D7 dan TestFlight, dan kunci APNs mana (Sandbox, Production, atau keduanya) yang dibuat di tim itu (#S3)?
5. **Umar:** proteksi branch `main` jadi diaktifkan (C18)? Dibutuhkan agar `reviewDecision` terisi dan review wajib.
6. **Alief:** iOS berapa di iPhone uji Alief dan orang tua? Menentukan jalur iOS 26.2 atau fallback yang diuji di 01S dan QA-E2E #17.
7. **Umar (C3, C6, C11, C12, C13):** masih terbuka dari run 03/04 (capability kamera/push/audio, review manual blocklist, `extensionLastSeenAt`, `GET /devices/me`, `owner=family`).

---

## I. Cek dokumentasi resmi

| # | Klaim di plan | Status | Sumber / koreksi |
|---|---|---|---|
| I1 | `SFSafariSettings.openExtensionsSettings(forIdentifiers:)` di iOS 26.2+, harus saat foreground, identifier = bundle ID extension (`fase-02:35`, `fase-01S:26,40`) | **VERIFIED** | https://developer.apple.com/documentation/safariservices/sfsafarisettings/openextensionssettings(foridentifiers:completionhandler:) — platform iOS/iPadOS/Mac Catalyst/visionOS 26.2; deklarasi `openExtensionsSettings(forIdentifiers: [String], completionHandler:)` + varian `async throws`; "returns an error unless you call it while your app is in the foreground". Kelas `SFSafariSettings` sendiri iOS 26.0. Identifier `Bundle.main.bundleIdentifier! + ".extension"` cocok dengan `ios/project.yml` (`$(SHOO_BUNDLE_ID).extension`) |
| I2 | `SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier:)` di iOS 26.2 (`fase-01S:22,26,39`, C17, D-alief-34) | **WRONG** | https://developer.apple.com/documentation/safariservices/sfsafariextensionmanager/getstateofsafariextension(withidentifier:completionhandler:) — **macOS 10.12** saja. Versi iOS: https://developer.apple.com/documentation/safariservices/sfsafariextensionmanager/getstateofextension(withidentifier:completionhandler:) — iOS/iPadOS/Mac Catalyst/visionOS 26.2, "check on the state of a Safari web extension embedded inside your app", varian `stateOfExtension(withIdentifier:) async throws -> SFSafariExtensionState`; https://developer.apple.com/documentation/safariservices/sfsafariextensionstate — properti `isEnabled` → #S2 |
| I3 | `UIApplication.openSettingsURLString` sebagai fallback iOS < 26.2 | **VERIFIED sebagian** | https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring — "display your app's custom settings, if it has any". Mendarat di halaman app, bukan Safari › Extensions; plan sekarang memakainya hanya sebagai fallback + ilustrasi (benar) |
| I4 | PiP: `AVAudioSession` `.playback`, `AVPlayerViewController` full screen, delegate restore, `UIBackgroundModes: [audio]` (`fase-02:37`, C3 butir 4) | **VERIFIED** | https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-standard-player — PiP aktif "after you configure your audio session and set the project capabilities"; otomatis "if your video is playing in full-screen mode and the user exits the app"; `canStartPictureInPictureAutomaticallyFromInline` untuk video yang tidak memenuhi layar; restore lewat `playerViewController(_:restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:)`. https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback — kategori `.playback` + background mode "Audio, AirPlay, and Picture in Picture" |
| I5 | `xcodebuild -project ios/Shoo.xcodeproj -target Shoo -showBuildSettings` memuat `PRODUCT_BUNDLE_IDENTIFIER` dan `SHOO_APP_GROUP` dari xcconfig (`ref/sim.sh:9-11`) | **VERIFIED sebagian** | `man xcodebuild`: "-showBuildSettings Lists the build settings for targets in a project or workspace. Does not initiate a build. Use with -target or with -scheme". Variabel xcconfig adalah build setting proyek (`configFiles` di `ios/project.yml` untuk Debug + Release, `#include? "Local.xcconfig"` di `ios/Config/Shoo.xcconfig`), jadi ikut terdaftar. Tidak diuji langsung: `ios/Shoo.xcodeproj` tidak ada di checkout ini dan `xcodegen` dilarang. Urutan `source` vs `xcodegen` → #R1 |
| I6 | `xcrun simctl push <udid> <bundle-id> <file>` tanpa `Simulator Target Bundle` (`fase-15:26,45`) | **VERIFIED** | `xcrun simctl help push` lokal: "Usage: simctl push <device> [<bundle identifier>] (<json file> \| -)"; key `Simulator Target Bundle` hanya dibutuhkan kalau bundle identifier tidak diberikan |
| I7 | APNs `apns-topic` = bundle ID; kunci + Team ID terikat tim (`ref/R3:93`, B7) | **VERIFIED**, plus fakta baru | https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns — "In general, the topic is your app's bundle ID/app ID". https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns — `iss` = Team ID; "APNs relates a team ID and associated bundle IDs to a connection"; **kunci team-scoped "restrict usage to either Sandbox or Production"**, kunci lama untuk keduanya tetap didukung, maks 2 kunci per environment → #S3 |
| I8 | `gh pr view <no> --json state,reviews,comments,commits`; `gh pr edit <no> --add-reviewer umarmuhdhor` untuk review ulang (`PROMPT.md:93,107`) | **VERIFIED** / **VERIFIED sebagian** | `gh pr view --help` lokal: field `reviews`, `comments`, `commits`, `latestReviews`, `reviewDecision` ada; `gh pr edit --help` memuat `--add-reviewer`. https://docs.github.com/en/rest/pulls/review-requests — "Once a requested reviewer submits a review, they are no longer considered a requested reviewer"; ada endpoint `POST /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers/rerequest`. Bahwa `--add-reviewer` me-request ulang orang yang sudah me-review: **NOT YET VERIFIED** → #R2 |
| I9 | `reviewDecision` kosong tanpa proteksi branch | **NOT YET VERIFIED** | Plan sudah menurunkannya jadi sinyal tambahan (`PROMPT.md:97`). `gh api …/branches/main` → `"protected": false` (diuji) |
| I10 | Postgres `clock_timestamp()` per statement + "autocommit (tanpa begin)" (R2 §5) | **VERIFIED** / **VERIFIED sebagian** | https://www.postgresql.org/docs/current/functions-datetime.html (run 04). https://www.postgresql.org/docs/current/protocol-flow.html §"Multiple Statements in a Simple Query": "those statements are executed as a single transaction, unless explicit transaction control commands are included" → #R10 |
| I11 | Domain = registrable domain (kontrak) | **VERIFIED** (dari repo) | `contracts/scan-result.schema.json:28-30`, `ios/ShooExtension/Resources/background.js` (`registrableDomain` + `psl.js`), PRD §5 ("Kalau bca-verifikasi.site ditandai Not safe, semua halamannya ikut diblokir") → #S1 |
| I12 | postgres.js di Workers lewat Hyperdrive: ≥ 3.4.5, `nodejs_compat`, `max: 5`, `fetch_types: false`, jangan `prepare: false` (R1, fase 07) | **VERIFIED** (dibaca ulang) | https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-drivers-and-libraries/postgres-js/ — "minimum version … is `3.4.5`", `nodejs_compat` "required for database drivers to function", `max: 5` "due to Workers' limits on concurrent external connections", `fetch_types` dimatikan kalau tidak ada tipe array, `prepare: false` "can cause queries to hang or fail intermittently" |
| I13 | Supabase: `supabase secrets set --env-file`, `functions serve --env-file ./supabase/functions/.env.local` (fase 11, R3 §7) | **VERIFIED** (dibaca ulang) | https://supabase.com/docs/guides/functions/secrets — `supabase secrets set --env-file .env`; lokal default `supabase/functions/.env`, file lain (mis. `.env.local`) hanya dibaca dengan `--env-file` di `functions serve`; baca dengan `Deno.env.get` |
| I14 | Hyperdrive `--caching-disabled`, lokal `localConnectionString` / env `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_DB`; Workers Free CPU 10 ms, 50 subrequest, 5 Cron | **VERIFIED** (run 02–04, tidak dibaca ulang) | https://developers.cloudflare.com/hyperdrive/concepts/query-caching/, https://developers.cloudflare.com/hyperdrive/configuration/local-development/, https://developers.cloudflare.com/workers/platform/limits/ |
| I15 | Supabase Storage REST, `verify_jwt = false` di `config.toml`, kuota Free + pause 7 hari | **VERIFIED** / **VERIFIED sebagian** (run 03–04, tidak dibaca ulang) | Run 03 I13–I16, run 04 I17–I18 |
| I16 | HTTP/2 dari Worker `fetch()` / Edge Function Deno ke APNs | **NOT YET VERIFIED** (tidak berubah) | Plan tetap memakai spike cloud fase 07 + uji relay lokal fase 11 |
| I17 | `.environment(\.locale)` + String Catalog; WhatsApp tidak membuat `shoo://` bisa diklik; jalur Settings iOS 17 vs 18 | **NOT YET VERIFIED** (tidak berubah) | Diuji di fase 01 langkah 5, QA-E2E #4, spike S2 |
| I18 | App Groups / Push di Personal Team | **NOT YET VERIFIED** / **VERIFIED sebagian** (run 04 I4–I5) | Plan menandainya jujur di 01S Risiko dan C3 |

## J. Cek wiring ujung ke ujung

### J1. `ShooRepository` (`fase-01:40`) → `contracts/api.md` → fase backend

| Method app | Endpoint kontrak | Backend | Catatan |
|---|---|---|---|
| `registerDevice(name:mode:)` | `POST /devices` | 07 §5 | Bahasa ID langsung `PATCH` (`fase-13:33`) |
| `updateMe(name:language:apnsToken:)` (+ `extensionLastSeenAt?` kalau C11) | `PATCH /devices/me` | 07 §6 | OK (`fase-13:37`) |
| `createFamilyCode()` | `POST /family/code` | 08 §1 | OK |
| `joinFamily(code:)` | `POST /family/join` | 08 §2 | OK (+ `already_connected`) |
| `familyMembers()` | `GET /family/members` | 08 §3 | OK |
| `removeMember(_:)` | `DELETE /family/members/{id}` | 08 §4 | OK |
| `leaveGuardian()` | `DELETE /family/guardian` | 08 §4 | OK |
| `scans(owner:status:cursor:)` | `GET /scans` | 09 §2 | OK |
| `scan(id:)` | `GET /scans/{id}` | 09 §3 | OK; target push dan `shoo://scan/<id>` (15) |
| `setVerdict(scanId:value:)` | `POST /verdicts` | 10 §1 | OK |
| — | `GET /devices/me` (usulan C12) | — | Celah tercatat (D-alief-21) |

Endpoint tim lain: `POST /scans` (extension EX-07, 09 — validasi `domain` → #S1), `GET /verdicts?domain=` (extension, 10 — rate limit → #R8), `GET /blocklist` (detector, 07 + 10), `GET /join` (browser, 08), `/healthz`, `/healthz/db` (B9). **Semua 10 operasi protocol terpetakan ke endpoint dan fase.** Pintu masuk app: push (`NotificationRouter`, 15), `shoo://join` (14), `shoo://scan/<id>` (15); **`shoo://activity` dan default "→ Shield" belum ada** (#S4).

### J2. Key App Group: penulis dan pembaca

| Key | Penulis | Pembaca | Status |
|---|---|---|---|
| `device.id`, `device.token`, `device.mode` | App fase 13 `SessionStore` | Extension `getSession` (`SafariWebExtensionHandler.swift`) → `background.js` `getSession()` (cache 30 s) | OK |
| `device.name` | App fase 13 + tulis ulang setelah `updateMe(name:)` | Extension `getSession` | OK |
| `guardian.name` | App fase 14 (join), dihapus saat `leaveGuardian()`/404 | Extension `getSession` | OK; pemutusan dari sisi Guardian tidak terdeteksi (D-alief-21) |
| `api.baseURL` | App fase 13 (`AppConfig`) | `background.js` `verdict()` (EX-02, sudah dipakai) | OK |
| `ai.baseURL` | App fase 13, `TODO(sync:imelda)` | `background.js` `analyze()` (EX-02, sudah dipakai) | Bergantung Imelda |
| `extension.lastSeenAt` | Extension: `content.js` (setiap halaman) → `background.js` (throttle 60 s) → handler | App `ExtensionStatus` (01; dipakai 01S, 02, 04, 05, 06) | OK |

Kedelapan key di `ios/ShooShared/AppGroup.swift` = delapan baris `contracts/app-group-keys.md`. **Setiap key punya penulis dan pembaca.** EX-02 tidak menambah key App Group atau native message (hanya pesan internal `domain`, `analyze`, `verdict` antara content script dan background). Nama suite selalu lewat `AppGroup.id`; plan tidak lagi menulis nama suite literal.

### J3. Env R3 §7 → LANGKAH MANUAL

| Variabel | Diset di | Status |
|---|---|---|
| `DB` (Hyperdrive) | fase 07 LANGKAH MANUAL 3 (B4, `--caching-disabled`); placeholder lokal | OK (placeholder BELUM DIVERIFIKASI) |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | fase 09 DoD (B5); lokal `.dev.vars` | OK |
| `INVITE_BASE_URL` | fase 07 LANGKAH MANUAL 4 (`vars`); lokal override | OK |
| `APNS_TOPIC` (baru) | fase 11 LANGKAH MANUAL 8 (`--env-file`, bundle ID build D7); fase 16 langkah 1 (bundle ID TestFlight) | OK |
| `APNS_ENV` | fase 11 langkah 8; fase 16 langkah 1 (`production`) | OK, tetapi kunci harus ikut diganti → #S3 |
| `PUSH_RELAY_URL`, `PUSH_RELAY_SECRET` | fase 11 LANGKAH MANUAL 8 | OK |
| `APNS_KEY_P8_B64`, `APNS_KEY_ID`, `APNS_TEAM_ID` | fase 11 langkah 8; fase 16 langkah 1 hanya kalau tim berbeda | Perlu diganti juga per environment → #S3 |
| `SCREENSHOT_MAX_BYTES` | `vars` `wrangler.jsonc` | OK |
| `APNS_SPIKE`, `SPIKE_KEY` | fase 07 LANGKAH MANUAL 4/6 → dihapus fase 11 | OK |
| Secret CI (5) | C2 ke Umar (fase 12) | OK |

Catatan kecil: uji relay lokal fase 11 langkah 7 memakai `supabase/functions/.env.local`; isinya harus memuat `APNS_TOPIC` dan `APNS_ENV` juga (tidak disebut eksplisit), kalau tidak Edge Function lokal mengirim header topic kosong.

### J4. Gate PROGRESS bisa dicapai dan diperbarui langkah 1?

| Gate | Cara tercapai | Diperbarui langkah 1? |
|---|---|---|
| G0 | Jawaban Umar di TODO C3/C11/C13 | Ya (`PROMPT.md:99`, dari kolom Status TODO) |
| G1 | Merge PR `docs/alief-plan` | Ya (baris fase 00 disegarkan, `PROMPT.md:98`) |
| G2 | Merge `chore/APP-test-targets` | Ya |
| G3 | Fase 07 LANGKAH MANUAL tercentang | Ya |
| G4 | Fase 10 uji cloud tercentang | Ya |
| G5 | Semua PR 01–06Q merged | Ya |
| G6 | Semua PR 07–12 merged + D8 | Ya; track c hanya butuh merged, D8 untuk fase 16 (`PROMPT.md:115`) |
| G7 | B6–B8 | Ya; B7 perlu kunci Production → #S3 |
| G8 | Laporan QA-E2E LULUS | Ya |

**Semua gate bisa dicapai dan disegarkan di langkah 1.**

### J5. Transisi status (PROMPT langkah 1, D-alief-31/35)

| Status | Masuk | Keluar | Status |
|---|---|---|---|
| `[ ]` | awal | `[~]` (langkah 4) | OK |
| `[~]` | langkah 4 | `[m]` (6h), `[r]` (langkah 10), `[!]` (13b) | OK |
| `[m]` | 6h (termasuk pengecualian 01S, `PROMPT.md:172`) | langkah 1 pilihan 1 → sisa Langkah kerja → 7–11 → `[r]` | OK |
| `[r]` | langkah 10 | `[x]` (MERGED), `[!]` (CLOSED), mode REVIEW | OK |
| REVIEW (pilihan 0) | review `CHANGES_REQUESTED`/komentar Umar lebih baru dari penanda | penanda "review ditangani @<sha>" + `--add-reviewer`; tidak dipilih lagi sampai ada review baru | **Ada syarat keluar**; deteksi masih bolong untuk komentar inline / hari yang sama / log di branch lain → #R2 |
| `[x]` | langkah 1 | final | OK |
| `[!]` | agent (blocker P0 / PR ditutup) atau manual (fase 17) | Alief → `[ ]`/`[~]` | OK |

### J6. Track spike 01S: konsistensi antar-file

| Aspek | PROMPT | README | PROGRESS | R6 | TODO | fase-01S / 02 / 06 | Status |
|---|---|---|---|---|---|---|---|
| Track + urutan | `:17,40` | `:17,63,95,107` | `:12` | `:34` | B6, C14, C17, D5 | `01S:5-10` | Konsisten |
| Folder yang boleh diubah | `:77` | `:95,97` | — | — | — | `01S:26-27` | Konsisten |
| Signing | `:178-181` (L0) | `:97` (L0) | — | — | B6 (L0) | `01S:7,33` | Konsisten (T1 run 04 FIXED) |
| Status di uji perangkat | `:172` (`[m]` untuk 01S) | `:17` | — | — | — | `01S:35` | Konsisten (S1 run 04 FIXED) |
| Branch dasar + PR | `:128-129` (stacked) | — | `:12` (masih `+ feat/ON-04-refine`) | — | — | `01S:7,46`; `02:74` (masih `feat/ON-04-refine`) | Sisa teks lama → #S5 |
| Prefix keputusan | `:163` (S), `:66` (A/B/C) | `:95` (S), `:48` (A/B/C) | — | — | — | `01S:44` (S) | Sisa → #R6 |
| Handoff ke 02/06 | — | `:107` (garis putus 01S → 02) | — | — | — | `01S:45`, `02:19,33`, `06:34` | Bisa hilang kalau PR spike belum merged → #S5 |
| API iOS 26.2 | — | — | — | — | C14 (lama), C17 (nama salah) | `01S:22,26,39` (nama salah), `02:35` (benar) | → #S2, #R5 |

### J7. Dampak EX-02 / EX-04 Umar (`4b165e6` di branch, `597a6d1` di `main`) terhadap asumsi plan

| Asumsi plan | Kode Umar | Status |
|---|---|---|
| Heartbeat `content.js` → `background.js` → handler → `extension.lastSeenAt` (ON-04, 01S S1) | `content.js:105` `send({type:"heartbeat"})` setiap halaman; `background.js` throttle 60 s → `sendNativeMessage` | **Tidak berubah**. Catatan untuk S1: heartbeat pertama butuh halaman dimuat; throttle 60 s ada di memori background, jadi setelah background dimuat ulang heartbeat langsung terkirim |
| `POST /scans` body = ScanResult tanpa `id`/`verdict` | Belum diimplementasikan (`content.js:4` "TODO(EX-07)"); `domain` di snapshot = registrable domain PSL | Bentuk sama, tetapi aturan `domain` server salah → #S1 |
| `GET /verdicts?domain=` hanya untuk polling EX-06 | Dipakai juga oleh pipeline EX-02 sekali per halaman ≥ 30 (cache 60 s, `fresh` untuk polling), 429/timeout → `verdict: null` | Rate limit plan terlalu ketat → #R8 |
| App Group keys + native messages | Tidak ada key/pesan baru; `getSession` di-cache 30 s | OK |
| `GET /blocklist` | Tidak dipakai extension (detector Imelda) | OK |
| Deep link dari popup EX-04 | `popup.js` (`597a6d1`): `shoo://scan/{recordId}` atau `shoo://activity`; PR #1 menambah "unknown → Shield" | Plan belum menangani `activity`/default → #S4 |

### J8. Mandat `docs/mandates/alief.md` → fase

| Checkbox mandat | Fase |
|---|---|
| S1, S2 | 01S |
| Fondasi | 01 |
| ON-01, ON-02, ON-03, ON-04, ON-05 | 02 (ON-04 + handoff 01S; risiko #S5) |
| DT-01 s.d. DT-06 | 03 |
| PR-04, PR-05 | 04 |
| GD-01, GD-02, GD-03, GD-05 | 05 |
| PF-01 | 06 |
| Devices · Family · Scans · Verdicts · Blocklist · Push · Retensi · Keamanan | 07 · 08 · 09 · 10 · 07+10 · 11 · 12 · 08/09/10/12 (dicentang di 12) |
| `ApiRepository` · key App Group | 13 · 13 |
| GD-04 · PR-01/PR-02 · PR-03 | 14 · 14 · 14 |
| GD-06 · GD-07 | 15 · 15 |
| Ditahan: Live Activity push | 17 |

Mandat Alief tidak berubah sejak `495c792` (`597a6d1` hanya mengubah `docs/mandates/umar.md`). **Semua checkbox terpetakan ke tepat satu fase, tidak ada yang dobel, tidak ada yang dikerjakan di luar folder Team App** (pengecualian tertulis: `project.yml` D-alief-02, `plan/alief/`, checkbox mandat, dua file spike).

### J9. Perintah Verifikasi dari root repo

| Fase | Hasil |
|---|---|
| 00 | `ls …` OK; grep `TODO(sync` kosong; `git diff --stat origin/main...HEAD -- . ':!plan/alief'` kosong (diuji) |
| 01, 02–06, 06Q | `source plan/alief/ref/sim.sh` (bash + zsh → `SIM=iPhone 17 Pro`, `bash -n` lulus); `xcodebuild -project ios/Shoo.xcodeproj` benar dari root setelah `xcodegen` |
| 01S | `git diff --name-only origin/main...HEAD -- ios/project.yml ios/ShooShared ios/ShooExtension` kosong (diuji); `-only-testing:ShooAppTests/ExtensionStatusTests` butuh fase 01 (prasyarat sudah tertulis); `ExtensionSpikeView` tidak terkompilasi kalau memakai method macOS (#S2) |
| 07, 12 | Subshell `(pnpm -C backend/api dev …&)` + `pnpm -C backend/api exec wait-on tcp:8787` + `pkill`; `wrangler dev --test-scheduled` + `/cdn-cgi/local/scheduled` |
| 08–11 | `(cd backend/db && supabase start && …)`, `pnpm -C backend/api exec vitest run <pola>`, `deno test --allow-env` benar |
| 13 | `plutil -p "$(xcrun simctl get_app_container booted "$BUNDLE_ID" "$APP_GROUP")/Library/Preferences/$APP_GROUP.plist"`: bentuk benar, tetapi `source` dijalankan sebelum `xcodegen` → variabel kosong di checkout baru (#R1) |
| 14 | `simctl openurl "${PROT_UDID:-booted}" …` valid; diff tiga titik Info.plist/entitlements benar |
| 15 | `simctl push "${GUARD_UDID:-booted}" "$BUNDLE_ID" …` valid (I6) dengan catatan #R1; `openurl … shoo://scan/<id seed dev_mom>` menguji jalur 404 (#R4) |
| 16 | gabungan perintah di atas; benar dari root |

### J10. Hardcode bundle ID / App Group

Grep `com\.shoo\.app|group\.com\.shoo` di `plan/alief` (tanpa `log/verify`): hanya `ref/sim.sh:7` (komentar larangan), `ARCHITECTURE.md:13` (default `AppGroup.id`), `PROMPT.md:180` (larangan), `DECISIONS.md:240` (keputusan). **Tidak ada perintah atau kode yang meng-hardcode nilai per developer.** Bundle ID extension diturunkan dari `Bundle.main.bundleIdentifier + ".extension"`, sesuai `ios/project.yml`.

---

## Catatan untuk run berikutnya

- Fokus ulang: #S1 (aturan `domain`), #S2 (nama API iOS), #S3 (kunci APNs per environment), #S4 (merge `597a6d1`, baca PR #1 deep links), #S5 (jalur handoff Refine ON-04).
- Sebelum menulis perbaikan: `git fetch origin && git log --oneline HEAD..origin/main` **dan** `gh pr list --repo umarmuhdhor/Final-CH7 --state open`. Run 03, 04, dan 05 semuanya menemukan `main` atau PR kontrak Umar bergerak beberapa menit setelah commit perbaikan.
- Uji kering mode REVIEW dengan contoh: PR 02 `[r]` dengan review `COMMENTED` berisi komentar inline setelah penanda, dan PR 03 stacked yang dibuat sebelum penanda ditulis di log 02.
- Yang tetap tidak bisa diverifikasi dari docs: HTTP/2 Worker/Edge Function → APNs, `id` Hyperdrive placeholder untuk lokal, App Groups/Push di Personal Team, `reviewDecision` tanpa proteksi branch, `gh pr edit --add-reviewer` sebagai re-request, locale environment + String Catalog, link WhatsApp, jalur Settings per versi iOS, keluaran `-showBuildSettings` di proyek ini (butuh `xcodegen`), wireframe PRD §7 (gambar).

## Verdict akhir

**SIAP** — 0 KRITIS, 0 TINGGI terbuka. Catatan: 5 SEDANG (#S1–#S5) dan 10 RENDAH sebaiknya ditutup sebelum fase 01S, 09, 15, dan 16.
