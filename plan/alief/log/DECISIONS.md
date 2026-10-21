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

## D-alief-16 · (diisi fase 07) · Jalur push APNs

- Keputusan: _menunggu spike fase 07_ — `ApnsSender` langsung dari Worker, atau `RelaySender` → Edge Function Supabase `push`.
