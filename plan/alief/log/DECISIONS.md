# Keputusan & deviasi — Alief (append-only)

Setiap perubahan stack, scope, atau usulan kontrak dicatat di sini. Jangan menghapus entri lama; kalau keputusan dibatalkan, tambah entri baru yang merujuk entri lama. ID memakai prefix `D-alief-NN`.

Format:

```text
## D-alief-<nomor> · <tanggal WITA> · fase <XX> · <judul singkat>
- Keputusan:
- Alasan:
- Alternatif yang ditolak:
- Dampak ke tim lain / kontrak:
- File yang diperbarui:
```

---

## D-alief-00 · 21 Okt 2026 · plan · Keputusan awal dari grilling

- Keputusan: lihat TODO §A (A1–A18). Ringkas: plan Indonesia, dua track paralel (app, be) + track c, aturan PR repo (reviewer Umar, agent tidak merge, PR boleh ditumpuk), siklus ECC ala IBM + Superpowers, QA format Catalyst, Opus untuk backend/keamanan, Sonnet untuk UI fixture/QA, semua aksi cloud manual.
- Alasan: hasil tanya-jawab dengan Alief.
- Dampak: –
- File: seluruh `plan/alief/`.

## D-alief-01 · 21 Okt 2026 · plan · API di Cloudflare Workers, data di Supabase

- Keputusan: API = Cloudflare Worker `shoo-api` (Hono + postgres.js via Hyperdrive). Database + Storage screenshot = Supabase `shoo-demo` (ap-southeast-1). PostgREST tidak dipakai. Retensi = Cron Trigger Worker. Satu stack cloud + lokal.
- Alasan: Alief ingin backend dan database terpisah; Workers Free tanpa kartu, tanpa cold start, sudah dikuasai (proyek IBM). Supabase direkomendasikan lead untuk DB.
- Alternatif yang ditolak: semua di Supabase Edge Functions (backend dan DB tidak terpisah); Cloud Run (butuh kartu billing, cold start); Render/Railway/Fly (tidur atau tanpa free tier); R2 untuk screenshot (Alief memilih Supabase saja; R2 jadi cadangan lewat adapter, TODO E1).
- Dampak: tidak ada perubahan bentuk JSON. `api.baseURL` = URL Worker.
- File: ARCHITECTURE.md, ref/R1–R3.

## D-alief-02 · 21 Okt 2026 · plan · Target test lewat PR kecil di `ios/project.yml`

- Keputusan: fase 01 membuka PR terpisah `chore/APP-test-targets` yang HANYA menambah target `ShooAppTests` + `ShooAppUITests`, scheme test, dan `excludes` (`Tests/**`, `UITests/**`, `ci/**`) di target Shoo. Alief memberi tahu Umar (TODO C1). Ini satu-satunya pengecualian hard rule 2.
- Alasan: TDD butuh target test; Alief meminta agent mengerjakannya sendiri dan cukup memberi tahu Umar. CODEOWNERS tetap mewajibkan approve Umar.
- Alternatif yang ditolak: paket SPM `ShooKit` di dalam `ios/ShooApp/` — target Shoo memakai `sources: path: ShooApp`, sehingga `Package.swift` dan symlink ke `ShooShared` ikut terkompilasi ke app dan merusak build tanpa edit `project.yml`.
- Dampak: Umar perlu me-review satu PR kecil.
- File: fase-01, ref/R1 §2, ref/R5 §4.

## D-alief-03 · 21 Okt 2026 · plan · `inviteUrl` berupa link https (usulan kontrak)

- Keputusan: `inviteUrl = https://<worker>/join?code=<code>`. Worker menyajikan halaman kecil yang membuka `shoo://join?code=<code>` dan menampilkan kode untuk diketik.
- Alasan: WhatsApp tidak membuat skema kustom `shoo://` bisa diklik; Universal Links butuh Associated Domains (capability lead + domain sendiri).
- Alternatif yang ditolak: `inviteUrl = shoo://join?code=` (tidak bisa diklik di WA); Universal Links (butuh capability + domain, P1).
- Dampak: kontrak hanya menyebut `inviteUrl` tanpa format, tapi mandat menyebut `shoo://join?code=1234`. Disampaikan ke Umar (TODO C5).
- File: ref/R3 §4, fase-08, fase-14.

## D-alief-04 · 21 Okt 2026 · plan · `screenshotUrl` hanya di `GET /scans/{id}`

- Keputusan: daftar `GET /scans` mengembalikan `screenshotUrl: null`; `GET /scans/{id}` mengembalikan signed URL 1 jam.
- Alasan: Activity tidak menampilkan screenshot (PR-05, GD-05), satu signed URL per item = subrequest dan egress yang tidak perlu (Workers Free 50 subrequest, Supabase 5 GB egress).
- Dampak: field memang opsional di skema. Disampaikan ke Umar (C10) karena extension tidak memakai daftar.
- File: ref/R3 §4, fase-09.

## D-alief-05 · 21 Okt 2026 · plan · Teks push mengikuti bahasa Guardian

- Keputusan: body push dibuat dalam bahasa Guardian (`devices.language`, diisi lewat `PATCH /devices/me {language}`); bentuk payload sama dengan kontrak.
- Alasan: semua teks wajib EN + ID (mandat butir 4).
- Dampak: contoh kontrak berbahasa Inggris tetap berlaku untuk Guardian EN. Info ke Umar (C9).
- File: ref/R3 §6, fase-11.

## D-alief-06 · 21 Okt 2026 · plan · Risiko peracunan blocklist (usulan)

- Keputusan: implementasi mengikuti kontrak (semua domain `not_safe` dari keluarga mana pun). Usulan ke lead: hanya domain dari scan `blocked` + allowlist domain resmi brand.
- Alasan: satu Guardian (atau device palsu) bisa memasukkan domain sah ke blocklist global (SECURITY T5).
- Dampak: menunggu keputusan Umar + Imelda (C6). `by_device_id` disimpan supaya bisa dibersihkan.
- File: SECURITY T5, ref/R2 §5, fase-10.

## D-alief-07 · 21 Okt 2026 · plan · Batas screenshot (usulan kontrak)

- Keputusan: server menerima `screenshotBase64` JPEG/PNG ≤ 150 KB; lebih besar dibuang (scan tetap disimpan). Dedupe pemilik+domain 24 jam, maks 50 per device per 24 jam. Usulan ke Umar: extension mengirim JPEG, sisi terpanjang ≤ 1280 px, quality 0,6.
- Alasan: Supabase Free 1 GB Storage + 5 GB egress.
- Dampak: extension Umar (C4).
- File: ref/R3 §4, ARCHITECTURE §3, fase-09.

## D-alief-08 · 21 Okt 2026 · plan · EX-06 tetap polling

- Keputusan: tidak ada realtime; extension polling `GET /verdicts?domain=` tiap 5 s sesuai kontrak.
- Alasan: paling sederhana, sudah di kontrak. Realtime = TODO E3.
- File: ref/R3 §4–§5.

## D-alief-09 · 21 Okt 2026 · plan · Verdict per (pemilik, domain)

- Keputusan: verdict berlaku untuk domain milik pemilik scan saja, sesuai `contracts/api.md`, bukan untuk seluruh keluarga.
- Alasan: kontrak menang atas kalimat PRD "masuk whitelist keluarga".
- Dampak: kalau lead ingin whitelist berlaku sekeluarga, itu perubahan kontrak.
- File: ref/R2 verdicts, ref/R4 §4.

## D-alief-10 · 21 Okt 2026 · plan · Penyimpanan token device

- Keputusan: server menyimpan SHA-256 token. App menyimpan token di Keychain dan, sesuai kontrak, di App Group `device.token` untuk extension.
- Alasan: kontrak App Group mewajibkan; Keychain sharing butuh entitlement lead.
- File: SECURITY T3, fase-13.

## D-alief-11 · 21 Okt 2026 · plan · Batas percobaan join

- Keputusan: 5 gagal per device dan per IP dalam 10 menit → `too_many_attempts`.
- Alasan: PRD §10 (kode mudah ditebak; 60 s + batas percobaan + maks 3).
- File: ref/R3 §5.

## D-alief-12 · 21 Okt 2026 · plan · Draf GitHub Action inert

- Keputusan: workflow ditulis di `backend/ci/backend.yml` dan `ios/ShooApp/ci/ios-app.yml`; Umar memindahkannya ke `.github/workflows/` dan menambah secret (C2). Sampai itu deploy manual.
- Alasan: `.github/` milik lead; workflow aktif tanpa secret akan gagal.
- File: fase-01, fase-07, fase-12.

## D-alief-13 · 21 Okt 2026 · plan · Avatar placeholder

- Keputusan: 12 avatar `avatar_01..avatar_12` (SF Symbol di lingkaran warna), server memilih acak. Re-skin saat desain final datang.
- File: fase-01, ref/R2 `devices.avatar_id`.

## D-alief-14 · 21 Okt 2026 · plan · Retensi tidak menghapus verdict

- Keputusan: retensi 14 hari menghapus scan, screenshot, kode, percobaan join, push_log. Verdict tetap.
- Alasan: verdict = keputusan keluarga yang dipakai blocklist dan unblock; bukan "data deteksi".
- File: ref/R2 §6, ref/R4 §5.

## D-alief-15 · 21 Okt 2026 · plan · Sumber `extensionActive` (usulan kontrak)

- Keputusan: usulkan field opsional `extensionLastSeenAt` di `PATCH /devices/me`, dikirim app Protected dari `AppGroup.Key.extensionLastSeenAt`. Sampai disetujui: `extensionActive = ada scan dalam 24 jam`.
- Alasan: GD-03 butuh "Not connected" saat extension orang tua mati, tapi kontrak tidak punya jalur data dari extension ke server.
- Dampak: perubahan kontrak kecil (Umar).
- File: ref/R3 §4, fase-05, fase-08.

## D-alief-16 · 21 Okt 2026 · plan (direvisi setelah verify run 01) · Jalur push APNs: relay dulu

- Keputusan: **jalur utama yang direncanakan = `RelaySender`** → Edge Function Supabase `push` (Deno) dengan shared secret. `ApnsSender` langsung dari Worker hanya dipakai kalau spike di Worker **yang sudah di-deploy** (bukan `wrangler dev`) membuktikan HTTP/2 ke APNs berhasil. Hasil spike ditulis sebagai entri baru `D-alief-B…` di fase 07.
- Alasan: tidak ada dokumen resmi Cloudflare bahwa `fetch()` Worker memakai HTTP/2 ke origin; laporan komunitas menyebut HTTP/1.1; APNs hanya HTTP/2. Spike lokal tidak mewakili jaringan edge.
- Dampak: tambah Edge Function di `backend/db/supabase/functions/push/` (folder kita); Supabase Free 500.000 invocation/bulan.
- File: ARCHITECTURE §1–§2, ref/R1, ref/R3 §6–§7, fase-07, fase-11.

## D-alief-17 · 21 Okt 2026 · plan (verify run 01) · Hyperdrive tanpa cache + Direct connection

- Keputusan: Hyperdrive dibuat dengan `--caching-disabled`. Connection string = Direct connection Supabase (role `shoo_api`); fallback session pooler port 5432 (user `shoo_api.<ref>`), bukan transaction pooler 6543. postgres.js `^3.4.5` dengan opsi `{ max: 5, fetch_types: false }`, `prepare` default (tidak `false`).
- Alasan: cache Hyperdrive aktif default (`max_age` 60 s + 15 s stale) → verdict, otorisasi, dan rate limit basi di cloud, sementara test lokal tidak memakai cache. Docs Cloudflare untuk Supabase menyarankan Direct connection dan melarang `prepare: false`.
- Alternatif yang ditolak: dua binding (cache hanya untuk `/blocklist`) — menambah konfigurasi untuk manfaat kecil (blocklist sudah punya `Cache-Control`).
- File: ARCHITECTURE §2–§3, ref/R1, ref/R3 §5, TODO B4, SECURITY T14, fase-07, fase-10.

## D-alief-18 · 21 Okt 2026 · plan (verify run 01) · Penghapusan dari blocklist (usulan kontrak)

- Keputusan: usulkan field `removed: [{ domain, removedAt }]` di respons `GET /blocklist?since=` untuk domain yang tidak lagi memenuhi syarat (not_safe → safe, atau dibersihkan). Sampai disetujui: detector disarankan full refresh (`since` kosong) 1×/hari.
- Alasan: `since` hanya mengirim penambahan; domain yang batal diblokir tetap terblokir selamanya di detector.
- Dampak: kontrak Umar + detector Imelda (TODO C6).
- File: ref/R2 §5, TODO C6.

## D-alief-19 · 21 Okt 2026 · plan (verify run 01) · `owner=family` termasuk Guardian sendiri

- Keputusan: `GET /scans?owner=family` = scan milik saya + Protected aktif saya, mengikuti fixture `contracts/fixtures/activity-family.json` (memuat `dev_me`). Dikonfirmasi ke Umar (TODO C13); kalau Umar bilang tidak, cukup ubah satu filter + MockRepository.
- Alasan: fixture adalah kontrak.
- File: ref/R3 §3, fase-05, fase-09.

## D-alief-20 · 21 Okt 2026 · plan (verify run 01) · `plan/alief/` di luar folder Team App

- Keputusan: `plan/alief/` (dokumen plan Alief) adalah pengecualian tertulis atas hard rule 1. Isinya hanya dokumen; perubahan di-review Umar lewat CODEOWNERS `*` (gate G1).
- Alasan: Alief meminta plan di `plan/alief/` mengikuti struktur proyek IBM.
- File: README §4.

## D-alief-21 · 21 Okt 2026 · plan (verify run 01) · Status Protected (usulan kontrak `GET /devices/me`)

- Keputusan: usulkan `GET /devices/me` → `{ deviceId, name, avatarId, mode, language, guardian: { deviceId, name, avatarId } | null }`. Sampai disetujui: app menyimpan guardian (nama + avatar) dari respons join; `leaveGuardian()` atau 404 di endpoint keluarga menghapus `guardian.name` dari App Group; pemutusan oleh Guardian tidak terdeteksi Protected (celah tercatat).
- Alasan: kontrak tidak punya cara bagi Protected mengetahui guardian-nya setelah join atau bahwa ia sudah dihapus (PR-04, PF-01, EX-06 "Waiting for [nama]").
- File: TODO C12, fase-13, fase-14.

## D-alief-22 · 21 Okt 2026 · plan (verify run 01) · Avatar tampil setelah registrasi

- Keputusan: ON-02 hanya nama. Setelah ON-03 (`registerDevice` → `avatarId`), layar "Hi, [nama]" menampilkan avatar acak dari server.
- Alasan: `POST /devices` butuh `mode`, jadi avatar baru ada setelah ON-03; PRD hanya mensyaratkan avatar acak, bukan urutannya.
- File: fase-02.

## D-alief-23 · 21 Okt 2026 · plan (verify run 01) · Ambang Active = `AppGroup.extensionActiveWindow`

- Keputusan: app memakai `AppGroup.extensionActiveWindow` (24 jam, `ios/ShooShared/AppGroup.swift`) tanpa konstanta sendiri; server memakai jendela yang sama.
- Alasan: `ios/ShooApp/CLAUDE.md` "Do not invent another way". Nilai lain = usulan ke Umar setelah spike #2.
- File: fase-04, ref/R3 §4.

## D-alief-24 · 21 Okt 2026 · plan (verify run 01) · Revisi D-alief-02, D-alief-06, D-alief-15

- D-alief-02: diff `ios/project.yml` yang diizinkan PERSIS: (1) target baru `ShooAppTests` (`type: bundle.unit-test`, `platform: iOS`, `sources: [ShooApp/Tests]`, `dependencies: [{target: Shoo}]`), (2) target baru `ShooAppUITests` (`type: bundle.ui-testing`, `sources: [ShooApp/UITests]`, `dependencies: [{target: Shoo}]`), (3) di target `Shoo` source `ShooApp`: `excludes` ditambah `Tests/**`, `UITests/**`, `ci/**` (tetap `CLAUDE.md`), (4) scheme `Shoo`: `test.targets` = kedua target. Kunci lain tidak disentuh. Alief memutuskan agent boleh langsung membuat PR ini dan cukup memberi tahu Umar (C1); Umar tetap approver lewat CODEOWNERS. Key Info.plist/entitlement (kamera, push, Team ID) BUKAN bagian pengecualian ini → permintaan ke Umar (C3).
- D-alief-06: filter blocklist bawaan sudah diterapkan sebagai default fase 10 (R2 §5) sambil menunggu keputusan C6.
- D-alief-15: fallback diubah: tanpa data `extensionActive: true` (tidak pernah "Not connected" tanpa bukti); yang mengirim `extensionLastSeenAt` adalah extension (maks 1×/jam) + app saat foreground (C11).

## D-alief-25 · 21 Okt 2026 · plan (verify run 02) · Blocklist global lewat antrean + review manual

- Keputusan: `POST /verdicts` hanya mengisi antrean `blocklist_entries` (kelayakan disimpan saat keputusan: scan milik Protected yang terhubung, bukan allowlist). `GET /blocklist` hanya mengirim entri yang `approved_at`-nya diisi Alief/Umar lewat SQL editor (LANGKAH MANUAL berkala). `nextSince` memakai `approved_at`. `BLOCKLIST_MIN_FAMILIES` dihapus; `families` hanya membantu reviewer.
- Alasan: verify run 02 #N2: filter otomatis bisa dilewati dengan Guardian + Protected milik penyerang yang sama (dua `POST /devices` anonim), lalu domain sah terblokir untuk semua pengguna. Run 02 #N6: filter waktu `decided_at` + `having` melewatkan domain di refresh inkremental, dan filter `family_links` saat query membuat isi berubah diam-diam setelah disconnect.
- Alternatif yang ditolak: `MIN_FAMILIES = 2` + umur link/device (masih bisa dilewati dengan 4 device; tetap opsi C6).
- File: R2 §2 + §5, R3 §4 + §7, R4 §4, R7 #11, SECURITY T5, fase-07, fase-10, TODO C6. Merevisi D-alief-06/24.

## D-alief-26 · 21 Okt 2026 · plan (verify run 02) · Status `[m]` dan aturan lanjut di mode auto

- Keputusan: status baru `[m]` = fase berhenti di LANGKAH MANUAL dan belum punya PR. Mode auto melanjutkan fase `[~]`/`[m]` milik track dulu (untuk `[m]`: berhenti lagi kalau checklist LANGKAH MANUAL di log belum dicentang), baru memilih fase `[ ]` pertama. Fase yang hanya menunggu pihak luar tanpa memblokir kode (C3, iPhone, Team ID) dibuka PR-nya dengan status `[r]` + catatan "pending …"; butir itu diuji ulang di fase yang disebut file fase. Baris gate G2/G5/G6/G8 diperbarui di PROMPT langkah 1 saat status disegarkan, bukan di DoD fase.
- Alasan: verify run 02 #N1 (regresi perbaikan run 01 #7): aturan "fase pertama `[ ]`" melewati fase yang berhenti di LANGKAH MANUAL, sehingga fase 07–12 tidak pernah diverifikasi atau dibuka PR-nya. Run 02 #N7: DoD yang mewajibkan gate `[x]` tidak bisa dipenuhi karena agent tidak merge.
- File: PROMPT langkah 1 + 6h, PROGRESS legenda, README §1, fase-06Q, fase-12, fase-16.

## D-alief-27 · 21 Okt 2026 · plan (verify run 02) · Deploy cloud dari branch fase

- Keputusan: LANGKAH MANUAL deploy di fase be (07–12) dijalankan Alief dari branch fase yang belum di-review, karena cloud `shoo-demo` hanya untuk demo/uji dan Imelda butuh `GET /blocklist` lebih awal (G3). Migrasi tetap maju saja; kalau PR berubah saat review, deploy ulang dari `main` setelah merge. Deploy final (fase 12) dan QA-E2E (fase 16) memakai `main`.
- Alasan: verify run 02 §6 pertanyaan 7.
- File: fase-07, fase-10, fase-12, fase-16.

## D-alief-28 · 21 Okt 2026 · plan (verify run 02) · Revisi D-alief-24: Info.plist target test

- Keputusan: diff `ios/project.yml` yang diizinkan ditambah satu setting di kedua target test: `settings: { base: { GENERATE_INFOPLIST_FILE: YES } }`. Tidak ada kunci lain.
- Alasan: verify run 02 #N3: folder test tidak punya Info.plist, dan preset XcodeGen untuk bundle test tidak membuatnya, jadi build target test bisa gagal.
- File: fase-01, TODO C1.

## D-alief-29 · 21 Okt 2026 · plan (verify run 03) · ON-04 + spike S1/S2 masuk plan (mandat `981ad73`)

- Keputusan: mengikuti mandat terbaru Umar. ON-04 dikerjakan di fase 02 dari fallback PRD §10 (Settings umum + ilustrasi langkah + video PiP, status dari heartbeat App Group saat kembali ke app). Spike S1/S2 menjadi fase 01S (track `spike`, iPhone Alief, worktree `../Final-CH7-spike`); hasilnya menyempurnakan ON-04 (handoff ke fase 02 atau PR `feat/ON-04-refine`). Pengecualian folder: `docs/spikes/extension-status.md` + `docs/spikes/open-extension-settings.md` (diizinkan mandat). Ubahan signing lokal di `ios/project.yml` / `AppGroup.id` untuk iPhone Alief tidak pernah di-commit (pakai L0 `ios/Local.xcconfig` kalau sudah ada). C14 lama (MVP tanpa ON-04) dihapus; C14 baru = hasil spike, C15 = video PM, C3 butir 4 = `UIBackgroundModes` audio untuk PiP. Fase 17 tinggal Live Activity push.
- Alasan: verify run 03 #T1, `docs/mandates/alief.md` + `docs/spikes/README.md` di `origin/main` (`981ad73`).
- File: fase-01S (baru), fase-02, fase-05, fase-14, fase-17, PROGRESS, README §1/§3/§4/§5/§7, PROMPT (track spike), TODO B6/C3/C14/C15/D5, R1, R6, R7, VERIFY_PROMPT. Merevisi D-alief-23 (window Active diusulkan dari hasil S1).

## D-alief-30 · 21 Okt 2026 · plan (verify run 03) · Revisi D-alief-27: deploy fase 12 dan sumber build QA-E2E

- Keputusan: LANGKAH MANUAL fase 12 deploy dari branch fase 12 (seperti fase be lain), bukan dari `main`. Deploy ulang dari `main` setelah semua PR 07–12 di-merge = TODO D8, syarat G6, dicek di PROMPT langkah 1. QA-E2E memakai app dari ujung branch fase 15 (stack 13–15 boleh masih `[r]`) + backend `main` setelah D8; header laporan mencatat kedua commit + nomor build.
- Alasan: verify run 03 #T2 (fase 12 melingkar: kode cron fase 12 belum ada di `main` saat DoD-nya diperiksa) dan #S7 (QA-E2E "memakai `main`" tanpa ApiRepository/pairing/push).
- File: fase-12, fase-16, PROGRESS G6, PROMPT 6h, TODO D8.

## D-alief-31 · 21 Okt 2026 · plan (verify run 03) · Transisi status lengkap + prioritas aturan

- Keputusan: (a) PR `[r]` dengan `reviewDecision = CHANGES_REQUESTED` dipilih dulu oleh mode auto (pilihan 0: perbaiki di branch yang sama, rebase stack, status tetap `[r]`); PR `CLOSED` tanpa merge → `[!]` + tanya Alief. (b) `[!]` diset agent saat berhenti karena blocker P0 / keputusan user / PR ditutup, dibuka kembali hanya oleh Alief. (c) Resume `[m]` meneruskan Langkah kerja yang belum dicentang dulu (mis. fase 16 langkah 2–6), baru langkah 7–11. (d) Menunggu merge Umar bukan LANGKAH MANUAL. (e) File fase kalah dari PROMPT/DECISIONS yang lebih baru; plan kalah dari mandat di `origin/main`. (f) Semua gate G1–G8 diperbarui di langkah 1. Fase 11 dan 14 memakai `[r]` + "pending" untuk penantian pihak luar.
- Alasan: verify run 03 #S1, #S2, #S3, #R1.
- File: PROMPT langkah 1 + 6h + konteks, PROGRESS legenda, fase-11, fase-14.

## D-alief-32 · 21 Okt 2026 · plan (verify run 03) · Deep link `shoo://scan/<scanId>`

- Keputusan: app menangani `shoo://scan/<scanId>` → Detail (fungsi murni `NotificationRouter.route(url:)`, fase 15), dipakai popup "See detail" (EX-04, mandat Umar U2) dan "Review in Shoo" (EX-06). Format diusulkan masuk `contracts/` lewat TODO C16. Deep link hanya membuka layar, tidak pernah memicu aksi (SECURITY T15).
- Alasan: verify run 03 #S6.
- File: fase-15, R1, SECURITY T15, TODO C16.

## D-alief-33 · 21 Okt 2026 · plan (verify run 03) · Perbaikan kecil run 03

- Keputusan: grant `shoo_api` + RLS untuk `blocklist_entries` di migrasi awal fase 07 (fase 10 hanya menambah `global_eligible`); review blocklist satu domain per statement dengan `clock_timestamp()`, entri `removed_at` tidak hidup lagi otomatis, antrean review `families > 0`, review harian = TODO D9; `410 ExpiredToken` juga mengosongkan token; diff tiga titik `origin/main...HEAD` di semua cek "harus kosong"; UDID simulator alih-alih `booted` saat dua simulator menyala; `allowlist.ts` masuk R1 dengan sumbernya; override var lokal (`.dev.vars` / `miniflare.bindings`) untuk `INVITE_BASE_URL` + `PUSH_RELAY_URL`; Hyperdrive `id` placeholder sampai LANGKAH MANUAL; kolom Waktu di matriks QA; `extensionLastSeenAt` opsional di `updateMe` kalau C11 disetujui; B6/C3 memakai L0 `Local.xcconfig` + pertanyaan pemegang akun berbayar.
- Alasan: verify run 03 #S4, #S5, #R2–#R11.
- File: R1, R2, R3, R5, R7, qa/README, fase-00, 01, 07, 10, 11, 13, 14, 15, TODO.

## D-alief-34 · 21 Okt 2026 · plan (verify run 04) · Revisi D-alief-29: L0 + API extension iOS 26.2

- Keputusan: (a) signing ke iPhone sendiri hanya lewat L0 (`ios/Config/Local.xcconfig`, `main` `495c792`); fallback ubah `project.yml` / `AppGroup.id` lokal dihapus. Bundle ID dan App Group per developer, jadi plan tidak meng-hardcode `com.shoo.app` / `group.com.shoo.app`: var baru `APNS_TOPIC` (R3 §6–7), `$BUNDLE_ID` / `$APP_GROUP` dari `ref/sim.sh` untuk perintah `simctl`, payload `.apns` tanpa `Simulator Target Bundle`. Kunci APNs + Team ID + topic dari tim yang sama dengan build yang diuji (B7). (b) Tombol Turn on ON-04 memakai `SFSafariSettings.openExtensionsSettings(forIdentifiers:)` di iOS 26.2+ (fallback `openSettingsURLString` + ilustrasi); status tetap heartbeat sampai Umar menyetujui `SFSafariExtensionManager.getStateOfSafariExtension` sebagai sumber tambahan (C17). Ketersediaan di iOS 26.2 dari pembacaan docs verify run 04, BELUM DIVERIFIKASI di perangkat (uji 01S). (c) Track spike memakai prefix `D-alief-S…`, PR spike di PROMPT langkah 11, prasyarat PR fase 01 merged atau stacked, dan tidak mengubah `TurnOnExtensionView`: refine ON-04 = handoff yang dikerjakan fase 02 atau 06.
- Alasan: verify run 04 #T1, #T2, #S1, #S2, #S4.
- File: fase-01S, fase-02, fase-06, fase-11, fase-13, fase-15, fase-16, PROMPT 6g/6h/6k, README §4, TODO B6/B7/B8/C3/C17, R3, ref/sim.sh, ARCHITECTURE.

## D-alief-35 · 21 Okt 2026 · plan (verify run 04) · Mode REVIEW yang bisa selesai

- Keputusan: pilihan 0 dipicu oleh review `CHANGES_REQUESTED` atau komentar `umarmuhdhor` yang lebih baru dari catatan "review ditangani @<sha>" di log fase (`gh pr view --json state,reviews,comments,commits`), bukan oleh `reviewDecision` saja. Setelah ditangani: catatan di log + `gh pr edit --add-reviewer umarmuhdhor`, fase tidak dipilih lagi sampai ada review baru. Minta Umar mengaktifkan branch protection (C18). G0–G8 dan baris fase 00 disegarkan di langkah 1.
- Alasan: verify run 04 #T3, #R1 (`reviewDecision` tetap `CHANGES_REQUESTED` setelah push, dan bisa kosong tanpa proteksi branch).
- File: PROMPT langkah 1, PROGRESS, TODO C18.

## D-alief-36 · 21 Okt 2026 · plan (verify run 04) · Perbaikan kecil run 04

- Keputusan: PiP ON-04 lengkap (`AVAudioSession` `.playback`, pemutar full screen, delegate restore); ilustrasi Settings per versi iOS; `ops_heartbeat.source` (`cron`/`healthz`) sebagai bukti cron fase 12; review blocklist autocommit per statement; track c cukup PR merged, D8 untuk fase 16; ARCHITECTURE alur blocklist disamakan dengan D-alief-25; sel T15 diperbaiki; contoh deep link memakai id scan seed; worktree spike di fase 00; README §1 resume `[m]` disamakan.
- Alasan: verify run 04 #S3, #R2–#R10.
- File: fase-02, fase-12, fase-15, fase-00, R2, PROMPT, ARCHITECTURE, SECURITY, README, log/fase-00.

## D-alief-37 · 21 Okt 2026 · plan (verify run 05) · Perbaikan SEDANG/RENDAH run 05

- Keputusan: (a) `POST /scans` memvalidasi `domain` sebagai registrable domain (kontrak + PSL di EX-02): lowercase, tanpa `www.`, host `url` = domain atau `*.domain`; server tidak menghitung ulang PSL. (b) API status iOS 26.2 = `SFSafariExtensionManager.stateOfExtension(withIdentifier:)` / `getStateOfExtension` (`getStateOfSafariExtension` hanya macOS); merevisi D-alief-34(b). (c) Kunci APNs per environment: Sandbox untuk D7, Production untuk QA-E2E (B7). (d) Deep link mengikuti kontrak PR #1 Umar: `scan/{id}`, `activity`, `join`, default Shield; merevisi D-alief-32, C16 jadi permintaan merge. (e) Rekomendasi ON-04 dari spike ditulis di `docs/spikes/open-extension-settings.md` (ikut PR spike ke `main`), dibaca fase 02/06/06Q/16. (f) `ops_heartbeat` satu baris per `source`; mode REVIEW memakai komentar PR "Review handled @<sha> <ISO>" dan endpoint re-request reviewer; rate limit `GET /verdicts` token bucket 10/10 s + `Retry-After`; `xcodegen` sebelum `source sim.sh`; QA-E2E #18 deep link, #19 subdomain.
- Alasan: verify run 05 #S1–#S5, #R1–#R10 (verdict run 05 SIAP).
- File: R1, R2, R3, R7, SECURITY, ARCHITECTURE, PROMPT, PROGRESS, README, TODO, ref/sim.sh, fase-01S, 02, 06, 06Q, 09, 10, 11, 12, 13, 14, 15, 16.


## D-alief-38 · 21 Okt 2026 · plan · Sinkron plan dengan kontrak yang di-merge lead

- Keputusan: kontrak PR #1 (deep links), #3 (catatan extension), #4 (usulan backend), #6 (`/public-blocklist`) sudah di `main`. Plan mengikuti kontrak: `GET /devices/me` dibangun di fase 08 dan dipakai app (`me()`) di fase 13; `extensionLastSeenAt` di `PATCH /devices/me` disimpan sejak fase 07; `removed[]` di `GET /blocklist` (fase 10); Guardian lain → 403 `verdict_not_allowed` (bukan 404); kode umum `invalid_body`/`bad_json`/`too_large`/`rate_limited` + `Retry-After`/`internal`. TODO C4–C6, C9–C13, C16 ditandai diterima. Sisa izin dari Umar: C3.
- Alasan: hard rule 3 (semua JSON wajib cocok `contracts/`); teks "kalau C11/C12 disetujui" sudah usang.
- File: TODO §C, PROGRESS (fase 00, G0, G1), fase-01, 07, 08, 09, 10, 13, R2 §5, R3 §1/§4, R7 #15b.

## D-alief-39 · 21 Okt 2026 · plan · Privasi & keamanan ekosistem Apple

- Keputusan: tambah SECURITY §3 (P1–P12): privacy manifest app (fase 01), label privasi App Store (fase 16), hapus data di dalam app lewat usulan `DELETE /devices/me` (fase 06/08/13, flag sampai C19), Keychain `AfterFirstUnlockThisDeviceOnly`, ATS tanpa pengecualian umum, `os.Logger` `.private`, izin just-in-time, pasteboard `.localOnly` + kedaluwarsa, screenshot tanpa cache disk, push tanpa URL, export compliance, kebijakan privasi. PROMPT langkah 6l mewajibkannya. Permintaan ke Umar: TODO C19.
- Alasan: permintaan Alief (21 Okt): produk berjalan di ekosistem Apple dan memproses riwayat browsing berisiko, nama, dan screenshot; App Store Review 5.1.1 mewajibkan manifest, label, dan penghapusan akun.
- File: SECURITY §3 (§ lama bergeser ke §4–§6), PROMPT 6l, fase-01, 06, 08, 13, 14, 16, TODO C19.

## D-alief-B01 · 21 Okt 2026 · fase 07 · Spike APNs dari Worker cloud: lulus

- Hasil: `POST /debug/apns-spike` di Worker cloud `https://shoo-api.afindo-mi01.workers.dev` (LANGKAH MANUAL 6, log fase 07) → `{"reached":true,"status":403,"body":"{\"reason\":\"InvalidProviderToken\"}","ms":1242,"colo":"CDG"}`. APNs hanya melayani HTTP/2 dan menjawab dengan JSON `reason` miliknya, jadi `fetch()` Worker yang sudah di-deploy mencapai `api.sandbox.push.apple.com` lewat HTTP/2. `403 InvalidProviderToken` memang yang diharapkan (kunci P-256 sekali pakai, Key ID/Team ID palsu). Setelah uji: `APNS_SPIKE: "0"`, deploy ulang, endpoint → `404`.
- Keputusan: syarat D-alief-16 terpenuhi. Fase 11 memakai **`ApnsSender` langsung dari Worker sebagai jalur utama** (komponen paling sedikit: tanpa Edge Function, tanpa shared secret relay, kunci `.p8` hanya di secret Worker). `RelaySender` + Edge Function `push` hanya dibuat kalau uji push nyata di fase 11 (D7) gagal di jalur langsung; keputusan akhir dicatat di log fase 11. `LogSender` tetap untuk lokal/test tanpa secret APNs.
- Batas bukti: satu request ke sandbox dari satu colo (CDG). Belum dibuktikan: push yang diterima iPhone (butuh kunci `.p8` asli B7 + token perangkat, fase 11/15) dan endpoint Production (`api.push.apple.com`, QA-E2E B7).
- Alasan: D-alief-16 mensyaratkan bukti dari Worker cloud, bukan `wrangler dev`; bukti itu ada.
- Dampak ke tim lain / kontrak: tidak ada.
- File yang diperbarui: `plan/alief/log/fase-07.md` (hasil butir 6). Fase 11 membaca entri ini (lebih baru dari teks file fase 11 yang menyebut relay sebagai jalur utama).

## D-alief-B02 · 21 Okt 2026 · fase 07 · Tabel `rate_limit_hits` untuk batas umum

- Keputusan: batas umum R3 §5 yang bukan join (`POST /devices` 10/jam per IP, `/healthz/db` 1/menit per IP, nanti `POST /family/code`, `POST /scans`) memakai satu tabel `rate_limit_hits(bucket, key_hash, hit_at)` dengan jendela geser. `key_hash = sha256('<bucket>:<ip atau device>')`, jadi IP mentah tidak pernah disimpan. Join tetap memakai `join_attempts` (R2). Baris > 1 hari dihapus cron retensi (fase 12).
- Alasan: R3 §5 meminta batas berbasis Postgres, tetapi R2 §2 tidak punya tabel untuk batas per IP; menyimpan IP di `devices` = data pribadi tanpa guna (SECURITY §3).
- Alternatif yang ditolak: kolom `created_ip` di `devices` (menyimpan IP), KV/Durable Object (ARCHITECTURE: tanpa KV di MVP).
- Dampak ke tim lain / kontrak: tidak ada (bentuk 429 + `Retry-After` sesuai kontrak).
- File yang diperbarui: `backend/db/supabase/migrations/20261021130000_init.sql`, `backend/api/src/http/rateLimit.ts`, `backend/README.md`. R2 §2 + §6 perlu baris tambahan saat fase 12 (catatan handoff).

## D-alief-B03 · 21 Okt 2026 · fase 07 · Tanpa `sql.end()` per request; `since` lewat `::text`

- Keputusan: (a) Worker membuat client postgres.js per request dan **tidak** memanggil `sql.end()`. (b) Parameter waktu yang butuh mikrodetik (`since` di `GET /blocklist`) dikirim sebagai `${since}::text::timestamptz`, dan waktu keluaran dibentuk di SQL dengan `to_char(... 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`.
- Alasan: (a) docs Hyperdrive (connection lifecycle): koneksi Worker → Hyperdrive dibersihkan otomatis saat request selesai; `sql.end()` (polyfill socket postgres.js 3.4.9) menghasilkan unhandled rejection "This socket has been closed." di setiap request (67 error di vitest, test tetap lulus). (b) Ditemukan oleh test: postgres.js menyerialkan parameter bertipe `timestamptz` lewat `Date` JS, mikrodetik hilang, sehingga `approved_at > since` mengirim ulang domain lama. Cursor R2 §5 bergantung pada mikrodetik.
- Alternatif yang ditolak: `ctx.waitUntil(sql.end())` (error sama), `dangerouslyIgnoreUnhandledErrors` di vitest (menyembunyikan error asli).
- Dampak ke tim lain / kontrak: `nextSince`/`addedAt`/`removedAt` berformat ISO UTC dengan 6 digit pecahan detik (tetap ISO 8601).
- File yang diperbarui: `backend/api/src/app.ts`, `backend/api/src/db/repo/blocklist.ts`, test `blocklist.test.ts`.

## D-alief-B04 · 21 Okt 2026 · fase 07 · Detail kecil API fase 07

- Keputusan: (a) `PATCH /devices/me {apnsToken: null}` mengosongkan token (app memanggilnya kalau izin notifikasi dicabut); string harus hex 32–200. (b) `GET /blocklist` memakai `Cache-Control: private, max-age=300` (bukan `max-age=300` saja), karena request membawa Bearer. (c) Respons blocklist tanpa `since` tidak memuat `removed` (kontrak: opsional; full refresh sudah membuang yang dihapus); dengan `since`, `removed` selalu ada (boleh `[]`). Halaman kosong mengembalikan `nextSince = since` (sesuai `lists.js`: `next === since` = sudah sinkron). Penambahan dan penghapusan dipaging bersama berdasarkan waktu kejadian (maks 1000), jadi halaman berikutnya tidak melewatkan apa pun. (d) `test/helpers/schema.ts` (ajv + `scan-result.schema.json`) ditunda ke fase 09, saat respons ScanResult pertama ada. BELUM DIVERIFIKASI: ajv `compile` memakai `new Function`, yang mungkin ditolak workerd; kalau begitu fase 09 memakai ajv standalone (dikompilasi di Node) atau validasi di file test Node terpisah.
- Alasan: kontrak tidak mengatur detail ini; pilihan paling sederhana yang tetap sesuai `contracts/api.md`.
- Dampak ke tim lain / kontrak: tidak ada perubahan bentuk JSON.
- File yang diperbarui: `backend/api/src/routes/{devices,blocklist}.ts`, `backend/README.md`.

## D-alief-B05 · 21 Okt 2026 · fase 07 · Perbaikan dari review fase 07

- Keputusan: (a) Nama device menolak karakter kontrol (`\p{Cc}`, termasuk NUL yang ditolak Postgres → dulu 500) dan bidi override (`U+200E/F`, `U+202A–202E`, `U+2066–2069`) → 422. (b) Waktu ISO (`since`, `extensionLastSeenAt`) dibatasi tahun 1970–2100 → 422, bukan 500 dari Postgres. (c) Body JSON dibaca sebagai stream dengan penghitung byte; body chunked tanpa `content-length` berhenti di batas (413). (d) `hit()` rate limit atomik: `pg_advisory_xact_lock` per kunci di dalam transaksi. (e) Kunci rate limit IPv6 = prefix /64. (f) Migrasi baru `20261021150000_blocklist_times.sql`: CHECK `removed_at` butuh `approved_at`, `approved_at` butuh `approved_by`; trigger UPDATE memberi `approved_at`/`removed_at` = `clock_timestamp()` (approve massal = waktu unik, re-approve setelah remove = `addedAt` baru). (g) `GET /blocklist` memperpanjang halaman penuh dengan semua event yang waktunya sama dengan event terakhir, jadi seri waktu tidak pernah terpotong di batas 1000. (h) Avatar tanpa bias modulo. (i) Draf CI: `permissions: contents: read`, tidak membatalkan run di `main`, versi Supabase CLI dipatok, ref proyek lewat `env`.
- Alasan: review fase 07 (`ecc:typescript-reviewer` + `ecc:database-reviewer` 3 HIGH, `ecc:security-reviewer` 0 CRITICAL/HIGH, 4 MEDIUM). Migrasi `init` sudah di-push ke cloud, jadi tidak diubah; perbaikan skema = migrasi baru.
- Ditunda (dicatat, bukan blocker): grant `shoo_api` lebih sempit + role admin terpisah untuk approve blocklist, `statement_timeout`/`connection limit` role (fase 12 hardening); batas per IP untuk 401 berulang (fase 12); `x-spike-key` tidak constant-time (endpoint di-gate `APNS_SPIKE=0` dan dihapus fase 11); `join_attempts.ip` mentah dan `family_full` lewat pesan error (fase 08); bucket `screenshots` tanpa `file_size_limit` (fase 09); `POST /devices` menghitung rate limit sebelum validasi body (disengaja: setiap percobaan dihitung).
- Dampak ke tim lain / kontrak: tidak ada perubahan bentuk JSON. Cloud: migrasi baru + kode ini ikut deploy berikutnya (LANGKAH MANUAL fase 08); sampai itu cloud memakai kode fase 07 awal (blocklist cloud masih 0 baris, jadi tidak ada risiko cursor).
- File yang diperbarui: `backend/api/src/http/{validate,rateLimit}.ts`, `src/routes/{devices,blocklist}.ts`, `src/db/repo/blocklist.ts`, `test/{devices,blocklist}.test.ts`, `backend/db/supabase/migrations/20261021150000_blocklist_times.sql`, `tests/schema.test.sql`, `backend/ci/backend.yml`, `backend/README.md`.

## D-alief-B06 · 21 Okt 2026 · fase 08 · Detail family dan join

- Keputusan: (a) `join_attempts.ip inet` diganti `ip_hash bytea not null` = sha256(`join:<IP atau IPv6 /64>`), sama dengan `rate_limit_hits` (D-alief-B02): tidak ada IP mentah. (b) Batas join gagal: **5/10 menit per device** (tetap) dan **20/10 menit per IP** (dulu 5): operator seluler Indonesia memakai CGNAT, satu IP dibagi banyak rumah tangga, jadi 5 per IP mengunci orang tua lain karena salah ketik satu orang. Brute force tetap terbatas oleh batas device + batas `POST /devices` 10/jam per IP + kode 60 s. `too_many_attempts` membawa `Retry-After` seperti `rate_limited`. (c) Semua langkah join (R4 §2) dalam satu transaksi dengan advisory lock per device lalu per IP (urutan tetap → tanpa deadlock), lalu lock guardian; kode dicek ulang setelah lock guardian (kode bisa diganti saat menunggu). Hanya `code_invalid`/`code_expired` dicatat sebagai gagal. Race yang tersisa dipetakan: PK → `already_connected`, trigger I3 → `family_full`, FK guardian terhapus → `code_invalid`. (d) Kode baru menghapus kode lama guardian; kode kedaluwarsa yang bentrok diambil alih lewat `on conflict … where expires_at <= now()`. (e) "Jam disuntik" di test = `expires_at`/`attempted_at` digeser langsung di DB (tanpa abstraksi jam di kode). (f) `GET /join` satu bahasa per `Accept-Language` (`id…` → ID, selain itu EN); CSP lebih ketat dari R3 §4 (`+ base-uri 'none'; form-action 'none'; frame-ancestors 'none'`), plus `Cache-Control: no-store`, `Referrer-Policy: no-referrer`; parameter `code` ganda = tanpa kode. (g) `GET /family/members` diurutkan menurut waktu bergabung; `lastScan.detectedAt` ISO dengan milidetik. (h) `DELETE /devices/me` (usulan C19) aktif tanpa flag server (endpoint tambahan, tidak mengubah JSON yang ada; flag ada di app, `AppConfig.dataDeletionEnabled`). Menghapus Guardian ikut menghapus verdict yang dia buat (SECURITY §3 P3: "verdict yang dibuat/ditujukan ke device"); Protected-nya kembali tanpa Guardian. Objek screenshot dihapus setelah commit; sampai fase 09 hanya placeholder (belum ada upload), jadi P3 belum dianggap selesai sampai fase 09.
- Alasan: file fase 08, R4 §1–§2, review fase 08 (`ecc:security-reviewer` 0 CRITICAL/HIGH, 3 MEDIUM; `ecc:typescript-reviewer` + database 0 CRITICAL/HIGH, 3 MEDIUM).
- Ditunda: rem global untuk tebakan join (alarm kalau > N gagal/menit) dan pepper HMAC (secret Worker) untuk hash IP → fase 12 hardening; fail-closed kalau `cf-connecting-ip` hilang (Cloudflare selalu mengisinya) → fase 12.
- Dampak ke tim lain / kontrak: kode error tambahan `code_unavailable` (503, R3 §1) dan endpoint usulan `DELETE /devices/me` → dilaporkan di PR "Contract proposals" (TODO C19).
- File yang diperbarui: `backend/db/supabase/migrations/20261021160000_family.sql`, `backend/api/src/**` (family, join-page, devices), `ref/R3` §5, `SECURITY.md` T2, `backend/README.md`.

## D-alief-B07 · 21 Okt 2026 · fase 09 · Detail scans dan screenshot

- Keputusan: (a) `SUPABASE_URL` = **var** di `wrangler.jsonc` (bukan secret seperti tertulis di R3 §7 lama): URL proyek Supabase publik dan sudah ada di banyak file plan. Yang rahasia hanya `SUPABASE_SERVICE_ROLE_KEY`. (b) Storage dipanggil lewat REST dengan header `apikey` + `Authorization: Bearer` (keduanya kunci yang sama); terverifikasi lokal dengan `sb_secret_…` dan JWT `service_role`. Upload `POST /storage/v1/object/screenshots/<path>`, signed URL `POST /storage/v1/object/sign/screenshots/<path> {expiresIn: 3600}` (respons relatif → diawali `${SUPABASE_URL}/storage/v1`), hapus `DELETE /storage/v1/object/screenshots {prefixes}`; timeout 5 s. (c) ajv 2020 + ajv-formats jalan di workerd lewat `@cloudflare/vitest-plugin` → D-alief-B04(d) terjawab, test memvalidasi respons dengan `contracts/schemas` langsung. (d) Screenshot: base64 ketat, magic bytes JPEG/PNG, dimensi dibaca dari header (PNG IHDR, JPEG SOFn), sisi > 1280 px dibuang; semua alasan buang dicatat `screenshot_dropped {reason}` tanpa isi. Bucket juga membatasi `file_size_limit 153600` + `image/jpeg,image/png` (migrasi `20261021170000_screenshot_bucket.sql`). (e) Dedupe + kuota + reservasi path dalam satu transaksi dengan `pg_advisory_xact_lock(3, hashtext(owner))`: upload paralel tidak bisa melewati 50/24 jam. Path ditulis sebelum upload; gagal upload → path dikosongkan; scan terhapus selama upload (DELETE /devices/me) → objek dihapus. (f) Teks bebas dari detector (`pageTitle`, `signals[].evidence`, `label.en/id`) dibersihkan dari karakter kontrol dan bidi (sama dengan D-alief-B05 a), bukan ditolak: extension tidak bisa memperbaiki judul halaman penipu. (g) Push: `guardianPush` membaca Guardian + token selama request; hanya `send` di `waitUntil`. `pushSender` = `LogSender` sampai fase 11 (`TODO(sync:alief)`). (h) Cursor `GET /scans` = base64url(`detected_at mikrodetik|id`), keyset `(detected_at, id) <`. (i) Lokal: setelah `supabase link`, `.temp/storage-version` mematok versi Storage cloud; container lama harus di-restart (`supabase stop && supabase start …`) atau upload gagal `42P10`.
  (j) Upload gagal → path dikosongkan di **semua** scan owner yang menunjuknya (dedupe bisa sudah memakainya), objek dihapus juga (upload yang timeout bisa tetap tersimpan). (k) Kegagalan lookup push dan screenshot tidak pernah membuat `POST /scans` 500 (scan sudah tersimpan; retry = duplikat). `url` dengan karakter kontrol/bidi → 422 (NUL ditolak Postgres). `signals[].id` = string 1–64 bebas (kontrak tanpa pola). Index parsial `scans_owner_shot` untuk kuota/dedupe. (l) Screenshot di-upload dengan `cache-control: no-store` (disimpan di metadata objek, dikirim Storage di setiap GET signed URL). Smoke cloud: tanpa header, Storage memakai default `max-age=3600` dan signed URL masih 200 setelah `DELETE /devices/me` padahal `storage.objects` sudah kosong (salinan CDN). Ditolak: menerima jendela ≤ 1 jam (data dihapus harus benar-benar hilang, SECURITY §3 P3); signed URL lebih pendek (tetap ada jendela, dan Detail butuh URL yang tahan selama layar dibuka). Lokal Storage menyimpan setting (`object/info` → `cache_control`) tetapi tidak mengirim header lewat Kong, jadi test memeriksa metadata; cek header nyata = LANGKAH MANUAL fase 09 (b).
- Alasan: file fase 09, R3 §4, review fase 09 (`ecc:security-reviewer` 0 CRITICAL/HIGH, 3 MEDIUM; `ecc:typescript-reviewer` 0 CRITICAL, 2 HIGH; `ecc:database-reviewer` 0 CRITICAL, 1 HIGH + 1 untuk fase 12), semua HIGH diperbaiki dengan test.
- Ditunda: retensi 14 hari (fase 12) harus menghapus objek hanya kalau tidak ada scan tersisa yang menunjuk path itu (akibat dedupe).
- Dampak ke tim lain / kontrak: tidak ada perubahan bentuk JSON. Cloud: secret `SUPABASE_SERVICE_ROLE_KEY`, migrasi bucket, deploy (LANGKAH MANUAL fase 09).
- File yang diperbarui: `backend/api/src/**` (scans, images, screenshots, push), `backend/db/supabase/migrations/20261021170000_screenshot_bucket.sql`, `tests/storage.test.sql`, `ref/R3` §7, `backend/README.md`.

## D-alief-B08 · 21 Okt 2026 · fase 09 · Screenshot hanya lewat Worker (privasi Apple)

- Keputusan (Alief: "so lets follow apple privacy"): screenshot yang dihapus atau diputus aksesnya harus **langsung** tidak bisa dilihat, bukan setelah TTL. (a) `screenshotUrl` di `GET /scans/{id}` = link Worker `<origin>/screenshots/{scanId}?v=<viewerDeviceId>&exp=<unix>&sig=<base64url HMAC-SHA256("screenshot:v1|scanId|viewer|exp")>`, berlaku 1 jam (kontrak "valid 1 h" tetap). Kunci = secret `SCREENSHOT_URL_SECRET`; kosong → `screenshotUrl` null. (b) `GET /screenshots/{scanId}` tanpa Bearer (app memuat dengan AsyncImage/URLSession biasa): sig dicek dengan `crypto.subtle.verify` (konstan-waktu), exp ≤ now + 1 jam + 60 s, lalu **setiap request** query DB: scan ada, punya screenshot, viewer = pemilik atau Guardian saat ini (`family_links`). Baru objek dialirkan dari Storage (`/object/authenticated/…`, service key) dengan `Cache-Control: private, no-store`, `nosniff`, CSP `sandbox`, `no-referrer`. Gagal apa pun → 404 (juga `no-store`). Tidak pernah redirect ke URL Supabase. (c) Origin link = `INVITE_BASE_URL` (URL Worker yang dipatok di `wrangler.jsonc`), bukan Host request. (e) Fetch Worker → Storage `cache: "no-store"`: path dedupe bisa dipakai beberapa scan, jadi salinan cache tidak boleh tersaji. (f) Rate limit `screenshots_view` 120/menit per viewer (setelah sig sah, sebelum DB). (g) `sig` harus encoding base64url kanonik. Ditunda: device id viewer + sig tampak di log URL Cloudflare Workers Logs (link bearer ≤ 1 jam dan tetap dicek DB; alias acak = fase 12 hardening kalau perlu); signed URL Supabase yang dibagikan sebelum deploy ini hidup ≤ 1 jam (satu kali). (d) Signed URL Supabase tidak dipakai lagi; `cache-control: no-store` saat upload (D-alief-B07 l) tetap, tidak merugikan.
- Alasan: review `ecc:security-reviewer` 0 CRITICAL/HIGH (2 MEDIUM, 4 LOW, semua MEDIUM diperbaiki). Smoke cloud fase 09 (b): CDN Supabase (Free, tanpa purge Smart CDN) meng-cache respons signed URL sampai kedaluwarsa dan mengabaikan `cacheControl` objek → `200` dari cache setelah `DELETE /devices/me` (SECURITY §3 P3, T6). Cek DB per request membuat hapus, retensi 14 hari, dan disconnect berlaku seketika.
- Alternatif yang ditolak: signed URL Supabase dengan TTL pendek (60–300 s): jendela tetap ada, dan Detail yang terbuka lama kehilangan gambar; Bearer di request gambar: AsyncImage tidak bisa mengirim header, dan token device tidak boleh masuk URL.
- Dampak ke tim lain / kontrak: bentuk JSON sama (string URL, 1 jam, `null` di daftar). Teks `contracts/api.md` menyebut "signed URL" → catatan untuk Umar (TODO C20, draf). App (fase 13): muat `screenshotUrl` apa adanya, cache memori saja (SECURITY P9). Cloud: secret baru + deploy = LANGKAH MANUAL fase 09 (c).
- File yang diperbarui: `backend/api/src/routes/screenshots.ts`, `src/services/{screenshotLinks,screenshots,scans}.ts`, `src/db/repo/scans.ts` (`screenshotPathForViewer`), `src/http/{crypto,validate}.ts`, `src/routes/scans.ts`, `src/app.ts`, `src/env.ts`, `.dev.vars.example`, `vitest.config.ts`, `test/screenshots.test.ts`, `test/scans.test.ts`, `ref/R3` §4 + §7, `SECURITY.md` T6 + P9, `ARCHITECTURE.md`, `TODO.md` B5 + C20, `backend/README.md`.

## D-alief-B09 · 21 Okt 2026 · fase 09 · Cek privasi Apple P1–P13 (D-alief-40)

- Keputusan (aturan Alief D-alief-40, PR #12, P13): (a) Middleware `app.ts` memberi **default `Cache-Control: private, no-store`** ke setiap respons (sukses dan error): JSON API memuat token, nama, URL, scan, kode undangan. Route tanpa data pengguna boleh menimpa: hanya `GET /blocklist` (`private, max-age=300`, daftar domain global). (b) Log tanpa id: `scanId` diganti `requestId`, error handler mencatat pola route, `push_logged` tanpa id. (c) Workers invocation logs dimatikan (`observability.logs.invocation_logs: false`): log bawaan itu mencatat URL lengkap, termasuk `v`/`sig` link screenshot dan `?code=` undangan; log JSON kita sendiri tetap. (d) Device id viewer di link screenshot (`v`) tetap: UUID acak tanpa informasi pribadi, dibutuhkan server untuk cek akses, link tetap dicek DB setiap request, dan tidak lagi tercatat di log bawaan (c).
- Alasan: P13 meminta respons berisi data pengguna memakai `private, no-store`; tanpa header, `URLCache` iOS default boleh menyimpan respons GET ke disk (bertahan setelah hapus data). "Kalau ragu, pilih opsi paling menjaga privasi" → (b) dan (c).
- Alternatif yang ditolak: header hanya di route tertentu (mudah terlewat di route baru); mengenkripsi device id di link (kerumitan tanpa manfaat setelah (c)).
- Dampak ke tim lain / kontrak: tidak ada perubahan JSON. App (fase 13) tidak perlu kebijakan cache sendiri untuk API, tetapi tetap cache memori saja untuk gambar (P9). Debug cloud: invocation logs tidak ada lagi; pakai `x-request-id` + log JSON.
- File yang diperbarui: `backend/api/src/app.ts`, `src/routes/scans.ts`, `src/services/push/sender.ts`, `wrangler.jsonc`, `test/cache-headers.test.ts`, `plan/alief/log/fase-09.md`.
