# Dataset v4 untuk training / uji (13 Nov 2026)

Dibuat oleh [`dataset.mjs`](dataset.mjs) dari hasil run v4 (`links.csv`, `snapshots/`, `.probe/`). Keluaran ada di `dataset/` dan **di-gitignore**: isinya link phishing hidup dan repo ini publik. Jangan di-commit.

Label: **scam = 1, legit = 0**. Dibagi **per situs** ke train / dev / test (80 / 10 / 10 per label, dihitung pada baris halaman): satu situs hanya ada di satu bagian.

## File

| File | Isi | Baris |
|---|---|---|
| `dataset/links.csv` | `id,url,label,split,site,hidup,halaman`. Semua link. `hidup` = lolos cek hidup; `halaman` = ada barisnya di `pages-*.jsonl` | 579.519 |
| `dataset/pages-train.jsonl` | satu halaman per baris | 47.516 |
| `dataset/pages-dev.jsonl` | idem | 5.940 |
| `dataset/pages-test.jsonl` | idem | 5.940 |
| `dataset/summary.json` | hitungan per bagian dan alasan yang dibuang | - |

Baris halaman: `id, split, site, label, url, original_url, title, lang, text, forms, imageAlts`. `url`, `title`, `lang`, `text`, `forms` (per form: `action`, `fields[]` = `type, name, id, label, placeholder, autocomplete, accept, capture`), dan `imageAlts` sama dengan `PageSnapshot` di `contracts/detector-interface.md` (teks sudah disamarkan oleh `parseHtml`: email, telepon, angka panjang). `url` = halaman yang dibaca (query disamarkan), `original_url` = link di `links.csv`. `id` sama dengan `id` di `links.csv` dan nama file di `snapshots/`.

## Jumlah

| | train | dev | test |
|---|---|---|---|
| Halaman scam | 4.696 | 587 | 587 |
| Halaman legit | 42.820 | 5.353 | 5.353 |
| Link scam | 186.206 | 22.646 | 31.984 |
| Link legit | 270.846 | 33.796 | 34.041 |
| Situs | 146.140 | 18.053 | 18.215 |
| Kit scam (judul + susunan kolom sama) | 2.818 | 260 | 343 |

Cek: situs di dua bagian = 0, kit di dua bagian = 0, baris halaman yang tidak cocok dengan `links.csv` = 0.

## Aturan

- **Situs** = `domainKey` di `ai/test-regresi/fitur.mjs` (domain induk, atau host penuh untuk hosting gratis). Halaman **scam** dengan judul dan susunan kolom yang sama (satu kit di banyak host) digabung ke satu grup; legit tidak, supaya halaman "Sign in" generik tidak menyatukan situs legit yang tidak berhubungan.
- Grup dibagi secara greedy supaya jumlah scam dan legit seimbang di tiap bagian. Grup tanpa halaman dibagi dengan hash. Karena itu rasio **link** scam tidak persis 80/10/10 (77 / 9 / 13%); rasio **halaman** persis.
- Halaman dibuang: tidak terbaca (scam 21.370, legit 4.077), `kosong` (18.480, 3.721), host resmi (1.331, 324), isi sama persis dengan label berbeda (142, 102). Isi sama persis dengan label sama: satu disimpan (5.900 scam, 1.324 legit dibuang).

## Yang harus diperhatikan saat melatih atau menguji

- **Kelas sangat tidak seimbang di halaman:** scam 5.870 lawan legit 53.526 (±10% scam). Pakai bobot kelas atau subsampling.
- **Scam yang tersisa adalah yang bertahan hidup dan terbaca** (5.870 dari 240.836 link scam). Halaman scam dengan form lengkap kemungkinan paling dulu dimatikan, jadi tidak mewakili semua scam.
- **Label scam bisa kotor.** Halaman yang hidup tapi sudah diganti isinya (diparkir, blog kosong) tetap berlabel scam. Aturan "scam sudah mati" di `ai/test-regresi/1-kumpul.mjs` **tidak** dipakai di sini.
- **Legit hanya sampel** (23,5% dari link legit yang hidup, diambil dari awal daftar yang sudah diacak) dan condong ke situs yang melayani `GET` polos dari skrip.
- **Jangan jadikan skema (`http://`, `https://`) dan `www.` fitur.** Di data ini keduanya membedakan label karena cara pengumpulan (legit 97,9% https; phishing 26,7% http), bukan karena scam. Bersihkan dari `url` dan `original_url` sebelum dipakai.
- **Data lama dan tidak dari Indonesia.** Data Alief berisi laporan baru; distribusinya beda, jadi hasil uji pada v4 tidak otomatis berlaku untuk data Alief.
- Halaman yang `teks_ekstrem` (deretan ≥ 20.000 karakter) tidak diparse dan ikut terbuang sebagai "tidak terbaca".
