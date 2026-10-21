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

