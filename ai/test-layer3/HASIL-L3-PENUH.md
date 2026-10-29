# Hasil layer 3 penuh (RDAP + field + Telegram): skor dan waktu

Status: **sudah dijalankan 29 Okt 2026**, satu sesi. Plan: [PLAN-L3-PENUH.md](PLAN-L3-PENUH.md). Telegram adalah **prototipe dengan bobot kandidat** di skrip uji ([l3-penuh.mjs](l3-penuh.mjs)), bukan kode `src/`. Layer 4 (LLM) mati. Tabel di bawah dicetak oleh `node l3-penuh.mjs --report` dari `.hasil/l3-penuh.json`.

**Ringkasan jujur:** angka "umur hari ini" **tidak stabil**. RDAP dari server baru kena batas 1,5 dtk di 25% permintaan, dan tiap kali itu terjadi sinyal umur hilang. Jadi tangkapan "umur hari ini" ditulis sebagai **rentang antar pass**, bukan satu angka. Angka "umur beku" dan "Telegram" bisa diulang. **Update (malam hari, bagian 7):** diulang di jaringan yang sama beberapa jam kemudian, RDAP dingin hanya kena batas di 2% permintaan (bukan 25%) dan tangkapan umur hari ini naik ke 18–19 dari 25. Jadi masalah RDAP ini **bergantung pada kondisi jaringan atau waktu**, bukan bug yang jelas di kode.

## 0. Cara baca

**Sumber dan cara ulang.**
- 25 scam + 10 legit: `ai/test-layer3/snapshots/`. HTML untuk Telegram: `ai/test-layer3/.html/` (di-gitignore, `shasum -c SHA256SUMS`: 68 file OK sebelum uji).
- Ulang: comment baris `LLM_*` di `ai/.env`, lalu `node ai/test-layer3/l3-penuh.mjs` (menjalankan dan mematikan servernya sendiri, ±6 menit) dan `node ai/test-layer3/l3-penuh.mjs --report`. Skrip menolak jalan kalau ada `LLM_*` aktif.
- Versi kode: commit `5c19d6f` + 4 file belum di-commit (`src/layer3/content.js`, `src/layer3/forms.js`, `test/content.test.mjs`, `test/forms.test.mjs`). Node v26.8.1. Mac Apple M5.
- Waktu uji: 29 Okt 2026, 14.03 sampai 14.07 WITA (06:03–06:07 UTC). Jaringan: **tidak tercatat** (macOS tidak melaporkan jaringan Wi-Fi; jenis koneksi tidak diketahui).

**Tiga sumber skor:**

| bagian | dari mana |
|---|---|
| field + teks | `POST /analyze` (rules di `src/layer3`), body `{ snapshot, localSignals: [] }` |
| umur domain | RDAP live di `/analyze` (`SHOO_RDAP=1`), dibandingkan dengan `rdapAgeDays` beku di snapshot (26–28 Okt) |
| Telegram | prototipe di `l3-penuh.mjs`: token +35, host+method +30, host +10, ambil yang tertinggi, total dibatasi 100. Token ditulis `[disamarkan]` |

**Cara kerja uji (penyimpangan kecil dari plan, semua ditulis di sini):**
- Mode **mati** dan **hangat**: satu server hidup, 5 putaran × 35 situs berurutan. Putaran 1 mode hangat adalah **Lapis A** (server baru, cache kosong), putaran 2–5 adalah hangat.
- Mode **dingin**: plan menulis "restart tiap situs". Di sini server di-start ulang **tiap permintaan** (175 server), supaya kelima ulangan benar-benar dingin: cache dan bootstrap IANA kosong tiap kali. Akibatnya ada 175 unduhan bootstrap IANA dan 175 query registry dalam ±3,5 menit. Ulangan di luar, situs di dalam, supaya satu registry tidak kena 5 kali berturutan.
- Tiap server dingin menerima dulu **1 permintaan ke host resmi** (`www.bca.co.id`, RDAP dilewati) untuk memanaskan JIT server. Waktunya dicatat terpisah dan tidak masuk C2.
- Run pertama tiap situs dibuang **hanya untuk waktu**. Sinyal dari semua run dipakai untuk keajegan.
- Skor: jumlah bobot sinyal, dibatasi 100. Tangkapan dihitung di skor ≥ 30 / 50 / 80.
- `ai/test-layer3/.gitignore` (baru, isi `.hasil/`) dibuat karena `.hasil/` ternyata belum di-gitignore oleh `ai/.gitignore`.

**Batas.** Waktu diukur di Mac lewat 127.0.0.1. Jaringan HP ke server tidak termasuk. Waktu RDAP bergantung pada jaringan Mac saat itu dan server registry tiap TLD: ini contoh satu waktu, bukan angka tetap.

---

## 1. Tangkapan per versi

| versi | scam ≥ 30 | scam ≥ 50 | scam ≥ 80 | legit ≥ 30 | legit maks |
|---|---:|---:|---:|---:|---:|
| field + umur beku | 19 / 25 | 11 / 25 | 5 / 25 | 0 / 10 | 15 |
| field + umur hari ini (RDAP live) | 15 / 25 | 10 / 25 | 5 / 25 | 0 / 10 | 15 |
| field + umur hari ini + Telegram | 16 / 25 | 13 / 25 | 8 / 25 | 0 / 10 | 15 |

- Tidak tertangkap (< 30), umur beku: 05 (12), 11 (0), 14 (0), 15 (0), 20 (15), 22 (15)
- Tidak tertangkap (< 30), umur hari ini: 05 (12), 08 (15), 11 (0), 12 (25), 13 (25), 14 (0), 15 (0), 16 (25), 20 (15), 22 (15)
- Tidak tertangkap (< 30), + Telegram: 08 (15), 11 (0), 12 (25), 13 (25), 14 (0), 15 (0), 16 (25), 20 (15), 22 (15)
- Situs yang berubah status karena Telegram: 05
- Situs yang berubah status karena umur hari ini vs beku: 08 (35 → 15), 12 (35 → 25), 13 (35 → 25), 16 (35 → 25)

### Keajegan tangkapan antar pass RDAP (tiap pass = 35 situs, server baru per permintaan)

| pass | scam ≥ 30 | ≥ 50 | ≥ 80 | scam ≥ 30 + Telegram | ≥ 50 + Tg | ≥ 80 + Tg | legit ≥ 30 (+ Tg) |
|---|---:|---:|---:|---:|---:|---:|---:|
| A (server baru, pass 1) | 15 | 10 | 5 | 16 | 13 | 8 | 0 (0) |
| dingin 1 | 17 | 11 | 5 | 18 | 13 | 9 | 0 (0) |
| dingin 2 | 18 | 11 | 3 | 19 | 13 | 9 | 0 (0) |
| dingin 3 | 18 | 11 | 4 | 19 | 13 | 9 | 0 (0) |
| dingin 4 | 15 | 10 | 3 | 16 | 13 | 8 | 0 (0) |
| dingin 5 | 17 | 11 | 4 | 18 | 13 | 9 | 0 (0) |

Rentang antar pass: scam ≥ 30 15–18, ≥ 50 10–11, ≥ 80 3–5; dengan Telegram ≥ 30 16–19, ≥ 50 13–13, ≥ 80 8–9.

## 2. Umur domain: beku vs hari ini

| hasil RDAP hari ini | jumlah | situs |
|---|---:|---|
| sinyal ada, kelompok bobot sama dengan beku | 5 | 01, 02, 04, 07, 18 |
| sinyal ada, kelompok bobot bergeser | 1 | 03 (6 → 7 hari) |
| sinyal ada, beku `null` | 0 | - |
| tanpa sinyal, beku > 90 hari (masih tua) | 24 | 05, 06, 09, 10, 11, 14, 15, 19, 20 (beku null, hari ini tanpa sinyal), 21, 22, 23, 24, 25, L01, L02, L03, L04, L05, L06, L07, L08, L09, L10 |
| tanpa sinyal, beku ≤ 90 hari, jawaban cepat (bukan timeout) | 1 | 16 (beku 68 hari) |
| tanpa sinyal, beku ≤ 90 hari, kena batas 1,5 dtk (selisih waktu ≥ 1,4 dtk) | 4 | 08 (beku 22 hari), 12 (beku 68 hari), 13 (beku 87 hari), 17 (beku 53 hari) |
| tidak dicek (host resmi / populer atau bukan domain terdaftar) | 0 | - |

## 3. Per situs

| id | field + teks | umur beku → hari ini | Telegram | skor beku | skor hari ini | skor + Telegram | ≥ 30 |
|---|---:|---|---:|---:|---:|---:|:-:|
| 01 | 65 | 7 → 8 | +35 (host+token [disamarkan]+method) | 85 | 85 | 100 | ya |
| 02 | 65 | 7 → 8 | +35 (host+token [disamarkan]+method) | 85 | 85 | 100 | ya |
| 03 | 65 | 6 → 7 | +35 (host+token [disamarkan]+method) | 95 | 85 | 100 | ya |
| 04 | 65 | 21 → 22 | +35 (host+token [disamarkan]+method) | 85 | 85 | 100 | ya |
| 05 | 12 | 2247 → tanpa sinyal | +35 (host+token [disamarkan]+method) | 12 | 12 | 47 | ya |
| 06 | 35 | 10634 → tanpa sinyal | +0 | 35 | 35 | 35 | ya |
| 07 | 35 | 18 → 19 | +0 | 55 | 55 | 55 | ya |
| 08 | 15 | 22 → tanpa sinyal | +0 | 35 | 15 | 15 | - |
| 09 | 60 | 505 → tanpa sinyal | +35 (host+token [disamarkan]+method) | 60 | 60 | 95 | ya |
| 10 | 50 | 505 → tanpa sinyal | +35 (host+token [disamarkan]+method) | 50 | 50 | 85 | ya |
| 11 | 0 | 9584 → tanpa sinyal | +0 | 0 | 0 | 0 | - |
| 12 | 25 | 68 → tanpa sinyal | +0 | 35 | 25 | 25 | - |
| 13 | 25 | 87 → tanpa sinyal | +0 | 35 | 25 | 25 | - |
| 14 | 0 | 140 → tanpa sinyal | +0 | 0 | 0 | 0 | - |
| 15 | 0 | 259 → tanpa sinyal | +0 | 0 | 0 | 0 | - |
| 16 | 25 | 68 → tanpa sinyal | +0 | 35 | 25 | 25 | - |
| 17 | 40 | 53 → tanpa sinyal | +35 (host+token [disamarkan]+method) | 50 | 40 | 75 | ya |
| 18 | 65 | 10 → 11 | +35 (host+token [disamarkan]+method) | 85 | 85 | 100 | ya |
| 19 | 50 | 2465 → tanpa sinyal | +0 | 50 | 50 | 50 | ya |
| 20 | 15 | null → tanpa sinyal | +0 | 15 | 15 | 15 | - |
| 21 | 40 | 3179 → tanpa sinyal | +0 | 40 | 40 | 40 | ya |
| 22 | 15 | 6759 → tanpa sinyal | +0 | 15 | 15 | 15 | - |
| 23 | 40 | 9584 → tanpa sinyal | +35 (host+token [disamarkan]+method) | 40 | 40 | 75 | ya |
| 24 | 40 | 9584 → tanpa sinyal | +35 (host+token [disamarkan]+method) | 40 | 40 | 75 | ya |
| 25 | 55 | 9584 → tanpa sinyal | +35 (host+token [disamarkan]+method) | 55 | 55 | 90 | ya |
| L01 | 0 | 10715 → tanpa sinyal | tidak terbaca | 0 | 0 | 0 | - |
| L02 | 0 | 2626 → tanpa sinyal | +0 | 0 | 0 | 0 | - |
| L03 | 15 | 10715 → tanpa sinyal | +0 | 15 | 15 | 15 | - |
| L04 | 0 | 11430 → tanpa sinyal | +0 | 0 | 0 | 0 | - |
| L05 | 15 | 4604 → tanpa sinyal | +0 | 15 | 15 | 15 | - |
| L06 | 0 | 8554 → tanpa sinyal | +0 | 0 | 0 | 0 | - |
| L07 | 0 | 3878 → tanpa sinyal | +0 | 0 | 0 | 0 | - |
| L08 | 0 | 2876 → tanpa sinyal | +0 | 0 | 0 | 0 | - |
| L09 | 0 | 3149 → tanpa sinyal | +0 | 0 | 0 | 0 | - |
| L10 | 15 | 9666 → tanpa sinyal | +0 | 15 | 15 | 15 | - |

## 4. Waktu

Sampel per mode: 35 situs × 4 (run pertama dibuang) = 140. Median dan p95 (nearest-rank) dihitung dari semua sampel; p95 per situs dari 4 sampel tidak bermakna, jadi per situs hanya median.

| mode | n | median (ms) | p95 (ms) | maks (ms) |
|---|---:|---:|---:|---:|
| rules in-process (analyzeSnapshot, CPU) | 140 | 0.050 | 0.467 | 1.8 |
| C1 RDAP mati (rules + HTTP) | 140 | 1.7 | 2.0 | 2.9 |
| C2 RDAP dingin (HTTP) | 140 | 1132 | 1508 | 1511 |
| C3 RDAP hangat (HTTP) | 140 | 2.1 | 3.0 | 5.4 |
| C4 Telegram, pindai di Node | 136 | 0.008 | 0.147 | 0.352 |

- Waktu RDAP ≈ C2 − C1 (selisih median per situs): median 1153 ms, maks 1508 ms. Hangat (C3 − C1): median 0.392 ms, maks 0.963 ms.
- Permintaan pertama setelah server start (host resmi, tanpa RDAP): median 6.4 ms, maks 22.2 ms (n=175). Tidak dihitung di C2.
- Cek /_dev/layer4: RDAP mati off/off, RDAP hidup off/off, dingin 175 cek (off).

### Per situs (median 4 sampel, ms)

| id | C1 mati | C2 dingin | C3 hangat | C2 − C1 | kena batas | Telegram | rules in-process |
|---|---:|---:|---:|---:|:-:|---:|---:|
| 01 | 1.9 | 1366 | 2.9 | 1364 | - | 0.011 | 0.727 |
| 02 | 2.0 | 1110 | 2.4 | 1108 | - | 0.012 | 0.418 |
| 03 | 1.7 | 1230 | 2.3 | 1228 | - | 0.006 | 0.181 |
| 04 | 1.7 | 1223 | 2.6 | 1221 | - | 0.008 | 0.221 |
| 05 | 1.6 | 799 | 2.4 | 798 | - | 0.004 | 0.063 |
| 06 | 1.6 | 1259 | 2.1 | 1257 | - | 0.131 | 0.057 |
| 07 | 1.6 | 799 | 2.1 | 797 | - | 0.006 | 0.075 |
| 08 | 1.6 | 1313 | 2.1 | 1312 | - | 0.003 | 0.047 |
| 09 | 1.6 | 1112 | 2.0 | 1111 | - | 0.003 | 0.037 |
| 10 | 1.6 | 1010 | 2.0 | 1008 | - | 0.004 | 0.050 |
| 11 | 1.6 | 1505 | 2.1 | 1503 | ya | 0.010 | 0.046 |
| 12 | 1.8 | 1251 | 2.2 | 1249 | - | 0.010 | 0.242 |
| 13 | 1.8 | 1507 | 2.6 | 1505 | ya | 0.009 | 0.222 |
| 14 | 1.7 | 1509 | 2.2 | 1508 | ya | 0.004 | 0.050 |
| 15 | 1.7 | 1504 | 2.3 | 1502 | ya | 0.006 | 0.063 |
| 16 | 1.8 | 1505 | 2.2 | 1503 | ya | 0.009 | 0.123 |
| 17 | 1.8 | 1229 | 2.3 | 1227 | - | 0.009 | 0.129 |
| 18 | 1.7 | 1505 | 2.3 | 1503 | ya | 0.007 | 0.161 |
| 19 | 1.6 | 877 | 1.9 | 875 | - | 0.011 | 0.042 |
| 20 | 1.7 | 319 | 2.0 | 317 | - | 0.006 | 0.044 |
| 21 | 1.6 | 918 | 1.9 | 916 | - | 0.009 | 0.036 |
| 22 | 1.6 | 1155 | 2.0 | 1153 | - | 0.004 | 0.020 |
| 23 | 1.9 | 1506 | 2.3 | 1504 | ya | 0.004 | 0.125 |
| 24 | 1.9 | 1485 | 2.1 | 1483 | ya | 0.004 | 0.091 |
| 25 | 1.7 | 1233 | 2.0 | 1231 | - | 0.003 | 0.059 |
| L01 | 1.6 | 600 | 2.0 | 598 | - | - | 0.030 |
| L02 | 1.7 | 809 | 1.9 | 807 | - | 0.048 | 0.058 |
| L03 | 1.6 | 553 | 1.9 | 552 | - | 0.003 | 0.014 |
| L04 | 1.6 | 624 | 1.9 | 623 | - | 0.066 | 0.022 |
| L05 | 1.6 | 662 | 1.8 | 661 | - | 0.116 | 0.023 |
| L06 | 1.6 | 1332 | 1.9 | 1330 | - | 0.122 | 0.016 |
| L07 | 1.7 | 997 | 1.9 | 995 | - | 0.037 | 0.035 |
| L08 | 1.7 | 632 | 2.1 | 631 | - | 0.068 | 0.046 |
| L09 | 1.7 | 957 | 1.9 | 955 | - | 0.330 | 0.023 |
| L10 | 1.6 | 751 | 2.0 | 749 | - | 0.005 | 0.026 |

- Kena batas 1,5 dtk (diduga dari waktu, C2 − C1 ≥ 1,4 dtk): 8 situs: 11, 13, 14, 15, 16, 18, 23, 24
- Dari 175 permintaan dingin (5 ulangan), 44 kena batas (25%). Situs dan jumlahnya: 11 3/5, 12 2/5, 13 5/5, 14 3/5, 15 4/5, 16 3/5, 17 2/5, 18 3/5, 22 1/5, 23 3/5, 24 4/5, 25 1/5, 04 1/5, 01 2/5, 09 1/5, 06 2/5, L06 2/5, 02 1/5, 08 1/5

### Batas lulus

| ukuran | batas | hasil | lulus |
|---|---|---|:-:|
| rules (sync) | < 100 ms | maks 1.8 ms | ya |
| RDAP | ≤ 1,5 dtk | maks selisih dingin 1508 ms; 8 situs kena batas (batas = tanpa sinyal, bukan error) | ya (dipotong di batas) |
| total /analyze | ≤ 6,5 dtk | maks dingin 1511 ms, maks hangat 5.4 ms | ya |
| p95 HTTP dari klien | < 8 dtk | dingin 1508 ms, hangat 3.0 ms | ya |
| legit ≥ 30 | 0 dari 10 | umur beku 0, hari ini 0, + Telegram 0 | ya |

Permintaan non-200 atau error klien (semua mode): tidak ada. Sampel di atas 8 dtk: 0.

### Keajegan sinyal umur (RDAP hidup)

Situs yang sinyal `new_domain`-nya tidak sama di semua putaran (5 dingin + 5 di server hidup): 01 (dingin 3/5, server hidup 5/5), 02 (dingin 4/5, server hidup 5/5), 08 (dingin 4/5, server hidup 0/5), 12 (dingin 3/5, server hidup 0/5), 13 (dingin 1/5, server hidup 0/5), 16 (dingin 2/5, server hidup 0/5), 17 (dingin 4/5, server hidup 0/5), 18 (dingin 2/5, server hidup 5/5)
Sinyal rules lewat HTTP berbeda dari in-process: tidak ada

### Telegram (HTML desktop tersimpan)

- Scam dengan bobot > 0: 12 dari 25: 01 +35, 02 +35, 03 +35, 04 +35, 05 +35, 09 +35, 10 +35, 17 +35, 18 +35, 23 +35, 24 +35, 25 +35
- Legit dengan bobot > 0: tidak ada. Tidak terbaca: L01

### Meta

- Node v26.8.1, commit 5c19d6f, belum di-commit: M src/layer3/content.js; M src/layer3/forms.js; M test/content.test.mjs; M test/forms.test.mjs
- CPU: Apple M5. Mulai 2026-10-29T06:03:00.322Z. RDAP hidup selesai 2026-10-29T06:03:49.383Z; dingin selesai 2026-10-29T06:07:13.716Z.

---

## 5. Batas dan peringatan

- **Skor "umur hari ini" tidak stabil.** Di tabel keajegan: pass A 15/25, lima pass dingin 15–18/25 (scam ≥ 30). Sumbernya satu: RDAP kena batas 1,5 dtk lalu `null`. Situs yang kehilangan sinyal umur dan jatuh di bawah 30: 08, 12, 13, 16 (beku 35, tinggal 15–25). Jangan kutip satu angka dari pass A.
- **Timeout di server hidup dicache 10 menit** (`FAIL_TTL_MS`). Jadi putaran hangat 2–5 untuk situs yang timeout di pass A **mengulang** hasil pass A, bukan sampel baru. Itu sebabnya "server hidup 0/5" di keajegan tidak boleh dibaca sebagai 5 pengukuran. Waktu hangat (C3) hanya mengukur **cache hit**.
- **"Kena batas" disimpulkan dari waktu** (selisih C2 − C1 ≥ 1,4 dtk), bukan dilihat langsung. Penyebabnya (bootstrap IANA lambat atau registry lambat) **tidak dipisahkan di uji ini**; lihat bagian 7. Klasifikasi di bagian 2 dari satu pass; contoh 16: "jawaban cepat" di pass A, tapi di pass dingin 3 dari 5 kena batas.
- **"Beku > 90 hari" tidak membedakan tua dari `null`.** `/analyze` hanya memberi sinyal untuk umur ≤ 90 hari, jadi situs tanpa sinyal bisa tua atau gagal dicek. Untuk beku > 90 hari diasumsikan tetap tua. Tidak ada query RDAP tambahan untuk memastikan.
- Umur bergeser tiap hari: 03 dari 6 menjadi 7 hari pindah kelompok bobot (30 → 20, skor 95 → 85). Skor "hari ini" hanya berlaku untuk 29 Okt.
- Telegram dihitung dari HTML `curl` (tanpa JavaScript). URL yang dirakit saat runtime, base64, dan file `<script src>` tidak terbaca (situs 19 tidak kena walau mengirim OTP ke Telegram). Di produksi pindainya ada di ekstensi; angka Simulator di bawah adalah batas bawah CPU Mac.
- Telegram **belum masuk `/analyze`**: skrip uji menambahkan bobotnya ke skor dari server. Bentuk `Signal` dan field di `PageSnapshot` butuh keputusan Lead (lihat `hasil-analisis-telegram.md` §9).
- Bobot Telegram belum terkalibrasi: 12 dari 12 situs yang kena memegang token + host + method sekaligus, jadi data ini tidak memisahkan kandidat. Semuanya +35.
- Layer 4 mati: **total waktu produksi lebih besar** karena L4 memakai sisa anggaran 6,5 dtk. Tidak diukur di sini.
- Server produksi (Cloudflare Worker) punya jaringan ke registry yang berbeda dari Mac ini; sinyal timeout di sini belum tentu sama di sana.

### Telegram: Simulator (diambil dari `hasil-analisis-telegram.md` §4, tidak diukur ulang)

| ukuran | median (ms) | maks (ms) | batas | lulus |
|---|---:|---:|---|:-:|
| pindai, semua situs ber-HTML (34) | 0,028 | 2,475 | median < 5 ms, terbesar < 20 ms | ya |

### Perbandingan dengan perkiraan manual (`hasil-analisis-telegram.md` §8)

- Perkiraan manual: 19 → 20 dari 25 (umur beku + Telegram). Dihitung dari tabel per situs: umur beku + Telegram juga menghasilkan 20, karena hanya situs 05 yang pindah (12 → 47). Cocok.
- Dengan umur hari ini dan Telegram: 16 (pass A), 16–19 antar pass. Telegram selalu menambah **1** situs (05); selisih dengan 20 datang dari RDAP yang timeout, bukan dari Telegram.

---

## 6. Yang belum terukur / langkah berikutnya

1. Waktu dari iPhone lewat jaringan seluler ke server (anggaran sekitar 1,5 dtk dari 8 dtk).
2. Waktu produksi di Cloudflare Worker, dengan RDAP dari jaringan Worker dan cache KV.
3. Layer 4 (LLM) dan total waktunya bersama RDAP.
4. ~~Penyebab RDAP dingin kena batas~~ Sudah diukur di bagian 7: bagian terbesar adalah **query registry**, bukan bootstrap. Yang belum terjawab: kenapa siang itu 25% kena batas dan malam hanya 2% (jaringan Mac, waktu, atau beban registry). Satu hari data tidak cukup untuk memastikan; ulangi di jam dan jaringan lain.
5. Apakah timeout RDAP dingin di server nyata terlalu sering: 25% di uji siang, 2% di uji malam, di Mac ini. Memanaskan bootstrap tidak banyak membantu (bootstrap median 134 ms, registry median 640 ms). Belum jadi issue (CLAUDE.md rule 7); `src/` tidak diubah.
6. Telegram di ekstensi asli dan di iPhone asli; 25 legit tambahan untuk menilai host dan method.
7. `consider.md`, `HASIL-ANALISIS.md`, `hasil-analisis-telegram.md` **belum diperbarui** (menunggu persetujuan).

---

## 7. Diagnosa RDAP dan ulangan malam hari

Dibuat setelah pertanyaan "kenapa RDAP kena batas". Skrip: [rdap-diagnosa.mjs](rdap-diagnosa.mjs). Query tambahan ke registry untuk domain 35 situs (3 ulangan) diizinkan Imelda, 29 Okt 2026. Tiap percobaan jalan di proses Node baru, meniru klien di `src/rdap/rdap.js` (bootstrap IANA lalu registry, tanpa redirect). Domain tidak ditulis di sini.

### 7a. Bootstrap vs registry

Percobaan: 105 (3 ulangan × 35 situs), tiap percobaan di proses baru. Node v26.8.1, 2026-10-29T13:23:40.482Z. Format sel: median / p95 / maks (ms).

| bagian | n | median / p95 / maks | lewat 1,5 dtk |
|---|---:|---|---:|
| (1) unduh bootstrap IANA, sampai tubuh habis | 105 | 134 / 223 / 248 | 0/105 |
| (1a) bootstrap sampai header pertama | 105 | 131 / 217 / 242 | - |
| (1b) parse JSON bootstrap | 105 | 0 / 0 / 1 | - |
| (2) query registry, sampai tubuh habis | 102 | 640 / 866 / 8002 | 1/102 |
| (2a) registry sampai header pertama | 102 | 639 / 862 / 1194 | - |
| **(1) + (2) berurutan** (yang dibatasi 1,5 dtk) | 102 | 784 / 1070 / 8143 | 1/102 |

Ukuran bootstrap: 70 KB (median). Status bootstrap: {"200":105}.

Dari 1 percobaan yang totalnya lewat 1,5 dtk: bagian terbesar adalah bootstrap di 0, registry di 1.
Bootstrap saja sudah lewat 1,5 dtk di 0 dari 105. Registry saja lewat 1,5 dtk di 1 dari 102.

### Per host registry (query registry saja, ms)

| host registry | situs | n | median / p95 / maks | status |
|---|---|---:|---|---|
| rdap.zdnsgtld.com | 08 | 3 | 1085 / 1194 / 1194 | 200×3 |
| rdap.radix.host | 15 | 3 | 861 / 1042 / 1042 | 200×3 |
| rdap.blog.fury.ca | 14 | 3 | 860 / 879 / 879 | 200×3 |
| rdap.verisign.com | 01, 02, 03, 04, 06, 11, 12, 13, 16, 17, 18, 22, 23, 24, 25, L06 | 48 | 680 / 854 / 8002 | 200×47 TimeoutError×1 |
| pubapi.registry.google | 05, 09, 10, 19 | 12 | 430 / 550 / 550 | 200×12 |
| rdap.identitydigital.services | 21, L02 | 6 | 316 / 464 / 464 | 200×6 |
| rdap.pandi.id | 07, L01, L03, L04, L05, L07, L08, L09, L10 | 27 | 179 / 613 / 780 | 200×27 |

Tanpa server RDAP di bootstrap (TLD tidak terdaftar): 20 (.io).

### Per situs (median 3 ulangan, ms)

| id | bootstrap | registry | total | lewat 1,5 dtk (dari 3) | status registry | umur hari ini |
|---|---:|---:|---:|---:|---|---:|
| 01 | 214 | 695 | 899 | 0 | 200 | 8 |
| 02 | 130 | 739 | 869 | 1 | TimeoutError,200 | 9 |
| 03 | 126 | 683 | 831 | 0 | 200 | 8 |
| 04 | 160 | 642 | 810 | 0 | 200 | 23 |
| 05 | 148 | 433 | 581 | 0 | 200 | 2248 |
| 06 | 197 | 752 | 962 | 0 | 200 | 10636 |
| 07 | 152 | 195 | 325 | 0 | 200 | 20 |
| 08 | 127 | 1085 | 1216 | 0 | 200 | 24 |
| 09 | 208 | 443 | 666 | 0 | 200 | 507 |
| 10 | 127 | 394 | 551 | 0 | 200 | 507 |
| 11 | 160 | 707 | 832 | 0 | 200 | 9585 |
| 12 | 124 | 652 | 777 | 0 | 200 | 70 |
| 13 | 131 | 658 | 784 | 0 | 200 | 89 |
| 14 | 190 | 860 | 999 | 0 | 200 | 142 |
| 15 | 194 | 861 | 1077 | 0 | 200 | 260 |
| 16 | 143 | 636 | 812 | 0 | 200 | 70 |
| 17 | 153 | 711 | 922 | 0 | 200 | 54 |
| 18 | 138 | 714 | 853 | 0 | 200 | 12 |
| 19 | 128 | 380 | 515 | 0 | 200 | 2466 |
| 20 | 135 | - | 135 | 0 | tanpa server | - |
| 21 | 132 | 319 | 528 | 0 | 200 | 3181 |
| 22 | 222 | 654 | 861 | 0 | 200 | 6760 |
| 23 | 148 | 659 | 798 | 0 | 200 | 9585 |
| 24 | 127 | 656 | 798 | 0 | 200 | 9585 |
| 25 | 218 | 658 | 876 | 0 | 200 | 9585 |
| L01 | 211 | 178 | 387 | 0 | 200 | 10716 |
| L02 | 133 | 313 | 508 | 0 | 200 | 2627 |
| L03 | 191 | 133 | 313 | 0 | 200 | 10716 |
| L04 | 129 | 179 | 315 | 0 | 200 | 11432 |
| L05 | 128 | 202 | 330 | 0 | 200 | 4605 |
| L06 | 125 | 706 | 907 | 0 | 200 | 8555 |
| L07 | 137 | 220 | 357 | 0 | 200 | 3880 |
| L08 | 134 | 206 | 340 | 0 | 200 | 2878 |
| L09 | 125 | 188 | 314 | 0 | 200 | 3150 |
| L10 | 131 | 110 | 301 | 0 | 200 | 9667 |


**Bacaan:**
- Bootstrap IANA cepat dan konsisten: median 134 ms, maks 248 ms, 70 KB. **Bukan penyebab.**
- Query registry yang dominan: median 640 ms. Paling lambat: `rdap.zdnsgtld.com` (situs 08, ±1,1 dtk), `rdap.radix.host` (15), `rdap.blog.fury.ca` (14), lalu Verisign (±0,7 dtk, host terbanyak). `rdap.pandi.id` dan `rdap.identitydigital.services` cepat.
- Total bootstrap + registry: median 784 ms, p95 1070 ms. Hanya 1 dari 102 lewat 1,5 dtk, dan itu satu **timeout 8 dtk** dari Verisign (situs 02), bukan lambat bertahap.
- Situs 08 (registry paling lambat) sendiri total 1216 ms: dekat batas, jadi paling mudah kehilangan sinyal umur kalau jaringan sedikit lebih lambat.
- `.io` (situs 20) tidak punya server RDAP di bootstrap: sinyal umur untuk situs itu **tidak akan pernah ada**, di kondisi apa pun.

### 7b. Ulangan mode dingin (malam) vs uji siang

| ukuran | uji siang (14.03 WITA) | ulangan malam (21.22–21.26 WITA) |
|---|---:|---:|
| C2 dingin, median / p95 / maks (ms) | 1132 / 1508 / 1511 | 759 / 1047 / 1505 |
| permintaan dingin yang kena batas | 44 dari 175 (25%) | 4 dari 175 (2%) |
| scam ≥ 30 per pass (5 pass dingin) | 15–18 | 18–19 |
| scam ≥ 30 + Telegram | 16–19 | 19–20 |
| scam ≥ 50 / ≥ 80 | 10–11 / 3–5 | 11 / 4–5 |
| legit ≥ 30 | 0 | 0 |

- Kode, server, dan situs sama; yang berubah hanya waktu dan kondisi jaringan. Ukur terpisah (7a, malam) cocok dengan ulangan malam, bukan dengan uji siang.
- **Penyebab uji siang lebih lambat tidak diketahui**: bisa jaringan Mac, jalur ke registry, atau beban registry saat itu. Tidak diselidiki lebih jauh.
- Saat RDAP berjalan normal, tangkapan umur hari ini (18–19) hampir sama dengan umur beku (19), dan Telegram menambah 1 (jadi 19–20, cocok dengan perkiraan manual 20).
- Satu hari data, satu jaringan. Jangan disimpulkan bahwa 2% adalah angka produksi.
- Ulangan malam menimpa hasil dingin di `.hasil/l3-penuh.json`; hasil siang disimpan di `.hasil/l3-penuh-run1.json` dan tabel bagian 1–4 di atas adalah uji siang.
