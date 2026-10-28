# L2 v2 (dissector `suspicious_link`): temuan + usulan perbaikan

Status: **bahan pertimbangan, belum ada kode yang diubah.** Kalau mau dikerjakan, perubahan di `detector/` perlu lewat lead (Umar), dan data di `detector/data/link-rules.json`.

## Temuan

Dua URL dari kasus nyata dijalankan lewat `ShooDetector.analyzeLocal` (build yang sama dengan yang dipakai extension). Halamannya **tidak dibuka**, ini murni analisis string URL.

| URL | Hasil |
|---|---|
| `https://cusbsi.com/` | `[]`, tidak ada signal |
| `https://regs-apps14.regnows-dfg.com/code.php` | `[]`, tidak ada signal |

### Kenapa URL ke-2 lolos
Satu-satunya rule yang kena adalah `file_ext` (+5, karena `.php`). `LINK_MIN_EMIT = 10`, jadi dibuang.

| Rule | Syarat | URL ke-2 |
|---|---|---|
| `many_labels` | nama domain >= 4 label | 2 label, tidak kena |
| `many_hyphens` | >= 3 hyphen dalam satu label | 1 hyphen per label, tidak kena |
| `digit_label` | label >= 8 huruf dan digit >= 40% | `regs-apps14` = 2/11, tidak kena |
| `path_bait` | kata di path ada di keyword list | `code` tidak ada di list |
| `rare_tld` / `cheap_tld` | TLD murah/langka | `.com`, tidak kena |
| brand / lookalike | mirip brand di `brands.json` | tidak ada brand |

Pola yang tidak tertangkap: `<kata>-<kata><angka>.<domain-acak-ber-hyphen>/<file>.php`.

### Kenapa URL ke-1 lolos
`cusbsi.com` adalah domain root polos: https, `.com`, tanpa path, tanpa subdomain. Tidak ada satu pun bagian URL yang bisa dinilai. Ini bukan bug di rule, tapi batas dari analisis URL.

## Usulan perbaikan

### A. Untuk URL ke-2 (bisa ditangkap dari string)
Semua usulan di bawah dibuat kecil, supaya false positive tidak naik.

1. **`kata_angka_subdomain`**: label subdomain berbentuk `<huruf>[-<huruf>]<angka>` (contoh `regs-apps14`, `portal2`, `secure88`) di atas domain registrable. +5 sampai +8.
2. **`hyphen_registrable`**: domain registrable (bukan subdomain) mengandung hyphen dan bukan brand (contoh `regnows-dfg`). +4 sampai +6. Domain sah juga pakai hyphen, jadi bobot kecil.
3. **Perluas `path_bait`** dengan kata generik seperti `code`, `verify`, `activate`, `claim` (cek dulu `baitWords` supaya tidak dobel).
4. **Gabungan**: `file_ext` (+5) ditambah rule 1 dan 2 jadi ~14-19, di atas `LINK_MIN_EMIT` (10). Cek dengan korpus (`ai/testing-ai`, `ai/test-layer2`) apakah false positive naik sebelum menetapkan bobot final.

Wajib diuji: tambah kasus ke `detector/test/detector.test.mjs` untuk kedua sisi (URL ini tertangkap, dan situs normal seperti `github.com`, `kompas.com`, `toko-maju.co.id` tetap `[]`).

### B. Untuk URL ke-1 (domain bagus, tidak bisa dari URL)
Domain yang namanya terlihat wajar tidak bisa dibedakan hanya dari string. Menambah rule URL tidak akan membantu, dan kalau dipaksa malah menandai domain sah. Pemeriksaan harus pakai sinyal lain, yang sebagian sudah ada di rencana:

| Sinyal | Layer / fase | Catatan |
|---|---|---|
| Umur domain (baru didaftar) | fase-03 `konten-new-domain` | Scam biasanya domain baru. Butuh data WHOIS/RDAP, jadi server-side |
| Isi halaman: form login/OTP/pembayaran, brand yang ditiru | `analyze-forms` (fase-02) | Domain bersih tapi halaman minta data sensitif |
| Blocklist publik / reputasi | fase-05 | Kalau sudah dilaporkan orang lain |
| Reality check LLM atas konten halaman | fase-06, layer 3-4 | Untuk kasus yang lolos semua di atas |
| Redirect chain, domain tujuan akhir | belum ada | Domain polos sering cuma pintu masuk |

Catatan: `cusbsi.com` sudah dicek isi halamannya (27 Okt 2026, HTML mentah, tidak dieksekusi): **phishing klon BSI Cash Management**. Lihat bagian "Isi halaman cusbsi.com" di bawah.

### Hasil cek umur domain (RDAP, 27 Okt 2026)

| Domain | Terdaftar | Umur | Registrar | NS |
|---|---|---|---|---|
| `cusbsi.com` | 2026-10-06 | 21 hari | Registrar.eu | NS1 |
| `regnows-dfg.com` | 2026-08-01 | 87 hari | WebNic.cc | Cloudflare |

Keduanya domain baru. `cusbsi.com` masih sangat baru, jadi sinyal umur domain (fase-03) akan menangkap kasus yang tidak bisa ditangkap rule URL. Umur domain bukan bukti scam, cuma sinyal pendukung: harus digabung dengan isi halaman / blocklist. 
### Isi halaman `cusbsi.com` (hasil: scam)

- Judul `BSI Cash Management`, logo BSI, badge "Norton", footer memuat link asli `www.bankbsi.co.id` dan telepon 1500789, padahal domain `cusbsi.com`.
- Tiga langkah form berurutan: login (Company ID, User ID, password, captcha), ganti password (lama, baru, nomor HP), OTP 6 digit.
- Script mengirim isian ke Telegram bot (`api.telegram.org/bot.../sendMessage`) di setiap langkah. Token tidak dicatat di sini.
- Hosting Netlify, gambar dari imgur, domain umur 21 hari.

Yang menangkap kasus ini adalah layer 3 (`analyze-forms`) dan layer 1: form password + OTP, brand bank, domain bukan `bankbsi.co.id`. Cek apakah BSI sudah ada di `brands.json` dengan domain resmi yang benar, supaya `brand_logo_offsite` bisa kena.

## Pertanyaan terbuka
- Siapa yang memutuskan ambang `LINK_MIN_EMIT` kalau gabungan rule A masih di bawahnya? (Umar, lewat issue sesuai CLAUDE.md rule 7.)
- Umur domain di layer 3 server: `PageSnapshot.domain` (registrable domain, tanpa `www`) sudah ada di kontrak (`contracts/detector-interface.md`) dan ikut terkirim ke `/analyze`, jadi mungkin **tidak perlu ubah kontrak**. `ai/CLAUDE.md` bilang URL mentah tidak dikirim, jadi path/query tetap aman. Yang perlu dikonfirmasi ke Umar: boleh tidak server memanggil RDAP dengan domain itu (domain keluar ke pihak ketiga), dan siapa yang cache hasilnya. Belum ada issue di GitHub, nanti dibuat.
- Koreksi: sebelumnya dikira hostname perlu masuk kontrak. Setelah dicek, `domain` sudah ada di snapshot.

## Celah yang ditemukan di run baseline (27 Okt 2026, `dataset.md`, 25 scam)

Baseline sebelum perubahan: 16/25 ada signal L2, 1/25 popup. Legit: 0/23 false positive. Penyebab tiap link yang lolos (dicek dengan menjalankan `dissectLink` dan membaca `analyzeBrand`):

| Link | Skor L2 | Penyebab | Status |
|---|---|---|---|
| `qlolla-bybri.com` (03) | 4 | Cek brand hanya mencocokkan potongan utuh. `bybri` ≠ `bri`. Fuzzy butuh panjang ≥ 6 dan nama brand ≥ 6 huruf, `bri` cuma 3. | **Diperbaiki**: pola connector + brand |
| `kodepembatalanbybni.pages.dev` (05) | 3 | `bybni` sama. `kode` dan `pembatalan` tidak ada di daftar umpan. | **Sebagian**: `bybni` kena (+14). Kosakata umpan belum |
| `cusbsi.com` (04) | 0 | `cus` + `bsi` menempel. `matchGlued` hanya mengenali brand + kata di `keywords`. | Terbuka. Brand 3 huruf di tepi label, risiko false positive, perlu uji korpus |
| `sites.google.com/view/pengembalian-request/…` (06) | 3 | `analyze()` langsung `return []` kalau `isOfficial(host)`. `isOfficial` mencocokkan semua akhiran host, jadi subdomain apa pun dari `google.com` dianggap resmi, termasuk Google Sites dan Forms yang isinya buatan pengguna. Path tidak pernah dibaca. Selain itu `pengembalian` tidak ada di daftar umpan. | Terbuka. Butuh daftar host konten-pengguna yang dikecualikan dari `isOfficial` (`sites.google.com`, `docs.google.com`, `forms.gle`, `drive.google.com`, `script.google.com`, `forms.office.com`) |
| `yaigsjv.1238bll.my.id/ca/bin/2c.html` (07) | 5 | `digit_label` butuh label ≥ 8 karakter, `1238bll` hanya 7 (57% angka). Tidak ada rule label acak atau `.my.id`. | Terbuka |
| `storee-dp9hsk1cxr2y.edgeone.dev` (09, 10) | 0 | `edgeone.dev` tidak ada di `freeHosts`. `digit_label` menghitung seluruh label: 3 angka dari 19 karakter = 16%. | Terbuka. Tambah `edgeone.dev`, cek `digit_label` per potongan di antara `-` |
| `m-pajak.top` (08) | 4 + `cheap_tld` 5 | `pajak` bukan kata umpan atau brand. Skor dissector 4 dibuang karena di bawah `LINK_MIN_EMIT`, jadi tidak dijumlahkan dengan `cheap_tld`. | Terbuka. Pertimbangkan menjumlahkan skor sub-ambang dengan sinyal L2 lain |
| `viinwkwk-dot.github.io/instagram./` (20) | 3 | Cek brand hanya membaca host. `instagram` di path tidak diperiksa. | Terbuka. Rule brand di path pada host yang bukan resmi |
| `apply.wozspace.site/info` (15) | 0 + `cheap_tld` 5 | `apply` dan `info` bukan kata umpan. | Terbuka (kosakata umpan) |
| `deddydanchika.blogspot.com` (11) | 3 | Nama pribadi di blogspot, tidak ada kata umpan. Tidak bisa dibedakan dari blog sah lewat string URL. | Di luar L2, ditangani layer 3 |

### Perubahan yang sudah dibuat (27 Okt 2026)

Pola **connector + brand** di `detector/src/detector.js` (`matchByBrand`): potongan nama host yang berakhir `by|via|from` + nama brand (bukan brand yang juga kata biasa: dana, apple, mandiri) dihitung sebagai `brand_plus_keyword` (+14), connector jadi kata kuncinya. Hyphen di nama (`qlolla-bybri`) tidak dihitung dua kali. Tiga test baru di `detector/test/detector.test.mjs`, termasuk false positive yang dikunci (`hobbydana`, `baby-shop`, `ruby-store`, `viabus`, `standbyapple`, `toko-by-sari`). 59/59 test lulus. Hasil build sudah disinkronkan ke `ios/ShooExtension/Resources/detector.js`.

Hasil tes ulang: scam **18/25 ada signal** (dari 16), popup tetap 1/25; legit tetap **0/23 false positive**.

Bobot (+14) memakai nilai `brand_plus_keyword` yang sudah ada, bukan angka baru. Bobot lain di `hasil-analisis.md` belum disentuh dan belum diuji korpus.

### Perubahan ke-2 (27 Okt 2026)

- `digit_label` dinilai per potongan di antara `-`: potongan ≥ 6 karakter berisi huruf, ≥ 3 digit, dan digit ≥ 25%. Sebelumnya seluruh label harus ≥ 8 karakter dan digit ≥ 40%. Dilewati untuk `*.cloudfront.net` (id distribusi CloudFront selalu berbentuk begitu di situs asli). Bobot tetap +8.
- `edgeone.dev` masuk `freeHosts`.
- `pengembalian`, `pembatalan`, `kode` masuk `baitWords` (label dan nama file di free host) dan `pathBait` (path).
- 62/62 test lulus, termasuk false positive yang dikunci (`smpn1-jakarta.sch.id`, `covid19info.com`, `k24klik.com`, `mp3juices.com`, `d111abcdef.cloudfront.net`, `web3-dev.com`).
- Tes ulang: scam **20/25 ada signal, 2 popup** (`kodepembatalanbybni.pages.dev` = 33), legit tetap **0/23**.

Masih lolos setelah perubahan ke-2: `cusbsi.com` (04), `sites.google.com/...pengembalian...` (06, dilewati `isOfficial`), `m-pajak.top` (08), `storee-dp8iiud7biuu.edgeone.dev` (10, hanya 2 digit, di bawah syarat 3 digit), `apply.wozspace.site/info` (15), `deddydanchika.blogspot.com` (11), `viinwkwk-dot.github.io/instagram./` (20, brand hanya di path).
