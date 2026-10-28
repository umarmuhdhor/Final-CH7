# Perubahan layer 2 (27 Okt 2026)

Ringkasan semua yang diubah di algoritma L2 pada sesi ini, kenapa, dan hasil tes ulangnya. Penyebab tiap link yang lolos ada di `consider.md`. Usulan bobot yang belum dikerjakan ada di `hasil-analisis.md`.

Semua perubahan ada di algoritma utama (`detector/src/detector.js`, `detector/data/link-rules.json`) dan sudah disinkronkan ke `ios/ShooExtension/Resources/detector.js` lewat `detector/scripts/sync-to-extension.sh`. Isi file extension sama persis dengan hasil build baru (diff kosong). Belum dicommit.

## Perubahan

| # | Rule | Sebelum | Sesudah | File |
|---|---|---|---|---|
| 1 | **Brand setelah connector** (`bybri`, `bybni`, `viabni`, `frombsi`) | Brand hanya dicocokkan sebagai potongan utuh (dipisah `-`). `bybri` tidak cocok dengan `bri`. | Potongan yang berakhir `by` / `via` / `from` + nama brand → `brand_plus_keyword` (+14), connector jadi kata kuncinya. Brand yang juga kata biasa (dana, apple, mandiri) dilewati. | `detector.js` (`matchByBrand`, `CONNECTORS`) |
| 2 | **Hyphen tidak dihitung dua kali** | `qlolla-bybri` kena `hyphen_registrable` (+4) padahal sudah kena brand. | Potongan berpola connector + brand ikut dikecualikan, seperti brand dan kata kunci. | `detector.js` (`dissectLink`) |
| 3 | **`digit_label` per potongan** | Seluruh label harus ≥ 8 karakter dan digit ≥ 40%. | Per potongan di antara `-`: ≥ 6 karakter, ada huruf, ≥ 3 digit, digit ≥ 25%. Dilewati untuk `*.cloudfront.net` (id distribusi CloudFront selalu begitu). Bobot tetap +8. | `detector.js` (`dissectLink`) |
| 4 | **`edgeone.dev` free host** | Tidak ada di daftar. | Ada di `freeHosts` (+3 dan label dinilai). | `link-rules.json` |
| 5 | **Kosakata umpan** | `pengembalian`, `pembatalan`, `kode` tidak ada. | Masuk `baitWords` (label dan nama file di free host) dan `pathBait` (path). | `link-rules.json` |

## Test

`node --test detector/test`: 56 → **62** test, semua lulus. Test baru:

- brand setelah connector kena (`qlolla-bybri.com`, `kodepembatalanbybni.pages.dev`, `kodeviabni.com`, `cashfrombsi.com`), bobot 14, evidence `bri · level 2 · by`;
- hyphen tidak dihitung dua kali pada `qlolla-bybri.com`;
- `digit_label` per potongan dan `edgeone.dev` sebagai free host;
- kata umpan baru di label, nama file, dan path; satu kata umpan di path sendirian tetap di bawah batas emit (10).

False positive yang dikunci supaya perubahan berikutnya ketahuan:

| Host | Alasan harus bersih |
|---|---|
| `hobbydana.com`, `baby-shop.com`, `ruby-store.co.id`, `viabus.com`, `standbyapple.com`, `toko-by-sari.com` | `by` / `via` bukan connector ke brand |
| `smpn1-jakarta.sch.id`, `covid19info.com`, `k24klik.com`, `mp3juices.com`, `web3-dev.com` | digit biasa di nama sah |
| `d111abcdef.cloudfront.net` | id distribusi CloudFront |

## Hasil tes ulang

Dataset: `dataset.md` (25 scam) dan `dataset-legit.md` (23 legit). Hanya teks URL yang dibaca. Laporan: `REPORT.md`, `REPORT-legit.md`.

| Ukuran | Awal sesi | + connector | + digit, edgeone, umpan (akhir) |
|---|---|---|---|
| Scam, ada signal L2 | 16 / 25 (64%) | 18 / 25 | **20 / 25 (80%)** |
| Scam, popup (≥ 30) | 1 / 25 | 1 / 25 | **2 / 25** |
| Legit, false positive | 0 / 23 | 0 / 23 | **0 / 23** |
| Waktu | 0,42 ms / URL | | 0,40 ms / URL |

Link yang berubah:

| Link | Sebelum | Sesudah |
|---|---|---|
| `qlolla-bybri.com` | 0 | 14 |
| `kodepembatalanbybni.pages.dev` | 0 | **33** (popup) |
| `yaigsjv.1238bll.my.id/ca/bin/2c.html` | 0 | 13 |
| `storee-dp9hsk1cxr2y.edgeone.dev` | 0 | 11 |

## Masih lolos (5 dari 25)

| Link | Kenapa |
|---|---|
| `cusbsi.com` | Brand 3 huruf menempel di ujung label. Risiko false positive, perlu korpus UMKM. |
| `sites.google.com/view/pengembalian-request/…` | `isOfficial` melewati seluruh subdomain `google.com` sebelum URL dibaca. Perlu persetujuan Umar. |
| `storee-dp8iiud7biuu.edgeone.dev` | Hanya 2 digit, di bawah syarat 3 digit. |
| `m-pajak.top`, `apply.wozspace.site/info`, `viinwkwk-dot.github.io/instagram./`, `deddydanchika.blogspot.com` | Kosakata `pajak` / `apply`, brand `instagram` di path, dan nama pribadi di blogspot. Yang terakhir di luar jangkauan URL (layer 3). |

## Batasan

- 48 URL terlalu kecil untuk menyimpulkan apa pun. Legit hanya situs besar; UMKM, blog lokal, dan toko `.co.id` belum terwakili.
- Bobot baru tidak ada. Hanya aturan pencocokan dan kosakata yang berubah, bobot memakai nilai yang sudah ada (+14, +8, dll.).
- Cara tes ulang: `node --test detector/test`, lalu `node ai/test-layer2/analyze.mjs` dan `node ai/test-layer2/analyze.mjs dataset-legit.md REPORT-legit.md`.
