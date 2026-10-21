# Verifikasi plan Alief — run 04

- **Tanggal:** 21 Okt 2026 (WITA)
- **Reviewer:** Claude Opus 5.5, sesi independen, read-only (satu-satunya file yang dibuat: file ini)
- **Branch/commit yang dibaca:** `docs/alief-plan` @ `1aa9d87` (perbaikan run 03; diff `1caf46c..1aa9d87` juga dibaca, 36 file)
- **Prompt:** `plan/alief/VERIFY_PROMPT.md` (cek A–H, format 1–6) + tambahan I (dokumentasi resmi), J (wiring), dan §2a (status temuan run 03)
- **Bacaan:** semua file di daftar `<bacaan>` dibaca lengkap: CLAUDE.md (root, ios, ios/ShooApp, backend), CODEOWNERS, `.github/pull_request_template.md`, docs/README, `docs/mandates/{alief,umar,README}.md`, 3 spike + `docs/spikes/README.md`, seluruh `contracts/` + fixtures, `ios/ShooShared/*.swift`, `ios/project.yml`, `ios/ShooApp/*.swift`, `ios/ShooExtension/SafariWebExtensionHandler.swift` + jalur heartbeat `content.js` → `background.js`, semua file `plan/alief/` termasuk `ref/sim.sh`, `log/DECISIONS.md`, `log/fase-00.md`, `log/verify/run-01.md`, `run-02.md`, `run-03.md`.
- **PRD v1.5:** berhasil dibaca dari Google Drive (`Shoo-PRD-v1.5.docx`, id `1n_1vngw5fFizP9YHWg0kT3VnqGhgXlbV`). Gambar wireframe §6–§7 tidak ikut terbaca (hanya teks), jadi perbandingan wireframe tidak bisa diverifikasi.
- **Laporan QA Catalyst:** dibaca dari Drive (`QA_Catalyst_DeepSeek_26Sep2026.docx`, id `1ZHVIvha4RxRS1Bgp1dK20VUIByez9mwT`) untuk cek H.
- **Penting — `origin/main` maju lagi:** branch ini sudah memuat `981ad73` (merge `5f37c0a`), tetapi **belum** memuat `495c792` ("L0: per-developer signing via ios/Config/Local.xcconfig", Umar, 21 Okt 2026 15:56 WITA, 21 menit sebelum commit perbaikan `1aa9d87`). Commit itu mengubah `ios/project.yml` (`configFiles`, `$(SHOO_BUNDLE_ID)`, `$(SHOO_APP_GROUP)`), `ios/ShooShared/AppGroup.swift` (`AppGroup.id` dari Info.plist `ShooAppGroup`), `contracts/app-group-keys.md`, `ios/CLAUDE.md`, `docs/mandates/alief.md` (cara signing untuk spike), `docs/mandates/umar.md` (L0 `[x]`), `.gitignore`, dan menambah `ios/Config/Shoo.xcconfig` + `Local.xcconfig.example`. Isinya dibaca read-only (`git show 495c792`, `git show origin/main:<file>`). Dampaknya → #T1.
- **Perintah read-only yang dijalankan:** `bash -n` + `source plan/alief/ref/sim.sh` (bash dan zsh → `SIM=iPhone 17 Pro`), grep Verifikasi fase 00 (kosong), `git diff --stat origin/main...HEAD -- . ':!plan/alief'` (kosong), `git diff --name-only origin/main...HEAD -- ios/project.yml ios/ShooShared ios/ShooExtension` (kosong), grep `git diff` dua titik (tidak ada lagi), grep `booted`, grep `com.shoo.app`/`Local.xcconfig`, `git log/show/diff` ke `origin/main`, `gh api repos/umarmuhdhor/Final-CH7/branches/main` (proteksi branch **tidak aktif**), `gh pr list` (belum ada PR), `gh pr view --help`, `xcrun simctl help push|get_app_container|openurl`, `supabase --version` (2.114.0) + `functions serve|secrets set|start --help`. Docs Apple dibaca lewat endpoint JSON `developer.apple.com/tutorials/data/documentation/…json` (halaman HTML-nya dirender JavaScript). Tidak ada build, `supabase start`, atau deploy.

---

## 1. Ringkasan pemahaman

1. Shoo = Safari Web Extension iPhone + app SwiftUI. Skor 0–100 per halaman: 30–79 Warning (popup, push ke Guardian), ≥ 80 Blocked (layar blokir tanpa bypass). Skor/sinyal milik Imelda, extension + layar blokir + kontrak + `project.yml` milik Umar, app + backend milik Alief.
2. Dua mode permanen tanpa login: **Guardian** (melindungi diri + Family mode ≤ 3 orang) dan **Protected** (orang tua; tidak pernah melihat tombol validasi).
3. App iOS 17 (`@Observable`, String Catalog EN/ID) memakai protocol `ShooRepository`: `MockRepository` (fixtures) di fase 01–06, `ApiRepository` di fase 13 tanpa mengubah view.
4. Backend = Worker Cloudflare `shoo-api` (Hono + zod + postgres.js `fetch_types: false`) → Hyperdrive `--caching-disabled` → Supabase Postgres (role `shoo_api`, PostgREST tidak dipakai) + Storage private (signed URL 1 jam).
5. Push: relay Worker → Edge Function Supabase `push` (Deno, `x-push-secret`, `verify_jwt = false`) → APNs HTTP/2 JWT ES256; langsung dari Worker hanya kalau spike cloud lulus (D-alief-16).
6. Auth per device: token `shoo_` + 32 byte, hash SHA-256 di DB; app menulis `device.*`, `guardian.name`, `api.baseURL`, `ai.baseURL` ke App Group untuk extension; extension menulis `extension.lastSeenAt`.
7. Pairing: kode 4 digit 60 s multi-pakai, maks 3 Protected, 5 gagal/10 menit per device dan per IP; `inviteUrl` https `/join?code=` yang membuka `shoo://join?code=`.
8. Alur inti: Protected membuka situs → extension `POST /scans` → Worker simpan + push (bahasa Guardian) → tap → Detail → It's safe → `POST /verdicts` (per pemilik+domain) → extension polling `GET /verdicts?domain=` 5 s → layar blokir terbuka (target ≤ 10 s). Deep link `shoo://scan/<id>` (baru, D-alief-32) membuka Detail dari popup/layar blokir.
9. Not safe atas scan Protected yang terhubung → hanya **antrean** `blocklist_entries`; `GET /blocklist` hanya mengirim entri yang disetujui manual (`clock_timestamp()`, satu domain per statement, D-alief-25/33, review harian TODO D9).
10. **Baru di run 04:** track **spike** fase 01S (S1 status extension, S2 buka pengaturan) di iPhone Alief + ON-04 di fase 02 dari fallback PRD §10, disempurnakan dari hasil 01S (D-alief-29). Urutan onboarding: Guardian ON-03 → ON-04 → ON-05; Protected ON-03 → PR-01 → PR-02 → ON-04 → ON-05.
11. Track **app** (01→06→06Q) dan **be** (07→12) paralel; track **c** (13→16) setelah semua PR 01–06Q dan 07–12 merged. Status `[ ] [~] [m] [r] [x] [!]` dengan transisi lengkap (D-alief-31): `CHANGES_REQUESTED` → mode REVIEW, `CLOSED` → `[!]`. Deploy fase 12 dari branch fase; redeploy `main` = TODO D8 (syarat G6, D-alief-30). QA-E2E memakai ujung branch fase 15 + backend `main` setelah D8.
12. QA dua ronde format Catalyst (QA-A di 06Q, QA-E2E di 16, 17 skenario termasuk ON-04 #17) dengan fixbug "satu bug = satu test gagal = satu commit", blok Retest, dan kolom Waktu.

## 2. Verdict

**BELUM SIAP** — tidak ada KRITIS dan kedua TINGGI run 03 sudah ditangani, tetapi ada tiga TINGGI baru: (a) plan tertinggal lagi dari `main` (`495c792`, L0 signing per developer): path `ios/Local.xcconfig` salah, fallback "ubah `project.yml`/`AppGroup.id` lokal" sekarang dilarang, dan `com.shoo.app` / `group.com.shoo.app` di-hardcode di `apns-topic`, `simctl`, dan App Group, sehingga push ke iPhone Alief (D7) gagal `DeviceTokenNotForTopic`; (b) klaim "`SFSafariExtensionManager` hanya macOS" SALAH: iOS 26.2 punya API publik untuk status extension dan untuk membuka langsung halaman extension di Settings, yang menyentuh kriteria P0 ON-04; (c) mode REVIEW (pilihan 0) bisa berputar terus karena `reviewDecision` tetap `CHANGES_REQUESTED` setelah perbaikan di-push, dan proteksi branch `main` tidak aktif sehingga nilainya kemungkinan kosong.

## 2a. Status temuan run 03

| run-03 # | Tingkat | Status | Bukti (file:baris di `1aa9d87`) |
|---|---|---|---|
| T1 | TINGGI | **PARTIALLY** | Mandat `981ad73` sudah diikuti: fase baru `fase-01S-spike-extension.md`, ON-04 di `fase-02-onboarding.md:8,24,33-38`, `PROGRESS.md:12,52-53`, `README.md:63-64,95,139`, `fase-17-ditahan.md:13`, `TODO.md:63-64,75` (C14 hasil spike, C15 video, D5), `ref/R7-protokol-qa.md:44,67`, D-alief-29 `log/DECISIONS.md:208-212`. Tetapi `main` maju lagi ke `495c792` (L0) sebelum commit perbaikan, dan isinya tidak diikuti → #T1 baru |
| T2 | TINGGI | **FIXED** | `fase-12-be-retensi-hardening.md:28` (deploy dari branch fase 12, D8 bukan LANGKAH MANUAL), `:45`, `TODO.md:78` (D8), `PROGRESS.md:40` (G6 + D8), `PROMPT.md:97,163`, D-alief-30 `DECISIONS.md:214-218` |
| S1 | SEDANG | **FIXED** | `fase-11-be-push.md:57` dan `fase-14-pairing.md:20` sekarang `[r]` + "pending"; aturan prioritas `PROMPT.md:70` |
| S2 | SEDANG | **FIXED** | `PROMPT.md:104-107` (teruskan Langkah kerja yang belum dicentang, mis. fase 16 langkah 2–6, baru 7–11), `:162`; D-alief-31(c) |
| S3 | SEDANG | **PARTIALLY** | Transisi tertulis di `PROMPT.md:93-103`, `PROGRESS.md:3,5`, D-alief-31 `DECISIONS.md:220-224`. Tetapi pilihan 0 tidak punya syarat keluar (status tetap `[r]`, `reviewDecision` tetap `CHANGES_REQUESTED` sampai Umar me-review ulang) dan bergantung pada field yang kemungkinan kosong karena proteksi branch `main` mati → #T3 |
| S4 | SEDANG | **FIXED** | `ref/R2-skema-db.md:124` (grant memuat `blocklist_entries`), `fase-07-be-fondasi.md:38` (tabel + grant + pgTAP di migrasi awal), `fase-10-be-verdicts.md:23` (hanya kolom `global_eligible`) |
| S5 | SEDANG | **FIXED** | Tiga titik di `fase-00-plan-tooling.md:40`, `fase-01-app-fondasi.md:55`, `fase-01S-spike-extension.md:52`, `fase-14-pairing.md:46`, `fase-15-push-validasi.md:47`, `PROMPT.md:174`. Grep: tidak ada lagi `git diff` dua titik. `git diff --stat origin/main...HEAD -- . ':!plan/alief'` sekarang kosong |
| S6 | SEDANG | **FIXED** (sisa kecil #R5, #R6) | `fase-15-push-validasi.md:25,28,33,46`, `ref/R1-struktur-repo.md:70`, `SECURITY.md:38` (T15), `TODO.md:65` (C16), D-alief-32 `DECISIONS.md:226-230` |
| S7 | SEDANG | **FIXED** | `fase-16-qa-e2e.md:7,22` (app dari ujung branch fase 15, backend `main` setelah D8, commit dicatat di header), D-alief-30 |
| R1 | RENDAH | **FIXED** (sisa G0 → #R1) | `PROMPT.md:96-97` (G1–G8 diperbarui di langkah 1 dengan sumber cek per gate) |
| R2 | RENDAH | **FIXED** | `ref/R5-konvensi.md:38` (`pnpm -C backend/api exec wait-on`) |
| R3 | RENDAH | **FIXED** (catatan #R9) | `ref/R2-skema-db.md:155` (`removed_at` tidak hidup otomatis), `:158` (`families > 0`), `:159,169` (`clock_timestamp()`, satu domain per statement) |
| R4 | RENDAH | **FIXED** | `TODO.md:79` (D9 review harian), `:56` (C7), `:57` (C8) |
| R5 | RENDAH | **FIXED** | `ref/R1-struktur-repo.md:44` (`data/allowlist.ts` + sumber) |
| R6 | RENDAH | **FIXED** (teks) | `ref/R3-catatan-api.md:104,106` (override lokal `.dev.vars` / `miniflare.bindings`), `fase-07-be-fondasi.md:26` (placeholder `id` + fallback env var, BELUM DIVERIFIKASI tertulis jujur) |
| R7 | RENDAH | **FIXED** | `ref/R3-catatan-api.md:93`, `fase-11-be-push.md:29,36` (`Unregistered` + `ExpiredToken`) |
| R8 | RENDAH | **FIXED** | `fase-13-api-repository.md:37` |
| R9 | RENDAH | **FIXED** | `fase-14-pairing.md:35,44-45`, `fase-15-push-validasi.md:35,45-46` (`GUARD_UDID`/`PROT_UDID`; `booted` hanya fallback). `fase-13:48` masih `booted`, wajar (satu simulator) |
| R10 | RENDAH | **FIXED** | `qa/README.md:65` (kolom "Waktu (s)"), `ref/R7-protokol-qa.md:69` |
| R11 | RENDAH | **PARTIALLY** | `TODO.md:41,52` sudah memakai L0 + pertanyaan pemegang akun berbayar, tetapi path-nya `ios/Local.xcconfig` (yang benar `ios/Config/Local.xcconfig`) dan L0 sudah selesai di `main` (`docs/mandates/umar.md` L0 `[x]`) → #T1 |

Ringkas: **16 FIXED (5 dengan sisa kecil), 3 PARTIALLY (T1, S3, R11), 0 NOT FIXED, 0 REGRESSION**.

## 3. Tabel temuan

| # | Tingkat | File § bagian | Masalah | Usulan perbaikan |
|---|---|---|---|---|
| T1 | TINGGI | `fase-01S-spike-extension.md:7,32,69`, `README.md:97`, `TODO.md:41` (B6), `:43` (B8), `:52` (C3 butir 3), D-alief-29 `DECISIONS.md:210`, `PROMPT.md:172-174`, `ref/R3-catatan-api.md:93` (`apns-topic: com.shoo.app`), `fase-13-api-repository.md:47-48`, `fase-15-push-validasi.md:26,45`, `ARCHITECTURE.md:13` vs `origin/main` `495c792` (`ios/Config/Shoo.xcconfig`, `Local.xcconfig.example`, `ios/project.yml`, `AppGroup.swift`, `ios/CLAUDE.md`, `docs/mandates/alief.md` bagian Spike) | **Plan tertinggal dari L0 (`495c792`).** (1) Path salah: plan menyuruh `ios/Local.xcconfig(.example)`, file sebenarnya `ios/Config/Local.xcconfig.example`. (2) Fallback "ubah bundle ID/App Group/Team lokal di `project.yml` dan `AppGroup.id` di `ShooShared`" sudah usang dan sekarang bertentangan dengan `ios/CLAUDE.md` ("never hardcode the App Group — use `AppGroup.id`"); L0 sudah `[x]`, jadi B6/C3 butir 3 bukan lagi permintaan. (3) Bundle ID dan App Group sekarang **per developer** (`SHOO_BUNDLE_ID`, `SHOO_APP_GROUP`; `Local.xcconfig` di-include untuk Debug **dan** Release, juga build simulator). Plan masih menulis `com.shoo.app` dan `group.com.shoo.app` secara literal: `apns-topic` di Worker/Edge Function, `simctl push … com.shoo.app`, `"Simulator Target Bundle": "com.shoo.app"`, `simctl get_app_container booted com.shoo.app group.com.shoo.app` + path plist. Akibat: D7 (push ke iPhone Alief yang ditandatangani dengan bundle ID miliknya) mendapat `400 DeviceTokenNotForTopic` (docs Apple), yang menurut R3 §6 hanya dicatat; DoD fase 11 dan uji perangkat fase 15 tidak pernah lulus, dan perintah Verifikasi fase 13/15 gagal di checkout yang punya `Local.xcconfig`. (4) B8 "record `com.shoo.app`" belum tentu bundle ID milik pemegang akun TestFlight. | Rebase/merge `origin/main` lagi. (a) Ganti semua path ke `ios/Config/Local.xcconfig` (salin dari `.example`), hapus fallback edit `project.yml`/`AppGroup.id`, tandai B6 dan C3 butir 3 selesai oleh L0 (sisa: pertanyaan akun berbayar). (b) Tambah var `APNS_TOPIC` (R3 §7) untuk Edge Function (dan Worker kalau sender langsung), diset di LANGKAH MANUAL fase 11 (bundle ID build D7) dan fase 16 (bundle ID build TestFlight); test vitest/Deno memakai nilai env, bukan literal. (c) Perintah simulator membaca bundle ID dari build settings, mis. `BUNDLE_ID=$(xcodebuild -project ios/Shoo.xcodeproj -scheme Shoo -showBuildSettings 2>/dev/null \| awk '/ PRODUCT_BUNDLE_IDENTIFIER /{print $3; exit}')` dan App Group dari `plutil -extract ShooAppGroup raw` Info.plist hasil build; payload `.apns` tanpa `Simulator Target Bundle` (bundle id diberikan di argumen). (d) ARCHITECTURE: "App Group `AppGroup.id` (default `group.com.shoo.app`)". (e) Entri DECISIONS baru yang merevisi D-alief-29. |
| T2 | TINGGI | `fase-01S-spike-extension.md:38-40`, `fase-02-onboarding.md:33-37`, `README.md:139` (§7 butir 1), D-alief-29, `TODO.md:63` (C14 "tanpa link langsung publik"), PRD §8.1 ON-04 ("Tombol Turn on membuka pengaturan extension Safari") | **Klaim API salah dan ON-04 dikunci ke fallback.** 01S butir S1 menulis "`SFSafariExtensionManager` hanya macOS". Docs Apple sekarang: `SFSafariExtensionManager` tersedia di **iOS 26.2+** ("In iOS and visionOS, use this class to find out the current state of a Safari web extension"), dengan `getStateOfExtension(withIdentifier:completionHandler:)` (iOS 26.2). Untuk S2 ada `SFSafariSettings.openExtensionsSettings(forIdentifiers:completionHandler:)` (iOS 26.2): satu identifier → "Settings opens to that extension's detail view"; harus dipanggil saat app di foreground. Sementara itu `UIApplication.openSettingsURLString` menurut docs membuka "your app's custom settings" — bukan Safari › Extensions. Fase 02 langkah 4 memakai `openSettingsURLString` saja, jadi di iOS ≥ 26.2 tombol Turn on tidak memenuhi "Selesai kalau" ON-04 padahal API publik ada; checklist 01S mengarahkan spike ke kesimpulan "tidak ada API". Pemakaian API status juga perlu izin Umar karena `ios/ShooApp/CLAUDE.md` berkata "Extension Active/Off = `extensionLastSeenAt` … Do not invent another way". | 01S langkah 3: ganti butir menjadi "uji `SFSafariExtensionManager.getStateOfExtension(withIdentifier: <bundle id extension>)` dan `SFSafariSettings.openExtensionsSettings(forIdentifiers: [<bundle id extension>])` di iPhone iOS 26.2+ (catat versi iOS); `openSettingsURLString` mendarat di mana untuk iOS < 26.2". Fase 02 langkah 4: `if #available(iOS 26.2, *)` → `openExtensionsSettings`, selain itu `openSettingsURLString` + ilustrasi; status tetap dari heartbeat, plus `getStateOfExtension` sebagai sumber tambahan **hanya** setelah Umar setuju (usulan baru di TODO §C + DECISIONS, karena aturan CLAUDE.md). Bundle ID extension diambil dari `Bundle.main.bundleIdentifier + ".extension"` (L0). Ubah C14 dan README §7. Catat di PR spike bahwa `docs/spikes/extension-status.md` milik Umar menulis klaim lama. |
| T3 | TINGGI | `PROMPT.md:93-95,101-103`, `:23`, `PROGRESS.md:5`, D-alief-31(a) `DECISIONS.md:222`; `gh api repos/umarmuhdhor/Final-CH7/branches/main` → `"protected": false` | **Mode REVIEW tidak pernah selesai, atau tidak pernah terpicu.** (a) Pilihan 0: kalau `reviewDecision = CHANGES_REQUESTED` → perbaiki, push, balas, status tetap `[r]`, "lalu kembali ke langkah 1". Push commit baru tidak mengubah review "request changes"; nilainya tetap sampai Umar me-review ulang. Langkah 1 memilih fase yang sama lagi di pilihan 0, terus-menerus, jadi fase lain di track itu tidak pernah dikerjakan dan tidak ada syarat berhenti. (b) `reviewDecision` dihitung dari aturan review branch (enum docs GitHub: APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, field nullable). Proteksi branch `main` saat ini tidak aktif, jadi field ini kemungkinan kosong walaupun Umar menekan "Request changes" (BELUM DIVERIFIKASI langsung, belum ada PR). (c) "Komentar review Umar belum dijawab" tidak punya perintah deteksi di langkah 1 (hanya `--json state,reviewDecision`). | Ganti syarat pilihan 0 dengan sesuatu yang bisa selesai: `gh pr view <no> --json reviews,comments,commits` → pilih fase kalau ada review `CHANGES_REQUESTED` atau komentar dari `umarmuhdhor` yang **lebih baru** dari commit terakhir branch dan belum dibalas. Setelah menangani: catat "review ditangani @<sha> <tanggal>" di log fase, minta review ulang (`gh pr edit <no> --add-reviewer umarmuhdhor`), dan lewati fase itu sampai ada review/komentar baru. Pakai `reviewDecision` hanya sebagai sinyal tambahan. Tambah ke TODO §C: minta Umar mengaktifkan proteksi branch (CODEOWNERS sudah menyarankan "enable branch protection on main"). |
| S1 | SEDANG | `fase-01S-spike-extension.md:34` (langkah 3 "set `[m]`, berhenti") vs `PROMPT.md:164-166` (6h: "iPhone fisik … jangan pakai `[m]`; selesaikan fase, buka PR, status `[r]` + pending") dan `PROMPT.md:70` (file fase kalah dari PROMPT) | Dua aturan bertentangan untuk satu-satunya fase yang seluruh hasilnya berasal dari iPhone fisik. Kalau agent mengikuti aturan prioritas, ia membuka PR spike dengan `## Result` kosong (status `[r]` + "pending iPhone"), sehingga DoD 01S dan C14 tidak pernah terpenuhi dan `[m]` tidak pernah dipakai. | Di 6h, kecualikan dengan jelas: "kalau hasil fase itu sendiri berasal dari uji perangkat (01S), pakai `[m]`". Atau ubah contoh "iPhone fisik" menjadi "uji ulang di iPhone fisik untuk kode yang sudah lulus di simulator". |
| S2 | SEDANG | `fase-01S-spike-extension.md:5-7,43-44`, `PROMPT.md:40,109,123-124,157-158`, `README.md:17,95`, `PROGRESS.md:12`, `fase-02-onboarding.md:19,33` | **Alur branch/PR track spike tidak tersambung.** (a) Prasyarat "01" tetapi branch `spike/S1-S2-extension` dibuat dari `origin/main` (langkah 5; PROMPT 3c hanya menumpuk di atas fase sebelumnya **di track yang sama**). Kalau PR 01 masih `[r]`, branch spike tidak punya `ExtensionStatus` maupun target `ShooAppTests`, jadi `ExtensionSpikeView` tidak terkompilasi dan perintah Verifikasi `-only-testing:ShooAppTests/ExtensionStatusTests` gagal. (b) PR dibuka di langkah 5 (di tengah Langkah kerja), lalu PROMPT langkah 10–11 membuka PR lagi; PR kedua `feat/ON-04-refine` (langkah 6) tidak punya baris/kolom PR, status, atau aturan kapan dibuat setelah 01S sudah `[r]` (mode auto melewati `[r]`). (c) Kalau 01S selesai saat fase 02 sedang `[~]` di worktree app, hasilnya tidak terlihat oleh fase 02 (dibaca dari `docs/spikes/` di `origin/main`, belum merged) dan tidak ada jalur refine. (d) Track spike memakai prefix keputusan `D-alief-A…` yang sama dengan track app, padahal 6g memisahkan prefix supaya worktree paralel tidak bentrok; spike dan app juga sama-sama mengubah `TurnOnExtensionView`. | Tulis di 01S: syarat mulai = PR 01 (`chore/APP-test-targets` + `feat/APP-foundation`) MERGED, atau tumpuk di atas `feat/APP-foundation` dan tulis "Stacked on #N". Satukan PR spike ke langkah 11 PROMPT (hapus PR dari langkah 5). Jadikan refine ON-04 butir handoff di log 01S yang **dibaca fase 02/06Q** (atau baris PROGRESS sendiri `01S-r`), dikerjakan oleh track app setelah PR spike merged. Prefix keputusan spike `D-alief-S…` (PROMPT 6g, README §4). |
| S3 | SEDANG | `fase-02-onboarding.md:24,37`, `:68`, `TODO.md:52` (C3 butir 4) | PiP ON-04 belum lengkap. Docs Apple ("Adopting Picture in Picture in a Standard Player"): pemutar mendukung PiP "after you configure your audio session and set the project capabilities"; PiP otomatis saat keluar app berlaku kalau video diputar **full screen**, sedangkan `canStartPictureInPictureAutomaticallyFromInline` hanya untuk pemutar **inline**. Plan hanya menyebut dua properti + `UIBackgroundModes: [audio]`; kategori `AVAudioSession` `.playback` tidak disebut, dan cara pemutar disajikan (sheet full screen vs inline) tidak ditetapkan. Tanpa itu PRD ON-04 "tetap tampil saat di Settings" bisa gagal walaupun C3 butir 4 sudah ada. Juga perlu delegate restore (`restoreUserInterfaceForPictureInPictureStop…`) supaya kembali dari PiP tidak kehilangan layar ON-04. | Tambah di fase 02 langkah 4: `try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)` sebelum play, sajikan `AVPlayerViewController` full screen (atau inline + `canStartPictureInPictureAutomaticallyFromInline`), implement delegate restore; uji PiP di iPhone (simulator tidak cukup) → QA-E2E #17. |
| S4 | SEDANG | `TODO.md:42` (B7), `:41` (B6), `:52` (pertanyaan C3), `fase-11-be-push.md:41` (D7), `fase-16-qa-e2e.md:22`, `ARCHITECTURE.md:64-65` | Kunci APNs dan topic terikat ke **tim** yang menandatangani build. Dengan L0, D7 memakai build iPhone Alief (tim Alief), sedangkan QA-E2E memakai build TestFlight (tim pemegang akun berbayar). B7 hanya menyiapkan satu `.p8` + `APNS_TEAM_ID`. Kalau timnya berbeda, push QA-E2E gagal (`InvalidProviderToken` / `TopicDisallowed`). Personal Team (gratis) juga tidak mendukung capability Push Notifications (pesan Xcode yang dikutip DTS di Apple Forums), jadi D7 butuh tim berbayar. | B7: "kunci `.p8` + `APNS_TEAM_ID` + `APNS_TOPIC` dari tim yang sama dengan build yang diuji; kalau D7 dan TestFlight beda tim, ganti ketiga secret di LANGKAH MANUAL fase 16 langkah 1". Ubah pertanyaan C3 menjadi keputusan konkret: tim mana untuk D7 dan untuk TestFlight. |
| R1 | RENDAH | `PROGRESS.md:10,35,41`, `PROMPT.md:93,96-97`, D-alief-31(f) | G0 tidak diperbarui oleh langkah 1 ("G1–G8"); baris G0 juga diletakkan setelah G6. Baris fase 00 (track "–", `[~]`, kolom PR kosong) tidak pernah dipindah ke `[r]`/`[x]` karena penyegaran hanya untuk baris `[r]` milik TRACK; G1 bisa dicek dengan `gh pr view docs/alief-plan`, tapi tidak tertulis. | Langkah 1: "G0–G8"; G0 dicek dari kolom Status TODO C3/C11/C13. Tambah aturan untuk baris 00 (Alief mengisi nomor PR saat membuka PR plan; langkah 1 menyegarkannya juga) dan pindahkan baris G0 ke atas. |
| R2 | RENDAH | `PROMPT.md:39,110-112`, `README.md:82`, `fase-13-api-repository.md:7` vs `PROGRESS.md:40` (G6 = merged + D8) | Gerbang track c hanya mengecek PR MERGED, sedangkan G6 juga mensyaratkan D8. Fase 13–15 memakai backend lokal, jadi tidak memblokir, tetapi dua definisi "track be selesai" berbeda. | Tulis di PROMPT langkah 1: "track c butuh PR merged; D8 baru wajib untuk fase 16 (Prasyarat fase 16)". |
| R3 | RENDAH | `fase-12-be-retensi-hardening.md:43` (DoD), `ref/R2-skema-db.md:104-107`, `TODO.md:44` (B9) | Bukti "satu run cloud tercatat di `ops_heartbeat`" tidak membedakan cron dari `/healthz/db` (monitor B9 memanggil `/healthz/db` setiap hari dan juga menulis `ops_heartbeat`). Cron pertama juga baru jalan 03:00 WITA. | Tambah kolom `source text` (`cron`/`healthz`) di `ops_heartbeat`, atau pakai bukti dashboard Worker "Cron Events"/`wrangler tail` + log jumlah baris terhapus. |
| R4 | RENDAH | `ARCHITECTURE.md:74` (§4 butir 4) vs D-alief-25, `ref/R4-state-machine.md:60` | "`not_safe` → domain masuk `GET /blocklist`" masih teks lama; sekarang hanya masuk antrean dan muncul setelah review manual. | Samakan dengan R4 §4. |
| R5 | RENDAH | `SECURITY.md:38` (T15) | Baris T15 hanya punya 4 sel di tabel 5 kolom: mitigasi berada di kolom "Dampak", fase di kolom "Mitigasi", kolom "Fase / test" kosong. | Isi Dampak ("membuka Detail milik orang lain / memicu aksi") lalu geser sel. |
| R6 | RENDAH | `fase-15-push-validasi.md:46` | Contoh deep link `shoo://scan/scan_01`: tidak ada scan dengan id itu di fixture atau seed (`blocked-92.json` memakai UUID `6f1c2a4e-…-0a1b2c3d4e03`), jadi perintah Verifikasi menguji jalur 404, bukan Detail. | Pakai id scan dari seed lokal (mis. id `blocked-92.json`) atau id dari `POST /scans` di langkah 4. |
| R7 | RENDAH | `log/fase-00.md:22` ("fase-00 langkah 4"), `fase-00-plan-tooling.md:32` | Rujukan langkah sudah bergeser (worktree sekarang langkah 5), dan langkah 5 belum membuat worktree `../Final-CH7-spike` (README §4). | Perbaiki rujukan; tambah worktree spike. |
| R8 | RENDAH | `fase-02-onboarding.md:34` | Ilustrasi hanya "Settings › Apps › Safari › Extensions". App mendukung iOS 17, yang (sebelum menu "Apps" di iOS 18) memakai Settings › Safari › Extensions (BELUM DIVERIFIKASI dari docs; halaman Apple Support tidak terbaca). | Catat dua jalur per versi iOS di ilustrasi, dan biarkan S2 memastikan dengan screenshot per versi. |
| R9 | RENDAH | `ref/R2-skema-db.md:156-169` | `clock_timestamp()` memberi waktu eksekusi, bukan waktu commit (docs Postgres). Kalau reviewer membungkus beberapa `update` dalam satu transaksi yang lama, entri yang di-commit belakangan bisa punya `approved_at` lebih kecil dari `nextSince` yang sudah diambil detector, lalu terlewat di refresh inkremental. | Tulis di prosedur: jalankan setiap `update` sebagai statement autocommit terpisah (tanpa `begin`), atau tetap sarankan full refresh harian (sudah ada untuk `removed`). |
| R10 | RENDAH | `README.md:19` vs `PROMPT.md:104-107`, D-alief-31(c) | README §1 masih menulis bahwa fase `[m]` dilanjutkan dengan "(review, verifikasi, PR)", tanpa menyebut sisa Langkah kerja. | Samakan dengan PROMPT langkah 1 pilihan 1. |

Jumlah: **KRITIS 0 · TINGGI 3 · SEDANG 4 · RENDAH 10**.

## 4. Kontradiksi antar-dokumen

- **`fase-01S:7,32`, `README.md:97`, `TODO.md:41,52`, D-alief-29 (`ios/Local.xcconfig`, edit lokal `project.yml`/`AppGroup.id`) ↔ `origin/main:docs/mandates/alief.md` + `ios/CLAUDE.md` + `ios/Config/Local.xcconfig.example` (`ios/Config/Local.xcconfig`, `project.yml` tidak diubah, App Group tidak di-hardcode):** (#T1).
- **`ref/R3:93` (`apns-topic: com.shoo.app`), `fase-13:47-48`, `fase-15:26,45` ↔ `origin/main:ios/project.yml` (`PRODUCT_BUNDLE_IDENTIFIER: $(SHOO_BUNDLE_ID)`, App Group `$(SHOO_APP_GROUP)`):** (#T1).
- **`fase-01S:38` ("`SFSafariExtensionManager` hanya macOS") ↔ docs Apple (`SFSafariExtensionManager`, `SFSafariSettings.openExtensionsSettings` di iOS 26.2):** (#T2). Klaim yang sama ada di `docs/spikes/extension-status.md` milik Umar.
- **`fase-02:35` (`openSettingsURLString` = "membuka Settings") ↔ PRD ON-04 ("Tombol Turn on membuka pengaturan extension Safari") ↔ docs Apple (`openSettingsURLString` = "your app's custom settings"):** (#T2).
- **`PROMPT.md:101-103` (pilihan 0, status tetap `[r]`, kembali ke langkah 1) ↔ semantik `reviewDecision` GitHub (tetap `CHANGES_REQUESTED` sampai review ulang):** (#T3).
- **`fase-01S:34` (uji iPhone → `[m]`) ↔ `PROMPT.md:164-166` (iPhone fisik → jangan `[m]`) + `PROMPT.md:70` (PROMPT menang):** (#S1).
- **`fase-01S:43` (PR dibuka di langkah 5) ↔ `PROMPT.md:198-204` (PR di langkah 10–11):** (#S2).
- **`README.md:95` (spike memakai `D-alief-A…`) ↔ `PROMPT.md:157-158` (prefix per track supaya worktree paralel tidak bentrok):** (#S2).
- **`TODO.md:42` (satu `.p8`/Team ID) ↔ build D7 dan TestFlight yang bisa ditandatangani tim berbeda (L0):** (#S4).
- **`PROGRESS.md:40` (G6 = merged + D8) ↔ `PROMPT.md:110-112`, `fase-13:7` (track c = PR merged):** (#R2).
- **`ARCHITECTURE.md:74` (`not_safe` → `/blocklist`) ↔ D-alief-25, `ref/R4:60` (antrean + review):** (#R4).
- **`log/fase-00.md:22` ("langkah 4") ↔ `fase-00:32` (worktree di langkah 5):** (#R7).
- **`README.md:19` ↔ `PROMPT.md:104-107` (resume `[m]`):** (#R10).
- **`contracts/api.md` Blocklist ("all domains with a `not_safe` verdict from any family") ↔ D-alief-25:** deviasi makna yang sudah diusulkan ke Umar + Imelda (C6). Bukan temuan baru; PR fase 10 wajib memuat "Contract proposals".
- **PRD §5 Validasi ("masuk whitelist keluarga") ↔ D-alief-09 (per pemilik):** deviasi tercatat sejak run 01, masih menunggu konfirmasi Umar.

## 5. Lima risiko terbesar untuk MVP + mitigasi

1. **Push tidak pernah terbukti di perangkat** (#T1, #S4): topic `com.shoo.app` tidak cocok dengan bundle ID per developer, kunci APNs dari tim yang salah, Personal Team tanpa Push. GD-06 (P0) dan definisi selesai butir 2 tertahan. Mitigasi: `APNS_TOPIC` + `APNS_TEAM_ID` per build, putuskan tim berbayar untuk D7 dan TestFlight sekarang, uji lokal relay dengan token dummy tetap jalan.
2. **ON-04 tidak memakai API iOS 26.2** (#T2): orang tua harus menavigasi Settings sendiri, padahal ada link langsung ke halaman extension; spike S1/S2 bisa menyimpulkan "tidak ada API". Mitigasi: uji kedua API di 01S, `#available(iOS 26.2, *)` di fase 02, minta izin Umar untuk sumber status kedua.
3. **Mode auto macet di review** (#T3): satu "Request changes" dari Umar membuat track berputar di fase yang sama; tanpa proteksi branch, review tidak terdeteksi sama sekali. Mitigasi: syarat pilihan 0 berbasis review/komentar yang lebih baru dari commit terakhir + catatan "ditangani @sha", aktifkan proteksi branch.
4. **Track spike tidak terkompilasi atau hasilnya tidak sampai ke ON-04** (#S1, #S2): branch dari `main` tanpa fase 01, konflik aturan `[m]`, refine ON-04 tanpa pemilik. Mitigasi: spike ditumpuk di atas fase 01 atau menunggu merge, `[m]` eksplisit untuk 01S, refine menjadi handoff yang dibaca fase app.
5. **`main` terus bergerak lebih cepat dari plan** (T1 run 03, T1 run 04): Umar menyelesaikan L0 dan mengubah mandat 21 menit sebelum commit perbaikan. Mitigasi: sebelum setiap commit plan dan setiap run verifikasi jalankan `git fetch origin && git log HEAD..origin/main --oneline -- docs ios contracts CLAUDE.md`; PROMPT langkah 3a sudah fetch, tambahkan "baca diff mandat/`ios/CLAUDE.md` sejak run terakhir".

## 6. Pertanyaan yang harus dijawab sebelum fase 01 dan 07

1. **Alief:** merge `495c792` dan ganti semua `com.shoo.app` / `group.com.shoo.app` literal dengan nilai dari build (`APNS_TOPIC`, bundle ID dari build settings) (#T1)?
2. **Alief/Umar:** tim Apple berbayar mana yang dipakai untuk D7 (iPhone Alief) dan untuk TestFlight? Apakah satu tim yang sama, supaya `.p8` dan topic cukup satu set (#S4)?
3. **Umar:** boleh app memakai `SFSafariExtensionManager.getStateOfExtension` (iOS 26.2+) di samping heartbeat, mengingat `ios/ShooApp/CLAUDE.md` "Do not invent another way" (#T2)? `SFSafariSettings.openExtensionsSettings` untuk tombol Turn on disetujui?
4. **Umar:** mau mengaktifkan proteksi branch `main` (review wajib + CODEOWNERS)? Tanpa itu `reviewDecision` tidak bisa dipakai sebagai sinyal (#T3).
5. **Alief:** spike 01S menunggu PR fase 01 merged, atau ditumpuk di atas `feat/APP-foundation` (#S2)?
6. **Umar (C3 butir 4):** `UIBackgroundModes: [audio]` untuk PiP ON-04 kapan? (Plus kategori audio session `.playback` di sisi app, #S3.)
7. **Umar (C6, C11, C12, C13, C16):** masih terbuka dari run 03 (review manual blocklist, `extensionLastSeenAt`, `GET /devices/me`, `owner=family`, `shoo://scan/<id>` di `contracts/`).
8. **Alief:** iOS berapa di iPhone uji Alief dan orang tua? Menentukan apakah jalur iOS 26.2 atau fallback yang diuji di 01S dan QA-E2E #17.

---

## I. Cek dokumentasi resmi

| # | Klaim di plan | Status | Sumber / koreksi |
|---|---|---|---|
| I1 | `UIApplication.openSettingsURLString` membuka Settings untuk ON-04 (`fase-02:35`, `fase-01S:25,39`) | **VERIFIED sebagian** | https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring — "deep link to your app's custom settings in the Settings app … display your app's custom settings, if it has any". Mendarat di halaman app sendiri, bukan Safari › Extensions → #T2 |
| I2 | "`SFSafariExtensionManager` hanya macOS", tidak ada API status/link langsung di iOS (`fase-01S:38,40`, C14) | **WRONG** | https://developer.apple.com/documentation/safariservices/sfsafariextensionmanager — platform iOS 26.2+, "In iOS and visionOS, use this class to find out the current state of a Safari web extension"; `getStateOfExtension(withIdentifier:completionHandler:)` iOS 26.2. https://developer.apple.com/documentation/safariservices/sfsafarisettings/openextensionssettings(foridentifiers:completionhandler:) — iOS 26.2, "If the value is a single identifier, Settings opens to that extension's detail view", error kalau app tidak di foreground. `getStateOfSafariExtension(withIdentifier:)` dan `SFSafariApplication.showPreferencesForExtension` tetap macOS saja → #T2 |
| I3 | PiP: `allowsPictureInPicturePlayback`, `canStartPictureInPictureAutomaticallyFromInline`, butuh `UIBackgroundModes: [audio]` (`fase-02:37`, C3 butir 4) | **VERIFIED sebagian** | https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-standard-player — PiP aktif "after you configure your audio session and set the project capabilities"; otomatis kalau "playing in full-screen mode and the user exits the app". https://developer.apple.com/documentation/avkit/avplayerviewcontroller/canstartpictureinpictureautomaticallyfrominline — iOS 14.2, berlaku saat konten "inline". Audio session `.playback` tidak ada di plan → #S3 |
| I4 | App Groups mungkin butuh akun berbayar (`fase-01S:32,69`) | **NOT YET VERIFIED** (plan sudah jujur menandainya) | https://developer.apple.com/help/account/reference/supported-capabilities-ios — sel tabel tidak terbaca otomatis. Apple Forums (https://developer.apple.com/forums/thread/834802): App Group terikat satu tim, Personal Team terisolasi. Mandat Umar juga mencatat "akun gratis / Personal Team kemungkinan tidak bisa" |
| I5 | Push butuh akun berbayar (implisit di C3/B7) | **VERIFIED sebagian** | Pesan Xcode "Personal development teams do not support the Push Notifications and iCloud capabilities" dikutip di Apple Forums (hasil pencarian, thread https://developer.apple.com/forums/thread/746373) → #S4 |
| I6 | XcodeGen: `configFiles` + override xcconfig per developer (L0, `main`) | **VERIFIED sebagian** | https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md — `configFiles` "`.xcconfig` files per config" (project dan target); spec tidak menulis urutan xcconfig vs `settings` (komentar Umar di `project.yml`: project settings menimpa file). `bundleIdPrefix` mengisi bundle id target yang tidak punya `PRODUCT_BUNDLE_IDENTIFIER` → target test fase 01 mendapat `com.shoo.ShooAppTests` tanpa kunci tambahan (D-alief-24 tetap cukup) |
| I7 | `GENERATE_INFOPLIST_FILE: YES` untuk target test (D-alief-28) | **VERIFIED sebagian** (run 03, tidak berubah) | Sama dengan run 03 I20; bukti akhir = `xcodebuild test` fase 01 |
| I8 | Postgres `clock_timestamp()` berbeda per statement, `now()` tetap per transaksi (R2 §5) | **VERIFIED** | https://www.postgresql.org/docs/current/functions-datetime.html — "`clock_timestamp()` returns the actual current time, and therefore its value changes even within a single SQL statement … `now()` is a traditional PostgreSQL equivalent to `transaction_timestamp()`". Catatan waktu commit → #R9 |
| I9 | APNs `410 Unregistered` + `410 ExpiredToken` → kosongkan token; `400 BadDeviceToken` (juga environment salah) → simpan (R3 §6, fase 11) | **VERIFIED** | https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns — `410 ExpiredToken` "The device token has expired", `410 Unregistered` "inactive for the specified topic", `400 BadDeviceToken` "Verify … that the token matches the environment". Juga `400 DeviceTokenNotForTopic` "The device token doesn't match the specified topic" dan `400 TopicDisallowed` → #T1, #S4 |
| I10 | `gh pr view <no> --json state,reviewDecision`; `CHANGES_REQUESTED` sebagai pemicu (PROMPT langkah 1) | **VERIFIED sebagian** | `gh pr view --help` lokal: `--json`, `--comments`, field `reviews`, `comments`, `commits` tersedia. https://docs.github.com/en/graphql/reference/pulls — `reviewDecision` "The current status of this pull request with respect to code review", enum APPROVED / CHANGES_REQUESTED / REVIEW_REQUIRED. Bahwa nilainya kosong tanpa aturan review branch: **NOT YET VERIFIED** dari docs; `main` sekarang tidak diproteksi (`gh api …/branches/main` → `"protected": false`) → #T3 |
| I11 | Diff tiga titik `origin/main...HEAD` = perubahan branch sejak merge-base (D-alief-33) | **VERIFIED** | https://git-scm.com/docs/git-diff — "`git diff A...B` is equivalent to `git diff $(git merge-base A B) B`"; bentuk `git diff <commit> -- <path>` membandingkan working tree dengan commit (alasan S5 run 03 benar). Uji: `git diff --stat origin/main...HEAD -- . ':!plan/alief'` kosong di `1aa9d87` |
| I12 | `xcrun simctl openurl/push/get_app_container <UDID> …` (fase 13–15) | **VERIFIED** | `xcrun simctl help openurl|push|get_app_container` lokal: argumen pertama `<device>` (UDID atau `booted`); `push` boleh tanpa bundle id kalau payload memuat `Simulator Target Bundle`; `get_app_container … <group identifier>` didukung. Bundle id/group harus mengikuti L0 → #T1 |
| I13 | Hyperdrive `--caching-disabled` (B4, D-alief-17) | **VERIFIED** (run 02/03, tidak dibaca ulang) | https://developers.cloudflare.com/hyperdrive/concepts/query-caching/ |
| I14 | Hyperdrive lokal: `localConnectionString`, env `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_<BINDING>` menang; `id` placeholder sebelum Hyperdrive cloud (fase 07) | **VERIFIED**; `id` placeholder **NOT YET VERIFIED** | https://developers.cloudflare.com/hyperdrive/configuration/local-development/ — env var format `…_<BINDING_NAME>` dan "the environment variable takes precedence"; pooling dan caching tidak berlaku lokal; halaman tidak menyatakan `id` wajib/opsional untuk `wrangler dev` lokal (plan sudah menandai BELUM DIVERIFIKASI + fallback) |
| I15 | postgres.js ≥ 3.4.5, `nodejs_compat`, `max: 5`, `fetch_types: false`, jangan `prepare: false` (R1, fase 07) | **VERIFIED** | https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-drivers-and-libraries/postgres-js/ — "minimum version … is `3.4.5`", `nodejs_compat` "required for database drivers", `max: 5`, `fetch_types: false` kalau tidak ada tipe array, peringatan terhadap `prepare: false` |
| I16 | Workers Free: CPU 10 ms per request dan per Cron, 50 subrequest, 5 Cron/akun (ARCHITECTURE §3, R2 §6) | **VERIFIED** | https://developers.cloudflare.com/workers/platform/limits/ — juga 6 koneksi keluar simultan |
| I17 | Supabase CLI: `functions serve --no-verify-jwt --env-file`, `secrets set --env-file`, `start -x studio,imgproxy,edge-runtime,logflare,vector` | **VERIFIED** | CLI lokal 2.114.0 `--help` memuat ketiga flag; daftar `--exclude` memuat nama yang dipakai. Docs: https://supabase.com/docs/reference/cli/supabase-functions-serve, https://supabase.com/docs/reference/cli/supabase-secrets-set |
| I18 | Supabase Storage REST (upload/sign/hapus `prefixes`), Edge Function `verify_jwt` di `config.toml`, kuota Free + pause 7 hari | **VERIFIED** / **VERIFIED sebagian** (run 03, tidak dibaca ulang) | Run 03 I13, I15, I16 |
| I19 | HTTP/2 dari Worker `fetch()` / Edge Function Deno ke APNs | **NOT YET VERIFIED** (tidak berubah) | Plan tetap memakai spike cloud fase 07 + uji relay lokal fase 11 |
| I20 | `.environment(\.locale)` + String Catalog; WhatsApp tidak membuat `shoo://` bisa diklik | **NOT YET VERIFIED** (tidak berubah) | Diuji di fase 01 langkah 5 dan QA-E2E #4 |
| I21 | Jalur Settings iOS 17 vs 18 untuk ilustrasi ON-04 | **NOT YET VERIFIED** | https://support.apple.com/guide/iphone/get-extensions-iphab0432bf6/ios tidak terbaca otomatis → #R8 |

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
| `scan(id:)` | `GET /scans/{id}` | 09 §3 | OK; juga target push (15) dan `shoo://scan/<id>` (15) |
| `setVerdict(scanId:value:)` | `POST /verdicts` | 10 §1 | OK |
| — | `GET /devices/me` (usulan C12) | — | Celah tercatat (D-alief-21) |

Endpoint tim lain: `POST /scans` (extension, 09), `GET /verdicts?domain=` (extension, 10), `GET /blocklist` (detector, 07 + 10), `GET /join` (browser, 08), `/healthz`, `/healthz/db` (B9). **Semua 10 operasi protocol terpetakan ke endpoint dan fase.** Pintu masuk app: push (`NotificationRouter`, 15), `shoo://join` (14), `shoo://scan/<id>` (15, sekarang ada).

### J2. Key App Group: penulis dan pembaca

| Key | Penulis | Pembaca | Status |
|---|---|---|---|
| `device.id`, `device.token`, `device.mode` | App fase 13 `SessionStore` | Extension `getSession` (`SafariWebExtensionHandler.swift`) | OK |
| `device.name` | App fase 13 + tulis ulang setelah `updateMe(name:)` | Extension `getSession` | OK |
| `guardian.name` | App fase 14 (join), dihapus saat `leaveGuardian()`/404 | Extension `getSession` | OK; pemutusan dari sisi Guardian tidak terdeteksi (D-alief-21) |
| `api.baseURL` | App fase 13 (`AppConfig`) | Extension `getSession` | OK |
| `ai.baseURL` | App fase 13, `TODO(sync:imelda)` | Extension `getSession` | Bergantung Imelda |
| `extension.lastSeenAt` | Extension: `content.js` (setiap halaman) → `background.js` (throttle 60 s) → `SafariWebExtensionHandler` | App `ExtensionStatus` (01; dipakai 01S, 02 ON-04, 04, 05, 06) | OK |

Kedelapan key di `ios/ShooShared/AppGroup.swift` = delapan baris `contracts/app-group-keys.md`. **Setiap key punya penulis dan pembaca.** Yang berubah di `main`: **nama suite** App Group sekarang per developer (`AppGroup.id` dari Info.plist `ShooAppGroup`). Kode app aman selama memakai `AppGroup.defaults`, tetapi perintah cek fase 13 (`…group.com.shoo.app.plist`) dan ARCHITECTURE masih memakai nama tetap → #T1.

### J3. Env R3 §7 → LANGKAH MANUAL

| Variabel | Diset di | Status |
|---|---|---|
| `DB` (Hyperdrive) | fase 07 LANGKAH MANUAL 3 (B4, `--caching-disabled`); placeholder lokal | OK (placeholder BELUM DIVERIFIKASI, I14) |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | fase 09 DoD "LANGKAH MANUAL deploy fase 09 + secret" (B5); lokal `.dev.vars` | OK |
| `INVITE_BASE_URL` | fase 07 LANGKAH MANUAL 4 (`vars`); lokal `.dev.vars`/`miniflare.bindings` | OK |
| `APNS_ENV` | fase 11 LANGKAH MANUAL 8; fase 16 langkah 1 (`production`) | OK |
| `PUSH_RELAY_URL`, `PUSH_RELAY_SECRET` | fase 11 LANGKAH MANUAL 8 | OK |
| `APNS_KEY_P8_B64`, `APNS_KEY_ID`, `APNS_TEAM_ID` | fase 11 LANGKAH MANUAL 8 (env-file di luar repo, lalu `rm`) | OK, tetapi tidak ada langkah ganti tim untuk TestFlight → #S4 |
| `SCREENSHOT_MAX_BYTES` | `vars` `wrangler.jsonc` | OK |
| `APNS_SPIKE`, `SPIKE_KEY` | fase 07 LANGKAH MANUAL 4/6 → dihapus fase 11 | OK |
| Secret CI (5) | C2 ke Umar (fase 12) | OK |
| **`APNS_TOPIC` (belum ada)** | — | **Hilang**: topic di-hardcode `com.shoo.app` (R3 §6) → #T1 |

### J4. Gate PROGRESS bisa dicapai dan diperbarui langkah 1?

| Gate | Cara tercapai | Diperbarui langkah 1? |
|---|---|---|
| G0 | Jawaban Umar di TODO C3/C11/C13 | **Tidak** (langkah 1 hanya G1–G8) → #R1 |
| G1 | Merge PR `docs/alief-plan` | Ya (`gh pr view`), tetapi baris fase 00 tidak punya nomor PR / aturan status → #R1 |
| G2 | Merge `chore/APP-test-targets` | Ya |
| G3 | Fase 07 LANGKAH MANUAL tercentang | Ya ("checklist LANGKAH MANUAL tercentang") |
| G4 | Fase 10 uji cloud tercentang | Ya |
| G5 | Semua PR 01–06Q merged | Ya |
| G6 | Semua PR 07–12 merged + D8 | Ya (D8 `[x]`); gerbang track c tidak mengecek D8 → #R2 |
| G7 | B6–B8 | Ya; B6 sudah terpenuhi L0 (path di TODO salah, #T1); B7 per tim → #S4 |
| G8 | Laporan QA-E2E LULUS | Ya |

### J5. Transisi status (PROMPT langkah 1, D-alief-31)

| Status | Masuk | Keluar | Status |
|---|---|---|---|
| `[ ]` | awal | `[~]` (langkah 4) | OK |
| `[~]` | langkah 4 | `[m]` (6h), `[r]` (langkah 10), `[!]` (13b) | OK |
| `[m]` | 6h | langkah 1 pilihan 1 → sisa Langkah kerja → 7–11 → `[r]` | OK; untuk 01S bertentangan dengan 6h → #S1 |
| `[r]` | langkah 10 | `[x]` (MERGED), `[!]` (CLOSED), mode REVIEW (`CHANGES_REQUESTED`) | Ada, tetapi mode REVIEW tidak punya keluar → #T3 |
| `[x]` | langkah 1 | final | OK |
| `[!]` | agent (blocker P0 / PR ditutup) atau manual (fase 17) | Alief → `[ ]`/`[~]` | OK |

### J6. Track spike 01S: konsistensi antar-file

| Aspek | PROMPT | README | PROGRESS | R6 | TODO | fase-01S | Status |
|---|---|---|---|---|---|---|---|
| Track + urutan | `:17,40,48,77` (setelah 01, tidak jadi syarat track lain) | `:17,63,95,107` | `:12` | `:34` | B6, C14, D5 | `:5-10` | Konsisten |
| Folder yang boleh diubah | `:77` | `:95,97` (pengecualian 4) | — | — | — | `:26,32` | Konsisten (D-alief-29) |
| Signing | `:172-174` ("sebelum L0") | `:97` (`ios/Local.xcconfig`) | — | — | B6/C3 (`ios/Local.xcconfig`) | `:7,32` | Usang terhadap `495c792` → #T1 |
| Status di uji perangkat | `:164-166` (jangan `[m]`) | `:17` ("berhenti di uji perangkat") | — | — | — | `:34` (`[m]`) | Bertentangan → #S1 |
| Branch dasar + PR | `:109,123-124` | — | `:12` (dua branch, satu kolom PR) | — | — | `:43-44` | Tidak tersambung → #S2 |
| Prefix keputusan | `:157-158` (app/be/c) | `:95` (`D-alief-A…`) | — | — | — | `:42` (`D-alief-A…`) | Bentrok dengan track app → #S2 |
| Klaim API iOS | — | — | — | — | C14 "tanpa link langsung publik" | `:38,40` | WRONG → #T2 |

### J7. Urutan onboarding

| Sumber | Guardian | Protected | Status |
|---|---|---|---|
| PRD §8.1–8.2 | ON-05 "Diminta setelah ON-04" | PR-02 "Lanjut ke ON-04" | Acuan |
| `fase-02-onboarding.md:26,39-40` | ON-03 → ON-04 → ON-05 | ON-03 → Connect (placeholder) → ON-04 → ON-05 | Konsisten |
| `fase-14-pairing.md:26` | — | ProtectedByView → ON-04 → ON-05 → Home | Konsisten |
| `ref/R7-protokol-qa.md:67` (#17) | Guardian + Protected, lanjut ke ON-05 | sama | Konsisten |

### J8. Mandat `origin/main:docs/mandates/alief.md` → fase

| Checkbox mandat | Fase |
|---|---|
| S1, S2 | 01S |
| Fondasi | 01 |
| ON-01, ON-02, ON-03, ON-04, ON-05 | 02 (ON-04 + hasil 01S) |
| DT-01 s.d. DT-06 | 03 |
| PR-04, PR-05 | 04 |
| GD-01, GD-02, GD-03, GD-05 | 05 |
| PF-01 | 06 |
| Devices · Family · Scans · Verdicts · Blocklist · Push · Retensi · Keamanan | 07 · 08 · 09 · 10 · 07+10 · 11 · 12 · 08/09/10/12 (dicentang di 12) |
| `ApiRepository` · key App Group | 13 · 13 |
| GD-04 · PR-01/PR-02 · PR-03 | 14 · 14 · 14 |
| GD-06 · GD-07 | 15 · 15 |
| Ditahan: Live Activity push | 17 |

**Semua checkbox terpetakan ke tepat satu fase, tidak ada yang dobel.** Satu-satunya teks mandat yang tidak diikuti adalah cara signing di bagian Spike (#T1).

### J9. Perintah Verifikasi dari root repo

| Fase | Hasil |
|---|---|
| 00 | `ls …` OK; grep `TODO(sync` kosong; `git diff --stat origin/main...HEAD -- . ':!plan/alief'` kosong (diuji) |
| 01, 01S, 02–06, 06Q | `source plan/alief/ref/sim.sh` (bash + zsh → `SIM=iPhone 17 Pro`, `bash -n` lulus); `xcodebuild -project ios/Shoo.xcodeproj` benar dari root; 01S `git diff --name-only origin/main...HEAD -- ios/project.yml ios/ShooShared ios/ShooExtension` kosong di branch ini (diuji). 01S `-only-testing:ShooAppTests/ExtensionStatusTests` gagal kalau branch spike tidak memuat fase 01 (#S2) |
| 07, 12 | Subshell `(pnpm -C backend/api dev …&)` + `pnpm -C backend/api exec wait-on tcp:8787` + `pkill`; `wrangler dev --test-scheduled` + `/cdn-cgi/local/scheduled` (run 03 I9) |
| 08–11 | `(cd backend/db && supabase start && …)`, `pnpm -C backend/api exec vitest run <pola>`, `deno test --allow-env` benar |
| 13 | `get_app_container booted com.shoo.app group.com.shoo.app` + `group.com.shoo.app.plist` gagal kalau `ios/Config/Local.xcconfig` ada (#T1) |
| 14 | `simctl openurl "${PROT_UDID:-booted}" …` valid; `git diff --stat origin/main...HEAD -- …Info.plist …entitlements` benar |
| 15 | `simctl push … com.shoo.app …` gagal dengan bundle ID per developer (#T1); `openurl … shoo://scan/scan_01` menguji id yang tidak ada (#R6) |
| 16 | gabungan perintah di atas; benar dari root |

---

## Catatan untuk run berikutnya

- Fokus ulang: #T1 (merge `495c792`, `APNS_TOPIC`, bundle ID/App Group dari build), #T2 (API iOS 26.2 di 01S + fase 02), #T3 (syarat keluar mode REVIEW), lalu #S1–#S4.
- Sebelum menulis perbaikan, jalankan `git fetch origin && git log --oneline HEAD..origin/main` dan baca setiap commit yang menyentuh `docs/`, `ios/`, `contracts/`, `CLAUDE.md`. Dua run berturut-turut gagal karena `main` maju di menit-menit terakhir.
- Uji kering mode auto dengan PROGRESS contoh: 02 `[r]` + review `CHANGES_REQUESTED` yang sudah ditangani (harus dilewati sampai ada review baru), 01S `[m]` dengan checklist belum dicentang, 07 `[m]` tercentang, 12 `[r]` "pending", G6 belum D8.
- Yang tetap tidak bisa diverifikasi dari docs: HTTP/2 Worker/Edge Function → APNs, `id` Hyperdrive placeholder untuk lokal, App Groups di Personal Team, `reviewDecision` tanpa proteksi branch, locale environment + String Catalog, link WhatsApp, jalur Settings per versi iOS, build target test (butuh `xcodegen` + build), wireframe PRD §7 (gambar).
