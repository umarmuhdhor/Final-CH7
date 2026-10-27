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
