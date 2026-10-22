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

## D-alief-A01 · 22 Okt 2026 · app (fase 01) · Hook uji di `MockRepository` dan launch argument

- Keputusan: error kontrak join dipicu kode ajaib (`0000` code_invalid, `9999` code_expired, `8888` family_full, `7777` too_many_attempts, `6666` already_connected). Skenario `-mock.scenario empty` untuk empty state. Launch argument `-settings.language`, `-settings.mode`, `-settings.onboardingCompleted` (domain argumen `UserDefaults`) untuk UI test dan screenshot; galeri komponen hanya di DEBUG (`-debug.gallery YES`).
- Alasan: fase 01 langkah 3 meminta error kontrak bisa dipicu untuk preview/test; launch argument tidak menambah kode produksi di luar DEBUG kecuali pembacaan `UserDefaults` yang memang dipakai.
- File: `ios/ShooApp/Data/MockRepository.swift`, `App/AppEnvironment.swift`, `App/AppSettings.swift`, `App/RootView.swift`, `UITests/SmokeUITests.swift`.

## D-alief-A02 · 22 Okt 2026 · app (fase 01) · Bahasa in-app lewat `\.locale` + helper `L10n`

- Keputusan: `RootView` memasang `.environment(\.locale, settings.language.locale)`. `Text("literal")` dan `Label("literal", …)` ikut. Teks yang dibangun sebagai `String` (view model, nilai aksesibilitas, judul navigasi) memakai `L10n.string(_:language:)` = `String(localized:bundle:locale:)` dengan bundle `<code>.lproj`. `navigationTitle(Text(_:))` tidak ikut berganti saat bahasa diganti live (UI test `testLanguageSwitchesLiveFromProfile` gagal), jadi judul memakai `navigationTitle(localized:)`.
- Alasan: fase 01 langkah 5 (BELUM DIVERIFIKASI → sekarang terbukti oleh `LocalizationTests` + `SmokeUITests`). Bahasa app terpisah dari bahasa iPhone (PF-01); extension tetap mengikuti bahasa iPhone.
- File: `Support/L10n.swift`, `Support/AppLanguage.swift`, `App/RootView.swift`, `Tests/LocalizationTests.swift`, `UITests/SmokeUITests.swift`.

## D-alief-A03 · 22 Okt 2026 · app (fase 01) · `SiteIcon` = monogram, favicon tidak diunduh

- Keputusan: `SiteIcon` menampilkan huruf pertama domain; `faviconUrl` dari kontrak tidak dimuat.
- Alasan: memuat favicon berarti app menghubungi host yang dicurigai penipuan (bocor IP + "pernah dibuka" ke pelaku) dan menyimpan gambarnya di cache disk. Opsi paling privat (SECURITY §3, sejalan P9). Fase 01 langkah 7 mengizinkan "favicon atau huruf awal domain".
- File: `Components/SiteIcon.swift`.

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

## D-alief-40 · 21 Okt 2026 · plan · Keamanan & privasi Apple wajib untuk semua pekerjaan

- Keputusan: aturan PROMPT 6l diperluas dari "fase app" menjadi semua pekerjaan (app, backend, plan, langkah manual, QA); review langkah 8 wajib mencocokkan diff dengan SECURITY §3; tambah P13 "hapus = langsung hilang" (tanpa salinan cache/CDN); aturan emas README #10; baris aturan di `backend/CLAUDE.md` dan `ios/ShooApp/CLAUDE.md`.
- Alasan: permintaan Alief (21 Okt): "add a rule, everything we do must follow apple security & privacy". Pemicu: uji asap fase 09 menunjukkan screenshot yang sudah dihapus masih tersaji dari CDN Supabase sampai signed URL kedaluwarsa (log fase-09 (b)).
- File: PROMPT 6l + langkah 8, README §6, SECURITY §3 (P13), `backend/CLAUDE.md`, `ios/ShooApp/CLAUDE.md`.

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

## D-alief-B10 · 22 Okt 2026 · fase 10 · Verdicts, antrean blocklist, privasi putus hubungan

- Keputusan: (a) `POST /verdicts`: Guardian boleh memutus scan miliknya sendiri dan scan Protected yang **saat ini** terhubung; Protected → 403 `forbidden`; scan tidak ada / id bukan UUID / FK hilang di tengah request → 404; bukan pemilik/Guardian-nya → 403 `verdict_not_allowed`; bukan `blocked` → 409 `verdict_not_allowed` (urutan kontrak; 403 vs 404 membuka keberadaan UUID acak, risiko diterima, sama dengan kontrak). `by_name` = nama Guardian saat itu, `decided_at = clock_timestamp()`. 60/menit per Guardian. (b) Urutan lock di mana pun: baris `family_links` (`for share` di verdict, hapus di disconnect) → advisory lock domain `(4, hashtext(domain))` terurut. (c) Kelayakan antrean (snapshot saat keputusan): `not_safe`, pemilik Protected yang terhubung, bukan allowlist (`src/data/allowlist.ts`: bank/e-wallet/layanan publik/populer + sufiks `go.id`, `ac.id`, …, subdomain ikut) dan bukan sufiks publik/host bersama (`co.id`, `github.io`, `vercel.app`, … persis), dan Guardian belum mengantrekan 10 domain lain dalam 24 jam. Verdict keluarga tetap langsung berlaku walau tidak layak antre. (d) **Privasi (D-alief-40, P13):** putus hubungan (`DELETE /family/members/{id}`, `DELETE /family/guardian`) dan `DELETE /devices/me` menghapus verdict Guardian lama untuk member itu (nama + id Guardian tidak lagi terlihat; halaman kembali menunggu keputusan baru), lalu `families` dihitung ulang. Entri yang sudah disetujui tetap disajikan (hanya `families` berubah), jadi isi `GET /blocklist` tidak berubah diam-diam (tujuan snapshot D-alief-25 tetap). (e) `GET /verdicts?domain=`: trim + lowercase + tanpa titik akhir + tanpa `www.`, regex domain sama dengan `POST /scans`, 30 req / 10 s per device (DB, `Retry-After`). (f) Antrean: lock per Guardian `(5, guardian)` sebelum lock domain (batas 10/24 jam tahan paralel); konfirmasi ulang domain yang sudah antre tidak dihitung baru; baris antrean yang belum disetujui dan tidak didukung lagi **dihapus** (domain riwayat browsing tidak disimpan tanpa guna, D-alief-40); baris disetujui/dihapus reviewer tetap sebagai catatan. CHECK `global_eligible` hanya untuk `not_safe`. Deadlock/serialisasi → `POST /verdicts` dicoba ulang sekali. (g) **Deviasi latensi (cloud 22 Okt):** DoD p95 < 300 ms untuk `GET /verdicts` belum tercapai dari klien uji di Indonesia (p95 total 1547 ms, server 741 ms; `/healthz` tanpa DB sudah p50 115 ms). Perbaikan murah dalam fase ini: rate limit lookup jadi satu statement (`hitLight`, 4 → 1 round trip). Sisanya (Smart Placement, gabung query auth + verdict, cek Hyperdrive) dipindah ke fase 12; fungsi (verdict terlihat di GET pertama) sudah lulus. Extension mem-poll tiap 5 s dan memakai koneksi ulang, jadi latensi ini menunda tampilan, bukan membuka blokir yang salah.
- Alasan: file fase 10, R2 §5, D-alief-25; review `ecc:security-reviewer` (0 CRITICAL, 1 HIGH: verdict + nama Guardian lama tetap terbaca setelah disconnect; 4 MEDIUM: TOCTOU link, `families` basi saat cascade, banjir antrean, batas lookup terlalu ketat untuk beberapa tab); `ecc:typescript-reviewer` 0 CRITICAL/HIGH (2 MEDIUM); `ecc:database-reviewer` 0 CRITICAL/HIGH (2 MEDIUM). File fase menulis "disconnect setelah verdict → `global_eligible` tetap (snapshot)": diganti karena aturan privasi Alief lebih tinggi (pelanggaran = TINGGI); daftar yang disajikan tetap stabil.
- Alternatif yang ditolak: menyaring verdict saat dibaca (data Guardian lama tetap tersimpan tanpa guna); 10/10 s untuk lookup (5+ tab polling 5 s → 429 bagi orang yang justru menunggu); batas umur device untuk `families` (lebih rumit, review manual tetap gerbang utama).
- Dampak ke tim lain / kontrak: tidak ada perubahan JSON. C8 (draf) menyebut 30/10 s dan verdict hilang setelah putus hubungan. Reviewer antrean: `families` = petunjuk, bukan bukti (SECURITY T5).
- File yang diperbarui: `backend/api/src/routes/verdicts.ts`, `src/db/repo/{verdicts,families,devices}.ts`, `src/data/allowlist.ts`, `src/http/{errors,rateLimit,validate}.ts`, `src/routes/scans.ts`, `src/app.ts`, `backend/db/supabase/migrations/20261021180000_verdicts.sql`, `tests/verdicts.test.sql`, `test/verdicts.test.ts`, `ref/R3` §4–§5, `SECURITY.md` T5 + T10, `TODO.md` C8 + D4, `backend/README.md`.

## D-alief-A04 · 22 Okt 2026 · app (fase 02) · Alur onboarding hanya maju, titik lanjut setelah relaunch

- Keputusan: `OnboardingModel` hanya maju: splash → nama → mode → sapaan → (Connect, Protected) → ON-04 → ON-05. Mode disimpan sekali lewat `AppSettings.chooseMode` (setter `mode` jadi `private(set)`). Relaunch sebelum selesai: mode belum ada → splash; Protected yang belum melewati Connect → Connect (`settings.onboardingConnectPassed`); selain itu → ON-04. Token registrasi tidak disimpan di model (fase 13: Keychain + App Group, `TODO(sync:alief)` di `AppEnvironment.register`).
- Alasan: fase 02 langkah 3 ("tidak ada jalan kembali ke ON-03") + temuan review H2 (Protected yang menutup app di Connect tidak boleh melewatkannya).
- File: `Features/Onboarding/OnboardingModel.swift`, `App/AppSettings.swift`, `App/AppEnvironment.swift`, `Tests/OnboardingTests.swift`.

## D-alief-A05 · 22 Okt 2026 · app (fase 02) · Hook uji onboarding (DEBUG)

- Keputusan: launch argument DEBUG `-UITestReset YES` (hapus preferensi app), `-UITestExtensionActive YES` (status extension dianggap Active tanpa menulis App Group asli), `-UITestNotifications granted|denied` (jawaban izin tetap, tanpa alert sistem), `-debug.onboardingStep <step>` (screenshot gerbang UI). Semua di dalam `#if DEBUG`.
- Alasan: simulator tidak punya heartbeat extension, dan alert izin sistem tidak bisa direset per test untuk notifikasi; UI test harus deterministik. Catatan review: key `-settings.*` lewat domain argumen `UserDefaults` juga terbaca di Release, tapi hanya bisa diset oleh orang yang menjalankan app dari Xcode/`devicectl`.
- File: `App/AppEnvironment.swift`, `Support/NotificationPermission.swift`, `Features/Onboarding/OnboardingFlow.swift`, `UITests/OnboardingUITests.swift`.

## D-alief-A06 · 22 Okt 2026 · app (fase 02) · ON-04: langkah per versi iOS + `SFSafariSettings`

- Keputusan: iOS 26.2+ → `SFSafariSettings.openExtensionsSettings(forIdentifiers: [bundleId + ".extension"])` (API dicek di header `SafariServices/SFSafariSettings.h` SDK iOS 27.1: `API_AVAILABLE(ios(26.2))`, dipanggil saat foreground); gagal atau iOS lebih lama → `UIApplication.openSettingsURLString`. Tidak ada `App-prefs:`. Langkah bergambar (SF Symbols) per versi: 26.2+ "Tap Turn on", 18+ "Settings › Apps › Safari › Extensions", 17 "Settings › Safari › Extensions". Nama menu Pengaturan berbahasa Indonesia dan perilaku di perangkat BELUM DIVERIFIKASI (01S / QA-E2E #17).
- Alasan: fase 02 langkah 4; ID extension tidak di-hardcode (L0).
- File: `Features/Onboarding/ExtensionSetup.swift`, `TurnOnExtensionView.swift`.

## D-alief-A07 · 22 Okt 2026 · app (fase 02) · Video tutorial placeholder + PiP

- Keputusan: `Resources/onboarding-tutorial-placeholder.mp4` (4 s warna polos, ±4 KB, dibuat dengan ffmpeg) sampai video PM ada (C15, `TODO(sync:umar)`). Pemutar `AVPlayerViewController` layar penuh, `allowsPictureInPicturePlayback`, `AVAudioSession .playback/.moviePlayback` saat dibuka dan dinonaktifkan saat ditutup. PiP di luar app (di atas Settings) butuh `UIBackgroundModes: [audio]` = TODO C3 butir 4 (Umar); sampai itu video hanya diputar di dalam app.
- Alasan: fase 02 langkah 4, risiko "Video PM belum ada".
- File: `Features/Onboarding/TutorialVideoPlayer.swift`, `Resources/onboarding-tutorial-placeholder.mp4`.

## D-alief-A08 · 22 Okt 2026 · app (fase 02) · Izin notifikasi dan pengingat

- Keputusan: izin diminta di ON-05 dengan `[.alert, .sound]` (payload push tanpa badge). Guardian tidak bisa melewati ON-05 tetapi tetap lanjut kalau menolak; Protected boleh "Nanti saja". Banner pengingat di Shield hanya untuk Guardian (hanya Guardian yang menerima push menurut kontrak); belum pernah ditanya → tombol memunculkan prompt, ditolak → membuka Settings notifikasi app. `registerForRemoteNotifications()` setelah izin diberikan; token dikirim di fase 15. Tidak ada dialog konfirmasi tambahan untuk mode permanen: PRD hanya meminta teks peringatan (saran review MEDIUM, dicek ulang di QA-A).
- Alasan: fase 02 langkah 5, SECURITY §3 P7 (just-in-time, teks jujur).
- File: `Support/NotificationPermission.swift`, `Components/NotificationReminderBanner.swift`, `Features/Onboarding/NotificationPermissionView.swift`, `Features/Shield/ShieldPlaceholderView.swift`.

## D-alief-B11 · 22 Okt 2026 · fase 11 · Push APNs langsung dari Worker, `push_log` tanpa teks

- Keputusan: (a) **Jalur push = `ApnsSender` langsung dari Worker** (D-alief-B01 lebih baru dari teks relay di file fase 11): tidak ada Edge Function `push`, `RelaySender`, `PUSH_RELAY_*`, atau test Deno. Relay hanya dibuat kalau uji iPhone nyata (D7) gagal di jalur langsung. Secret APNs (`APNS_KEY_P8_B64`, `APNS_KEY_ID`, `APNS_TEAM_ID`) di Worker; `APNS_TOPIC` + `APNS_ENV` = var. Salah satu kosong / `APNS_ENV` bukan `sandbox|production` → `LogSender` (`push_log` `logged`), peringatan sekali per isolate berisi nama saja. (b) JWT ES256 di-cache per isolate per `keyId:teamId` (maks 50 menit, single flight; 403 `ExpiredProviderToken` membuang hanya token yang dipakai send itu). Header `apns-expiration` = +1 jam, timeout 5 s, tanpa retry. Token device divalidasi hex sebelum masuk path URL. (c) **Privasi (D-alief-40):** kolom `push_log.body` dihapus (menyalin nama Protected ke tabel kedua dan basi setelah ganti nama; teks bisa dibangun ulang dari `scan_id`); `push_log.result` dibatasi CHECK ke kode pendek (`sent`, `logged`, `failed:<3 digit>[ <Reason>]`, `failed:timeout|network|config`) supaya token/JWT tidak mungkin tersimpan; insert `push_log` memakai `FOR KEY SHARE` pada device + scan (scan/Guardian yang dihapus di tengah pengiriman tidak meninggalkan baris; 23503 ditelan). Log hanya nama error + SQLSTATE (`errorInfo`), tidak pernah pesan error (bisa memuat URL berisi token atau nilai SQL). (d) Batas lunak 10 push / 10 menit per Guardian (review keamanan M1): satu device berpasangan tidak bisa membanjiri lock screen; scan tetap tersimpan, hanya push dilewati. Lunak: scan paralel bisa melewati sedikit (baris ditulis setelah kirim); `POST /scans` 120/jam per device tetap batas keras. (e) 410 `Unregistered`/`ExpiredToken` → `apns_token` dikosongkan compare-and-clear (token yang didaftarkan ulang di tengah jalan tetap); 400 `BadDeviceToken` → token tetap (R3 §6).
- Alasan: file fase 11, D-alief-16, D-alief-B01, R3 §6; review `ecc:security-reviewer` (0 CRITICAL/HIGH; M: banjir push per Guardian), `ecc:typescript-reviewer` (0 CRITICAL/HIGH; M: referensi JWT per send, test log kosong, DB di `waitUntil`), `ecc:database-reviewer` (0 CRITICAL/HIGH; M: race FK `push_log`, CHECK `not valid` + `validate`). Bukti lokal: `wrangler dev` dengan kunci P-256 sekali pakai → `push_log` `failed:network` karena workerd lokal memakai HTTP/1.1 (curl: APNs sandbox `--http2` → 403, `--http1.1` → koneksi ditolak); jalur HTTP/2 dari Worker cloud sudah terbukti di D-alief-B01, dan diulang di LANGKAH MANUAL fase 11.
- Alternatif yang ditolak: relay Edge Function sebagai jalur utama (komponen + secret tambahan tanpa kebutuhan setelah B01); `apns-collapse-id` (menggabungkan push beda scan, Guardian kehilangan scanId lama); batas keras dengan baris `pending` sebelum kirim (perlu nilai `result` baru + update kedua; batas lunak cukup untuk MVP).
- Dampak ke tim lain / kontrak: tidak ada perubahan JSON. Payload = kontrak + `sound` (C9 sudah diterima). Fase 15 langkah 4 membangun ulang teks push dari `scan_id` bila perlu, bukan dari `push_log`.
- File yang diperbarui: `backend/api/src/services/push/{apns,sender,deliver,notify}.ts`, `src/db/repo/push.ts`, `src/http/logError.ts` (+ pemakaiannya), `src/routes/scans.ts`, `src/env.ts`, `src/app.ts` (route spike dihapus), `wrangler.jsonc`, `.dev.vars.example`, `vitest.config.ts`, migrasi `20261022100000_push_log_privacy.sql` + `tests/push_log.test.sql`, test `push-apns`, `push-deliver`, `push-notify`, `logError`, `apns`; `ref/R1`, `R2`, `R3` §6–§7, `R4`, `TODO.md` B5/B7, `backend/README.md`.

## D-alief-A30 · 22 Okt 2026 · app (fase 03) · Tombol verdict tetap tampil, menempel di bawah, optimistic + rollback

- Keputusan: Guardian melihat It's safe / Not safe di setiap item `blocked` (milik sendiri dan Protected-nya), juga setelah ada verdict (pilihan aktif ditandai isian lebih kuat + garis tepi + trait `isSelected`; menekan yang lain = ganti keputusan, sesuai `POST /verdicts` "keputusan terakhir menang"). Bar tombol menempel di bawah (`safeAreaInset`) supaya selalu terjangkau. Tanpa dialog (PRD §5, GD-07). Verdict optimistic (`byDeviceId`/`byName` = viewer, waktu sekarang), diganti hasil server; gagal → kembali ke verdict sebelumnya + pesan di bawah tombol. Tombol dikunci selama request (tap ganda diabaikan). Item `warning` tidak punya tombol (kontrak `verdict_not_allowed`).
- Alasan: PRD tidak menyebut apakah keputusan bisa diubah; kontrak dan backend (I6) mengizinkan, jadi opsi paling sederhana = tombol yang sama tetap ada.
- File: `Features/Detail/{DetailModel,VerdictButtons,DetailView}.swift`, `Tests/DetailModelTests.swift`.

## D-alief-A31 · 22 Okt 2026 · app (fase 03) · Link tidak pernah dibuka dari app; salin = teks biasa, perangkat ini saja

- Keputusan: DT-03 menampilkan URL lengkap sebagai teks (`Text(verbatim:)`, bukan link) untuk semua status, bukan hanya `blocked`. Tombol "Copy link" menulis `public.plain-text` saja ke `UIPasteboard` dengan `.localOnly: true` (tidak ke Universal Clipboard) dan `.expirationDate` = 5 menit (review keamanan L4: URL riwayat browsing tidak tinggal di pasteboard tanpa batas).
- Alasan: membuka situs penipuan dari app melewati alur extension; plan meminta "tidak bisa dibuka langsung untuk scan blocked", dan item warning pun tetap berisiko. P8 (`localOnly`) diterapkan juga di sini karena URL termasuk riwayat browsing (P2).
- File: `Features/Detail/{LinkCopy,DetailView}.swift`, `Tests/DetailPrivacyTests.swift`.

## D-alief-A32 · 22 Okt 2026 · app (fase 03) · Screenshot bukti: sesi ephemeral tanpa cache, tanpa share/simpan

- Keputusan: `ScreenshotView` memuat `screenshotUrl` (link Worker, D-alief-B08) lewat `URLSessionScreenshotLoader`: `URLSessionConfiguration.ephemeral`, **tanpa `URLCache`** (`urlCache = nil`, `reloadIgnoringLocalAndRemoteCacheData`; gambar hanya ada selama view Detail memegangnya), tanpa cookie/kredensial/`Authorization`, hanya host `AppConfig.apiBaseURL` + path `/screenshots/` (review keamanan M2), redirect tidak diikuti, HTTPS saja (HTTP hanya `localhost` di DEBUG), status 200 + body dibaca streaming dan berhenti di > 2 MB + header gambar dibaca dulu: sisi > 4096 px ditolak (decompression bomb, review keamanan M1), lalu didekode sekali dengan downsampling `CGImageSourceCreateThumbnailAtIndex` (maks 2048 px). Review swift (M5): cache memori 8 MB sempat dipakai, tapi itu menyimpan gambar sepanjang umur proses sehingga screenshot yang sudah dihapus/diputus masih bisa tampil saat Detail dibuka ulang (P13). Gagal/404 → "Screenshot isn't available anymore" + Try again (P13: setelah hapus/retensi/disconnect link langsung 404). `nil` → blok disembunyikan. Layar zoom (pinch, ketuk dua kali, tombol tutup) tanpa `ShareLink`, `contextMenu`, atau simpan. Untuk `MockRepository` (DEBUG) gambar diganti `FixtureScreenshotLoader` karena URL fixture `example.invalid` tidak pernah resolve.
- Alasan: SECURITY §3 P9 + P13. Server sudah mengirim `Cache-Control: private, no-store` (D-alief-B09); disk 0 di sisi app membuat itu tidak bergantung pada header.
- File: `Features/Detail/ScreenshotView.swift`, `Tests/DetailPrivacyTests.swift`.

## D-alief-A33 · 22 Okt 2026 · app (fase 03) · Nama pemilik di Detail

- Keputusan: baris "Opened by" tampil untuk Guardian bila scan milik orang lain (Protected-nya), atau bila Family mode menyala (scan sendiri → "You"). Protected tidak pernah melihatnya.
- Alasan: PRD DT-03 "Nama pemilik (Family mode)"; Detail juga dibuka dari push (fase 15) tanpa konteks toggle, jadi scan milik anggota keluarga selalu menyebut namanya.
- File: `Features/Detail/{DetailModel,DetailView}.swift`.

## D-alief-A34 · 22 Okt 2026 · app (fase 03) · Bukti: bobot untuk kedua mode, field `evidence` tidak ditampilkan

- Keputusan: maks 3 sinyal, bobot terbesar dulu, bobot sama = urutan kontrak. Guardian `label`, Protected `labelSimple`, keduanya dengan "+NN%" (PRD: "sinyal dan bobotnya"; yang lebih sederhana untuk Protected adalah bahasanya). Field `Signal.evidence` (teks yang di-highlight extension) tidak ditampilkan di app.
- Alasan: opsi paling sederhana yang memenuhi DT-04; `evidence` milik alur highlight extension (EX-05) dan bisa berisi potongan teks halaman.
- File: `Features/Detail/EvidenceList.swift`.

## D-alief-A35 · 22 Okt 2026 · app (fase 03) · `-debug.detail <scanId>` dan cakupan gerbang UI Protected

- Keputusan: launch argument DEBUG `-debug.detail <scanId>` membuka Detail di tab aktif (UI test + screenshot), satu blok di `AppEnvironment.live`. Gerbang UI Protected memakai 3 fixture milik `dev_mom` (`warning-41`, `blocked-92`, `blocked-marked-safe`); `warning-63` (milik Guardian) dan `blocked-verified-scam` (milik Dad) memang 404 untuk Mom (T1), teks Protected untuk keduanya dibuktikan di unit test.
- File: `App/AppEnvironment.swift`, `UITests/DetailUITests.swift`.

## D-alief-A36 · 22 Okt 2026 · app (fase 03) · Penutup privasi saat app tidak aktif

- Keputusan: `DetailView` dan layar zoom screenshot memakai `.privacyCover()`: saat `scenePhase != .active`, isi ditutup latar polos + ikon perisai. Snapshot app switcher yang ditulis iOS ke disk (`Library/SplashBoard/Snapshots`) tidak memuat URL penipuan, nama pemilik, atau screenshot bukti. Dicek di simulator: snapshot `.ktx` dikonversi ke PNG = hanya penutup (`qa/img/ui-03/app-switcher-snapshot-on-disk.png`).
- Alasan: review keamanan M3 (SECURITY §3 P9 + P13): snapshot di disk tidak ikut terhapus saat data dihapus/diputus. Layar lain (Activity, Shield) memuat data serupa → usulan untuk fase 04/05 (catatan handoff log fase 03).
- File: `Features/Detail/PrivacyCover.swift`, `DetailView.swift`, `ScreenshotView.swift`.

## D-alief-A10 · 22 Okt 2026 · app (fase 04) · Activity Guardian sudah memakai `ActivityView` (owner `.family`)

- Keputusan: `ActivityPlaceholderView` dihapus. Tab Activity Guardian memakai `ActivityView(owner: .family, showsOwner: true)` (nama pemilik di baris); Shield Guardian tetap placeholder sampai fase 05. Filter per orang (GD-05) menyusul di fase 05.
- Alasan: `ActivityModel` memang dirancang dipakai ulang GD-05; placeholder kosong lebih buruk daripada daftar yang sudah benar. `MainTabView` memberi `.id(ObjectIdentifier(env.repository))` ke akar tab supaya model layar dibuat ulang saat repository diganti (ganti mode, nanti sesi baru).
- File: `Features/Main/MainTabView.swift`, `Features/Activity/ActivityView.swift`.

## D-alief-A11 · 22 Okt 2026 · app (fase 04) · Baris Activity: host + path saja

- Keputusan: baris Activity menampilkan `host/path` (`ActivityRow.displayLink`), tanpa scheme, query, dan fragment. Link lengkap hanya di Detail (DT-03). VoiceOver membaca satu stop: domain, status, (pemilik), waktu.
- Alasan: SECURITY §3 P9: query/fragment halaman phishing sering membawa email, OTP, atau token; daftar terlihat oleh siapa pun yang melihat layar. Opsi paling menjaga privasi yang tetap memenuhi PR-05 ("link, domain tebal").
- File: `Features/Activity/ActivityView.swift`, test `ActivityModelTests.rowLinkHidesQueryAndFragment`.

## D-alief-A12 · 22 Okt 2026 · app (fase 04) · Gagal refresh tidak menghapus yang sudah tampil

- Keputusan: pull to refresh / refresh saat foreground yang gagal mempertahankan daftar dan kartu Shield (`refreshFailed` + baris "Couldn't refresh…", diumumkan VoiceOver); layar error hanya bila belum ada data. Halaman berikut yang gagal → baris "Retry". `URLError(.cancelled)` dan `CancellationError` bukan kegagalan (`Error.isCancellation`). `generation` dinaikkan saat permintaan halaman pertama mulai **dan** saat diterapkan, jadi halaman berikut untuk daftar lama dibuang. Ketuk chip yang sudah aktif tidak memuat ulang.
- Alasan: review `ecc:swift-reviewer` fase 04 (2 HIGH). Orang tua di jaringan lemah tidak boleh kehilangan riwayat karena satu tarikan gagal.
- File: `Features/Activity/ActivityModel.swift`, `Features/Shield/ShieldModel.swift`, `Support/Cancellation.swift`, test di `ActivityModelTests`/`ShieldModelTests`.

## D-alief-A13 · 22 Okt 2026 · app (fase 04) · Kontras teks sekunder dan isian status

- Keputusan: teks sekunder yang bermakna (waktu, "Protected by", link, subjudul status) memakai `.readableSecondary` = `Color(.label).opacity(0.72)` (≥ 4,5:1 terang/gelap), bukan `.secondary` (±3,5:1 di mode terang). Lingkaran status: hijau `#1A783D` / abu `#6B6B70` tanpa gradient (ikon putih ≥ 3:1). Chip terpilih: isian `#0061CC` + ikon centang (bukan hanya warna). Di ukuran aksesibilitas: chip bertumpuk lebar penuh, lingkaran dibatasi 160 pt, kartu blokir ring di atas teks.
- Alasan: review `ecc:a11y-architect` fase 04 (3 HIGH), persona 45–65 tahun. Komponen bersama fase 01 (`EmptyStateView` deskripsi, `StatusChip` `.caption`) belum diubah → dicatat untuk 06Q.
- File: `Components/ReadableSecondary.swift`, `Features/Shield/ProtectedShieldView.swift`, `Features/Activity/ActivityView.swift`.

## D-alief-A14 · 22 Okt 2026 · app (fase 04) · "Turn on" sementara membuka Settings; `-debug.activityFilter`

- Keputusan: saat Off, "Turn on" membuka `UIApplication.openSettingsURLString` (hint VoiceOver "Opens Settings"); sheet panduan `TurnOnExtensionView` fase 02 dipasang saat 02 digabung ke rantai sebelum 06Q (`TODO(sync:alief)`). Banner pengingat notifikasi tidak dipasang di PR-04 (hanya Guardian, D-alief-A08 di cabang fase 02). Launch argument DEBUG `-debug.activityFilter warning|blocked` membuka filter untuk screenshot gerbang UI.
- Alasan: fase 02 belum ada di rantai 01 → 03 → 04; tidak boleh menyalin layar 02 ke sini (konflik saat merge).
- File: `Features/Shield/ProtectedShieldView.swift`, `Features/Activity/ActivityView.swift`.

## D-alief-B12 · 22 Okt 2026 · fase 12 · Retensi, hardening, perbaikan review keamanan penuh

- Keputusan: (a) **Retensi harian** (`0 19 * * *` UTC = 03:00 WITA): batch 100 scan × maks 10 batch per run (bukan 500 di R4 §5; satu `DELETE` Storage per batch, jauh di bawah 50 subrequest Cron Workers Free; batch ke-10 penuh → log `backlog: true`). Per batch: pilih id (tanpa transaksi) → path yang tidak dipakai scan di luar batch → satu transaksi `lock_timeout`/`statement_timeout` lokal: tombstone path, `verdicts.scan_id = null`, hapus scan (urutan lock verdict → scan) → baru objek Storage dihapus. **Baris selalu hilang di hari ke-14 walau Storage mati** (review TypeScript M2; janji halaman privasi); objek yang gagal dihapus tetap tercatat di tombstone dan dicoba ulang. Satu kegagalan Storage menghentikan panggilan Storage berikutnya di run itu. Heartbeat `ops_heartbeat('cron')` paling awal; tiap langkah try/catch, error pertama dilempar di akhir; `scheduled()` meng-`await` retensi (bukan `waitUntil`) supaya run gagal terlihat di Cron Events. `family_codes` > 1 jam setelah kedaluwarsa, `join_attempts` > 1 hari, `push_log` > 14 hari, `rate_limit_hits` > 1 hari (chunk 20000 × maks 50). Verdict tetap (D-alief-14). (b) **Role `shoo_api`**: `statement_timeout 10s`, `idle_in_transaction_session_timeout 15s`, `lock_timeout 5s`. `blocklist_entries`: INSERT hanya `(domain, families)`, UPDATE hanya `families`, policy per perintah — Worker hanya boleh memasukkan dan menghapus baris yang belum diputus reviewer (`approved_at is null and removed_at is null`), jadi Worker yang bocor tidak bisa menyetujui atau menghapus domain yang disajikan (T5). (c) **`service_role` dicabut dari skema `public`** (temuan HIGH review keamanan): kunci rahasia Supabase Worker (hanya untuk Storage) memetakan ke `service_role`, yang lewat Data API melewati RLS dan bisa membaca/menyetujui semua tabel. Tabel dipakai lewat `shoo_api` saja; Data API dimatikan di dashboard (LANGKAH MANUAL). (d) **Header keamanan** di semua respons (nosniff, `no-referrer`, `DENY`, HSTS, CSP `default-src 'none'`, route boleh memasang CSP sendiri), tanpa CORS (OPTIONS → 404 / 401 di belakang auth), `content-length` > 256 KB → 413 sebelum auth/DB. (e) **Batas 401 per IP** untuk token yang bentuknya benar tapi tidak dikenal (`auth_fail` 60 / 10 menit); lewat batas jawabannya tetap 401 + `Retry-After` (bukan 429), supaya klien dengan token yang sudah dihapus tahu tokennya mati. (f) **Kunci rate limit dan `join_attempts.ip_hash` = HMAC-SHA256 dengan `RATE_KEY_SECRET`** (sha256 IPv4 bisa dibalik dengan 2^32 percobaan). Secret **wajib** ≥ 32 karakter, gagal tertutup: tanpa itu setiap request yang memakai rate limit → 500 (bukan jatuh diam-diam ke sha256). `SCREENSHOT_URL_SECRET` juga ≥ 32 karakter (lebih pendek = tidak ada link). (g) **`storage_tombstones` = log niat setiap objek screenshot** (P13; review database M1–M3): path ditulis di transaksi yang memesan upload (sebelum objek bisa ada) dan di transaksi `DELETE /devices/me`; tombstone hanya dihapus setelah Storage mengonfirmasi remove **dan** umurnya > 10 menit (upload dengan timeout 5 s bisa mendarat setelah remove). Cron menghapus path yang tidak ditunjuk scan mana pun (maks 500 per run); batch yang gagal ditandai `attempts`/`last_try_at` dan diantrekan di belakang, batch lain tetap jalan. Upload untuk scan yang sudah terhapus tidak dimulai (`reserveScreenshot` → `gone`). Jadi objek tidak pernah tertinggal tanpa catatan, juga kalau Storage gagal atau Worker mati di tengah upload. (g2) **Urutan lock tetap** verdicts `(owner_id, domain)` → scans `(id)` di retensi dan `deleteDevice` (review database M5); `DELETE /devices/me` dicoba ulang sekali pada `40P01`/`40001`/`55P03` (hapus data tidak boleh gagal karena race). (h) **Dedupe screenshot hanya memakai ulang upload asli** (path memuat id scan pemiliknya): rantai pemakaian ulang tidak bisa memperpanjang umur objek; objek hilang paling lambat 15 hari setelah upload (teks `/privacy`). Kuota per pemilik dan global menghitung upload asli saja, lewat index parsial `scans_original_shot` (index-only, bukan sort semua scan 24 jam; review database M6). (i) **Batas global + throughput retensi** (review database M4): scan tanpa screenshot dihapus dalam chunk 2000 × maks 25 per run (tanpa panggilan Storage), `POST /scans` dibatasi 2000 / jam untuk semua device (`hitLight`, kapasitas, bukan anti-tebak; dihitung setelah body valid), jadi retensi selalu bisa mengejar. Risiko yang diterima: ±17 device yang memakai batas penuh per device bisa menghabiskan batas global (scan orang lain 429); untuk demo lebih kecil daripada DB Free yang penuh. `devices_create_all` 1000 device baru / hari untuk semua pemanggil (IP berganti-ganti tidak bisa memenuhi DB Free; kalau tercapai hanya device baru yang tertolak), screenshot 300 / 24 jam untuk semua pemilik (300 × 150 KB × 15 hari ≈ 675 MB < 1 GB Storage Free; lewat batas → scan tetap tersimpan tanpa screenshot, log `global_quota`). (j) **`GET /privacy`** EN/ID (P12): data yang disimpan (termasuk `last_seen_at`), retensi (14 hari, screenshot ≤ 15 hari, `push_log` 14 hari tanpa teks, kode keluarga), hapus data, tanpa tracking, prosesor; kontak = placeholder `TODO(sync:alief)` (TODO E6). (k) Smart Placement (`placement.mode = "smart"`) untuk deviasi latensi D-alief-B10 (g); bisa dibalik satu baris. **Hasil cloud 22 Okt (Worker `bdc661e8`, 20 request dari klien uji di Indonesia): `GET /verdicts` p50 252 ms / p95 317 ms / max 347 ms** (fase 10: 435 / 1547 / 1713 ms). **Deviasi kecil diterima:** p95 17 ms di atas target 300 ms, diukur end-to-end dari klien (termasuk ±115 ms RTT klien → colo SIN dan TLS), bukan waktu server; tidak ada lagi perbaikan murah tanpa menggabungkan query auth + verdict (ditunda, butuh refactor middleware). Extension mem-poll tiap 5 s, jadi 17 ms tidak terasa; ukur ulang di D8 dan QA-E2E fase 16.
- Alasan: file fase 12, R4 §5, R2 §6, SECURITY (seluruhnya), D-alief-40; review `ecc:security-reviewer` atas seluruh `backend/` (0 CRITICAL, 1 HIGH: `service_role` + Data API; MEDIUM: secret opsional jatuh ke sha256, objek tertinggal kalau remove gagal, Worker bisa menghapus entri disetujui, tanpa batas global, cleanup `rate_limit_hits` terlalu pendek; LOW: rantai dedupe, teks privasi kurang lengkap, panjang secret, Content-Type); `ecc:database-reviewer` (0 CRITICAL/HIGH; MEDIUM: upload yang mendarat terlambat / Worker mati tanpa tombstone, `reserveScreenshot` mengabaikan jumlah baris, satu batch tombstone gagal memblokir semua, retensi maks 1000 scan/hari, risiko deadlock `deleteDevice` ↔ retensi, kuota global sort semua scan 24 jam, device tidak pernah dihapus → TODO E7; dua celah P13 diperlakukan TINGGI sesuai D-alief-40 dan diperbaiki); `ecc:typescript-reviewer` (0 CRITICAL/HIGH; MEDIUM: cron di `waitUntil` menyembunyikan kegagalan, Storage mati menahan baris scan > 14 hari (janji privasi → diperlakukan TINGGI), batas global terpakai body tidak valid, 429 untuk token mati, test yang bisa lulus karena alasan salah). Estimasi kuota lokal: 1000 scan ≈ 1,4 MB tabel `scans`; DB total 19 MB.
- Alternatif yang ditolak: fallback sha256 tanpa secret (kunci yang bisa dibalik di produksi tanpa tanda); antrean penghapusan di Storage saja (tidak bisa diulang kalau Storage mati); mewajibkan `Content-Type: application/json` sekarang (kontrak tidak menyebutnya; `URLSession` tanpa header mengirim `application/x-www-form-urlencoded` dan `fetch` dengan string mengirim `text/plain` → klien Umar/Alief bisa rusak; jadi usulan kontrak C21).
- Dampak ke tim lain / kontrak: tidak ada perubahan JSON. Usulan C21 (Content-Type wajib, query/fragment URL dibuang sebelum dikirim). Fase 13: `faviconUrl` dari scan **tidak boleh dimuat langsung** oleh app (IP Guardian bocor ke situs penipu) — tampilkan ikon default atau proxy lewat Worker.
- File yang diperbarui: `backend/api/src/cron/retention.ts`, `src/index.ts` (`scheduled`), `src/app.ts`, `src/http/{auth,keyHash,crypto,rateLimit}.ts`, `src/routes/{privacy,devices,family,screenshots}.ts`, `src/services/{scans,screenshots}.ts`, `src/db/repo/{scans,devices,tombstones,verdicts}.ts`, `wrangler.jsonc` (cron, placement), `vitest.config.ts`, `.dev.vars.example`, migrasi `20261022120000_hardening.sql` + `20261022130000_security_review.sql`, pgTAP `hardening`, `security_review`, `grants`, test `retention`, `security-headers`, `privacy`, `log-hygiene`, `security-review`, `backend/db/scripts/quota-estimate.sql`, `backend/ci/{backend.yml,README.md}`, `backend/.gitleaksignore`, `backend/README.md`; `ref/R2` §2/§6, `R4` §5, `SECURITY.md` T10/P12, `TODO.md`.

## D-alief-A23 · 22 Okt 2026 · app (rebase ke main) · Resolusi A18 pindah ke fase 04

- Keputusan: setelah #14, #16 dan #18 masuk main, rantai app di-rebase ke main dan merge commit fase 02 (A18) dibuang. #19 di-squash ke main sebelum resolusi ini sempat di-push, jadi bagian A18 yang menyentuh fase 04 menjadi commit pertama #21 (fase 05): `ExtensionStatus.live()` dihapus, `ProtectedShieldView(repository:extensionStatus:)` memakai `env.extensionStatus`, "Turn on" membuka `TurnOnExtensionView` sebagai sheet (menggantikan sementara D-alief-A14), dan `TurnOnExtensionView(refreshStatus:)` bisa dipakai di luar onboarding. Kunci "Opens Settings" dihapus dari katalog; UI test baru membuka dan menutup sheet.
- Alasan: satu sumber status extension (override `-UITestExtensionActive` lewat `AppEnvironment`), dan tiap PR bisa direview sendiri di atas main tanpa merge commit.
- File: `Features/Shield/ShieldModel.swift`, `Features/Shield/ProtectedShieldView.swift`, `Features/Main/MainTabView.swift`, `Features/Onboarding/TurnOnExtensionView.swift`, `Features/Onboarding/OnboardingFlow.swift`, `UITests/ProtectedUITests.swift`.

## D-alief-A15 · 22 Okt 2026 · app (fase 05) · Family mode: tombol "Family: On/Off" di toolbar, judul ikut berganti

- Keputusan: toggle GD-02 adalah tombol toolbar kiri atas (hanya Guardian, di tab Shield dan Activity) dengan teks terlihat "Family: On/Off" + ikon terisi/garis, VoiceOver "Family mode, On/Off" (trait toggle), dan pengumuman saat beralih. Disimpan di `AppSettings.familyModeOn` (sejak fase 01). Saat On judul layar "Family" / "Family activity"; saat Off layar Shield milik Guardian sendiri ("You're protected", tanpa baris "Protected by") dan Activity miliknya sendiri (`owner=me`). Pergantian membuat ulang model layar Guardian (`.id`), layar Protected tidak terpengaruh.
- Alasan: review `ecc:a11y-architect` fase 05 HIGH: `Toggle(.button)` di toolbar hanya menampilkan ikon dan status hanya lewat warna. Activity mengikuti toggle supaya GD-02 "mengganti tampilan" berlaku di kedua tab.
- File: `Features/Main/MainTabView.swift`, `Features/Shield/{FamilyShieldView,ProtectedShieldView}.swift`, `Features/Activity/ActivityView.swift`.

## D-alief-A16 · 22 Okt 2026 · app (fase 05) · Kartu keluarga membuka scan yang ditampilkan

- Keputusan: kontrak `lastScan` tidak punya id. `FamilyShieldModel` mengambil `scans(owner: .device(id))` per anggota (maks 3, paralel) dan memilih item yang `url` + `detectedAt`-nya sama dengan `lastScan`, atau item terbaru. Gagal untuk satu anggota → kartu itu saja tanpa tautan. Kartu tanpa situs bukan tombol (tidak diredupkan). "Not connected" hanya bila `extensionActive == false` (D-alief-15/24).
- Alasan: review `ecc:swift-reviewer` fase 05 (H1, M2, M3). Usulan kecil untuk Umar (bukan blocker): `lastScan.id` di `GET /family/members` akan menghapus N panggilan tambahan → dicatat di PR.
- File: `Features/Shield/FamilyShieldModel.swift`, `Features/Shield/FamilyShieldView.swift`.

## D-alief-A17 · 22 Okt 2026 · app (fase 05) · Filter orang Family Activity

- Keputusan: chip Everyone / You / nama anggota → `owner` `.family` / `.me` / `.device(id)`, digabung dengan chip status. Daftar orang dibaca ulang setiap load/refresh; anggota yang sudah dihapus → kembali ke Everyone. Skenario mock DEBUG `oneMember` dan `threeMembers` (anggota ketiga "Grandma" hanya di mock, bukan fixture kontrak) untuk gerbang 0/1/2/3 anggota.
- Alasan: PRD GD-05 + review M4/M5. Fixture kontrak hanya punya 2 anggota.
- File: `Features/Activity/{ActivityModel,ActivityView}.swift`, `Data/MockRepository.swift`.

## D-alief-A18 · 22 Okt 2026 · app (fase 06) · Fase 02 digabung ke cabang fase 06 di awal fase 06

- Keputusan: `origin/feat/ON-01-05-onboarding` (#16, tip 4f7367c) di-merge (`--no-ff`) ke `feat/PF-01-profile` **di awal** fase 06, bukan tepat sebelum 06Q, karena PF-01 butuh layar fase 02 (Disconnect → Connect, ON-04 untuk status extension). Belum ada PR app yang masuk `main`, jadi rebase tidak mungkin. Penyelesaian konflik:
  - `Localizable.xcstrings`: gabungan kedua katalog (140 key); satu key beda terjemahan ("Couldn't save…") memakai versi fase 03.
  - `ShieldPlaceholderView` (dihapus di 05, diubah di 02): tetap dihapus; banner pengingat notifikasi Guardian (D-alief-A08) dipindah ke `GuardianShieldView`.
  - `AppEnvironment`: versi 02 (`extensionStatus` closure, `notifications`, `register`/`finishOnboarding`) + argumen DEBUG fase 03; `ExtensionStatus.live()` fase 04 dihapus, `ShieldModel` menerima `env.extensionStatus` (satu sumber `-UITestExtensionActive`).
  - "Turn on" di Shield (Protected dan Guardian) membuka `TurnOnExtensionView` fase 02 sebagai sheet (tutup otomatis saat heartbeat Active); `TurnOnExtensionView` menerima closure `refreshStatus` alih-alih `OnboardingModel`.
  - `FailingRepository` ganda: versi `Tests/TestDoubles.swift` dipakai, salinan di `OnboardingTests` dihapus.
  - `PROGRESS.md` baris 02 dari 02, baris 03–05 dari rantai ini; `DECISIONS.md` A04–A08 disisipkan sebelum A30.
- Alasan: instruksi koordinator (gabungkan 02 ke cabang 06 sebelum 06Q, catat di DECISIONS). PR fase 06 menyebut "Stacked on #21 + merges #16".
- File: lihat commit merge di `feat/PF-01-profile`.

## D-alief-A19 · 22 Okt 2026 · app (fase 06) · Bahasa: berlaku langsung, server menyusul

- Keputusan: pilihan bahasa di Profile (picker inline, kedua pilihan selalu terlihat) langsung mengubah `AppSettings.language` (seluruh app tanpa restart, lewat `.environment(\.locale)`), lalu `updateMe(language:)` di task yang dibatalkan oleh pilihan berikutnya. Gagal → app tetap memakai pilihan + alert; `ProfileModel.load()` mengirim ulang bila `me().language` berbeda.
- Alasan: PF-01 + D-alief-05 (push dilokalkan sesuai bahasa server). Review M5: dua tap cepat tidak boleh meninggalkan server di bahasa lama.
- File: `Features/Profile/{ProfileModel,ProfileView}.swift`.

## D-alief-A20 · 22 Okt 2026 · app (fase 06) · Putus dan hapus data: server dulu, lalu awal yang bersih

- Keputusan: Disconnect (Protected) = `leaveGuardian()` → `Router.reset()` → `onboardingConnectPassed = false`, `onboardingCompleted = false` → onboarding lanjut di Connect (mode tetap Protected). "Delete my data" = `deleteMe()` (usulan `DELETE /devices/me`, ditambahkan ke protokol `ShooRepository` milik app, mock menghapus scan sendiri, keluarga, guardian) → `Router.reset()` → `AppSettings.reset()` → onboarding dari awal; UI di belakang `AppConfig.dataDeletionEnabled = false` sampai C19 dijawab. `notFound` (dan `unauthorized` untuk hapus) setelah jawaban hilang = sudah selesai. Dialog konfirmasi iOS standar dipakai (bukan validasi GD-07).
- Alasan: SECURITY §3 P3 / P13 (hapus = langsung hilang), review M1/M2. Kontrak belum punya endpoint → tidak boleh tampil di build.
- File: `Features/Profile/ProfileModel.swift`, `Data/{ShooRepository,MockRepository}.swift`, `App/Router.swift`, `App/AppConfig.swift` (flag sudah ada sejak fase 01).

## D-alief-A40 · 22 Okt 2026 · app (fase 06) · "Delete my data" selalu tampil

- Keputusan: flag `AppConfig.dataDeletionEnabled` dihapus. Tombol "Delete my data" di Profile selalu tampil untuk kedua mode; `ProfileModel` tidak lagi menerima flag. Test `deleteMyDataIsHiddenUntilTheContractExists` diganti UI test `testDeleteMyDataStartsOnboardingOver` (hapus → konfirmasi → onboarding dari awal).
- Alasan: PR #10 Umar menambahkan `DELETE /devices/me → { ok }` ke `contracts/api.md` (C19 butir 1). Backend sudah punya endpoint sejak fase 08. App Store Guideline 5.1.1(v), SECURITY §3 P3.
- File: `App/AppConfig.swift`, `Data/ShooRepository.swift`, `Features/Profile/{ProfileModel,ProfileView}.swift`, `Tests/ProfileModelTests.swift`, `UITests/ProfileUITests.swift`.

## D-alief-A21 · 22 Okt 2026 · app (fase 06Q) · Pengingat notifikasi Guardian ikut tergulir

- Keputusan: Banner "Notifications are off" (D-alief-A08) tidak lagi di `safeAreaInset(edge: .top)` `GuardianShieldView`, tapi jadi baris pertama konten gulir `ProtectedShieldView` (perspektif Guardian) dan `FamilyShieldView` (parameter `reminder`). Tombol "Invite your family" saat keluarga kosong menempel di atas tab bar di ukuran teks biasa, dan ikut tergulir di ukuran aksesibilitas.
- Alasan: QA-A P2-4 / P2-7: di iPhone SE + XL banner menempel setinggi ±300 pt, ruang gulir tinggal sepotong dan geseran di banner tidak menggulir; tombol Invite tertutup tab bar di SE ukuran default.
- File: `Features/Shield/{FamilyShieldView,ProtectedShieldView}.swift`; test `UITests/QALayoutUITests.swift`.

## D-alief-A22 · 22 Okt 2026 · app (fase 06Q) · Tata letak teks besar dari QA-A

- Keputusan: Cincin skor Detail tidak ikut membesar dengan Dynamic Type (`ScoreRing.maxScale = 1`, angka 42 pt); kartu lain tetap boleh 2×. `EmptyStateView` memakai tata letak sendiri (judul membungkus, deskripsi `.readableSecondary`, satu elemen VoiceOver) menggantikan `ContentUnavailableView`. Slide splash berakhir 52 pt di atas titik halaman. Kartu mode ON-03 menaruh ikon di baris sendiri pada ukuran aksesibilitas.
- Alasan: QA-A P2-1, P2-2, P2-3, P2-5 (iPhone SE, XL). Audit `performAccessibilityAudit` di simulator banyak positif palsu (efek tepi gulir iOS 26), jadi diputuskan dari screenshot + UI test frame.
- File: `Components/{ScoreRing,EmptyStateView}.swift`, `Features/Detail/DetailView.swift`, `Features/Onboarding/{SplashView,ModeView}.swift`; test `Tests/ComponentLogicTests.swift`, `UITests/QALayoutUITests.swift`, `UITests/AccessibilityAuditUITests.swift` (atas permintaan).

## D-alief-C01 · 22 Okt 2026 · track c (fase 13) · `ApiRepository` default, `-UITestMock YES` untuk UI test

- Keputusan: `AppEnvironment.live()` selalu memakai `ApiRepository` (Debug → `http://localhost:8787`, Release → `https://shoo-api.afindo-mi01.workers.dev`). `MockRepository` hanya lewat argumen `-UITestMock YES` (hanya Debug) dan untuk preview; semua UI test lama memakai argumen itu. Dengan mock, `session` = `nil` sehingga fixture tidak pernah menulis App Group/Keychain asli.
- Alasan: fase 13 langkah 2 (mock tetap untuk preview/UI test), R5 §6 (URL di `AppConfig`, bukan Info.plist).
- Alternatif yang ditolak: memilih mock otomatis kalau ada `-mock.scenario` (diam-diam, mudah lupa); mock di Release (tidak boleh).
- Dampak ke tim lain / kontrak: tidak ada. Uji manual app di simulator butuh `pnpm -C backend/api dev`.
- File: `App/{AppEnvironment,AppConfig}.swift`, `UITests/*.swift`.

## D-alief-C02 · 22 Okt 2026 · track c (fase 13) · App Group hanya key kontrak; avatar guardian di memori

- Keputusan: `SessionStore` menulis key kontrak saja (`device.id`, `device.token`, `device.mode`, `device.name`, `guardian.name`, `api.baseURL`, `ai.baseURL`). Guardian lengkap (nama + `avatarId`) disimpan di memori, diisi dari `POST /family/join` dan setiap `GET /devices/me`; layar membaca `me()` seperti sebelumnya. `guardian.name` dihapus saat `leaveGuardian()` (ok atau 404) dan saat `GET /devices/me` → `guardian: null`; `device.name` ditulis ulang setelah `updateMe(name:)` berhasil dan dari `me()`. `extension.lastSeenAt` milik extension tidak pernah dihapus app.
- Alasan: SECURITY §3 P4 (tidak ada data pengguna lain di `UserDefaults`), kontrak app-group-keys, D-alief-21.
- Alternatif yang ditolak: avatar guardian di `UserDefaults` standar (data tambahan tanpa kebutuhan; `me()` selalu membawanya).
- File: `Data/{SessionStore,ApiRepository}.swift`.

## D-alief-C03 · 22 Okt 2026 · track c (fase 13) · Sesi rusak = layar "Session expired" + onboarding ulang

- Keputusan: 401 dari endpoint ber-token, atau device terdaftar tanpa token di Keychain (backup dipulihkan ke iPhone lain: item `ThisDeviceOnly` tidak ikut, salinan App Group tidak dipercaya), → `SessionStore.clear()` (Keychain + key App Group, extension langsung kehilangan sesi) → layar "Session expired" (EN/ID) dengan tombol "Start again" → `AppSettings.reset()` + `Router.reset()` → onboarding dari awal (device baru). `DELETE /devices/me` yang menjawab 401/404 = sudah terhapus: sesi dibersihkan, Profile lanjut ke onboarding tanpa layar ini. 401 dengan `Retry-After` (batas token tak dikenal) tetap 401 = token mati.
- Alasan: fase 13 langkah 4, SECURITY T3 (rotasi = onboarding ulang), P4, P13.
- Alternatif yang ditolak: coba lagi otomatis (token mati tidak hidup lagi); memakai token dari App Group setelah restore (melemahkan P4).
- File: `App/{AppEnvironment,RootView}.swift`, `Data/APIClient.swift`, `Features/Main/SessionExpiredView.swift`.

## D-alief-C04 · 22 Okt 2026 · track c (fase 13) · Link screenshot kedaluwarsa: minta scan sekali lagi

- Keputusan: kalau screenshot gagal dimuat (404 juga berarti link 1 jam sudah lewat), Detail memanggil `GET /scans/{id}` sekali per load. Link baru → dimuat ulang; link sama / tanpa link → "Screenshot isn't available anymore"; 404 → layar "tidak ada lagi". Tetap tanpa cache disk (P9), tanpa `Authorization`.
- Alasan: instruksi koordinator + `contracts/api.md` (`screenshotUrl` 1 jam, dicek ulang tiap request). Deviasi kecil dari DoD "diff `Features/` hanya injeksi": `DetailModel.refreshScreenshotLink()` + parameter `refreshLink` di `ScreenshotView`.
- File: `Features/Detail/{DetailModel,DetailView,ScreenshotView}.swift`, `Tests/DetailScreenshotLinkTests.swift`.

## D-alief-C05 · 22 Okt 2026 · track c (fase 13) · `ai.baseURL` tidak ditulis sampai URL Imelda ada

- Keputusan: `AppConfig.aiBaseURL = nil` (`TODO(sync:imelda)`); selama `nil`, key `ai.baseURL` dihapus dari App Group, sehingga extension melewati layer 3–4 (`background.js`: `skipped: "no_ai_url"`) dan tidak mengirim halaman ke host placeholder.
- Alasan: privasi (tidak ada data ke host yang bukan milik tim), kontrak app-group-keys.
- Dampak: Imelda/Umar memberi URL layanan AI → satu baris di `AppConfig`.
- File: `App/AppConfig.swift`, `Data/SessionStore.swift`.

## D-alief-C06 · 22 Okt 2026 · track c (fase 13) · Sinkron saat foreground dan bahasa setelah registrasi

- Keputusan: setiap `scenePhase == .active` (device terdaftar, sesi sehat): `PATCH /devices/me { extensionLastSeenAt }` dengan heartbeat App Group (dipotong ke "sekarang" kalau jam extension di masa depan; dilewati kalau belum ada heartbeat), lalu `GET /devices/me` mengisi ulang `SessionStore`. Gagal = dicatat di log saja. Setelah `POST /devices`: Keychain + App Group dulu, baru `chooseMode`; kalau bahasa app ID → `PATCH /devices/me { language: "id" }` (gagal tidak membatalkan registrasi; Profile mengirim ulang, D-alief-A19).
- Alasan: fase 13 langkah 3 + 7, kontrak `extensionLastSeenAt`.
- Alternatif yang ditolak: throttle per jam di app (MVP: dua request kecil per foreground cukup; backend punya batas umum).
- File: `App/{AppEnvironment,RootView}.swift`.

## D-alief-C07 · 22 Okt 2026 · track c (fase 14) · Link/QR hanya mengisi kode; join selalu lewat tap "Connect" (T11)

- Keputusan: `shoo://join?code=`, `https://<host API>/join?code=` dan hasil scan QR hanya mengisi 4 digit di ConnectView (`ConnectModel.prefill` / `scanned` tidak pernah memanggil `joinFamily`). Pengguna melihat kodenya lalu menekan "Connect". Setelah onboarding, link membuka sheet Connect di tab Shield; sebelum registrasi, kode disimpan di `Router.pendingJoinCode` (memori saja, tidak ke disk) sampai langkah Connect onboarding. Mode Guardian, link rusak, host lain, `http` di luar localhost Debug, kode ganda (`code=1&code=2`), atau digit non-ASCII → Shield (kontrak "Deep links"). `scan`/`activity` diterima parser tapi dirutekan di fase 15.
- Alasan: SECURITY T11 (link tidak boleh menghubungkan tanpa konfirmasi). Kontrak tidak punya endpoint "preview" (nama guardian sebelum join), jadi konfirmasinya adalah tap eksplisit pada kode yang terlihat; nama guardian muncul di PR-02 setelah join, dan Profile → Disconnect membatalkannya.
- Alternatif yang ditolak: join otomatis dari link (melanggar T11); dialog "Join Adhella's family?" (butuh endpoint preview baru di `contracts/`, bukan wewenang Team App); menyimpan kode tertunda di UserDefaults (data undangan tidak perlu hidup setelah app ditutup, P1).
- File: `App/{DeepLink,AppEnvironment,Router}.swift`, `Features/Pairing/{ConnectModel,ConnectView}.swift`, `Features/Onboarding/OnboardingFlow.swift`, `Features/Main/MainTabView.swift`.

## D-alief-C08 · 22 Okt 2026 · track c (fase 14) · Tab default "Enter code"; kamera diminta saat tab Scan QR dibuka

- Keputusan: ConnectView membuka tab "Enter code". Tab "Scan QR" memakai `DataScannerViewController` (VisionKit) khusus QR; izin kamera diminta (`AVCaptureDevice.requestAccess`) baru saat tab itu dibuka. Tidak ada foto/frame yang disimpan; hanya string QR yang dibaca, dan hanya link undangan dari host yang diizinkan yang diterima (lainnya: "That QR code isn't a Shoo family code."). Simulator / iPhone tanpa dukungan / izin ditolak → catatan + "Open Settings" (saat ditolak), tab Enter code tetap ada. `AppConfig.cameraEnabled = true` karena C3 (`NSCameraUsageDescription`) sudah masuk lewat #27.
- Alasan: SECURITY P7 (izin tepat waktu, minimal), PRD PR-01; kode 4 digit bisa dibaca lewat telepon, jadi tidak memaksa kamera.
- Alternatif yang ditolak: `AVCaptureSession` + `AVCaptureMetadataOutput` manual (lebih banyak kode, sama hasilnya); minta izin kamera saat ConnectView muncul.
- File: `Features/Pairing/{QRScannerView,ConnectView}.swift`, `App/AppConfig.swift`.

## D-alief-C09 · 22 Okt 2026 · track c (fase 14) · Kode keluarga: refresh di 0 s, jam miring = 60 s, keluarga penuh = tanpa kode

- Keputusan: FamilyCodeView meminta `POST /family/code` saat muncul dan setiap hitung mundur mencapai 0. `secondsLeft` dihitung dari `expiresAt` server; kalau hasilnya di luar 1…60 s (jam iPhone miring dari server) dipakai 60 s, supaya tidak macet di 0 atau meminta kode terus-menerus. Kalau anggota sudah 3 (`FamilyShieldModel.maxMembers`), tidak ada kode yang diminta: tampil "Your family is full (3 people)…" dan daftar anggota dengan Remove; setelah ada yang dihapus kode langsung diminta. Gagal → "Couldn't get a code" + Try again. Sheet memakai `.privacyCover()` (kode tidak terlihat di app switcher).
- Alasan: PRD GD-04 + §10 risiko kode 4 digit (umur pendek, refresh otomatis), kontrak `family_full`.
- Alternatif yang ditolak: memakai jam iPhone apa adanya (kode bisa terlihat "0 s" terus); tetap meminta kode saat penuh (server menolak join, pengguna bingung).
- File: `Features/Pairing/{FamilyCodeModel,FamilyCodeView}.swift`.

## D-alief-C10 · 22 Okt 2026 · track c (fase 14) · Anggota dibaca ulang tiap 5 s selama kode tampil

- Keputusan: selama FamilyCodeView terbuka, `GET /family/members` diulang tiap 5 s (bersama loop hitung mundur, berhenti saat sheet ditutup). Saat ditutup, Family Shield / Profile memuat ulang.
- Alasan: Guardian perlu melihat "Mom connected" segera setelah Mom memasukkan kode; kontrak tidak punya push/event untuk join, dan polling hanya berjalan selama layar ini terbuka (paling lama beberapa menit).
- Alternatif yang ditolak: push "X joined" (butuh perubahan kontrak + fase 11); tanpa refresh (Guardian harus menutup sheet untuk melihat).
- File: `Features/Pairing/FamilyCodeModel.swift`.

## D-alief-C11 · 22 Okt 2026 · track c (fase 14) · "Copy invite link": pasteboard lokal, hilang saat kode kedaluwarsa

- Keputusan: teks undangan EN/ID (berisi `inviteUrl` + kode) disalin dengan `UIPasteboard.setItems(_:options:)` memakai `.localOnly: true` (tidak ke Universal Clipboard) dan `.expirationDate` = `expiresAt` kode (dijepit 1…60 s). Tombol berubah jadi "Copied" + pengumuman VoiceOver; kembali saat kode baru muncul.
- Alasan: SECURITY P8; kode tidak berguna setelah kedaluwarsa, jadi tidak perlu tinggal di clipboard.
- Alternatif yang ditolak: `UIPasteboard.general.string = …` (sinkron ke Mac/iPad, tidak kedaluwarsa); `ShareLink` (bisa ditambah nanti, tapi PRD meminta "Copy invite link" untuk WhatsApp).
- File: `Features/Pairing/FamilyCodeModel.swift`, `Tests/PairingTests.swift`.

## D-alief-C12 · 22 Okt 2026 · track c (fase 14) · Link saat sheet lain terbuka: sheet itu ditutup dulu, Connect menyusul dari `onDismiss`

- Keputusan: `Router.showConnect()` kembali ke tab Shield; kalau Profile atau "Turn on" (PR-04) sedang terbuka, keduanya ditutup dan `wantsConnect` dicatat, lalu Connect dibuka dari `onDismiss` sheet itu (`Router.sheetDismissed()`). Status sheet "Turn on" di Shield pindah ke `Router.isTurnOnPresented` supaya link bisa menutupnya. Link kedua saat Connect sudah terbuka hanya mengisi ulang kode. Kode tertunda dibuang saat app ke background dan saat registrasi sebagai Guardian.
- Alasan: review swift fase 14 (HIGH): SwiftUI hanya menampilkan satu sheet; jeda waktu tetap (700 ms) menebak kapan animasi selesai dan bisa membuat flag Connect macet `true` tanpa sheet. Urutan dari state tidak menebak.
- Alternatif yang ditolak: satu `enum ActiveSheet` + `.sheet(item:)` untuk semua sheet (lebih rapi, tapi menyentuh banyak layar fase 04–06; dicatat untuk refactor setelah MVP); cek `presentedViewController` UIKit + jeda (ikut menghitung alert/dialog sistem yang tidak bisa ditutup app).
- File: `App/{Router,AppEnvironment,RootView}.swift`, `Features/Main/MainTabView.swift`, `Features/Shield/ProtectedShieldView.swift`, `Tests/PairingTests.swift` (`DeepLinkRoutingTests`).
