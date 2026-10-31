# Plan: jalan ulang eval layer 3 + ukur waktu pindai Telegram

Status: **dijalankan 29 Okt 2026** (hasil di bagian "Hasil"). Tidak ada commit, tidak ada issue (D1 di [consider.md](consider.md) tidak disentuh).
Pemilik: **Imelda** (plan ini dan folder `ai/`). Semua langkah di `ai/`. Hal di luar `ai/` (ekstensi, kontrak) hanya dicatat untuk Umar. Setelah Imelda memutuskan, baru `consider.md` dan hasil di-update.

## Tujuan

1. **Lapis A.** Pastikan hasil eval L3 bisa diulang persis dari snapshot tersimpan, tanpa jaringan, dan buktikan kenaikan 17 → 19 berasal dari perubahan yang belum di-commit.
2. **Lapis B.** Ukur berapa milidetik yang dibutuhkan untuk mendeteksi **pengiriman data ke Telegram** (usulan sinyal `sends_to_chat_bot`, lihat D1), dan berapa situs legit yang salah tertangkap.
3. **Lapis C.** Ukur pindai yang sama di **Safari iOS Simulator** (engine WebKit sungguhan, DOM sungguhan), bukan hanya Node. Hanya Simulator; iPhone asli opsional nanti.

Tidak termasuk: mengambil ulang situs scam (cepat mati, hasil tidak akan sama), mengambil file JS eksternal situs scam, memanggil LLM, mengubah ekstensi atau kontrak, `t.me` / Discord / WhatsApp (hanya Telegram bot API).

## Yang dicari (sinyal Telegram)

Hanya data yang dikirim ke Telegram. Tiga kolom dicatat terpisah, tidak digabung jadi satu angka:

| kolom | pola | catatan |
|---|---|---|
| host | `api.telegram.org` (literal) | |
| token | `\d{8,10}:[A-Za-z0-9_-]{35}` | nilai token ditulis `[disamarkan]` |
| method | `sendMessage`, `sendDocument`, `sendPhoto` | |

Sumber teks: isi `<script>` inline dan atribut `action` form. `<script src>` **tidak dibaca** (lihat B1).

## Batas lulus (ditetapkan sebelum mengukur)

Pindai dianggap **murah** kalau, di Simulator:
- median seluruh situs **< 5 ms**, dan
- situs terbesar **< 20 ms**.

Salah tangkap legit: target **0 dari 10**.

## Prasyarat

| butir | cara cek | kalau tidak ada |
|---|---|---|
| Node terpasang | `node --version` (terakhir: v26.8.1) | pasang Node |
| Snapshot tersimpan | `ls ai/test-layer3/snapshots` berisi `01.json`..`25.json`, `L01.json`..`L10.json` (ada per 29 Okt) | tanpa ini lapis A tidak bisa jalan; ambil ulang lewat [PROMPT.md](PROMPT.md) |
| HTML mentah scam | `ls ai/test-layer3/.html/*-desktop.html` | salin dari `/tmp/l3-html` (langkah P1). Kalau `/tmp` sudah hilang, ambil ulang lewat `PROMPT.md` bagian pengambilan |
| `.html/` di-gitignore | `git check-ignore ai/test-layer3/.html/x` | tambahkan ke `.gitignore` di `ai/` (P1) |
| Kode versi yang sama | `git rev-parse --short HEAD` dan `git status --short ai/src/layer3 ai/test` | catat versi di hasil |

### P1: amankan HTML (sekali, sebelum A)

`/tmp` terhapus saat Mac restart, dan scratchpad hilang saat sesi berganti.
1. Tambah `test-layer3/.html/` ke `.gitignore` di `ai/`, cek dengan `git check-ignore`.
2. Salin `/tmp/l3-html/*` ke `ai/test-layer3/.html/`.
3. Tulis `sha256` tiap file ke `ai/test-layer3/.html/SHA256SUMS` (ikut di-gitignore). Sebelum B dan C, cek dengan `shasum -c`.

Perkiraan: 5 menit.

## Langkah dan perkiraan waktu

Waktu di kolom ini **perkiraan lama mengerjakan**, bukan hasil ukur.

### Lapis A: eval L3 offline

Umur domain sudah tersimpan di snapshot (`rdapAgeDays`), jadi skor tidak bergeser walau dijalankan hari lain.

| # | langkah | perkiraan |
|---|---|---|
| A1 | Catat versi kode dan perubahan yang belum di-commit di `ai/src/layer3/` dan `ai/test/` | 2 menit |
| A2 | Jalankan `node ai/test-layer3/run.mjs` **dua kali**: (a) di HEAD: `git stash push -- ai/src/layer3 ai/test`, jalankan, `git stash pop`, lalu cek `git status` sama seperti A1; (b) dengan perubahan. Simpan kedua keluaran | 5 menit |
| A3 | Bandingkan dengan `HASIL-ANALISIS.md` bagian 6: target (a) 17 dari 25, (b) 19 dari 25 (consider.md bagian A), dan 0 legit mencapai 30 | 10 menit |
| A4 | Jalankan tes `ai/test` dan catat jumlah lulus | 3 menit |
| A5 | Catat selisih. `HASIL-ANALISIS.md` hanya diubah setelah Imelda setuju | 5 menit |

Total lapis A: sekitar 25 menit.

Penulisan legit di hasil:
- **"0 dari 10, bisa diulang"** untuk L01–L10.
- 25 situs di [HASIL-LEGIT-TAMBAHAN.md](HASIL-LEGIT-TAMBAHAN.md) ditulis **"tidak bisa diulang, beda cara ambil"** (Chrome headless, tanpa snapshot; scam pakai `curl`). Membuat snapshot untuk 25 situs itu tugas terpisah, di luar plan ini.

**Kalau meleset** (A2 bukan 17/19, atau A4 ada tes gagal): B dan C tetap jalan, karena tidak bergantung pada skor L3. Selisihnya ditulis di bagian paling atas hasil.

### Lapis B: ukur waktu pindai Telegram (Node)

| # | langkah | perkiraan |
|---|---|---|
| B1 | Hitung ulang dari HTML desktop **dan** iPhone, tiga kolom (host, token, method), catat daftar id. Ini menyelesaikan selisih 13 / 19 / 18. Hitung juga situs yang punya `<script src>` dari domain sendiri dan beri label "tidak terbaca" (file JS-nya tidak diambil) | 15 menit |
| B2 | Tulis `ai/test-layer3/ukur-telegram.mjs`: baca HTML dari `ai/test-layer3/.html/`, ambil teks tiap `<script>` inline dan atribut `action` form, cari tiga pola, cetak waktu per situs. Hanya baca | 20 menit |
| B3 | Jalankan 5 kali per situs, ambil **median** dan maksimum. Pakai `performance.now()`, buang run pertama (pemanasan) | 5 menit |
| B4 | Ukur pembanding di mesin yang sama: `analyzeSnapshot` (rules L3) per snapshot | 5 menit |
| B5 | Catat ukuran total teks `<script>` inline per situs (KB) | 5 menit |
| B6 | Isi tabel hasil B dan tulis kesimpulan satu paragraf | 10 menit |
| B7 | **Salah tangkap legit.** Ambil HTML halaman pertama L01–L10 pakai `curl` (UA iPhone dan desktop, situs sah), simpan di `.html/` dengan nama `L01-desktop.html` dst., tambah ke `SHA256SUMS`. Jalankan `ukur-telegram.mjs` pada 10 situs itu, catat yang terdeteksi per kolom | 10 menit |

Total lapis B: sekitar 70 menit.

### Lapis C: ukur di Safari iOS Simulator (WebKit sungguhan)

Idenya: sajikan HTML tersimpan dari localhost dengan CSP yang memblokir semua JavaScript scam, semua jaringan, semua form, dan semua perpindahan halaman, lalu jalankan skrip ukur milik kita di Safari Simulator. Yang diukur adalah DOM dan pencarian string Safari, bukan eksekusi halaman scam.

Header CSP yang wajib terkirim di setiap halaman scam:

```text
Content-Security-Policy: default-src 'none'; script-src 'nonce-<acak>'; connect-src 'self'; form-action 'none'; base-uri 'none'
```

`connect-src 'self'` hanya untuk mengirim hasil ke server 127.0.0.1. `default-src 'none'` tidak menahan form dan `<meta http-equiv="refresh">`, jadi dua hal itu ditangani terpisah (header `form-action` dan langkah C1).

| # | langkah | perkiraan |
|---|---|---|
| C1 | Tulis `ai/test-layer3/ukur-safari/` berisi server statis kecil (Node, hanya `127.0.0.1`) dan halaman ukur. Server: (1) kirim header CSP di atas; (2) **buang** tag `<meta http-equiv="refresh">` dan `<meta http-equiv="Content-Security-Policy">` dari HTML sebelum disajikan; (3) sisipkan skrip ukur ber-nonce; (4) satu endpoint `POST /hasil` yang menulis hasil ke `ukur-safari/hasil.json` (di-gitignore). HTML dibaca dari `.html/`, tidak disalin ke tempat lain | 35 menit |
| C2 | Skrip ukur (satu-satunya yang ber-nonce): `querySelectorAll('script:not([src])')`, ambil `textContent`, ditambah atribut `action` form, cari tiga pola. Timer Safari kasar (sekitar 1 ms), jadi ulangi pindai 200 kali lalu bagi. Kirim hasil ke `POST /hasil` | 20 menit |
| C3a | **Uji pagar dulu.** Buat 1 halaman uji berisi `<meta http-equiv="refresh" content="0;url=https://example.com">`, `<script>` tanpa nonce, form dengan tombol submit, dan `<img src="https://example.com/x.png">`. Buka di Simulator. Lulus kalau: halaman tetap di 127.0.0.1, skrip tanpa nonce tidak jalan, submit diblokir, tidak ada permintaan keluar. Cek juga header CSP lewat `curl -I`. **Kalau tidak lulus, berhenti, jangan buka halaman scam** | 10 menit |
| C3 | Boot Simulator iPhone, buka halaman ukur lewat `open_url`, jalankan untuk situs terbesar dulu, lalu semua situs yang punya skrip inline. Catat model simulator dan versi iOS | 20 menit |
| C4 | Buang run pertama, ambil median dari 5 kali halaman dimuat ulang per situs (dari `hasil.json`). Bandingkan dengan angka Node di Lapis B dan dengan batas lulus | 10 menit |
| C5 | Isi tabel hasil C dan tulis satu paragraf: lulus batas atau tidak, dan seberapa jauh angka Simulator dari Node | 10 menit |

Total lapis C: sekitar 105 menit.

Peringatan yang harus ikut ditulis di hasil:
- Simulator memakai CPU Mac, jadi lebih cepat dari iPhone asli. Angkanya batas bawah, bukan angka iPhone.
- Yang diukur hanya pindai. Waktu mengunduh halaman tidak dihitung, karena ekstensi membaca halaman yang sudah termuat.
- Ini bukan waktu di ekstensi asli.
- Opsional nanti, oleh Imelda: buka `http://<IP-Mac>:<port>/` di Safari iPhone asli (satu Wi-Fi) untuk angka sebenarnya. Server dibuka ke jaringan lokal hanya untuk itu, dan ditutup setelahnya.

### Yang tidak bisa dikerjakan di sini (untuk Umar, belum jadi issue)

| butir | alasan |
|---|---|
| Ukur waktu pindai di dalam ekstensi asli di iPhone | menyentuh `ios/ShooExtension/`, milik Lead |
| Tambah `endpoints` ke `PageSnapshot` | menyentuh `contracts/`, milik Lead |

Dicatat di sini saja. Masuk ke issue D1 setelah Imelda memutuskan.

## Hasil (dijalankan 29 Okt 2026)

Versi kode: `5c19d6f` + 4 file belum di-commit (`ai/src/layer3/content.js`, `forms.js`, `ai/test/content.test.mjs`, `forms.test.mjs`). Node v26.8.1. Simulator: iPhone 17 Pro, iOS 26.3 (runtime 26.3.1, 23D8133); Safari melaporkan `iPhone OS 18_7 ... Version/26.3` (string user-agent iOS dibekukan). Tidak ada commit, push, atau issue. `consider.md` dan `HASIL-ANALISIS.md` tidak diubah.

### Selisih dan hal yang meleset (baca ini dulu)

1. **Lapis A: HEAD menghasilkan 18 dari 25, bukan 17.** Dengan perubahan: 19 dari 25 (cocok dengan target). Yang naik karena perubahan yang belum di-commit hanya satu situs: 19 (25 → 50). Angka 17 di `HASIL-ANALISIS.md` tidak terulang dari HEAD; penyebab selisih 17 vs 18 tidak diselidiki (di luar plan). Jadi kalimat "naik 17 → 19 berasal dari perubahan yang belum di-commit" **tidak benar**: dari perubahan itu hanya 18 → 19.
2. **Angka Telegram tidak ada yang 18.** Dihitung sendiri dari 25 HTML tersimpan (desktop dan iPhone; hasil keduanya sama):
   - **12 situs** punya host, token, dan method sekaligus di isi `<script>` inline atau atribut `action` form (01, 02, 03, 04, 05, 09, 10, 17, 18, 23, 24, 25). Ketiga kolom jatuh di situs yang sama, jadi gabungannya juga 12.
   - **13 situs** kalau host dicari di seluruh HTML: tambahan 06, yang menaruh kode (host + token + `sendToTelegram`) sebagai teks ber-escape (`&lt;script&gt;`) di luar tag `<script>`, jadi pindai script inline tidak melihatnya. Dari HTML saja tidak bisa dipastikan itu kode yang jalan atau teks yang ditampilkan.
   - **19 situs** kalau yang dicari kata "telegram" (tanpa membedakan huruf besar kecil). Ini yang dicatat `consider.md` sebagai "19 menyebut". Sebagian besar hanya menyebut Telegram sebagai saluran ("PENDAFTARAN VIA TELEGRAM" di 12, 13, 16; "kode dikirim ke Telegram" di 14, 15), bukan mengirim data.
   - **18**: tidak bisa saya ulang dengan cara apa pun yang saya coba, jadi tidak ditulis sebagai fakta.
   - Situs 19 mengirim OTP lewat fungsi pembungkus `userDB.sendOtpDataToTelegram(...)` (komentar "Send the entered OTP to Telegram"). Tiga kolom tidak menangkapnya (bukan host, bukan token, bukan `sendMessage/Document/Photo`).
3. **Legit B7: 9 dari 10 terbaca, bukan 10.** Halaman pertama L01 (`sso.undip.ac.id/auth/user/login`) dijawab 302 ke `login.microsoftonline.com` dengan isi 0 byte, lalu berputar (redirect > 3). Tidak ada HTML untuk dipindai, jadi L01 "tidak terbaca", bukan "bersih". Dengan HTML: **0 dari 9** terdeteksi.
4. **Situs dengan `<script src>` sendiri ("tidak terbaca")**: 6 dari 25 scam (04, 07, 12, 13, 16, 19) dan 9 dari 9 legit terbaca. File JS-nya tidak diambil, jadi jumlah situs scam yang mengirim ke Telegram lewat file luar tidak terhitung. Angka 12 adalah batas bawah.

### Lapis A

| versi | scam tertangkap (dari 25) | legit ≥ 30 (dari 10) | tes lulus |
|---|---:|---:|---|
| HEAD | 18 (phishing 14/20, scam 4/5) | 0 (maks 15: L03, L05, L10) | 332 dari 332 |
| dengan perubahan | 19 (phishing 15/20, scam 4/5) | 0 (maks 15: L03, L05, L10) | 337 dari 337 |

- Diulang dari `snapshots/` tanpa jaringan: `node ai/test-layer3/run.mjs` (a) di HEAD lewat `git stash push -- ai/src/layer3 ai/test` lalu `git stash pop`, (b) dengan perubahan. `git status` sebelum dan sesudah stash sama (diff patch ai/src/layer3 + ai/test juga identik). Ada satu stash lain milik branch lain (`wip-xcstrings-reorder`) yang sudah ada sebelum sesi ini dan tidak disentuh.
- Beda skor HEAD → dengan perubahan: 01, 02, 03 (+25, sinyal `asks_otp` `mobileToken`), 09 (+25, brand Agoda), 19 (+25, brand Shopee; satu-satunya yang berpindah ke tertangkap), 17 (skor sama, bukti OTP `otpInput` → `keyBca`).
- Tidak tertangkap setelah perubahan: 05 (12), 11 (0), 14 (0), 15 (0), 20 (15), 22 (15). Dari 12 situs yang mengirim ke Telegram, hanya **05** ada di daftar ini; 11 situs lain sudah ≥ 30 dengan atau tanpa sinyal Telegram.
- Legit "tidak bisa diulang": 25 situs di `HASIL-LEGIT-TAMBAHAN.md` (Chrome headless, tanpa snapshot). Tidak diukur dan tidak ditulis sebagai fakta di sini.

### Lapis B (Node v26.8.1). Angka Node hanya pembanding kasar, bukan angka iPhone.

Cara ukur: satu "run" = rata-rata 200 pindai berurutan (ekstrak teks `<script>` inline + `action` form dari HTML mentah dengan regex, lalu tiga pola); 5 run, run pertama dibuang, median dan maks dari 4 run sisanya. HTML desktop. Pola token memakai `(?<!\d)` di depan agar tidak cocok di tengah angka panjang; selain itu sama dengan plan.

| id | skrip inline (KB) | `<script src>` sendiri | median pindai (ms) | maks (ms) | host | token | method |
|---|---:|---:|---:|---:|:-:|:-:|:-:|
| 01 | 11.0 | 0 | 0.008 | 0.010 | ya | ya | ya |
| 02 | 11.0 | 0 | 0.007 | 0.007 | ya | ya | ya |
| 03 | 8.9 | 0 | 0.004 | 0.005 | ya | ya | ya |
| 04 | 11.6 | 1 | 0.006 | 0.007 | ya | ya | ya |
| 05 | 2.2 | 0 | 0.001 | 0.001 | ya | ya | ya |
| 06 | 60.0 | 0 | 0.110 | 0.115 | - | - | - |
| 07 | 3.6 | 1 | 0.005 | 0.006 | - | - | - |
| 08 | 1.1 | 0 | 0.002 | 0.002 | - | - | - |
| 09 | 2.5 | 0 | 0.002 | 0.002 | ya | ya | ya |
| 10 | 3.6 | 0 | 0.003 | 0.003 | ya | ya | ya |
| 11 | 6.1 | 0 | 0.008 | 0.008 | - | - | - |
| 12 | 5.7 | 2 | 0.009 | 0.010 | - | - | - |
| 13 | 5.7 | 2 | 0.010 | 0.010 | - | - | - |
| 14 | 1.6 | 0 | 0.003 | 0.003 | - | - | - |
| 15 | 3.8 | 0 | 0.007 | 0.007 | - | - | - |
| 16 | 5.7 | 2 | 0.009 | 0.009 | - | - | - |
| 17 | 13.7 | 0 | 0.007 | 0.008 | ya | ya | ya |
| 18 | 11.6 | 0 | 0.005 | 0.006 | ya | ya | ya |
| 19 | 10.1 | 2 | 0.011 | 0.011 | - | - | - |
| 20 | 3.9 | 0 | 0.005 | 0.005 | - | - | - |
| 21 | 2.1 | 0 | 0.007 | 0.007 | - | - | - |
| 22 | 2.4 | 0 | 0.003 | 0.003 | - | - | - |
| 23 | 2.7 | 0 | 0.003 | 0.003 | ya | ya | ya |
| 24 | 3.5 | 0 | 0.003 | 0.004 | ya | ya | ya |
| 25 | 3.4 | 0 | 0.003 | 0.003 | ya | ya | ya |

Ringkasan Node: semua 34 situs ber-HTML median **0,007 ms**, maks **0,256 ms**. Scam saja: median 0,005 ms, maks 0,115 ms (situs 06). Legit saja: median 0,051 ms, maks 0,256 ms (L09). Pembanding rules L3 (`analyzeSnapshot`, 35 snapshot): median 0,033 ms, maks 0,196 ms. Pindai Telegram di Node sebanding dengan rules L3, dan jauh di bawah 1 ms.

Lapis B7 (legit, HTML halaman pertama dari `curl`, UA iPhone dan desktop, 29 Okt 2026):

| id | skrip inline (KB) | `<script src>` sendiri | median pindai (ms) | host | token | method |
|---|---:|---:|---:|:-:|:-:|:-:|
| L02 | 21.9 | 14 | 0.044 | - | - | - |
| L03 | 0.7 | 1 | 0.003 | - | - | - |
| L04 | 16.4 | 27 | 0.051 | - | - | - |
| L05 | 49.6 | 15 | 0.088 | - | - | - |
| L06 | 89.4 | 3 | 0.113 | - | - | - |
| L07 | 7.4 | 8 | 0.029 | - | - | - |
| L08 | 26.0 | 5 | 0.058 | - | - | - |
| L09 | 175.7 | 20 | 0.253 | - | - | - |
| L10 | 0.3 | 15 | 0.008 | - | - | - |
| L01 | - | - | - | tidak terbaca | tidak terbaca | tidak terbaca |

Terdeteksi: **0 dari 9** terbaca di ketiga kolom (desktop dan iPhone sama). L01 tidak terbaca (lihat selisih 3). Catatan: nama method seperti `sendMessage` mudah muncul di kode sah (misalnya widget chat); di sampel ini tidak ada yang muncul, tetapi sampelnya hanya 9.

### Lapis C (Safari iOS Simulator). Model simulator dan versi iOS: iPhone 17 Pro, iOS 26.3 (26.3.1, 23D8133).

**Angka Simulator adalah batas bawah**: Simulator memakai CPU Mac, lebih cepat dari iPhone asli. Ini bukan angka iPhone, bukan waktu di ekstensi asli, dan hanya pindai (mengunduh halaman tidak dihitung).

Cara ukur: server `ukur-safari/server.mjs` (hanya `127.0.0.1`, cek header Host) menyajikan HTML desktop tersimpan dengan header CSP persis seperti plan, `<meta http-equiv>` dibuang, dan satu skrip ber-nonce. Skrip membaca DOM sungguhan (`script:not([src])` + `form[action]`). Per muatan halaman: minimal 200 pindai dan minimal 50 ms, dirata-rata (timer Safari kasar, ±1 ms). 5 muatan per situs, muatan pertama dibuang, median dan maks dari 4 sisanya. Urutan: skrip inline terbesar dulu. 170 muatan selesai, 0 error. Hasil 12 situs yang kena sama persis dengan Node (tidak ada beda hit di 34 situs, stabil di semua muatan).

Uji pagar C3a **lulus** sebelum halaman scam dibuka (halaman uji milik sendiri `uji-pagar.html`, berisi meta refresh, meta CSP, skrip tanpa nonce, `<script src>`, form + tombol, img, iframe, `preconnect`/`dns-prefetch`/`prefetch`): tetap di 127.0.0.1; skrip tanpa nonce tidak jalan; submit diblokir `form-action` (lewat `requestSubmit`; ketukan nyata di tombol: halaman tetap dan port penjebak tetap 0); img, iframe, `<script src>` diblokir; port penjebak lokal (127.0.0.1:8766) menerima 0 koneksi; `curl -I` menunjukkan `content-security-policy: default-src 'none'; script-src 'nonce-<acak>'; connect-src 'self'; form-action 'none'; base-uri 'none'`. Selisih dari plan: permintaan keluar diuji ke port penjebak lokal (bukan `example.com`) supaya kebocoran akan terlihat; server juga membuang semua `<meta http-equiv>` (bukan hanya refresh dan CSP) dan `<link>` preconnect/prefetch, menolak halaman bila `http-equiv` masih tersisa, dan menolak halaman scam sampai berkas `.uji-pagar-lulus` ada.

| id | skrip inline (KB) | median pindai (ms) | maks (ms) | kali pertama, kasar (ms) | median Node (ms) | host | token | method |
|---|---:|---:|---:|---:|---:|:-:|:-:|:-:|
| L09 | 175.7 | 2.425 | 2.475 | 3.0 | 0.253 | - | - | - |
| L06 | 89.4 | 1.098 | 1.115 | 2.0 | 0.113 | - | - | - |
| 06 | 60.0 | 0.742 | 0.745 | 1.0 | 0.110 | - | - | - |
| L05 | 49.6 | 0.635 | 0.650 | 1.0 | 0.088 | - | - | - |
| L08 | 26.0 | 0.370 | 0.380 | 1.0 | 0.058 | - | - | - |
| L02 | 21.9 | 0.290 | 0.290 | 1.0 | 0.044 | - | - | - |
| L04 | 16.2 | 0.220 | 0.220 | 1.0 | 0.051 | - | - | - |
| 17 | 13.7 | 0.004 | 0.004 | 0.0 | 0.007 | ya | ya | ya |
| 04 | 11.6 | 0.002 | 0.002 | 0.0 | 0.006 | ya | ya | ya |
| 18 | 11.6 | 0.002 | 0.002 | 0.0 | 0.005 | ya | ya | ya |
| 01 | 11.0 | 0.013 | 0.014 | 1.0 | 0.008 | ya | ya | ya |
| 02 | 11.0 | 0.013 | 0.014 | 0.0 | 0.007 | ya | ya | ya |
| 19 | 9.9 | 0.143 | 0.146 | 0.0 | 0.011 | - | - | - |
| 03 | 8.9 | 0.004 | 0.004 | 0.0 | 0.004 | ya | ya | ya |
| L07 | 7.4 | 0.098 | 0.100 | 0.0 | 0.029 | - | - | - |
| 11 | 6.1 | 0.078 | 0.078 | 0.0 | 0.008 | - | - | - |
| 12 | 5.7 | 0.076 | 0.077 | 0.0 | 0.009 | - | - | - |
| 13 | 5.7 | 0.075 | 0.076 | 0.0 | 0.010 | - | - | - |
| 16 | 5.7 | 0.076 | 0.076 | 1.0 | 0.009 | - | - | - |
| 15 | 3.8 | 0.050 | 0.051 | 1.0 | 0.007 | - | - | - |
| 20 | 3.8 | 0.056 | 0.056 | 0.0 | 0.005 | - | - | - |
| 07 | 3.6 | 0.048 | 0.049 | 1.0 | 0.005 | - | - | - |
| 10 | 3.6 | 0.004 | 0.004 | 1.0 | 0.003 | ya | ya | ya |
| 24 | 3.5 | 0.002 | 0.002 | 0.0 | 0.003 | ya | ya | ya |
| 25 | 3.4 | 0.001 | 0.001 | 0.0 | 0.003 | ya | ya | ya |
| 23 | 2.7 | 0.002 | 0.002 | 1.0 | 0.003 | ya | ya | ya |
| 09 | 2.5 | 0.004 | 0.004 | 0.0 | 0.002 | ya | ya | ya |
| 22 | 2.3 | 0.030 | 0.030 | 0.0 | 0.003 | - | - | - |
| 05 | 2.2 | 0.002 | 0.002 | 0.0 | 0.001 | ya | ya | ya |
| 21 | 2.0 | 0.026 | 0.027 | 0.0 | 0.007 | - | - | - |
| 14 | 1.6 | 0.021 | 0.022 | 0.0 | 0.003 | - | - | - |
| 08 | 1.1 | 0.014 | 0.015 | 0.0 | 0.002 | - | - | - |
| L03 | 0.7 | 0.008 | 0.008 | 0.0 | 0.003 | - | - | - |
| L10 | 0.3 | 0.005 | 0.005 | 1.0 | 0.008 | - | - | - |

Ringkasan Simulator: semua 34 situs median **0,028 ms**, maks **2,475 ms**. Scam saja: median 0,014 ms, maks 0,745 ms (06). Legit saja: median 0,290 ms, maks 2,475 ms (L09). **Lulus batas** (median < 5 ms dan situs terbesar < 20 ms), dengan selisih besar. Situs terbesar (skrip inline): **L09**, 175,7 KB, 2,425 ms (legit, oss.go.id). Terbesar di antara scam: 06, 60,0 KB, 0,742 ms. Pada situs tanpa hit Safari sekitar 4 sampai 13 kali lebih lambat dari Node (L09: 2,425 vs 0,253 ms); pada situs yang kena, hampir sama. Waktu terburuk ada di halaman tanpa hit karena regex membaca seluruh teks; halaman yang kena berhenti cepat. Kolom "kali pertama" = satu pindai dengan timer 1 ms, maksimum 3 ms (L09); ini batas kasar waktu dingin, bukan rata-rata hangat.

### Belum terukur

- iPhone asli (opsional, oleh Imelda, lewat `http://<IP-Mac>:8765/`; server sekarang hanya `127.0.0.1` dan perlu dibuka ke jaringan hanya untuk itu).
- Waktu di dalam ekstensi Safari asli (tugas Umar, `ios/ShooExtension/`) dan lebar pindai di sana (apa saja yang dikirim dalam `PageSnapshot`).
- Isi file `<script src>` situs scam (6 dari 25) dan URL yang dirakit saat runtime atau base64: pindai teks tidak melihatnya.
- Waktu dingin satu kali di Node (angka "sekali" di Node sudah hangat) dan waktu dingin presisi di Safari (timer 1 ms).
- 25 legit tambahan (tidak ada snapshot) dan HTML iPhone di Safari (Safari hanya menyajikan HTML desktop; hit di Node sama untuk kedua UA).
- Selisih 17 vs 18 di HEAD pada Lapis A.

### Berkas yang dibuat

`ai/test-layer3/ukur-telegram.mjs`, `ai/test-layer3/ukur-safari/{pola.js,ukur.js,uji.js,uji-pagar.html,server.mjs}`, empat baris `.gitignore` baru di `ai/.gitignore` (`.html/`, `hasil.json`, `hasil-uji.json`, `.uji-pagar-lulus`). Tidak ada berkas di luar `ai/` yang diubah. Berkas yang tidak masuk repo: `.html/` (HTML mentah + `SHA256SUMS`), `ukur-safari/hasil.json`, `ukur-safari/hasil-uji.json`, `ukur-safari/.uji-pagar-lulus`.

## Batas dan keamanan

- Hanya baca. Jangan buka situs scam asli di browser, jangan submit form, jangan jalankan JS halaman, jangan ambil file JS eksternal situs scam.
- Satu-satunya cara halaman scam dimuat di Safari adalah lapis C: dari `127.0.0.1`, dengan header CSP di atas, meta refresh dan meta CSP sudah dibuang, dan uji pagar C3a sudah lulus. Kalau salah satunya belum, jangan buka halamannya.
- Server lapis C hanya mendengarkan `127.0.0.1`. Tidak dibuka ke jaringan kecuali Imelda memintanya untuk uji iPhone asli, dan ditutup setelahnya.
- Jaringan hanya dipakai untuk: ambil HTML legit L01–L10 (B7), dan ambil ulang HTML scam yang hilang (prasyarat). Selain itu tidak ada.
- Token bot Telegram ditulis `[disamarkan]` di semua keluaran.
- HTML mentah dan `hasil.json` tidak masuk repo (`.html/` dan `ukur-safari/hasil.json` di-gitignore).
- Jangan ubah `contracts/`, `ios/`, `detector/`. Jangan buat issue. Jangan commit.

## Prompt untuk menjalankan (tempel ke chat baru di folder repo `Final-CH7`)

```text
Kamu mengerjakan plan di ai/test-layer3/PLAN-ULANG.md untuk proyek Shoo. Baca file itu dan ai/CLAUDE.md dulu. Pemilik plan dan folder ai/ adalah Imelda.

Tugas: jalankan P1, Lapis A (eval L3 offline), Lapis B (ukur waktu pindai Telegram di Node + salah tangkap legit), dan Lapis C (ukur di Safari iOS Simulator) sesuai plan, isi tabel hasil di plan, dan laporkan.

Aturan wajib:
- Hanya edit file di ai/. Jangan sentuh contracts/, ios/, detector/.
- Jangan buat atau ubah issue GitHub. Jangan sentuh bagian D di consider.md.
- Jangan commit, jangan push. Di A2, git stash hanya untuk ai/src/layer3 dan ai/test, lalu langsung git stash pop; cek git status sama seperti sebelumnya.
- Yang dicari hanya pengiriman ke Telegram: host api.telegram.org, token bot, dan method sendMessage/sendDocument/sendPhoto, dicatat sebagai tiga kolom terpisah. Bukan t.me, Discord, atau WhatsApp.
- Hanya baca situs scam lewat HTML tersimpan di ai/test-layer3/.html/ (salin dulu dari /tmp/l3-html, cek sha256). Jangan buka situs aslinya, jangan submit form, jangan jalankan JS halaman, jangan ambil file <script src> situs scam. Pengecualian satu-satunya: Lapis C, dari 127.0.0.1, dengan header CSP persis seperti di plan, meta refresh dan meta CSP dibuang, dan uji pagar C3a harus lulus dulu. Kalau C3a gagal, berhenti dan lapor.
- Jaringan hanya untuk curl HTML legit L01-L10 (B7) dan ambil ulang HTML scam yang hilang.
- HTML mentah dan hasil.json jangan masuk repo. Token bot Telegram ditulis [disamarkan].
- Waktu: median dari 5 kali jalan per situs, buang run pertama. Catat versi kode (git rev-parse --short HEAD) dan versi Node.
- Batas lulus: median < 5 ms dan situs terbesar < 20 ms di Simulator. Legit salah tangkap target 0 dari 10.
- Kalau Lapis A meleset, B dan C tetap jalan; tulis selisihnya di paling atas hasil.
- Angka yang tidak bisa diulang (misalnya "18 situs ke Telegram", atau 25 legit tambahan) jangan ditulis sebagai fakta. Tulis angka yang kamu hitung sendiri dan jelaskan caranya.

Langkah: P1, A1-A5, B1-B7, lalu C1, C2, C3a, C3-C5 seperti di plan. Untuk Lapis C, pakai tool simulator iOS: 'attach' dulu sebelum membuka halaman, tulis di hasil bahwa angka Simulator adalah batas bawah (CPU Mac), bukan angka iPhone. Kalau ada langkah yang tidak bisa dijalankan, tulis alasannya, jangan dilewati diam-diam.

Keluaran: tabel hasil terisi di PLAN-ULANG.md, file ai/test-layer3/ukur-telegram.mjs, folder ai/test-layer3/ukur-safari/, dan ringkasan 7 baris di chat: tertangkap per grup (HEAD vs dengan perubahan), median/maks waktu pindai di Node dan di Simulator + lulus batas atau tidak, situs terbesar, hitungan Telegram per kolom, legit salah tangkap, situs dengan script src "tidak terbaca", dan apa yang belum terukur. Berhenti setelah itu dan tunggu aku. Jangan update consider.md atau HASIL-ANALISIS.md sebelum aku bilang.
```
