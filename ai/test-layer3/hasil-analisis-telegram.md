# Hasil analisis sinyal "kirim data ke Telegram" (L3): angka dan usulan poin

Status: **usulan, belum terkalibrasi, belum ada kode L3 yang diubah.** Angka di bagian 1–5 **dihitung ulang dari berkas tersimpan** dan bisa diulang (cara di bagian 0). Poin di bagian 7 datang dari pengalaman (prior), bukan dari ukur: 12 situs scam yang kena semuanya kena di ketiga kolom sekaligus, jadi data ini tidak bisa memisahkan kolom mana yang paling berguna. Perubahan di `contracts/` (field baru di `PageSnapshot`) dan `ios/ShooExtension/` lewat lead (Umar); pertanyaannya belum dibuat jadi issue, lihat `consider.md` D1 dan bagian 9.

Hanya pengiriman ke Telegram bot API yang dicari. Bukan `t.me`, Discord, atau WhatsApp. Halaman scam tidak pernah dibuka di browser kecuali lewat Safari Simulator dari `127.0.0.1` dengan CSP yang memblokir semua JavaScript halaman (detail di `PLAN-ULANG.md`, Lapis C).

## 0. Cara baca

**Sumber dan cara ulang.**
- 25 scam: HTML mentah hasil `curl` (UA desktop dan iPhone) di `ai/test-layer3/.html/` (di-gitignore, checksum di `SHA256SUMS`). Umur domain dan skor L3 dari `snapshots/`.
- 10 legit: L01–L10. HTML halaman pertama diambil ulang 29 Okt 2026.
- Ulang: `node ai/test-layer3/ukur-telegram.mjs` (hitungan dan waktu Node), `node ai/test-layer3/run.mjs` (skor L3), server Safari di `ai/test-layer3/ukur-safari/`.
- Versi kode: `5c19d6f` + 4 file belum di-commit di `ai/src/layer3` dan `ai/test`. Node v26.8.1. Simulator iPhone 17 Pro, iOS 26.3.

**Yang dibaca pindai.** Isi tiap `<script>` inline dan atribut `action` form. Isi file `<script src>` **tidak** dibaca (tidak diambil).

**Tiga kolom, dicatat terpisah:**

| kolom | pola |
|---|---|
| host | `api.telegram.org` |
| token | `\d{8,10}:[A-Za-z0-9_-]{35}` (nilai tidak pernah ditulis) |
| method | `sendMessage`, `sendDocument`, `sendPhoto` sebagai kata utuh |

**Batas.** Curl tidak menjalankan JavaScript. URL yang dirakit saat runtime, base64, dan kode di file `<script src>` tidak terbaca. Semua hitungan "kena" adalah **batas bawah**.

---

## 1. Berapa situs scam yang mengirim ke Telegram?

Tidak ada satu angka. Tergantung apa yang dihitung:

| cara hitung | situs | jumlah |
|---|---|---:|
| host + token + method di skrip inline / `action` form | 01, 02, 03, 04, 05, 09, 10, 17, 18, 23, 24, 25 | **12** |
| host `api.telegram.org` di mana saja di HTML | 12 di atas + 06 | **13** |
| kata "telegram" di mana saja (tanpa beda huruf besar) | 19 situs | **19** |
| "18 situs" | tidak bisa diulang dengan cara apa pun yang dicoba | tidak ditulis |

- **12** adalah angka yang dipakai untuk sinyal: ketiga kolom jatuh di situs yang sama, jadi gabungannya juga 12. Hasil sama untuk HTML desktop dan iPhone.
- **06** menaruh kode (host, token, `sendToTelegram`) sebagai teks ber-escape di luar tag `<script>`. Dari HTML saja tidak bisa dipastikan itu kode yang jalan atau teks yang ditampilkan. Tidak dihitung.
- **19** sama dengan "19 menyebut" di `consider.md`. Sebagian besar hanya menyebut Telegram sebagai saluran: "PENDAFTARAN VIA TELEGRAM" (12, 13, 16), "kode dikirim ke Telegram" (14, 15). Itu bukan mengirim data.
- **Situs 19** mengirim OTP lewat pembungkus `userDB.sendOtpDataToTelegram(...)`. Tidak kena tiga kolom (bukan host, bukan token, bukan nama method standar). Contoh nyata kenapa pindai teks bisa dihindari dengan nama fungsi sendiri.
- **Situs dengan `<script src>` sendiri ("tidak terbaca"): 6 dari 25** (04, 07, 12, 13, 16, 19). Kalau pengiriman ke Telegram ada di file itu, tidak terhitung. 04 sudah kena lewat skrip inline; 07, 12, 13, 16, 19 tidak.

---

## 2. Legit

| hasil | jumlah |
|---|---:|
| L02–L10 (HTML terbaca): host / token / method | **0 / 0 / 0** dari 9 |
| L01 | **tidak terbaca**: halaman pertama 302 ke `login.microsoftonline.com`, isi 0 byte |
| legit yang punya `<script src>` sendiri | 9 dari 9 |

- "0 dari 10" **tidak bisa dinyatakan**; yang benar 0 dari 9 terbaca.
- Sampel kecil. Nama method seperti `sendMessage` mudah muncul di kode sah (widget chat, pembungkus `postMessage`). Di 9 situs ini tidak muncul, tapi itu bukan jaminan.
- 25 legit tambahan di `HASIL-LEGIT-TAMBAHAN.md` **tidak bisa diulang** (Chrome headless, tanpa snapshot). Tidak dipakai di sini.

---

## 3. Dampak ke skor L3 (Lapis A)

| versi | scam tertangkap (≥ 30) | legit ≥ 30 | tes |
|---|---:|---:|---|
| HEAD | 18 dari 25 | 0 dari 10 (maks 15) | 332 / 332 |
| dengan perubahan belum di-commit | 19 dari 25 | 0 dari 10 (maks 15) | 337 / 337 |

- HEAD menghasilkan **18**, bukan 17 seperti di `HASIL-ANALISIS.md` bagian 6. Dari perubahan yang belum di-commit hanya satu situs yang pindah ke tertangkap: **19** (25 → 50). Jadi "17 → 19 karena perubahan" tidak benar; dari perubahan itu hanya 18 → 19. Penyebab 17 vs 18 di HEAD tidak diselidiki.
- Tidak tertangkap setelah perubahan: 05 (12), 11 (0), 14 (0), 15 (0), 20 (15), 22 (15).
- **Irisan dengan Telegram:** dari 12 situs yang mengirim ke Telegram, **hanya 05** yang belum tertangkap. 11 lainnya sudah ≥ 30 dengan atau tanpa sinyal Telegram.

Artinya di set ini sinyal Telegram **menambah 1 situs** (05), bukan 12. Nilainya lebih ke cadangan: situs yang mengirim ke Telegram tetap tertangkap kalau sinyal lain hilang (misalnya umur domain tidak bisa dinilai di host bersama).

---

## 4. Waktu pindai

Angka Node hanya pembanding kasar. Angka Simulator memakai CPU Mac, jadi **batas bawah**, bukan angka iPhone, dan bukan waktu di ekstensi asli.

| ukuran | Node median / maks (ms) | Simulator median / maks (ms) |
|---|---:|---:|
| semua situs ber-HTML (34) | 0,007 / 0,256 | 0,028 / 2,475 |
| scam (25) | 0,005 / 0,115 | 0,014 / 0,745 |
| legit (9) | 0,051 / 0,256 | 0,290 / 2,475 |
| situs terbesar: L09 (legit), skrip inline 175,7 KB | 0,253 | 2,425 |
| scam terbesar: 06, 60,0 KB | 0,110 | 0,742 |
| pembanding rules L3 (`analyzeSnapshot`, 35 snapshot) | 0,033 / 0,196 | tidak diukur |

- **Lulus batas** (median < 5 ms, terbesar < 20 ms) di Simulator, dengan selisih besar.
- Waktu terburuk ada di halaman **tanpa** hit (regex membaca seluruh teks). Situs tanpa hit di Safari sekitar 4 sampai 13 kali lebih lambat dari Node; situs yang kena hampir sama.
- Satu muatan = rata-rata ≥ 200 pindai (≥ 50 ms). Itu waktu **hangat**. Waktu dingin satu kali hanya terukur kasar (timer Safari 1 ms): maksimum 3 ms (L09).
- Yang diukur hanya pindai DOM / teks. Mengunduh halaman, mengirim `PageSnapshot`, dan waktu di dalam ekstensi asli tidak termasuk.

---

## 5. Hasil Safari = hasil Node

170 muatan di Safari iOS Simulator (34 situs × 5), 0 error. Hit per situs sama persis dengan Node dan stabil di semua muatan. Uji pagar sebelum halaman scam dibuka lulus (skrip tanpa nonce tidak jalan, submit diblokir, tidak ada permintaan keluar). Detail di `PLAN-ULANG.md`.

---

## 6. Mudah dihindari

Sinyal ini hanya menangkap penyerang yang menulis kirim-ke-Telegram secara literal di halaman. Cara menghindari yang sudah terlihat atau mudah:

| cara | contoh / bukti | kena pindai? |
|---|---|---|
| bungkus lewat fungsi atau server sendiri | situs 19: `sendOtpDataToTelegram` | tidak |
| taruh di file `<script src>` | 6 dari 25 punya | tidak (file tidak dibaca) |
| rakit URL saat runtime / base64 | belum terlihat di 25 situs ini | tidak, kecuali token atau method tetap muncul |
| kirim lewat server perantara | tidak terlihat dari HTML | tidak |

Jadi: murah dan tanpa salah tangkap di sampel ini, tapi **bukan pertahanan utama**. Cocok sebagai pelengkap sinyal form dan umur domain.

---

## 7. Usulan poin (kandidat)

Satuan: poin tambahan di skor 0–100. Popup di 30. Prior = intuisi, bukan hasil ukur.

| Kombinasi | Poin | Prior & alasan |
|---|---:|---|
| **token** bot Telegram di skrip inline | **+35** | Token bot di JavaScript klien tidak punya alasan sah (siapa pun bisa membacanya). Cukup sendirian untuk melewati 30. |
| host `api.telegram.org` **dan** method `send*` | **+30** | Pola `fetch(.../bot…/sendMessage)`. Sangat spesifik. |
| host `api.telegram.org` saja | **+10** | Bisa tautan atau embed sah, kecil sendirian. |
| method `send*` saja | **0** | Nama umum di kode sah. Tidak dihitung. |

- Tidak digandakan: poin dari token dan dari host+method **tidak dijumlah**, ambil yang tertinggi.
- Token itu rahasia: jangan kirim nilainya ke server atau tampilkan di popup. Cukup penanda tetap, misalnya `[token bot disamarkan]`. Bentuk `Signal` untuk kasus ini perlu keputusan Lead (aturan `evidence` di `ai/CLAUDE.md` berlaku untuk sinyal teks).
- Data ini **tidak bisa memisahkan** token vs host vs method (12 dari 12 kena ketiganya). Pembedaan di atas murni dari prior.

---

## 8. Contoh hitung ulang (perkiraan manual, bukan hasil menjalankan kode)

| situs | skor L3 sekarang (dengan perubahan) | + usulan | hasil |
|---|---:|---|---|
| 05 (kena ketiga kolom) | 12 | +35 (token) | **≈ 47, popup**. Satu-satunya yang berubah status. |
| 01, 02, 03, 04, 09, 10, 17, 18, 23, 24, 25 | sudah ≥ 30 | +30 atau +35, total dibatasi 100 | tetap tertangkap |
| 19 (pembungkus `sendOtpDataToTelegram`) | 50 | tidak ada hit | **tetap 50** |
| 06 (kode ter-escape di luar script) | 0 | tidak ada hit | **tetap 0** |
| L02–L10 | 0–15 | tidak ada hit | **tetap 0–15** |

Perkiraan hasil: scam tertangkap 19 → **20 dari 25**, legit tetap 0. ~~Belum dijalankan lewat kode.~~ **Sudah dijalankan 29 Okt 2026** ([HASIL-L3-PENUH.md](HASIL-L3-PENUH.md), prototipe di `l3-penuh.mjs`):

| hitungan | scam ≥ 30 | legit ≥ 30 |
|---|---:|---:|
| umur beku, tanpa Telegram | 19 / 25 | 0 / 10 |
| umur beku + Telegram | **20 / 25** (hanya situs 05: 12 → 47) | 0 / 10 |
| umur hari ini + Telegram, 6 pass RDAP | 16–20 / 25 | 0 / 10 |

- Perkiraan manual **cocok**: Telegram menambah tepat 1 situs (05), di semua pass.
- Selisih ke 16–19 datang dari RDAP yang timeout (sinyal umur hilang), bukan dari Telegram.
- 12 dari 12 situs yang kena memegang token + host + method sekaligus, semuanya +35. Pindai di Node: median 0,008 ms, maks 0,35 ms.
- **Rekomendasi Imelda (29 Okt):** pindai di ekstensi (opsi b), hanya flag kecil ke server, token tidak keluar dari perangkat. Menunggu keputusan Lead di issue.

---

## 9. Yang perlu dilakukan sebelum masuk kode

1. **Di mana pindai dijalankan.** Dua pilihan, keputusan Lead:
   - **(a) Server (L3):** extension harus mengirim isi skrip inline. `PageSnapshot` sekarang tidak punya field itu (`contracts/`). Mengirim skrip sampai 175 KB per halaman berat dan menambah data yang meninggalkan perangkat.
   - **(b) Di perangkat (extension):** extension memindai sendiri dan hanya mengirim hasil kecil (misalnya `endpoints` atau flag). Butuh field baru di `PageSnapshot` dan perubahan di `ios/ShooExtension/`. Lebih ringan dan lebih privat; biaya pindainya di bagian 4.
2. **Pertanyaan untuk Umar (issue belum dibuat, ikuti `CLAUDE.md` rule 7):** (a) pilihan di atas; (b) bentuk `Signal` untuk sinyal tanpa teks halaman; (c) apakah sinyal ini masuk L2 (di perangkat) atau L3. Dicatat di `consider.md` D1; **D1 tidak diubah di dokumen ini**.
3. **Ukur di tempat yang benar.** Waktu di dalam ekstensi asli dan di iPhone asli belum terukur (bagian 4). Server Safari bisa dibuka ke jaringan lokal untuk uji iPhone asli kalau Imelda mau.
4. **Perluas legit.** 9 legit terlalu sedikit untuk menilai host dan method. Buat snapshot dan HTML untuk 25 legit tambahan sebelum bobot ditetapkan.
5. **Isi `<script src>` situs scam yang terkena (6 situs)** baru dibaca kalau diputuskan perlu, dengan cara aman terpisah (di luar plan ini, sekarang dilarang).
6. Tambah test di `ai/test/` untuk dua sisi: HTML scam kena, HTML legit tidak kena, setelah bobot disetujui.
7. `HASIL-ANALISIS.md` (angka 17) dan `consider.md` (angka 17 → 19, "19 menyebut") sudah diperbaiki 29 Okt 2026.
