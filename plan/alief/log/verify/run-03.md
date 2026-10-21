# Verifikasi plan Alief — run 03

- **Tanggal:** 21 Okt 2026 (WITA)
- **Reviewer:** Claude Opus 5.5, sesi independen, read-only (satu-satunya file yang dibuat: file ini)
- **Branch/commit yang dibaca:** `docs/alief-plan` @ `1caf46c` (perbaikan run 02; diff `60de56b..1caf46c` juga dibaca)
- **Prompt:** `plan/alief/VERIFY_PROMPT.md` (cek A–H, format 1–6) + tambahan I (dokumentasi resmi), J (wiring), dan §2a (status temuan run 02)
- **Bacaan:** semua file di daftar `<bacaan>` dibaca lengkap: CLAUDE.md (root, ios, ios/ShooApp, backend), CODEOWNERS, `.github/pull_request_template.md`, docs/README, mandat Alief, 3 spike, seluruh `contracts/` + fixtures, `ios/ShooShared/*.swift`, `ios/project.yml`, `ios/ShooApp/*.swift` (+ Info.plist, entitlements), semua file `plan/alief/` termasuk `ref/sim.sh`, `log/DECISIONS.md`, `log/fase-00.md`, `log/verify/run-01.md`, `log/verify/run-02.md`.
- **PRD v1.5:** berhasil dibaca dari Google Drive (`Shoo-PRD-v1.5.docx`, id `1n_1vngw5fFizP9YHWg0kT3VnqGhgXlbV`). Gambar wireframe §6–§7 tidak ikut terbaca (hanya teks), jadi perbandingan wireframe tidak bisa diverifikasi.
- **Laporan QA Catalyst:** dibaca dari Drive (`QA_Catalyst_DeepSeek_26Sep2026.docx`, id `1ZHVIvha4RxRS1Bgp1dK20VUIByez9mwT`) untuk cek H.
- **Penting — `origin/main` sudah maju:** `origin/main` @ `981ad73` ("Add lead mandate; move ON-04 spikes to Alief", Umar, 21 Okt 2026 15:54 WITA) belum ada di branch ini (merge-base `8930fd0`). Commit itu mengubah `docs/mandates/alief.md`, menambah `docs/mandates/umar.md`, `docs/mandates/README.md`, `docs/spikes/README.md`, `CLAUDE.md`, `.claude/commands/mandate.md`. Isinya dibaca read-only (`git show`, `git diff HEAD origin/main`) karena plan ini akan dieksekusi di worktree dari `origin/main` (PROMPT langkah 3b). Dampaknya → #T1, #S5.
- **Perintah read-only yang dijalankan:** `bash -n` + `source plan/alief/ref/sim.sh` (bash dan zsh), grep Verifikasi fase 00, `git diff --stat origin/main -- . ':!plan/alief'`, `git log/show/diff` ke `origin/main`, `xcrun simctl help push|get_app_container`, `supabase --version` (2.114.0), `supabase start|functions serve|secrets set --help`, `command -v gitleaks jq supabase deno xcodegen pnpm`, grep sisa teks. Tidak ada build, `supabase start`, atau deploy.

---

## 1. Ringkasan pemahaman

1. Shoo = Safari Web Extension iPhone + app SwiftUI. Skor 0–100 per halaman: 30–79 Warning (popup, push ke Guardian), ≥ 80 Blocked (layar blokir tanpa bypass). Skor/sinyal milik Imelda, extension + layar blokir + kontrak milik Umar, app + backend milik Alief.
2. Dua mode permanen tanpa login: **Guardian** (melindungi diri + Family mode ≤ 3 orang) dan **Protected** (orang tua; tidak pernah melihat tombol validasi).
3. App iOS 17 (`@Observable`, String Catalog EN/ID) memakai protocol `ShooRepository`: `MockRepository` (fixtures) di fase 01–06, `ApiRepository` di fase 13 tanpa mengubah view.
4. Backend = Worker Cloudflare `shoo-api` (Hono + zod + postgres.js `fetch_types: false`) → Hyperdrive `--caching-disabled` → Supabase Postgres (role `shoo_api`, PostgREST tidak dipakai) + Storage private (signed URL 1 jam).
5. Push: jalur utama relay Worker → Edge Function Supabase `push` (Deno, `x-push-secret`, `verify_jwt = false`) → APNs HTTP/2 JWT ES256. Push langsung dari Worker hanya kalau spike di Worker cloud lulus (D-alief-16).
6. Auth per device: token `shoo_` + 32 byte, hash SHA-256 di DB; app menulis `device.*`, `guardian.name`, `api.baseURL`, `ai.baseURL` ke App Group untuk extension.
7. Pairing: kode 4 digit 60 s multi-pakai, maks 3 Protected, 5 gagal/10 menit per device dan per IP; `inviteUrl` https `/join?code=` yang membuka `shoo://join?code=` (usulan C5).
8. Alur inti: Protected membuka situs → extension `POST /scans` (≥ 30, + screenshot) → Worker simpan + push (bahasa Guardian) → tap → Detail → It's safe → `POST /verdicts` (per pemilik+domain) → extension polling `GET /verdicts?domain=` 5 s → layar blokir terbuka (target ≤ 10 s).
9. **Baru di run 03:** Not safe atas scan Protected yang terhubung → hanya **antrean** `blocklist_entries` (kelayakan snapshot `global_eligible`); `GET /blocklist` hanya mengirim entri yang `approved_at`-nya diisi manual (SQL editor), `nextSince` = `approved_at` (D-alief-25).
10. Retensi 14 hari lewat Cron Worker harian (maks 10 batch); `ops_heartbeat` ditulis cron + `/healthz/db` supaya Supabase Free tidak pause.
11. Track **app** (01→06→06Q) dan **be** (07→12) paralel; track **c** (13→16) setelah semua PR 01–06Q dan 07–12 merged. Status `[ ] [~] [m] [r] [x] [!]`; `[m]` = berhenti di LANGKAH MANUAL, dilanjutkan dulu di mode auto (D-alief-26). Deploy cloud fase be dari branch fase (D-alief-27).
12. QA dua ronde format Catalyst (QA-A di 06Q, QA-E2E di 16) dengan fixbug "satu bug = satu test gagal = satu commit" dan blok Retest.

## 2. Verdict

**BELUM SIAP** — tidak ada KRITIS, dan semua TINGGI run 02 (N1, N2) sudah ditangani, tetapi ada dua TINGGI baru: (a) mandat Alief di `origin/main` (`981ad73`) sekarang memasukkan **ON-04 (P0) dan spike S1/S2** ke tugas Alief, sementara plan masih menahan ON-04 di fase 17 dan tidak punya fase untuk S1/S2; (b) **fase 12 melingkar**: deploy final "dari `main` setelah PR 07–11 di-merge" tidak memuat kode fase 12 sendiri (cron, hardening), padahal DoD fase 12 mewajibkan cron itu terdaftar dan berjalan di cloud sebelum PR fase 12 dibuka.

## 2a. Status temuan run 02

| run-02 # | Tingkat | Status | Bukti (file:baris di `1caf46c`) |
|---|---|---|---|
| N1 | TINGGI | **PARTIALLY** | Aturan pilih fase memakai `[~]`/`[m]` dulu (`PROMPT.md:20,84-95`, `PROGRESS.md:3,5`, `README.md:18`, D-alief-26 `log/DECISIONS.md:190-194`); "pending eksternal → `[r]`" di `PROMPT.md:149-151`. Tetapi dua file fase yang disebut run 02 masih menyuruh `[~]` untuk penantian eksternal: `fase-11-be-push.md:57` ("ATAU status `[~]` dengan alasan (B6/B7/C3 belum)") dan `fase-14-pairing.md:20` ("status `[~]` sampai C3") → #S1. Resume `[m]` juga melompati sisa Langkah kerja → #S2 |
| N2 | TINGGI | **FIXED** (catatan #S4) | Antrean + review manual: `ref/R2-skema-db.md:151-171`, `ref/R3-catatan-api.md:67`, `ref/R4-state-machine.md:60`, `SECURITY.md:28` (risiko sisa ditulis jujur), `fase-10-be-verdicts.md:23-25,37` (test "Guardian + Protected milik penyerang → menunggu review"), `TODO.md:55` (C6), D-alief-25 `DECISIONS.md:183-188`. Grant `shoo_api` untuk tabel baru terlupa → #S4 |
| N3 | SEDANG | **FIXED** | `fase-01-app-fondasi.md:25,38`, D-alief-28 `DECISIONS.md:202-206`, `TODO.md:50` (C1). Didukung docs sebagian (I20) |
| N4 | SEDANG | **FIXED** | `fase-11-be-push.md:35` (`[functions.push] verify_jwt = false` + `--no-verify-jwt` saat deploy), `:40` (serve `--no-verify-jwt`), `:29` (test relay 401 → `failed:401`) |
| N5 | SEDANG | **FIXED** | `ref/R7-protokol-qa.md:64-65` (15a/15b, rujuk D-alief-15/24 di "Batasan") |
| N6 | SEDANG | **FIXED** | `ref/R2-skema-db.md:153` (snapshot `global_eligible`), `:162-169` (`approved_at > since`), `fase-10-be-verdicts.md:37` (test verdict lama disetujui belakangan + disconnect setelah verdict) |
| N7 | RENDAH | **FIXED** (sisa kecil #R1) | `fase-06Q-qa-a.md:41`, `fase-12-be-retensi-hardening.md:45`, `fase-16-qa-e2e.md:42`, `PROMPT.md:88`. `PROMPT.md:88` hanya menyebut G5/G6 (dan G2), padahal D-alief-26 + `fase-16:42` menyebut G8 juga diperbarui di langkah 1 |
| N8 | RENDAH | **FIXED** | `fase-15-push-validasi.md:24` (registrasi gagal → log; `simctl push` tetap bisa) |
| N9 | RENDAH | **FIXED** | `ref/R5-konvensi.md:20` (`in ${sql(ids)}`, bukan `= any(${ids})`); didukung README postgres.js (I6) |
| N10 | RENDAH | **FIXED** | `ref/R3-catatan-api.md:95-111` (kolom "Di mana diset", `SPIKE_KEY`, nilai lokal dari `supabase status`). Sisa override lokal var → #R6 |
| N11 | RENDAH | **FIXED** (sisa teks #R2) | `supabase start` di `fase-08:40`, `fase-09:39`, `fase-10:33`, `fase-11:46`, `fase-12:33`; `pkill -f "wrangler dev"` di `fase-07:60`, `fase-12:37`, `fase-13:48`; `wait-on` devDependency `fase-07:26` + `pnpm -C backend/api exec wait-on` di `fase-07:57`, `fase-12:35`, `fase-13:45`. `ref/R5-konvensi.md:38` masih menulis `npx wait-on` |
| N12 | RENDAH | **FIXED** | `ref/R2-skema-db.md:175` ("R4 §5"), `ref/R3-catatan-api.md:25` + `ref/R4-state-machine.md:16` (503 `code_unavailable`), `PROMPT.md:62,144`, `README.md:47` (ID per track) |
| N13 | RENDAH | **FIXED** | `fase-07-be-fondasi.md:40` (kunci P-256 sekali pakai, `.p8` asli tidak dibutuhkan) |
| N14 | RENDAH | **FIXED** | `fase-11-be-push.md:35,41` (`APNS_KEY_P8_B64`, `--env-file` di luar repo, `rm`), `TODO.md:42` (B7), `ref/R3-catatan-api.md:108`. CLI lokal 2.114.0: `secrets set --env-file` ada |
| N15 | RENDAH | **FIXED** | `fase-12-be-retensi-hardening.md:43` (dashboard Settings → Triggers + `ops_heartbeat`), `fase-13-api-repository.md:47` (`get_app_container … group.com.shoo.app`, diuji dengan `simctl help`) |

Ringkas: **13 FIXED (3 dengan sisa kecil), 1 FIXED dengan catatan (N2), 1 PARTIALLY (N1), 0 REGRESSION**. Sisa `BLOCKLIST_MIN_FAMILIES` / `minFamilies`: tidak ada lagi di plan kecuali catatan penghapusan di D-alief-25 (grep bersih).

## 3. Tabel temuan

| # | Tingkat | File § bagian | Masalah | Usulan perbaikan |
|---|---|---|---|---|
| T1 | TINGGI | `fase-17-ditahan.md:1-20`, `PROGRESS.md:28,51`, `README.md:78,135` (§7 butir 1), `TODO.md:63` (C14), `:73` (D5), `fase-02-onboarding.md:8,32`, `fase-05-guardian-family.md:30`, `fase-14-pairing.md:26`, `ref/R7-protokol-qa.md:44` (matriks QA-A "kecuali 04") vs `origin/main:docs/mandates/alief.md` (`981ad73`) | **Plan tertinggal dari mandat terbaru.** Di `main`, Umar memindahkan spike ke Alief dan mencabut penahanan ON-04: tugas baru **S1** (deteksi extension On/Off di iPhone sendiri → isi `docs/spikes/extension-status.md` + usulan window Active), **S2** (buka pengaturan extension → isi `docs/spikes/open-extension-settings.md`, kode tes boleh di `ios/ShooApp/`), dan **ON-04 (P0) di Fase A**: "Mulai dengan fallback PRD §10, sempurnakan dari hasil S1 + S2". Bagian "Ditahan dulu" tinggal Live Activity push. Plan masih: ON-04 `[!]` di fase 17 yang "Jangan dikerjakan", placeholder `TODO(sync:umar)` di fase 02, MVP selesai tanpa ON-04 (C14), D5 menunggu spike Umar. Akibat: satu P0 (definisi sukses mandat butir 1: semua P0 8.1) tidak punya fase; S1/S2 tidak terjadwal, padahal hasil S1 dibutuhkan Umar untuk `extensionActiveWindow` dan U7/EX-01; `docs/spikes/*.md` ada di luar folder Team App (CODEOWNERS `*` = Umar) tanpa pengecualian tertulis seperti D-alief-20. Agent yang bekerja di worktree dari `origin/main` akan membaca dua instruksi yang bertentangan. | Rebase `docs/alief-plan` ke `origin/main`. Tambah fase spike S1/S2 di track app (minggu 1, butuh iPhone + signing L0 → LANGKAH MANUAL `[m]`), dan fase/butir ON-04 fallback (Settings umum + ilustrasi langkah + video PiP placeholder, cek `extension.lastSeenAt` saat foreground) di track app setelah 02 (atau di dalam 02). Entri `D-alief-29`: pengecualian folder untuk `docs/spikes/extension-status.md` + `open-extension-settings.md` (mandat mengizinkan). Hapus C14/D5, ubah README §7 butir 1, PROGRESS (ON-04 → fase baru), fase 02/05/14 (Turn on → layar ON-04), R7 matriks QA-A + QA-E2E (tambah ON-04). Fase 17 tinggal Live Activity push. |
| T2 | TINGGI | `fase-12-be-retensi-hardening.md:28` (langkah 7), `:43,45` (DoD), D-alief-27 `log/DECISIONS.md:198`, `PROGRESS.md:39` (G6), `PROMPT.md:145-151` (6h) | **Fase 12 melingkar.** Langkah 7: "LANGKAH MANUAL deploy final dari `main` setelah PR 07–11 di-merge". `main` pada saat itu belum berisi kode fase 12 (cron `triggers.crons`, hardening): `triggers.crons` masih kosong dari fase 07 (`fase-07:26`). DoD fase 12 menuntut "cron terdaftar di cloud … satu run cloud tercatat di `ops_heartbeat`" dan uji asap cloud — hanya bisa dipenuhi dengan kode fase 12, yang baru masuk `main` setelah PR fase 12 di-merge, sedangkan PR fase 12 baru dibuka setelah LANGKAH MANUAL selesai (6h → langkah 7–11). Selain itu "menunggu Umar merge 07–11" adalah penantian pihak luar, yang menurut 6h tidak boleh `[m]`. Mode auto akan berhenti di fase 12 `[m]` berulang kali; G6 ("deploy cloud hijau") dan track c tertahan. | Ubah langkah 7: deploy fase 12 **dari branch fase 12** (setelah di-rebase ke `origin/main` begitu 07–11 merged, sesuai D-alief-27 untuk fase be lain) untuk DoD; pindahkan "deploy ulang dari `main` setelah semua PR 07–12 merged" ke butir TODO §D baru (mis. D8) yang menjadi syarat G6, dicek di PROMPT langkah 1. Revisi D-alief-27 lewat entri baru. |
| S1 | SEDANG | `fase-11-be-push.md:57`, `fase-14-pairing.md:20` vs `PROMPT.md:149-151`, D-alief-26 | Sisa N1: kedua file fase masih memakai `[~]` untuk penantian pihak luar (B6/B7/C3). Dengan aturan baru, fase `[~]` milik track selalu dipilih lagi sebagai mode LANJUT (`PROMPT.md:90`) tanpa syarat berhenti, jadi fase 11 atau 14 bisa dipilih ulang terus dan fase 12 / 15 tidak pernah dimulai. Agent juga harus memilih antara file fase dan PROMPT 6h tanpa aturan prioritas. | Ganti kedua kalimat: "selesaikan fase, buka PR, status `[r]` + 'pending B6/B7/C3' di Ringkasan; uji perangkat diulang di fase 15/16". Tambah di PROMPT §konteks: "Kalau file fase bertentangan dengan PROMPT/DECISIONS yang lebih baru, yang lebih baru menang". |
| S2 | SEDANG | `PROMPT.md:90-93` (langkah 1 pilihan 1) + `:148` (6h "Sisa fase (langkah 7–11)") vs `PROMPT.md:103` (langkah 2 "teruskan dari checklist"), `fase-16-qa-e2e.md:22-27` | Resume `[m]` melompat langsung ke langkah 7–11 (review, verifikasi, dokumentasi, PR). Itu benar kalau LANGKAH MANUAL ada di akhir fase (07, 10, 11, 12), tetapi di fase 16 LANGKAH MANUAL adalah **langkah 1** (TestFlight, dua iPhone, `APNS_ENV=production`). Mengikuti PROMPT harfiah, setelah Alief mencentang persiapan, agent langsung review + PR tanpa menjalankan matriks QA-E2E, laporan, fixbug, dan retest (langkah 2–6). Langkah 2 berkata lain ("teruskan dari checklist"). | Langkah 1 pilihan 1: "Kalau semua sudah dicentang: cek hasilnya, lalu lanjutkan langkah kerja fase yang tersisa sesuai checklist log (langkah 6), baru 7–11". Samakan 6h. |
| S3 | SEDANG | `PROMPT.md:84-98` (legenda + transisi), `:95` ("Fase [r]/[x] tidak dikerjakan ulang"), `PROGRESS.md:3` | Transisi status tidak lengkap: (a) PR `[r]` yang diberi **changes requested** oleh Umar, atau ditutup tanpa merge (`gh pr view --json state` = `CLOSED`), tidak punya aturan; mode auto melewati fase `[r]`, jadi komentar review tidak pernah ditangani agent, dan branch stacked di atasnya tidak tahu harus rebase. (b) `[!]` tidak punya aturan kapan diset (mis. "blocker P0 yang butuh keputusan", langkah 13b) dan kapan dibuka kembali (fase 17 hanya punya catatan "auto melewati"). | Tambah: "`[r]` + `reviewDecision = CHANGES_REQUESTED` atau ada komentar belum dijawab → mode LANJUT fase itu (tangani review, push ke branch yang sama, rebase stack); `CLOSED` → `[!]` + tanya Alief". Definisikan `[!]`: diset saat berhenti karena blocker P0 / keputusan user, dibuka kembali hanya oleh Alief (ubah ke `[ ]`/`[~]`). Pakai `gh pr view <no> --json state,reviewDecision`. |
| S4 | SEDANG | `ref/R2-skema-db.md:124` (§3 grant) vs `:94-102` (`blocklist_entries`), `fase-07-be-fondasi.md:38` vs `fase-10-be-verdicts.md:23` | (a) Daftar grant `shoo_api` tidak memuat `blocklist_entries`. Dengan RLS aktif + `revoke … from anon, authenticated` dan role `shoo_api` `noinherit`, `GET /blocklist` di fase 07 gagal `permission denied` kalau migrasi mengikuti R2 §3. (b) Fase 07 berkata tabel `blocklist_entries` "sudah dibuat di migrasi awal" (dan seed punya 1 domain disetujui), fase 10 berkata "Migrasi: kolom `verdicts.global_eligible` + tabel `blocklist_entries` (+ grant …)". Dua fase bisa membuat tabel yang sama. | R2 §3: tambah `blocklist_entries` ke grant (minimal `select, insert, update`) + policy RLS `shoo_api_all`; pgTAP I9 mengecek `table_privs_are('blocklist_entries', 'shoo_api', …)`. Fase 10: "Migrasi: kolom `verdicts.global_eligible` (tabel `blocklist_entries` sudah ada sejak fase 07)". |
| S5 | SEDANG | `fase-00-plan-tooling.md:40`, `fase-01-app-fondasi.md:55`, `fase-14-pairing.md:45`, `fase-15-push-validasi.md:46` | Pemeriksaan memakai diff dua titik `git diff origin/main -- …`, yang membandingkan pohon `origin/main` dengan working tree. Begitu `main` maju, hasilnya tidak kosong walaupun branch tidak menyentuh file itu. **Terbukti sekarang:** `git diff --stat origin/main -- . ':!plan/alief'` di branch ini menampilkan 6 file (`CLAUDE.md`, `docs/mandates/*`, `docs/spikes/README.md`, `.claude/commands/mandate.md`) karena `981ad73`. Hal sama akan terjadi di fase 01 kalau Umar mengubah `project.yml` (L0) dan di fase 14/15 kalau C3 di-merge (Info.plist hasil generate ikut berubah di `main`). | Pakai tiga titik (perubahan branch sejak merge-base): `git diff --stat origin/main...HEAD -- . ':!plan/alief'`, `git diff origin/main...HEAD -- ios/project.yml`, `git diff --stat origin/main...HEAD -- ios/ShooApp/Info.plist ios/ShooApp/*.entitlements`. |
| S6 | SEDANG | `fase-14-pairing.md:27` (`onOpenURL` hanya `shoo://join`), `fase-15-push-validasi.md:23-25` (`NotificationRouter`), `ref/R1-struktur-repo.md:63`; PRD 8.5 EX-04 ("See detail" → Detail di app), EX-06 (Guardian "Review in Shoo" → Detail); `origin/main:docs/mandates/umar.md` U2 (`shoo://scan/{id}`) | App punya dua pintu masuk ke Detail (push dan list), tetapi tidak ada handler untuk deep link dari extension. Mandat Umar di `main` sudah memakai `shoo://scan/{id}` untuk "See detail", dan layar blokir Guardian butuh "Review in Shoo" → Detail. Bentuk URL ini tidak ada di `contracts/` dan tidak ada di plan, jadi EX-04/EX-06 berhenti di app yang terbuka di Home. | Fase 15 (atau 14): `onOpenURL` juga menangani `shoo://scan/<id>` → `Router.openDetail(id)` (pakai fungsi murni yang sama dengan `NotificationRouter`, test parsing + id rusak). TODO §C baru ke Umar: usulkan format deep link ini masuk `contracts/app-group-keys.md` (atau `api.md`) supaya satu sumber. |
| S7 | SEDANG | D-alief-27 `log/DECISIONS.md:198` ("QA-E2E (fase 16) memakai `main`"), `fase-16-qa-e2e.md:7,22` vs `PROMPT.md:95,109-110` (fase berikut ditumpuk di atas `[r]`) | Track c menumpuk 14 di atas 13 dan 15 di atas 14 tanpa menunggu merge, jadi saat fase 16 mulai, PR 13–15 kemungkinan masih `[r]`. QA-E2E "memakai `main`" berarti build TestFlight tanpa `ApiRepository`, pairing, dan push tap; sumber build tidak didefinisikan di B8/D6. | Pilih satu: (a) fase 16 mensyaratkan PR 13–15 MERGED (cek `gh pr view`, seperti gate track c), atau (b) QA-E2E memakai ujung branch fase 15 + Worker dari `main`, dan header laporan mencatat commit app + backend. Tulis di fase 16 langkah 1 dan revisi D-alief-27. |
| R1 | RENDAH | `PROMPT.md:88`, D-alief-26 (`DECISIONS.md:192`), `fase-16-qa-e2e.md:42`, `PROGRESS.md:34-42` | Langkah 1 hanya memperbarui G5/G6 (dan G2). G8 (disebut D-alief-26 dan fase 16) tidak ada; G1 (fase 00 bertrack "–", tidak pernah disegarkan oleh "baris [r] milik TRACK"), G3, G4, G7 tidak punya pengubah yang ditentukan. | Langkah 1: "perbarui G1–G8 yang syaratnya bisa dicek (`gh pr view`, log fase LANGKAH MANUAL tercentang, TODO B6–B8)". |
| R2 | RENDAH | `ref/R5-konvensi.md:38` | Masih "`npx wait-on tcp:8787`", sedangkan semua blok Verifikasi memakai `pnpm -C backend/api exec wait-on` (devDependency). | Samakan teks R5. |
| R3 | RENDAH | `ref/R2-skema-db.md:154-169` (§5) | (a) Paginasi `approved_at > since … limit 1000`: kalau reviewer menyetujui banyak domain dalam satu `update … where domain in (…)`, semua mendapat `now()` yang sama; batas halaman di tengah kelompok itu melewatkan sisa domain. (b) Upsert entri yang sudah `removed_at` karena verdict layak baru tidak didefinisikan (diaktifkan lagi? `approved_at` lama membuatnya tak terkirim lewat `since`). (c) Entri dengan `families = 0` (semua verdict berubah ke safe) tetap di antrean review. | (a) Kursor komposit `(approved_at, domain)` di `nextSince`, atau review satu domain per statement (tulis di prosedur). (b) Tulis aturan: entri `removed_at` tidak dihidupkan otomatis; reviewer yang memutuskan (`removed_at = null, approved_at = now()`). (c) Query review `where families > 0`. |
| R4 | RENDAH | `fase-10-be-verdicts.md:25` ("prosedur LANGKAH MANUAL berkala"), `TODO.md:56` (C7), `:65-75` (§D) | Review antrean blocklist tidak punya pemilik, jadwal, atau baris TODO §D; tanpa itu layer 1 "Shoo DB (Verified scam dari keluarga)" (PRD §5) tidak pernah bertambah di cloud. Pesan C7 ke Imelda tidak menyebut bahwa isi `/blocklist` disaring review manual. | TODO §D baru (mis. "D9 review `blocklist_entries` 1×/hari selama uji/demo, Alief"); tambah satu kalimat di C7 + C8 bahwa entri baru muncul setelah disetujui. |
| R5 | RENDAH | `ref/R2-skema-db.md:153` vs `ref/R1-struktur-repo.md:19-45` | `backend/api/src/data/allowlist.ts` dipakai R2 §5 tetapi tidak ada di pohon R1; sumber daftar (brand resmi + domain populer) tidak ditentukan. | Tambah ke R1; tulis sumber awal (mis. domain bank/e-wallet/pemerintah dari fixture + daftar manual) dan cara memperbaruinya. |
| R6 | RENDAH | `ref/R3-catatan-api.md:97-106` (§7), `fase-11-be-push.md:40`, `fase-07-be-fondasi.md:26,46` | (a) `INVITE_BASE_URL` dan `PUSH_RELAY_URL` punya nilai lokal yang berbeda dari cloud, tetapi kolom "Di mana diset" hanya `wrangler.jsonc vars` (satu nilai). Cara override lokal (`.dev.vars` mengalahkan `vars`, atau `miniflare.bindings`) tidak disebut. (b) Binding Hyperdrive di `wrangler.jsonc` butuh `id`; `id` asli baru ada di LANGKAH MANUAL fase 07 langkah 3, tapi test lokal jalan lebih dulu. Docs hanya memberi contoh dengan `id` (I3, NOT YET VERIFIED apakah placeholder cukup). | (a) Tambah "lokal: `.dev.vars` / `miniflare.bindings`" untuk dua var itu. (b) Tulis "pakai `id` placeholder sampai LANGKAH MANUAL; `localConnectionString` / env `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_DB` dipakai lokal", dan catat hasilnya di fase 07. |
| R7 | RENDAH | `ref/R3-catatan-api.md:93` (§6), `fase-11-be-push.md:29,36` | Hanya `410 Unregistered` yang mengosongkan token. Docs Apple juga punya `410 ExpiredToken` ("The device token has expired") dan melarang retry untuk `ExpiredToken`. Token kedaluwarsa akan terus dicoba. | "Status 410 (reason `Unregistered` atau `ExpiredToken`) → kosongkan `apns_token`"; tambah satu test. |
| R8 | RENDAH | `fase-01-app-fondasi.md:40` (protocol), `TODO.md:60` (C11 "app saat foreground"), `fase-13-api-repository.md:24-33` | `updateMe(name:language:apnsToken:)` tidak punya parameter `extensionLastSeenAt`, padahal C11 meminta app juga mengirimnya saat foreground. Kalau C11 disetujui, protocol berubah dan view model ikut berubah. | Tulis di fase 13: "kalau C11 disetujui, tambah `extensionLastSeenAt: Date?` (opsional) ke `updateMe` dan panggil saat `scenePhase == .active`". |
| R9 | RENDAH | `fase-13-api-repository.md:47`, `fase-14-pairing.md:35,44`, `fase-15-push-validasi.md:45` | Fase 14/15 memakai dua simulator yang menyala bersamaan; `booted` lalu menunjuk salah satu secara tak pasti (`simctl openurl/push/get_app_container booted …`). | Simpan UDID tiap simulator (`xcrun simctl list devices booted`) dan pakai UDID, bukan `booted`, di blok fase 14/15. |
| R10 | RENDAH | `qa/README.md:63-69`, `ref/R7-protokol-qa.md:59` vs laporan Catalyst (kolom "Detik") | Matriks template tidak punya kolom waktu, padahal QA-E2E #10 lulus berdasarkan waktu (≤ 10 s) dan fase 15 mencatat waktu. Format Catalyst mencatat detik per skenario. | Tambah kolom "Waktu" (opsional) di matriks QA-E2E. |
| R11 | RENDAH | `TODO.md:41` (B6 "Team ID diisi di `project.yml`"), `:52` (C3 butir 3), `TODO.md:20` (A10) vs `origin/main:docs/mandates/umar.md` L0, `alief.md` (spike: "jangan commit perubahan `project.yml`") | Umar sekarang merencanakan override signing per developer (`ios/Local.xcconfig` gitignored) alih-alih Team ID di `project.yml`. C3 butir 3 dan B6 perlu diselaraskan. Juga belum jelas siapa memegang Apple Developer Program berbayar (APNs `.p8`, capability Push, TestFlight), dan apakah akun Alief cukup untuk uji push perangkat D7. | Ubah B6/C3: "signing lewat L0 Umar (`Local.xcconfig`)"; tambah pertanyaan pemegang akun berbayar ke C3. |

Jumlah: **KRITIS 0 · TINGGI 2 · SEDANG 7 · RENDAH 11**.

## 4. Kontradiksi antar-dokumen

- **`fase-17-ditahan.md` + `PROGRESS.md:28,51` + `README.md:135` + `TODO.md:63` (ON-04 ditahan) ↔ `origin/main:docs/mandates/alief.md` (ON-04 Fase A, S1/S2 milik Alief):** plan mengikuti mandat lama (#T1).
- **`TODO.md:73` (D5 "Spike #2 dan #3 Umar") ↔ `origin/main:docs/spikes/README.md` (owner #2/#3 = Alief):** pemilik spike berubah (#T1).
- **`fase-12:28` (deploy final dari `main` setelah 07–11) ↔ `fase-12:43,45` (DoD cron + uji asap cloud):** kode fase 12 belum ada di `main` (#T2).
- **D-alief-27 ("Deploy final (fase 12) … memakai `main`") ↔ `PROMPT.md:150-151` (6h: penantian pihak luar bukan `[m]`):** menunggu merge Umar dijadikan LANGKAH MANUAL (#T2).
- **`fase-11:57`, `fase-14:20` (`[~]` saat menunggu B6/B7/C3) ↔ `PROMPT.md:149-151` + D-alief-26 (`[r]` + "pending"):** (#S1).
- **`PROMPT.md:92-93` (resume `[m]` → langkah 7–11) ↔ `PROMPT.md:103` ("teruskan dari checklist") ↔ `fase-16:22` (LANGKAH MANUAL di langkah 1):** (#S2).
- **`ref/R2-skema-db.md:124` (grant tanpa `blocklist_entries`) ↔ `fase-07:38` (`GET /blocklist` membaca `blocklist_entries`):** (#S4).
- **`fase-07:38` (tabel dibuat di migrasi awal) ↔ `fase-10:23` (migrasi fase 10 membuat tabel):** (#S4).
- **D-alief-26 + `fase-16:42` (G8 diperbarui di langkah 1) ↔ `PROMPT.md:88` (hanya G5/G6/G2):** (#R1).
- **`ref/R5-konvensi.md:38` (`npx wait-on`) ↔ `fase-07:57`, `fase-12:35`, `fase-13:45` (`pnpm … exec wait-on`):** (#R2).
- **`ref/R3:93` (hanya `410 Unregistered`) ↔ docs Apple (`410 ExpiredToken`, jangan retry):** (#R7).
- **`TODO.md:41,52` (Team ID di `project.yml`) ↔ `origin/main:docs/mandates/umar.md` L0 (`Local.xcconfig`):** (#R11).
- **`contracts/api.md` Blocklist ("all domains with a `not_safe` verdict from any family") ↔ D-alief-25 (hanya entri yang disetujui manual):** deviasi makna yang sudah diusulkan ke Umar + Imelda (C6). Bentuk JSON tetap sama. Bukan temuan baru, tapi fase 10 menerapkannya sebelum C6 dijawab, jadi PR fase 10 wajib memuat bagian "Contract proposals".
- **PRD §5 Validasi ("masuk whitelist keluarga") ↔ D-alief-09 (per pemilik):** deviasi tercatat sejak run 01, masih menunggu konfirmasi Umar.

## 5. Lima risiko terbesar untuk MVP + mitigasi

1. **Plan dan mandat tidak sinkron** (#T1): ON-04 (P0) dan S1/S2 tidak dikerjakan, MVP Alief gagal "Selesai kalau" PRD 8.1, dan Umar menunggu hasil S1 untuk `extensionActiveWindow` dan EX-01. Mitigasi: rebase ke `main`, tambah fase S1/S2 + ON-04 fallback, minta L0 (signing per developer) dari Umar lebih dulu karena S1/S2 butuh iPhone.
2. **Track be macet di fase 12** (#T2) atau loop di fase 11/14 (#S1), sehingga G6 dan track c tertunda. Mitigasi: deploy fase 12 dari branch-nya, redeploy `main` sebagai butir TODO §D untuk G6; ganti `[~]` eksternal ke `[r]` + pending; uji kering PROGRESS contoh (07 `[m]`, 11 `[r]` pending B6, 12 `[ ]`) sebelum mode auto.
3. **Push APNs** (HTTP/2 Worker/Edge Function → APNs belum terdokumentasi, I11/I12; akun berbayar untuk `.p8` dan entitlement belum jelas, #R11). GD-06 P0 bergantung padanya. Mitigasi: uji lokal relay fase 11 (token dummy → `BadDeviceToken`), uji perangkat D7, `PushSender` tetap interface sehingga sender bisa diganti.
4. **Review PR tidak tertangani otomatis** (#S3): komentar Umar pada PR `[r]` tidak pernah diproses; stack branch tertinggal dan konflik menumpuk. Mitigasi: aturan `CHANGES_REQUESTED` → mode LANJUT + rebase stack, cek `reviewDecision` di langkah 1.
5. **Ketergantungan keputusan Umar/Imelda** (C3 kamera/push, C6 blocklist, C11 `extensionLastSeenAt`, C12 `GET /devices/me`, C13, deep link `shoo://scan/{id}` #S6) plus extension yang benar-benar memanggil `POST /scans` dan polling verdict. Mitigasi: kirim paket C sekarang, placeholder `TODO(sync:umar)`, curl peniru extension untuk QA, review antrean blocklist terjadwal (#R4).

## 6. Pertanyaan yang harus dijawab sebelum fase 01 dan 07

1. **Alief:** mandat di `main` sekarang memberimu S1, S2, dan ON-04. Rebase plan ke `main` dan tambah fase S1/S2 + ON-04 fallback sebelum PR plan dibuka?
2. **Umar (L0):** kapan override signing per developer (`Local.xcconfig`) siap? S1/S2 dan uji push D7 butuh build ke iPhone Alief. Siapa pemegang Apple Developer Program berbayar (APNs `.p8`, Push capability, TestFlight)?
3. **Alief:** setuju deploy fase 12 dari branch fase 12 untuk DoD, lalu redeploy dari `main` setelah semua PR be merged sebagai syarat G6 (#T2)?
4. **Alief:** QA-E2E (fase 16) menunggu PR 13–15 merged, atau memakai ujung branch fase 15 (#S7)?
5. **Umar (C6):** review manual blocklist sebagai default fase 10 disetujui? Siapa yang mereview dan seberapa sering (#R4)?
6. **Umar:** format deep link extension → app untuk "See detail" / "Review in Shoo": `shoo://scan/{id}` masuk `contracts/` (#S6)?
7. **Umar (C3, C11):** `NSCameraUsageDescription` + `aps-environment` di `project.yml` kapan? Apakah extension akan mengirim `extensionLastSeenAt` (GD-03 "Not connected")?
8. **Umar (C12, C13):** boleh `GET /devices/me`? `owner=family` memuat scan Guardian sendiri?

---

## I. Cek dokumentasi resmi

| # | Klaim di plan | Status | Sumber / koreksi |
|---|---|---|---|
| I1 | Workers Free: 100k request/hari, CPU 10 ms per request dan per Cron, 50 subrequest, 5 Cron/akun (ARCHITECTURE §3, R2 §6) | **VERIFIED** | https://developers.cloudflare.com/workers/platform/limits/ — juga 6 koneksi keluar simultan per request |
| I2 | Cache Hyperdrive aktif default; `--caching-disabled` (TODO B4, D-alief-17) | **VERIFIED** (run 02, tidak dibaca ulang) | https://developers.cloudflare.com/hyperdrive/concepts/query-caching/ |
| I3 | Lokal: `localConnectionString` / `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_DB`; env var menang | **VERIFIED**; `id` placeholder sebelum Hyperdrive cloud dibuat **NOT YET VERIFIED** | https://developers.cloudflare.com/hyperdrive/configuration/local-development/ — semua contoh memuat `id`; env var terikat ke binding di config → #R6 |
| I4 | Hyperdrive + Supabase Direct connection, fallback session pooler 5432 `shoo_api.<ref>`; IPv6 Hyperdrive | **VERIFIED** (run 02); IPv6 **NOT YET VERIFIED** | https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-database-providers/supabase/, https://supabase.com/docs/guides/database/connecting-to-postgres |
| I5 | postgres.js `fetch_types: false` + daftar ID lewat `in ${sql(ids)}` (R5 §2) | **VERIFIED** | https://github.com/porsager/postgres — "Value lists can also be created dynamically, making `where in` queries simple"; `fetch_types` mengambil info tipe tabel/array saat koneksi pertama dan bisa dimatikan |
| I6 | `vitest@^4.1.0` + `@cloudflare/vitest-plugin` + `cloudflareTest()` | **VERIFIED** (run 02) | https://developers.cloudflare.com/workers/testing/vitest-integration/configuration/ |
| I7 | `miniflare.hyperdrives` untuk binding DB di test | **VERIFIED sebagian** | Halaman configuration hanya menyebut Hyperdrive di bagian konfigurasi dinamis (`provide()`/`inject()` port). Fallback `wrangler dev` + vitest Node tetap perlu (fase 07 langkah 10) |
| I8 | Test handler `scheduled()` dari vitest (fase 12 langkah 1) | **VERIFIED** (run 02: NOT YET) | https://developers.cloudflare.com/workers/testing/vitest-integration/test-apis/ — `createScheduledController()`, `createExecutionContext()`, `waitOnExecutionContext()` dari `cloudflare:test`, lalu panggil handler `scheduled` modul secara langsung |
| I9 | Cron lokal `/cdn-cgi/local/scheduled?cron=…` (+ `wrangler dev --test-scheduled`); bukti cron cloud dari dashboard Settings → Triggers | **VERIFIED** | https://developers.cloudflare.com/workers/configuration/cron-triggers/ — route lokal, "Local development does not run Cron Triggers automatically", dashboard Settings → Triggers → Cron Triggers. Flag `--test-scheduled`: run 02 (halaman perintah wrangler) |
| I10 | `fetch()` Worker bisa HTTP/2 ke APNs | **NOT YET VERIFIED** | Tidak ada docs; plan sudah menjadikan relay jalur utama + spike di Worker cloud (D-alief-16) |
| I11 | Edge Function Supabase (Deno) HTTP/2 ke APNs | **NOT YET VERIFIED** | Tidak ada docs Supabase; dibuktikan uji lokal fase 11 langkah 7 + D7 |
| I12 | `supabase functions serve --no-verify-jwt --env-file`, `secrets set --env-file` | **VERIFIED** | https://supabase.com/docs/reference/cli/supabase-functions-serve, https://supabase.com/docs/reference/cli/supabase-secrets-set; CLI lokal 2.114.0 `--help` memuat ketiga flag |
| I13 | `config.toml` `[functions.push] verify_jwt = false` "berlaku untuk serve dan deploy" (fase 11 langkah 2) | **VERIFIED sebagian** | https://supabase.com/docs/guides/functions/function-configuration — contoh `[functions.<nama>] verify_jwt = false` ada; halaman tidak menyatakan berlaku untuk `serve`/`deploy`. Plan tetap memakai `--no-verify-jwt` di keduanya, jadi aman |
| I14 | `supabase start -x studio,imgproxy,edge-runtime,logflare,vector`; `supabase test db` + pgTAP | **VERIFIED** | CLI lokal: `--exclude` menerima `studio, imgproxy, edge-runtime, logflare, vector` (nama benar); https://supabase.com/docs/reference/cli/supabase-test-db (run 02) |
| I15 | Storage REST upload/sign/hapus `prefixes` | **VERIFIED** (run 02) | https://github.com/supabase/storage-js/blob/main/src/packages/StorageFileApi.ts |
| I16 | Supabase Free: 500 MB DB, 1 GB Storage, 5 GB egress, 500k invocation, 2 proyek; pause setelah aktivitas rendah 7 hari | **VERIFIED** | https://supabase.com/docs/guides/platform/billing-on-supabase, https://supabase.com/docs/guides/platform/project-pausing ("low activity over a 7-day period"; beberapa request DB per hari biasanya cukup) |
| I17 | Supabase mencabut grant otomatis tabel `public` untuk Data API mulai 30 Okt 2026 (R2 §1) | **VERIFIED** | https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically — hanya berdampak ke Data API; plan tidak memakai PostgREST dan tetap `revoke` |
| I18 | APNs header (`apns-push-type`, `apns-topic`, `apns-priority`), host sandbox/production, JWT 20–60 menit | **VERIFIED** (run 02) | https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns, …/establishing-a-token-based-connection-to-apns; `TooManyProviderTokenUpdates` (≤ 1×/20 menit) cocok dengan cache ±50 menit |
| I19 | `410 Unregistered` → hapus token; `400 BadDeviceToken` juga untuk environment salah → jangan hapus | **VERIFIED**, dengan tambahan | https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns (dibaca ulang lewat `…/tutorials/data/…md`): BadDeviceToken "Verify … that the token matches the environment". Ada juga `410 ExpiredToken`, dan Apple melarang retry `ExpiredToken`/`Unregistered`/`BadDeviceToken` → #R7 |
| I20 | Target test XcodeGen + `GENERATE_INFOPLIST_FILE: YES` (D-alief-28) | **VERIFIED sebagian** | https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md: `INFOPLIST_FILE` hanya dari `info` atau pencarian sources; `TEST_HOST`/`TEST_TARGET_NAME` otomatis; spec tidak menyebut `GENERATE_INFOPLIST_FILE` (diteruskan sebagai build setting biasa). Apple Forums (https://developer.apple.com/forums/thread/773117): error "no Info.plist" menyarankan set `INFOPLIST_FILE` atau aktifkan generate. Bukti akhir = `xcodebuild test` fase 01 |
| I21 | XcodeGen menulis ulang Info.plist/entitlements setiap generate (PROMPT 6k, R5 §6) | **VERIFIED** (run 02) | ProjectSpec: "this will generate and write an `Info.plist` to the specified path" |
| I22 | `xcrun simctl push booted com.shoo.app <file.apns>` | **VERIFIED** | `xcrun simctl help push` lokal: bundle id opsional kalau payload punya `Simulator Target Bundle`, wajib `aps`, ≤ 4096 byte |
| I23 | `xcrun simctl get_app_container booted com.shoo.app group.com.shoo.app` | **VERIFIED** | `xcrun simctl help get_app_container` lokal: container `<group identifier>` didukung |
| I24 | Tanpa `aps-environment`, registrasi APNs gagal (fase 15) | **VERIFIED** (run 02) | Apple TN2265 https://developer.apple.com/library/archive/technotes/tn2265/_index.html |
| I25 | `xcodebuild test -only-testing:ShooAppTests/<Suite>` untuk Swift Testing | **VERIFIED sebagian** | Tidak ada docs Apple yang ditemukan; isu Tuist https://hive.tuist.dev/forage/items/github-issue/fde4d966-d361-4530-b81c-35c9924e74bf menyebut `-only-testing` memfilter Swift Testing per suite. Fallback `-only-testing:ShooAppTests` tetap berguna |
| I26 | `.environment(\.locale)` mengubah String Catalog | **NOT YET VERIFIED** (tidak berubah) | Diuji di fase 01 langkah 5, fallback `L10n` |
| I27 | WhatsApp tidak membuat `shoo://` bisa diklik (D-alief-03) | **NOT YET VERIFIED** (tidak berubah) | Desain `/join` https aman di kedua kemungkinan; diuji QA-E2E #4 |
| I28 | `gitleaks detect --source . --no-banner` | **VERIFIED** (run 02; `gitleaks` terpasang di Mac ini) | gitleaks 8.x: `detect` masih jalan (tersembunyi) |

## J. Cek wiring ujung ke ujung

### J1. `ShooRepository` (fase-01 §2) → `contracts/api.md` → fase backend

| Method app | Endpoint kontrak | Backend | Catatan |
|---|---|---|---|
| `registerDevice(name:mode:)` | `POST /devices` | 07 §5 | Bahasa ID langsung `PATCH` setelahnya (`fase-13:33`) |
| `updateMe(name:language:apnsToken:)` | `PATCH /devices/me` | 07 §6 | Belum ada `extensionLastSeenAt` kalau C11 disetujui (#R8) |
| `createFamilyCode()` | `POST /family/code` | 08 §1 | OK |
| `joinFamily(code:)` | `POST /family/join` | 08 §2 | OK (+ `already_connected`) |
| `familyMembers()` | `GET /family/members` | 08 §3 | OK (default `extensionActive: true`) |
| `removeMember(_:)` | `DELETE /family/members/{id}` | 08 §4 | OK |
| `leaveGuardian()` | `DELETE /family/guardian` | 08 §4 | OK; hapus `guardian.name` (`fase-13:25`) |
| `scans(owner:status:cursor:)` | `GET /scans` | 09 §2 | OK (`family` termasuk diri sendiri, D-alief-19) |
| `scan(id:)` | `GET /scans/{id}` | 09 §3 | OK; juga target deep link `shoo://scan/{id}` yang belum ditangani (#S6) |
| `setVerdict(scanId:value:)` | `POST /verdicts` | 10 §1 | OK; sekarang juga mengisi antrean `blocklist_entries` dalam satu transaksi |
| — | `GET /devices/me` (usulan C12) | — | Celah tercatat (D-alief-21) |

Endpoint tim lain: `POST /scans` (extension, 09), `GET /verdicts?domain=` (extension, 10), `GET /blocklist` (detector, 07 + 10), `GET /join` (browser, 08), `/healthz`, `/healthz/db` (monitor B9). **Semua 10 operasi protocol terpetakan ke endpoint dan fase.** Pintu masuk app: push (`NotificationRouter`, 15), `shoo://join` (14), `shoo://scan/{id}` dari extension **tidak ada** (#S6).

### J2. Key App Group: penulis dan pembaca

| Key | Penulis | Pembaca | Status |
|---|---|---|---|
| `device.id`, `device.token`, `device.mode` | App fase 13 `SessionStore` | Extension `getSession` | OK |
| `device.name` | App fase 13 + tulis ulang setelah `updateMe(name:)` | Extension `getSession` | OK |
| `guardian.name` | App fase 14 (join), dihapus saat `leaveGuardian()`/404 | Extension `getSession` ("Waiting for [nama]") | OK; pemutusan dari sisi Guardian tidak terdeteksi (D-alief-21) |
| `api.baseURL` | App fase 13 (`AppConfig` `#if DEBUG`) | Extension `getSession` | OK |
| `ai.baseURL` | App fase 13, placeholder `TODO(sync:imelda)` | Extension `getSession` | Bergantung Imelda |
| `extension.lastSeenAt` | Extension (heartbeat, sudah ada) | App `ExtensionStatus` fase 01 (dipakai 04, 05, 06, dan ON-04 setelah #T1) | OK |

Kedelapan key di `ios/ShooShared/AppGroup.swift:12-19` = delapan baris `contracts/app-group-keys.md`. **Setiap key punya penulis dan pembaca.** Tidak ada key baru di plan.

### J3. Env R3 §7 → LANGKAH MANUAL

| Variabel | Diset di | Status |
|---|---|---|
| `DB` (Hyperdrive) | fase 07 LANGKAH MANUAL 3 (B4, `--caching-disabled`) | OK; `id` lokal sebelum langkah ini → #R6 |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | fase 09 DoD "LANGKAH MANUAL deploy fase 09 + secret" (B5); lokal `.dev.vars` | OK (disebut di DoD, bukan Langkah kerja) |
| `INVITE_BASE_URL` | fase 07 LANGKAH MANUAL 4 (`vars`) | OK; override lokal → #R6 |
| `APNS_ENV` | fase 11 LANGKAH MANUAL 8 (env-file Edge Function); fase 16 langkah 1 (`production`) | OK |
| `PUSH_RELAY_URL` | fase 11 LANGKAH MANUAL 8 (`vars`) | OK; override lokal → #R6 |
| `PUSH_RELAY_SECRET` | fase 11 LANGKAH MANUAL 8 (Worker `secret put` + env-file Edge Function) | OK |
| `APNS_KEY_P8_B64`, `APNS_KEY_ID`, `APNS_TEAM_ID` | fase 11 LANGKAH MANUAL 8 (env-file di luar repo, lalu `rm`) | OK |
| `SCREENSHOT_MAX_BYTES` | `vars` `wrangler.jsonc` (ter-commit, ikut deploy) | OK |
| `APNS_SPIKE` | fase 07 LANGKAH MANUAL 4 (`1`) → 6 (`0`) → dihapus fase 11 langkah 5 | OK |
| `SPIKE_KEY` | fase 07 LANGKAH MANUAL 4 → `secret delete` fase 11 LANGKAH MANUAL 8 | OK |
| Secret CI (5) | C2 ke Umar (fase 12) | OK |

**Setiap variabel R3 §7 punya langkah yang men-set-nya.**

### J4. Gate PROGRESS bisa dicapai?

| Gate | Cara tercapai | Status |
|---|---|---|
| G0 | Jawaban Umar di TODO §C | Manual, OK (C14 harus diganti, #T1) |
| G1 | Merge PR `docs/alief-plan` | Bisa, tetapi tidak ada langkah yang memperbarui baris G1 / fase 00 (#R1) |
| G2 | Merge `chore/APP-test-targets` | OK (langkah 1 memperbarui G2) |
| G3 | Fase 07 LANGKAH MANUAL (`[m]` → lanjut) | Tercapai; baris G3 tanpa pengubah (#R1) |
| G4 | Fase 10 uji cloud | Tercapai; baris G4 tanpa pengubah (#R1) |
| G5 | Semua PR 01–06Q merged | OK (langkah 1) |
| G6 | Semua PR 07–12 merged + "deploy cloud hijau" | **Macet di fase 12** (#T2) |
| G7 | B6–B8 | Manual; B6 perlu diselaraskan dengan L0 (#R11) |
| G8 | README §7 | Butuh ON-04 sesuai mandat baru (#T1); baris G8 tidak disebut di langkah 1 (#R1) |

### J5. Transisi status (PROMPT.md)

| Status | Masuk | Keluar | Status |
|---|---|---|---|
| `[ ]` | awal | `[~]` di langkah 4 | OK |
| `[~]` | langkah 4 | `[m]` (6h), `[r]` (langkah 10) | OK; tetapi `fase-11:57`, `fase-14:20` memakai `[~]` untuk menunggu (#S1) |
| `[m]` | 6h | langkah 1 pilihan 1 → langkah 7–11 → `[r]` | OK untuk fase 07/10/11/12; fase 16 melompati langkah 2–6 (#S2) |
| `[r]` | langkah 10 | `[x]` di langkah 1 kalau MERGED | Tidak ada transisi untuk changes requested / CLOSED (#S3) |
| `[x]` | langkah 1 | final | OK |
| `[!]` | hanya diisi manual (fase 17) | tidak ada | Tidak didefinisikan (#S3) |

### J6. Antrean blocklist: `POST /verdicts` → review → `GET /blocklist`

1. `POST /verdicts` (fase 10 langkah 1): satu transaksi, upsert `verdicts (owner_id, domain)` + `global_eligible` (R2 §5 butir 1: `not_safe`, pemilik scan mode protected, `family_links` aktif ke Guardian pemutus, bukan allowlist) → upsert `blocklist_entries` + hitung `families` (butir 2), hitung ulang saat berubah ke safe (butir 3). **Tersambung.**
2. Review (R2 §5 butir 4): SQL editor, `approved_at`/`removed_at`; prosedur di `backend/README.md` (fase 10 langkah 3). **Tersambung, tetapi tanpa jadwal/pemilik** (#R4).
3. `GET /blocklist?since=` (R2 §5 butir 5, R3 §4): hanya `approved_at is not null and removed_at is null`, `nextSince = approved_at`. **Tersambung**, kecuali grant `shoo_api` pada tabel itu (#S4) dan seri waktu sama di batas halaman (#R3).
4. Test end-to-end (fase 10:37) dan QA-E2E #11 (R7:60) menutup alur ini. Penghapusan ke detector menunggu usulan `removed` (C6/D-alief-18).

### J7. Perintah Verifikasi dari root repo

| Fase | Hasil |
|---|---|
| 00 | `ls …` OK; grep `TODO(sync` OK (kosong); **`git diff --stat origin/main -- . ':!plan/alief'` sekarang menampilkan 6 file** karena `main` maju (#S5) |
| 01–06, 06Q, 13–16 | `source plan/alief/ref/sim.sh` diuji (`bash -n` lulus; bash + zsh → `SIM=iPhone 17 Pro`, tanpa spasi). `xcodebuild -project ios/Shoo.xcodeproj` benar dari root. Fase 01 `git diff origin/main -- ios/project.yml` → #S5 |
| 07 | Subshell benar; `pnpm -C backend/api exec wait-on tcp:8787` (devDependency) + `pkill` di akhir |
| 08, 09, 10, 12 | `(cd backend/db && supabase start && …)` benar; `pnpm -C backend/api exec vitest run <pola>` benar |
| 11 | `supabase start` + `deno test --allow-env` di folder fungsi (Deno terpasang) + grep literal secret: benar |
| 12 | `wrangler dev --test-scheduled` + `/cdn-cgi/local/scheduled` sesuai docs (I9); `gitleaks` terpasang |
| 13 | `plutil -p "$(xcrun simctl get_app_container booted com.shoo.app group.com.shoo.app)/Library/Preferences/group.com.shoo.app.plist"` sesuai `simctl help` (I23); `booted` ambigu kalau dua simulator (#R9) |
| 14, 15 | `simctl openurl`/`push` valid (I22); `git diff origin/main --stat -- …Info.plist …entitlements` → #S5; `booted` → #R9 |

---

## Catatan untuk run berikutnya

- Fokus ulang: #T1 (rebase ke `origin/main` + fase S1/S2/ON-04), #T2 (deploy fase 12), lalu #S1–#S4.
- Uji kering aturan status: PROGRESS contoh dengan 07 `[m]` (checklist tercentang), 11 `[r]` "pending B6", 12 `[ ]`, 14 `[r]` "pending C3" + `CHANGES_REQUESTED` → pastikan agent memilih fase yang benar dan menangani review.
- Pastikan plan dibaca terhadap `origin/main` terbaru (mandat bisa berubah lagi), dan semua pemeriksaan diff memakai tiga titik.
- Yang tetap tidak bisa diverifikasi dari docs: HTTP/2 Worker/Edge Function → APNs, IPv6 Hyperdrive, `id` Hyperdrive placeholder untuk lokal, locale environment + String Catalog, link WhatsApp, build target test (butuh `xcodegen` + build), wireframe PRD §7 (gambar).
