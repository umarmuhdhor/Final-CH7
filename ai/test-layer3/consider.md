# Consider: perubahan layer 3 yang masih terbuka

Status: **draf, diperbarui 29 Okt 2026**. Issue D1 dan D4 (bahasa Indonesia) disiapkan untuk Umar bersama satu PR; belum dikirim saat ini. D2 ditunda, D3 selesai.
Bukti angka: [HASIL-ANALISIS.md](HASIL-ANALISIS.md), [HASIL-LEGIT-TAMBAHAN.md](HASIL-LEGIT-TAMBAHAN.md).

## A. Sudah diubah di `ai/` (belum di-commit)

| file | perubahan | efek |
|---|---|---|
| `ai/src/layer3/forms.js` | keyword `asks_otp` + `mobile token`, `token lunak`, `soft token`, `keybca`, `key bca` | field token bank kena OTP. `csrf_token`, `_token`, `API token` tetap tidak kena |
| `ai/src/layer3/content.js` | kata aksi title brand + `otp`, `pin` | situs 19 (Shopee) naik 25 → 50 |
| `ai/test/forms.test.mjs`, `ai/test/content.test.mjs` | 5 tes baru | 337 tes lulus |
| `detector/data/brands.json` | tambah `agoda` (agoda.com, agoda.co.id) dan `dhl` (dhl.com, dhl.co.id). Menambah entri daftar, tidak perlu izin | situs 10 (Agoda) naik 25 → 50. Situs 22 (DHL) tetap 15: title tidak punya kata aksi |
| `ios/ShooExtension/Resources/detector.js` | hasil `detector/scripts/sync-to-extension.sh` | file generated, ikut di-commit |
| `detector/test/detector.test.mjs` | 3 tes baru: domain resmi diam, tiruan (`ag0da.com`, `dh1.com`) kena, kata berisi `dhl` (`adhlete.com`) tidak kena | 65 tes detector lulus |

Hasil: scam tertangkap 18 (HEAD) → **19 dari 25** (dulu ditulis 17; hanya situs 19 pindah). Legit: 0 dari 25 mencapai 30 (maks 15).

Uji penuh 29 Okt 2026 (RDAP live, umur hari ini, Telegram, waktu): [HASIL-L3-PENUH.md](HASIL-L3-PENUH.md). Ringkas: umur beku 19/25, umur hari ini 15–19/25 (tidak stabil karena RDAP), + Telegram 16–20/25, legit ≥ 30 selalu 0 dari 10, total /analyze maks 1,5 dtk.

**Batas tampilan di ekstensi (dikonfirmasi Imelda langsung, 29 Okt 2026; tidak ditanyakan ke Umar):** layer 2 maks 35, layer 3 maks 35, total 70. Tangkapan ≥ 30 tidak berubah oleh batas ini (35 > 30). Skor ≥ 80 tidak bisa dicapai layer 2 + 3.

## B. Mau diubah di `ai/` (wewenang saya, tidak perlu Umar)

1. Perbarui angka di `HASIL-ANALISIS.md` (17 → 18 dari 25, situs 19).
2. Masukkan sampel scam + legit berlabel ke `ai/eval/` dan laporkan precision/recall (wajib di `ai/CLAUDE.md` saat rule atau bobot berubah).
3. Ukur skor gabungan L1 + L2 + L3 lewat extension asli di Safari (eval L3 mengosongkan `localSignals`).
4. Commit di branch sendiri, satu PRD ID per branch.

## C. Tidak akan diubah (sudah dipertimbangkan)

| usulan | alasan ditolak |
|---|---|
| naikkan `asks_otp` 25 → 30 | situs sah sering minta OTP (2FA, login bank). Satu halaman OTP sah langsung memicu popup. FP belum terukur |
| naikkan `asks_password` di atas 15 | toko, PMB, dukcapil sah sudah 15 (L03, L05, L10) |
| keyword `kode pendaftaran` sebagai OTP | dipakai PPDB/pendaftaran sah. FP belum terukur, halaman sasarannya di balik login |

## D. Issue untuk Umar (draf, satu topik per issue)

Label `question`, assign `@umarmuhdhor`. Judul: `<area>: <pertanyaan>`.

### D1. `contracts / L3: sinyal kirim data ke Telegram`

**Context (angka dihitung ulang 29 Okt 2026, bukan 18).** 12 dari 25 situs scam punya host `api.telegram.org` + token bot + method `send*` di skrip inline atau `action` form; 13 punya host; 19 menyebut kata "telegram" (sebagian hanya saluran, bukan kirim data). 0 dari 9 situs sah yang HTML-nya terbaca (L01 tidak terbaca). 6 dari 25 punya `<script src>` sendiri yang tidak terbaca, dan situs 19 mengirim lewat pembungkus `sendOtpDataToTelegram` yang tidak kena pola. Detail: [hasil-analisis-telegram.md](hasil-analisis-telegram.md). Snapshot saat ini tidak memuat `<script>`, jadi L3 di server tidak bisa melihatnya.

**Hasil prototipe** ([HASIL-L3-PENUH.md](HASIL-L3-PENUH.md)): bobot kandidat token +35, host+method +30, host +10 (ambil yang tertinggi). Telegram menambah tepat 1 situs (05: 12 → 47), legit tetap 0. Pindai 0,008 ms median di Node, 0,03 ms di Simulator. Nilainya sebagai cadangan kalau RDAP timeout, bukan pertahanan utama (mudah dihindari lewat pembungkus atau file `<script src>`).

**Proposal (rekomendasi Imelda: opsi b, pindai di ekstensi).** Ekstensi memindai skrip inline dan `action` form sendiri, lalu hanya mengirim flag kecil. Token bot tidak pernah keluar dari perangkat. Field baru opsional dan aditif di `PageSnapshot`, misalnya `chatBotSink: { host: boolean, token: boolean, method: boolean }` (hanya boolean, tanpa isi skrip). Satu `Signal.id` baru, misalnya `sends_to_chat_bot`, di `scan-result.schema.json`. Opsi (a), mengirim isi skrip sampai 175 KB ke server, ditolak karena data keluar perangkat dan payload berat.

**Questions.**
1. Setuju opsi (b) (pindai di ekstensi, kirim flag boolean)? Kalau tidak, (a)?
2. Boleh menambah field `chatBotSink` ke `PageSnapshot` (aditif)? Siapa yang mengisinya di `ios/ShooExtension/`?
3. Boleh menambah id `sends_to_chat_bot` ke skema? Bentuk `Signal` untuk sinyal tanpa teks halaman (tanpa `evidence`)?
4. Sinyal ini masuk layer 2 (di perangkat) atau layer 3 (server)? Keduanya dibatasi 35 di ekstensi.
5. Daftar host yang dihitung: hanya `api.telegram.org`, atau juga `discord.com/api/webhooks` dan `api.whatsapp.com`?

**Until answered.** Tidak ada perubahan di `src/`. L3 tidak punya sinyal ini. Prototipe tetap di skrip uji.

### D2. `L3: peredam bobot untuk suffix pemerintah dan pendidikan`

**Status: usul ditunda.** Ini pencegahan, bukan perbaikan. Saat ini tidak ada situs sah yang salah-tangkap (maks 15). Perlu hanya kalau kita menambah sinyal OTP yang lebih agresif (misalnya `kode pendaftaran`). Karena itu sudah ditolak di bagian C, D2 tidak dibuat sebagai issue sampai ada kasus nyata.

**Context.** `go.id`, `ac.id`, `sch.id` sengaja dikeluarkan dari `LAYER3_QUIET` (D-imelda-30) karena situs kabupaten bisa diretas. Akibatnya SSO kampus dan login dukcapil sah tetap kena `asks_password` 15 (L03, L05, L10, M09). Belum jadi salah-tangkap (< 30), tapi ruangnya tipis kalau keyword OTP bertambah.

**Proposal.** Di host dengan suffix itu, bobot sinyal ambigu (`asks_otp`, `asks_password`, `asks_pin`) dikali 0,5. `brand_logo_offsite`, `urgent_language`, `new_domain` tetap penuh. Situs diretas yang menaruh brand atau urgent tetap tertangkap.

**Questions.**
1. Setuju peredam 0,5 untuk sinyal ambigu di `go.id`, `ac.id`, `sch.id`, atau tetap penuh?
2. Kalau setuju, `desa.id` dan `ac.id` yang dipakai kampus swasta ikut?

**Until answered.** Tidak ada perubahan. Bobot tetap penuh.

### D3. ~~brands.json: tambah Agoda dan DHL~~ (tidak jadi issue)

Menambah entri daftar tidak butuh izin. Sudah dikerjakan di bagian A. Shopee, Tokopedia, Lazada, dan J&T sudah ada di `brands.json`.

### D4. `L3: ukur skor gabungan L1 + L2 + L3 di ekstensi asli (OTP-only di host gratis)`

**Context (diperbarui 29 Okt 2026).** Ekstensi menampilkan layer 2 maks 35 dan layer 3 maks 35, total maks 70, popup di 30 (dikonfirmasi Imelda, bukan pertanyaan ke Umar). OTP sendirian bernilai 25 (< 30): situs 10 lolos (19 sudah tertutup perubahan title). Bobot OTP tidak dinaikkan karena OTP sah banyak. Dengan batas 35, OTP + satu sinyal lain (umur domain, logo brand, Telegram) sudah ≥ 30. Mungkin OTP-only di host gratis sudah tertutup layer 2 (`suspicious_link`), tapi belum terukur karena eval L3 memakai `localSignals` kosong.

**Proposal.** Tidak mengubah bobot. Ukur skor gabungan L1 + L2 + L3 lewat ekstensi asli dulu. Kalau OTP-only di host gratis masih lolos, baru bahas gate.

**Questions.**
1. Ada fixture atau skrip untuk menghitung skor gabungan L1 + L2 + L3 di ekstensi asli (bukan hanya `/analyze`)?
2. Apakah ambang popup 30 final?
3. Target mandat "≥ 90% scam ≥ 50" dan "≥ 70% ≥ 80" masih berlaku, atau diganti karena total maks 70?

**Until answered.** Tidak ada perubahan bobot. Saya ukur skor gabungan di Safari sendiri dulu.

## E. Yang belum terukur

- Halaman di balik klik (cek status PPDB, OTP 2FA sah, form NIK): tidak diuji karena aturan "jangan submit".
- Cloaking per jaringan (IP Indonesia).
- Perlu dicek manual di iPhone: **11**, **06**, **15**, **08**, **L03**, **L06**.
- Waktu pindai skrip untuk deteksi pengiriman ke Telegram: **sudah diukur** (Node 0,008 ms median, Simulator 0,03 ms; [HASIL-L3-PENUH.md](HASIL-L3-PENUH.md) dan [PLAN-ULANG.md](PLAN-ULANG.md)). Hitungan situs ke Telegram: 12 (host + token + method), 13 (host), 19 (menyebut), bukan 18.
- Waktu RDAP di server produksi (Cloudflare Worker) dan dari iPhone lewat jaringan seluler. Di Mac, RDAP dingin kena batas 1,5 dtk di 25% permintaan (siang) dan 2% (malam); penyebab perbedaan tidak diketahui.
