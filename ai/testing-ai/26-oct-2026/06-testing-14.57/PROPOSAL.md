# 06 · Usulan flow layer baru + L2 sebagai pembedah link utuh

Tanggal: 26 Okt 2026 · Status: **diterima Umar di #140 (26 Okt 2026)**, bagian L2 diimplementasikan di `feat/L2-v2-full-link-dissector` (v2 menjadi `suspicious_link` di `detector/`). Yang diputuskan lain dari usulan di bawah: penomoran layer **tidak** diganti, rules L3 dan gate form tetap, satu id `suspicious_link`, skor link saja dibatasi 29. Isi §1–§4 di bawah adalah usulan awal, bukan keadaan sekarang.

## 1. Flow baru (dari Imelda)

| Layer | Isi | LLM? |
|---|---|---|
| 1 | Cek blocklist dan real list (allowlist) | tidak |
| 2 | Cek domain / link, **JS di extension** (L2 tidak jadi Python) | tidak |
| 3 | Ambil konten, kirim prompt ke LLM, ambil hasil inti buat block | ya |
| 4 | Kirim reason ke user | tidak (format dari hasil L3) |

Alasan: kecepatan. Daftar domain terlalu banyak, jadi legit tidaknya dinilai dari bentuk link dan bagian-bagiannya. Data link legit baru ditambah kalau hasilnya memang jelek.

### Beda dengan kode sekarang

| Flow baru | Sekarang |
|---|---|
| L1 blocklist | Sama. `db_match` = 100, di extension (`ShooLists.match`). |
| L2 domain/link, JS | L2 JS di extension (`detector/src/detector.js`) tapi **hanya membaca hostname**. Path, query, fragment dibuang. Nama brand dicocokkan ke 25 brand hardcode di `detector/data/brands.json`. |
| L3 = LLM | L3 sekarang = rules form/konten + RDAP (`ai/src/layer3/`). LLM ada di L4 (`ai/src/layer4/`), hanya jalan kalau situs bukan official, ada form, dan skor rules ≥ 15. |
| L4 = reason | Sekarang label dibuat dari template kita (bilingual) di tiap signal. Belum ada layer "reason". |

## 2. Temuan (bukti)

**L2 sekarang buta terhadap path.** `grep pathname|.path|search detector/src/detector.js` kosong. Tes:

| URL | L2 sekarang |
|---|---|
| `helpnets.info/0442827f6o7cfb43933ba59e2881cc906b7c.html/` | 0 |
| `helpnets.xyz/0442...html/` (ganti TLD saja) | 5, sama dengan `helpnets.xyz/` |
| `bca-verifikasi.xyz/` | 29 (14 + 15), 1 poin di bawah popup |
| `d33wubrfki0l68.cloudfront.net/.../dhl123.html` | 0 |
| `simgratisonine.blogspot.com/` | 0 |
| `bantuannbansos2026.blogspot.com/` | 0 |
| `gratiskuota60gb.blogspot.com/` | 0 |

`.info` tidak ada di `cheapTlds`, dan `dhl` tidak ada di 25 brand.

**Prototipe v1 (pembedah URL utuh, di folder ini: `link-l2.mjs`, `dissect-lib.mjs`).** Tiap bagian (scheme, userinfo, host, TLD, port, path, ekstensi, trailing slash, kata umpan, query, fragment, panjang) dinilai sendiri.

- helpnets: 0 → **34** (nama acak 36 karakter +15, slash setelah nama file +8, `.info` +6, `.html` +5).
- Corpus `ai/eval/data` (103 URL: 50 scam, 53 legit): **0/50 scam ≥ 15**, 0/53 legit ≥ 30. Alasannya, 49 dari 50 scam di corpus sintetis dan bentuknya brand-di-domain (misalnya `bni-mobile-banking.click/login`), bukan pola helpnets. Skor scam tertinggi 14.
- Fitur link dan brand check **saling melengkapi**. `bca-verifikasi.xyz` hanya 6 di v1 (tanpa brand check), 29 di detector lama.

**Prototipe v2 (`dissect2.mjs`): hosting gratis.** Di blogspot, cloudfront, github.io dan sejenisnya, domain milik host, jadi yang dinilai label pertama dan nama file.

| URL | v1 | v2 |
|---|---|---|
| `bantuannbansos2026.blogspot.com` | 0 | 24 |
| `gratiskuota60gb.blogspot.com` | 0 | 24 |
| `cloudfront.net/.../dhl123.html` | 5 | 18 |
| `simgratisonine.blogspot.com` | 0 | 13 |
| helpnets | 34 | 34 |

False positive: blog legit `cara-cek-saldo-bca.html` 11 → 24, `andi-dev.github.io/panduan-login/` (corpus) 6 → 19, `infopaketwisata.blogspot.com` 0 → 13. Di corpus legit, 2 URL sekarang ≥ 15 (sebelumnya 0), tidak ada ≥ 30. Penyebab: kata umum (`login`, `update`, `paket`, `saldo`).

**Batas kejujuran angka.** Bobot di prototipe adalah tebakan, belum dikalibrasi. Daftar kata umpan dan daftar host gratis ditulis **setelah** melihat 2 dari 4 link tes, jadi angka 13–24 itu cocok karena jawabannya sudah dilihat. Itu bukan ukuran akurasi. Satu-satunya link scam nyata di tes ini: helpnets dan 3 link blogspot/cloudfront dari Imelda. Corpus punya 1 scam nyata (`lphone-login`).

## 3. Usulan

1. **L2 = pembedah link utuh**, tetap JS di extension, tanpa network, target < 50 ms. Seluruh URL dipakai, tidak ada bagian yang dibuang. Hosting gratis dikenali dan label pertamanya dinilai.
2. **Brand check (25 brand) tetap sebagai pelengkap**, bukan satu-satunya sumber.
3. **Skor L2 menentukan gate LLM**: halaman dengan skor L2 ≥ 15 dikirim ke LLM. Satu fitur lemah sendirian tidak boleh mencapai 30.
4. **L3 = satu panggilan LLM** yang mengembalikan `verdict + confidence + reason_code`. Dari uji 6 detik, timeout 40–50% dan rata-rata terbaik 2,6 s, jadi dua panggilan berurutan tidak aman.
5. **L4 = reason** diformat dari `reason_code` (enum) ke label bilingual kita, **bukan** teks bebas LLM, supaya aman dari prompt injection dan sesuai aturan "label hanya berisi kata-kata kita".
6. **Rules L3 yang ada (form, konten, RDAP) tetap jalan sebagai fallback dan gate**, supaya `/analyze` tetap menjawab kalau LLM lambat atau mati (`ai/CLAUDE.md`). Ini belum diputuskan: lihat pertanyaan 3.
7. **Privasi**: URL mentah tidak dikirim ke server atau LLM. Yang dikirim hanya hasil analisis (daftar fitur sus). Selaras dengan #97.

## 4. Dokumen yang perlu diubah kalau disetujui

| Dokumen | Perubahan |
|---|---|
| PRD | Definisi layer 1–4 (tabel flow di atas). §5 ambang (skor L2 jadi pemicu gate). §10 privasi: konten dikirim ke LLM, tidak disimpan, dan apa yang dikirim berubah. |
| `contracts/detector-interface.md` | Tabel Known signal ids: id baru untuk sinyal link. Penomoran layer di `Signal.layer`. |
| `contracts/scan-result.schema.json` | Cek apakah `layer` dibatasi enum. |
| `docs/README.md` | Keputusan #1 (privasi vs deteksi server). |
| `detector/CLAUDE.md` | L2 = analisis link utuh, bukan hanya nama. Daftar host gratis dan kata umpan di `detector/data/`. |
| `ai/CLAUDE.md` | Definisi L3/L4, gate, fallback. |
| Privacy policy + App Store privacy label (#97) | Kalau field atau gate ke LLM berubah. |
| #139 (provider L4) | Provider LLM ikut jadi L3 di flow baru. |

## 5. Isi folder ini

`link-l2.mjs` (prototipe v1 + 13 URL tes) · `dissect-lib.mjs` (v1 sebagai modul) · `dissect2.mjs` (v2, hosting gratis) · `run-corpus.mjs`, `run4.mjs`, `run-v2.mjs` (runner) · `urls-checked.md` (103 URL corpus + skor v1).

Catatan: runner membaca path absolut `/Users/imelda/...` dan `detector/data/brands.json`. Skrip ini prototipe, bukan bagian test suite.
