# Plan: jalankan layer 3 penuh (RDAP + field + Telegram) dan ukur waktunya

Status: **plan**. Belum dijalankan. Tidak ada commit, tidak ada issue (D1 di [consider.md](consider.md) tidak disentuh).
Pemilik: **Imelda** (plan ini dan folder `ai/`). Semua langkah di `ai/`. `src/` tidak diubah. Hasil ditulis ke [HASIL-L3-PENUH.md](HASIL-L3-PENUH.md).

## Tujuan

1. **Lapis A. L3 lewat HTTP.** Kirim 35 snapshot ke `POST /analyze` di `dev-server.mjs` (127.0.0.1), dengan RDAP live, lalu catat skor dan sinyal per situs.
2. **Lapis B. Telegram ditambahkan.** Pindai HTML tersimpan, lalu tambahkan bobot kandidat Telegram ke skor dari server, seolah ekstensi mengirim flag (pilihan 9b di [hasil-analisis-telegram.md](hasil-analisis-telegram.md)).
3. **Lapis C. Waktu.** Ukur waktu tiap bagian (rules + HTTP, RDAP dingin, RDAP hangat, Telegram) dan totalnya, lalu bandingkan dengan batas lulus.

Tidak termasuk: Layer 4 / LLM (dimatikan), mengubah `src/`, `contracts/`, `ios/`, membuka situs scam, menjalankan Safari lagi (angka Simulator diambil dari `hasil-analisis-telegram.md` bagian 4).

## Sinyal yang dijalankan

| bagian | dari mana | bobot |
|---|---|---|
| field (PIN, OTP, password, kartu, KTP) + teks | `src/layer3/forms.js`, `content.js` lewat `/analyze` | bobot di kode sekarang (termasuk 4 file belum di-commit) |
| umur domain | RDAP live di `/analyze` (`SHOO_RDAP=1`) | <7 hari 30, 7–30 hari 20, 31–90 hari 10, >90 hari 0 |
| Telegram | prototipe di skrip uji, pola dari `ukur-telegram.mjs` | **kandidat**: token +35, host+method +30, host saja +10. Ambil yang tertinggi, tidak dijumlah. Total skor dibatasi 100 |

## Batas lulus (ditetapkan sebelum mengukur)

| ukuran | batas | sumber |
|---|---|---|
| rules (sync) | < 100 ms CPU | `analyze.js` |
| RDAP | ≤ 1,5 dtk; lewat batas = tidak ada sinyal, bukan error | `rdap.js` `TIMEOUT_MS` |
| total `/analyze` | ≤ 6,5 dtk | `SERVER_DEADLINE_MS` |
| p95 HTTP (dari klien) | < 8 dtk | ekstensi menyerah di 8 dtk |
| legit ≥ 30 | 0 dari 10 | `ai/eval/README.md` |

Tangkapan scam dilaporkan di skor ≥ 30 (popup), ≥ 50, dan ≥ 80.

## Pengecualian aturan (khusus uji ini)

`dev-server.mjs` menulis "Never point it at scam domains" dan `ai/eval/README.md:102` menulis "scam domains must not be sent to a registry". Untuk uji ini **diizinkan oleh Imelda**: 35 query RDAP, termasuk ke 25 domain scam. Alasannya, yang dihubungi server registry (bukan situs scam), registry tidak menghubungi pemilik domain, dan di produksi server memang melakukan ini untuk setiap halaman. Kedua aturan itu **tidak diubah**.

## Prasyarat

| butir | cara cek | kalau tidak ada |
|---|---|---|
| Node | `node --version` (terakhir: v26.8.1) | pasang Node |
| Snapshot | `ls ai/test-layer3/snapshots` berisi `01..25.json`, `L01..L10.json` | ambil ulang lewat [PROMPT.md](PROMPT.md) |
| HTML tersimpan | `cd ai/test-layer3/.html && shasum -c SHA256SUMS` | lihat P1 di [PLAN-ULANG.md](PLAN-ULANG.md) |
| Port 8787 kosong | `lsof -i :8787` | pakai `PORT=` lain |
| Versi kode | `git rev-parse --short HEAD`, `git status --short ai/src ai/test` | catat di hasil |

### P1: matikan LLM (sebelum apa pun)

`ai/.env` berisi `LLM_API_KEY`, `LLM_MODEL`, dan `LLM_BASE_URL`, jadi `dev-server` akan menyalakan Layer 4 dengan biaya.
1. Comment ketiga baris `LLM_*` di `ai/.env` (tambah `# ` di depan). **Jangan cetak isi `.env`** ke chat atau log. Cek hanya nama: `grep -c '^LLM_' ai/.env` harus `0`.
2. Setelah server jalan: `curl -s http://127.0.0.1:8787/_dev/layer4` → jumlah panggilan harus 0. Cek lagi setelah semua putaran. **Kalau bukan 0, berhenti.**
3. Setelah selesai (P2), hapus `# ` itu lagi, lalu cek `grep -c '^LLM_' ai/.env` kembali ke `3`.

Perkiraan: 5 menit.

## Langkah dan perkiraan waktu

Waktu di kolom ini **perkiraan lama mengerjakan**, bukan hasil ukur.

### Lapis A: L3 lewat HTTP

| # | langkah | perkiraan |
|---|---|---|
| A1 | Catat versi kode, versi Node, dan tanggal/jam | 2 menit |
| A2 | Tulis `ai/test-layer3/l3-penuh.mjs`: baca snapshot, `POST /analyze` dengan body `{ snapshot, localSignals: [] }` sesuai `contracts/`, ukur waktu di sisi klien (`performance.now()`), simpan sinyal per situs ke `ai/test-layer3/.hasil/l3-penuh.json` (di-gitignore). Juga hitung skor "umur beku": sinyal rules dari server + `buildNewDomainSignal(rdapAgeDays)` dari snapshot | 30 menit |
| A3 | Jalankan server dengan `SHOO_RDAP=1 node ai/src/dev-server.mjs`, cek P1 langkah 2, lalu jalankan A2 | 5 menit |
| A4 | Bandingkan umur RDAP hari ini dengan `rdapAgeDays` di snapshot per situs: sama, bergeser, atau `null` (domain hilang, timeout, host bersama) | 10 menit |
| A5 | Hitung scam tertangkap di 30 / 50 / 80 dan legit ≥ 30, untuk dua versi: umur beku dan umur hari ini | 10 menit |

Total lapis A: sekitar 55 menit.

### Lapis B: tambah Telegram

| # | langkah | perkiraan |
|---|---|---|
| B1 | Di `l3-penuh.mjs`, impor pola dari `ukur-telegram.mjs` (atau `ukur-safari/pola.js`). Pindai HTML desktop tiap situs dari `.html/`, dapatkan host / token / method | 15 menit |
| B2 | Hitung bobot Telegram (ambil yang tertinggi), tambahkan ke skor dari server, batasi 100 | 10 menit |
| B3 | Hitung ulang 30 / 50 / 80 dan legit ≥ 30 dengan Telegram. Bandingkan dengan perkiraan manual di `hasil-analisis-telegram.md` bagian 8 (19 → 20) | 10 menit |
| B4 | L01 tidak punya HTML (302): tulis "tidak terbaca", bobot Telegram 0 | 2 menit |

Total lapis B: sekitar 35 menit.

### Lapis C: waktu

Setiap mode dijalankan **5 kali per situs**, run pertama dibuang, dilaporkan **median dan p95**.

| # | mode | cara | perkiraan |
|---|---|---|---|
| C1 | **RDAP mati** (rules + HTTP) | server tanpa `SHOO_RDAP` | 5 menit |
| C2 | **RDAP dingin** | `SHOO_RDAP=1`, server di-restart sebelum tiap situs supaya cache dan bootstrap IANA kosong. Kalau cache ternyata disimpan ke disk (cek `src/rdap/cache.js`), hapus dulu dan catat caranya | 20 menit |
| C3 | **RDAP hangat** | `SHOO_RDAP=1`, putaran kedua tanpa restart | 5 menit |
| C4 | **Telegram** | ukur pindai di Node dalam `l3-penuh.mjs` (5 kali, buang run pertama). Angka Simulator diambil dari `hasil-analisis-telegram.md` bagian 4 | 5 menit |
| C5 | Hitung: waktu RDAP ≈ C2 − C1 dan C3 − C1; total L3 penuh = C2 / C3 + Telegram. Bandingkan dengan batas lulus. Catat situs yang RDAP-nya kena batas 1,5 dtk | 15 menit |
| C6 | Cek P1 langkah 2 lagi (LLM 0 panggilan), matikan server | 2 menit |

Total lapis C: sekitar 55 menit.

### P2: bereskan

| # | langkah | perkiraan |
|---|---|---|
| P2a | Kembalikan baris `LLM_*` di `ai/.env` (P1 langkah 3) | 2 menit |
| P2b | Pastikan server sudah mati (`lsof -i :8787` kosong) | 1 menit |
| P2c | Isi [HASIL-L3-PENUH.md](HASIL-L3-PENUH.md) | 20 menit |

Total semua: sekitar 3 jam.

Peringatan yang harus ikut ditulis di hasil:
- Waktu diukur di Mac, lewat 127.0.0.1. Jaringan HP ke server (sekitar 1,5 dtk dari anggaran 8 dtk) tidak termasuk.
- Waktu RDAP bergantung pada jaringan Mac saat itu dan server registry masing-masing TLD. Ini contoh satu waktu, bukan angka tetap.
- Telegram masih prototipe di luar `src/`. Di produksi pindainya ada di ekstensi (Simulator: batas bawah, CPU Mac).
- Umur domain bergeser tiap hari. Skor "umur hari ini" hanya berlaku untuk tanggal uji.

### Yang tidak bisa dikerjakan di sini (untuk Umar, belum jadi issue)

| butir | alasan |
|---|---|
| Telegram masuk ke `/analyze` atau ekstensi | butuh field baru di `PageSnapshot` (`contracts/`) dan/atau `ios/ShooExtension/` |
| Waktu di iPhone asli lewat jaringan seluler | butuh ekstensi asli |

## Tabel hasil

Diisi di [HASIL-L3-PENUH.md](HASIL-L3-PENUH.md), bukan di sini.

## Batas dan keamanan

- Server hanya di `127.0.0.1`. Matikan setelah selesai.
- **LLM mati** sepanjang uji (P1). Kalau `/_dev/layer4` menunjukkan panggilan, berhenti.
- Isi `ai/.env` tidak pernah dicetak. Setelah selesai, baris `LLM_*` dikembalikan.
- Jaringan hanya untuk RDAP (registry dan bootstrap IANA). Tidak ada permintaan ke situs scam. Tidak mengambil HTML baru.
- Token bot Telegram ditulis `[disamarkan]` di semua keluaran.
- `.hasil/` dan `.html/` tidak masuk repo (cek `git check-ignore`).
- Jangan ubah `src/`, `contracts/`, `ios/`, `detector/`. Jangan buat issue. Jangan commit.

## Prompt untuk menjalankan (tempel ke chat baru di folder repo `Final-CH7`)

```text
Kamu mengerjakan plan di ai/test-layer3/PLAN-L3-PENUH.md untuk proyek Shoo. Baca file itu, ai/CLAUDE.md, dan ai/test-layer3/hasil-analisis-telegram.md dulu. Pemilik plan dan folder ai/ adalah Imelda.

Tugas: jalankan P1, Lapis A (L3 lewat POST /analyze dengan RDAP live), Lapis B (tambah bobot kandidat Telegram dari HTML tersimpan), Lapis C (waktu 3 mode server + Telegram), lalu P2, dan isi ai/test-layer3/HASIL-L3-PENUH.md.

Aturan wajib:
- LLM harus mati: comment baris LLM_* di ai/.env (jangan pernah cetak isinya), cek GET /_dev/layer4 = 0 panggilan sebelum dan sesudah. Kalau bukan 0, berhenti dan lapor. Setelah selesai, kembalikan baris LLM_* dan cek grep -c '^LLM_' ai/.env = 3.
- RDAP live ke 35 domain (termasuk scam) diizinkan Imelda khusus uji ini, sebagai pengecualian dari aturan di dev-server.mjs dan ai/eval/README.md. Jangan ubah kedua aturan itu.
- Server hanya 127.0.0.1. Tidak ada permintaan ke situs scam, tidak mengambil HTML baru.
- Hanya edit file di ai/test-layer3/ (dan comment/uncomment baris LLM_* di ai/.env). Jangan ubah ai/src/, contracts/, ios/, detector/. Jangan buat issue. Jangan commit, jangan push.
- Body /analyze harus sesuai contracts/ ({ snapshot, localSignals: [] }).
- Telegram: prototipe di skrip uji, bobot kandidat token +35, host+method +30, host +10, ambil yang tertinggi, total dibatasi 100. Token ditulis [disamarkan].
- Waktu: 5 kali per situs per mode, buang run pertama, laporkan median dan p95. Catat versi kode dan Node.
- Batas lulus: rules < 100 ms, RDAP <= 1,5 dtk, total <= 6,5 dtk, p95 HTTP < 8 dtk, legit >= 30 = 0 dari 10.
- Angka yang tidak bisa diulang jangan ditulis sebagai fakta. Kalau ada langkah yang tidak bisa dijalankan, tulis alasannya.

Keluaran: ai/test-layer3/l3-penuh.mjs, HASIL-L3-PENUH.md terisi, dan ringkasan 6 baris di chat: tertangkap 30/50/80 (umur beku vs hari ini vs + Telegram), legit >= 30, median/p95 tiap mode, RDAP yang kena batas, lulus batas atau tidak, dan apa yang belum terukur. Berhenti setelah itu dan tunggu aku. Jangan update consider.md, HASIL-ANALISIS.md, atau hasil-analisis-telegram.md sebelum aku bilang.
```
