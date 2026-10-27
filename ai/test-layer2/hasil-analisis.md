# Hasil analisis komponen link (L2): usulan poin per komponen

Status: **usulan, belum terkalibrasi, belum ada kode yang diubah.** Angka datang dari pengalaman (prior) plus sanity check ke `dataset.md` (25 scam) dan `dataset-legit.md` (23 legit, semuanya situs besar). Dua dataset ini terlalu kecil untuk menyimpulkan apa pun secara statistik, jadi semua angka harus diuji ulang di korpus sebelum masuk kode. Perubahan di `detector/` dan `detector/data/link-rules.json` lewat lead (Umar), lihat `consider.md` untuk pertanyaan terbuka.

Hanya teks URL yang dianalisis. Halaman tidak dibuka. Isi halaman, form, umur domain adalah layer 3 ke atas.

## 0. Cara baca

**Satuan.** Poin tambahan di skor 0–100, bukan persen. Kolom **prior** adalah intuisi "seberapa sering komponen ini muncul di scam dibanding situs biasa", dipakai untuk membenarkan angka poin. Prior bukan probabilitas hasil ukur.

| Prior | Arti kasar | Poin |
|---|---|---|
| sangat rendah | situs legit pakai ini terus (Vercel, GitHub Pages) | +0 s/d +2 |
| rendah | agak lebih sering di scam | +3 s/d +4 |
| sedang | jelas lebih sering di scam, tapi legit juga ada | +5 s/d +8 |
| tinggi | di legit jarang | +10 s/d +15 |
| sangat tinggi | hampir pasti niat menipu | +20 s/d +30 |

**Aturan skor yang sudah ada dan tetap dipakai:**
- Poin dijumlah. Satu bagian URL (host, path, query, dll.) dibatasi **25** (`LINK_PART_CAP`). Total maksimum 100.
- Di bawah **10** (`LINK_MIN_EMIT`) link tidak mengeluarkan signal.
- Popup di **30** (threshold extension 30/50/80).
- Layer 3–4 hanya membaca `suspicious_link` kalau jumlahnya ≥ 10 dan hanya bisa menaikkan gate +20 (ai/CLAUDE.md, D-imelda-31/27). Jadi komponen yang prior-nya sedang ke bawah tidak boleh bobotnya besar sendirian.

**Prinsip desain:**
1. Komponen yang gratis dipilih penyerang (label di free host, nama file, subdomain) lebih jujur sebagai sinyal daripada komponen yang dipakai bersama banyak situs sah.
2. Komponen yang situs sah juga sering pakai (hyphen, `.php`, https) bobotnya kecil, **tidak boleh sendirian lolos 10**.
3. Kombinasi lebih penting dari komponen tunggal. Bonus interaksi di bagian 12.
4. Tidak ada poin negatif. Jalur resmi (`brands.json`, `.go.id`, `.ac.id`) sudah ditangani layer 1 dan cek brand, jadi tidak dihitung dua kali.

---

## 1. Kata umpan (bait words)

Sekarang: `baitWords` di `link-rules.json` (flat, 31 kata) dan `keywords` di `brands.json` (flat). Bobot bait di path +6 flat, di label free host +10 (1 kata) / +16 (≥2 kata), di nama file +10. Semua kata sama bobotnya. Usulan: 4 grup berdasarkan seberapa langsung kata itu mengarah ke "ada uang / ada masalah, klik sekarang".

| Grup | Ciri | Poin (di host/path) | Kata (usulan) |
|---|---|---|---|
| **G1 uang & klaim** | menjanjikan uang masuk atau transaksi yang harus dibatalkan | **+10** | pembatalan, batal, pengembalian, refund, pencairan, klaim, claim, hadiah, undian, giveaway, bansos, bantuan, subsidi, saldo, cashback, pinjol, pinjaman, denda, tilang, pajak (jika bukan `.go.id`), bpjs, lelang |
| **G2 kredensial** | meminta kredensial atau kode | **+7** | verifikasi, verify, login, signin, masuk, otp, kyc, unlock, blokir, akun, account, update, perbarui, aktivasi, activate, reset, code, kode, pemulihan, recovery |
| **G3 daftar & promo** | daftar program / diskon / gratisan | **+4** | registrasi, regs, register(s), daftar, pendaftaran, apply, promo, gratis, free, bonus, voucher, kuota, pulsa, reward, lowongan, prakerja, kripto |
| **G4 kepercayaan palsu** | menumpang rasa percaya | **+2** | official, resmi, secure, security, support, cs, cek, tracking, kurir, paket, resi, undangan |

Catatan penempatan:
- `code`, `kode` ada di G2 karena pola "code.php" muncul di 4 dari 25 scam dataset (id 12, 13, 14, 16). Perlu uji FP (situs dev sah punya `/code`). Syarat usulan: hanya di segmen path terakhir, dan host bukan platform dev (github.io tidak dihitung).
- `pajak`, `bpjs`, `tilang` masuk G1 hanya kalau host bukan `go.id`. Cek hostnya dulu.
- Kata dicari sebagai substring di label (`wordsIn`), jadi `kodepembatalanbybni` mengandung `kode` dan `pembatalan`. Kata pendek (`cs`, `cek`, `kyc`, `otp`) hanya dihitung di batas kata (dipisah `-`, `_`, `.`, angka) supaya tidak kena `topics`.
- Kata ke-2 dari grup berbeda: +2 tambahan (maks +4 per bagian). Dua kata dari grup yang sama tidak dihitung dobel penuh: ambil kata tertinggi lalu +2.
- Bait **di label free host atau di nama domain** ×1.5 dibanding di path, karena bagian itu dipilih bebas oleh penyerang. Contoh: `pembatalan` di label pages.dev = 10 × 1.5 = **15**, di path = 10.
- Brand + bait tetap pakai `brand_plus_keyword` (+14) dari part A. Tidak dihitung dobel di bagian ini.
- Prior: G1 tinggi (uang gratis / urgensi), G2 sedang, G3 rendah–sedang (banyak toko sah pakai "promo"), G4 sangat rendah sendirian.

---

## 2. Suffix / TLD

Sekarang: `cheapTlds` di `brands.json` (+5 sendirian, +15 bersama brand), `rareTlds` (info, pw, cc, ws, su) +6. Semua TLD murah sama bobotnya. Usulan: 4 tier.

| Tier | Contoh | Poin | Prior & alasan |
|---|---|---|---|
| **T0 terpercaya** | `.go.id`, `.ac.id`, `.sch.id`, `.mil.id`, `.gov`, `.edu` | **0** | Registrasi terverifikasi. Tidak ada poin negatif, tapi tidak ditambah apa pun. |
| **T1 biasa** | `.com`, `.org`, `.net`, `.id`, `.co.id`, `.or.id`, `.io`, `.dev`, `.app` | **0** | Mayoritas situs sah dan scam. Tidak informatif. |
| **T2 murah / lokal gratisan** | `.my.id`, `.biz.id`, `.web.id`, `.site`, `.online`, `.link`, `.work`, `.fun`, `.vip`, `.rest`, `.quest`, `.blog`, `.store`, `.shop` | **+3 s/d +5** | Murah. Banyak juga dipakai UMKM sah. `.my.id` muncul di dataset scam id 07, `.site` di id 15. |
| **T3 sangat murah, abuse tinggi** | `.xyz`, `.top`, `.icu`, `.buzz`, `.cfd`, `.sbs`, `.click`, `.cyou`, `.bond`, `.monster`, `.tk`, `.ml`, `.ga`, `.cf`, `.gq` | **+8** | Obvious. Registrasi hampir gratis, laporan phishing per domain paling tinggi. `.top` di scam id 08. |
| **T3b langka** | `.info`, `.pw`, `.cc`, `.ws`, `.su`, `.zip`, `.mov` | **+6** | Sudah ada (`rare_tld`). `.zip`/`.mov` tambahan karena mirip nama file. `.info` di dataset id 21. |

Interaksi (bagian 12): TLD T3 + brand di nama domain tetap +15 (aturan yang sudah ada). TLD T3 + bait → +4 bonus.

Catatan: `.com` tetap 0 walau banyak scam pakai `.com` (cusbsi.com, regnows-dfg.com). Menambah poin untuk `.com` tidak adil ke semua situs sah. Itu masalah umur domain (layer 3 server).

---

## 3. Suffix platform (free host)

Sekarang: `freeHosts` (20 entri) semuanya `free_host` **+3 flat**. Ini kasar: Vercel dan 000webhost beda jauh. Tier usulan, dengan tambahan yang kurang di list.

| Tier | Platform | Poin | Prior & alasan |
|---|---|---|---|
| **P1 developer populer** | `vercel.app`, `github.io`, `netlify.app`, `web.app`, `firebaseapp.com` | **+2** | Dipakai jutaan developer & portofolio, porsi scam kecil (perkiraan ~3% dari subdomain, belum diukur). Tetap +2 karena penyerang suka gratisnya. |
| **P2 builder / blog** | `blogspot.com`, `blogspot.co.id`, `weebly.com`, `wixsite.com`, `wordpress.com`, `webflow.io`, `sites.google.com`, `pages.dev`*, `carrd.co`, `framer.app`, `godaddysites.com`, `mystrikingly.com` | **+4** | Banyak dipakai UMKM / blog sah, tapi blogspot adalah media scam bansos & kuota yang sangat sering di Indonesia (dataset id 11, 21, 23, 24, 25). |
| **P3 host gratis dengan sejarah abuse** | `000webhostapp.com`, `glitch.me`, `workers.dev`, `r2.dev`, `herokuapp.com`, `edgeone.dev`**, `surge.sh`, `onrender.com`, `fly.dev`, `repl.co`, `replit.app`, `lovable.app`, `bolt.host`, `trycloudflare.com`, `ngrok-free.app`, `bubbleapps.io`, `typedream.site` | **+6** | Subdomain acak gratis, tanpa verifikasi. Dipakai untuk landing sekali pakai. |
| **P4 CDN / object storage** | `cloudfront.net`, `s3.amazonaws.com`, `storage.googleapis.com`, `blob.core.windows.net` | **+2** | CDN sah di mana-mana. Yang mencurigakan adalah **`.html` langsung di CDN** (scam id 22), itu ditangkap `file_ext` + bait nama file. |

\* `pages.dev` ada di dataset scam (id 05) dan sering disalahgunakan; ditaruh di P2 walau secara tampilan mirip P1.
\*\* `edgeone.dev` **belum ada di `freeHosts`** padahal ada di dataset (id 09, 10). Belum ada di `link-rules.json` juga: `carrd.co`, `godaddysites.com`, `mystrikingly.com`, `surge.sh`, `onrender.com`, `fly.dev`, `repl.co`, `replit.app`, `lovable.app`, `bolt.host`, `trycloudflare.com`, `ngrok-free.app`, `bubbleapps.io`, `typedream.site`, `framer.app`, `storage.googleapis.com`, `blob.core.windows.net`.

**Label di platform** (nama yang dipilih orang): bait di label ×1.5 (bagian 1). Skor host = tier + bait(label)×1.5. Contoh `gratiskuota60gb.blogspot.com` = 4 (P2) + G3 gratis (4×1.5=6) + kuota (+2) + angka/kuota (+4) = **16**: muncul sebagai signal, bukan popup. `bantuannbansos2026.blogspot.com` = 4 + G1 bantuan (15) + bansos (+2) + tahun (+4) + interaksi free host + G1 (+4) = **29**.

---

## 4. Skema (HTTP / HTTPS)

Sekarang: `http` → +5 `http_no_tls`. Semua scam di dataset (25/25) pakai **https** karena sertifikat gratis (Let's Encrypt, Cloudflare). Jadi https tidak informatif dan tidak boleh menurunkan skor.

| Kondisi | Poin | Prior & alasan |
|---|---|---|
| `https` | **0** | Tidak membedakan. |
| `http` biasa | **+5** (tetap) | Situs modern hampir tidak pernah `http`. Situs lama dan intranet memang masih ada. |
| `http` + bait G2 (login/otp) di host atau path | **+5 bonus** (total ≥ 10, emit) | Halaman login tanpa TLS di 2026 tidak masuk akal bagi layanan resmi. |
| skema selain http(s) | 0, abaikan | Bukan scope extension. |

---

## 5. Userinfo (`user:pass@host`)

Sekarang: **+25**. Pertahankan. Prior sangat tinggi: `https://bca.co.id@evil.com` menipu mata, hampir tidak ada penggunaan sah di web modern.

---

## 6. Nama domain (label registrable, mis. `cusbsi` di `cusbsi.com`)

| Komponen | Sekarang | Usulan | Prior & alasan |
|---|---|---|---|
| Mirip brand (lookalike, homoglyph) | +25 (`lookalike_domain`) | **tetap** | Sinyal terkuat, sudah ada di part A. |
| Hanya nama brand di domain tidak resmi | +10 | **tetap** | Bisa domain sah pihak ke-3 (blog tentang BCA). |
| Brand + bait (bca-verifikasi) | +14 | **tetap** | |
| Brand 3 huruf sebagai substring di tepi label (`cusbsi`, `qlolla-bybri`) | tidak ada | **+8, kandidat, butuh uji FP** | Brand pendek (bsi, bni, bri, bca) sering nyangkut di kata biasa (`bribery`). Syarat usulan: brand di awal/akhir label atau diapit `-`, dan label ≤ 14 huruf. Dataset id 03, 04, 18. |
| Nama produk brand (BNI Direct, QLola, CUZ, myBCA, Cash Management) | tidak ada | **+8 kalau brand + nama produk** | Domain scam id 01, 02, 03, 17, 18 meniru nama produk. Butuh `brandProducts` di `brands.json` (data, bukan kode). |
| Hyphen di label registrable (`regnows-dfg`, `m-pajak`) | +4 (`hyphen_registrable`, kecuali ada brand/keyword) | **1 hyphen +3, 2 hyphen +5, ≥ 3 hyphen +8** | Situs sah juga pakai hyphen (`rfc-editor.org`), bobot kecil. 3 hyphen jarang di situs sah. |
| Awalan 1 huruf + hyphen (`m-pajak`, `e-bca`, `i-bank`) | tidak ada | **+3** | Meniru "mobile / e-". Situs sah juga ada (`e-commerce`). Kecil. |
| Label panjang (≥ 20 huruf di registrable) | tidak ada | **+3** | Domain yang menggabung banyak kata bait. |
| Gibberish (`yaigsjv`, `1238bll`) | tidak ada | **+5, kandidat** | Label ≥ 6 huruf tanpa pola suku kata (4+ konsonan berturut-turut, tanpa `ng/ny/sy/sh/th/ch`). Uji FP di korpus Indonesia (singkatan, nama daerah). |
| Punycode (`xn--`) | +5 | **+5**, **+15 jika campur skrip** | Campur skrip dalam satu label (Latin + Cyrillic) hampir selalu spoof. `fold(label) !== label` sudah bisa dipakai. |

---

## 7. Subdomain

| Komponen | Sekarang | Usulan | Prior & alasan |
|---|---|---|---|
| Kedalaman `a.b.domain.tld` | ≥ 4 label +8 (`many_labels`) | **3 label +3, ≥ 4 label +8, ≥ 6 label +12** | Subdomain banyak = menyembunyikan domain asli. |
| `www`, `m`, `app`, `api`, `docs`, `blog`, `mail` | 0 | **0**, abaikan di semua rule | Sangat umum di situs sah. |
| Kata-angka (`regs-apps14`, `portal2`, `secure88`) | +6 (`word_digit_subdomain`) | **+8** | Dataset id 12, 13, 14, 16 (4 dari 25): `kata-kata+angka` di atas domain ber-hyphen acak. Naik karena +6 sekarang kalah dari batas emit saat berdiri dengan `file_ext`. |
| Bait dalam subdomain (`login-mybca-bisnis.ibcbank-aceh.com`) | lewat `brand_plus_keyword` | **sesuai grup** ×1.5 | Pola klasik: kata resmi di subdomain, domain asli bukan brand. |
| Brand di subdomain, registrable bukan brand | +10 | **+15** jika ada bait atau angka | Mis. `bca.verifikasi-akun.xyz`. Part A. |
| Token acak (`storee-dp9hsk1cxr2y`) | `digit_label` +8 (≥ 8 huruf, ≥ 40% digit) | **+8**, **+4 jika berpola `kata-hex12`** | Subdomain otomatis dari generator (edgeone.dev, id 09 & 10). |

---

## 8. Angka di host

| Komponen | Sekarang | Usulan | Prior & alasan |
|---|---|---|---|
| IP langsung (`http://103.21.x.x/login`) | +20 | **+20**, **+30 kalau ada bait G1/G2 atau `.php`** | Layanan resmi pakai domain. IP + login hampir pasti phishing / kit. |
| IP bentuk lain (desimal, hex, oktal) | `new URL` mengubah ke dotted, ikut +20 | **tidak perlu rule baru** | Cukup tambah test, jangan tambah kode. |
| Campuran huruf+angka di label (`1238bll`) | +8 hanya jika ≥ 8 huruf & ≥ 40% digit | **+3 untuk campuran di registrable (bukan brand)**, tetap +8 untuk rasio tinggi | Umum di kit phishing, tapi situs sah juga ada. Kecil. |
| Tahun / kuota di label (`2026`, `60gb`) | +5 hanya di free host | **+4 di semua label** | "bansos2026", "kuota60gb" adalah umpan di mana pun. |
| Port | +10 untuk selain 80/443 | **8080/8443/3000/5000 +4, lainnya +10** | Port dev biasa tidak selalu berniat jahat. |

---

## 9. Path

| Komponen | Sekarang | Usulan | Prior & alasan |
|---|---|---|---|
| Bait di path | +6 flat (`path_bait`), kata `code`, `activate` | **G1 +6, G2 +7, G3 +3, G4 +1** (tanpa ×1.5) | Path bisa struktur situs sah (`/login`, `/promo`). Bobot di bawah bait di host. |
| Segmen terakhir `code` / `code.php` / `otp` / `otp.html` | `code` lewat pathBait +6 | **+8** | Pola 4 dari 25 dataset. FP: dokumentasi `/code`. |
| `wp-content`, `wp-includes`, `wp-admin` dengan `.php` di host tak dikenal | tidak ada | **+5** | WordPress diretas dipakai menyimpan kit phishing. |
| Path > 6 segmen | tidak ada | **+2** | Lemah, jangan lebih. |
| Segmen berisi email atau URL (`/redirect/http://…`) | tidak ada | **+8** | Redirect disamarkan. |

---

## 10. Nama file dan ekstensi

| Komponen | Sekarang | Usulan | Prior & alasan |
|---|---|---|---|
| Ekstensi skrip `.php`, `.asp(x)`, `.jsp`, `.html`, `.htm` | +5 (`file_ext`) | **+5**, **`.html` di free host / CDN +8** | Situs sah juga pakai (docs, `index.html`). Di CDN atau free host sebagai halaman langsung = umpan sekali pakai (id 07, 19, 22). |
| **Ekstensi unduhan `.apk`** | tidak ada | **+25** | Penipuan "resi / BPJS / undangan pernikahan .apk" sangat umum di Indonesia. Link biasanya dibagikan lewat WA ke banyak orang, termasuk yang membuka di iPhone. Tidak ada alasan sah. |
| Unduhan `.exe`, `.scr`, `.bat`, `.msi`, `.dmg`, `.pkg`, `.ipa`, `.zip`, `.rar`, `.iso`, `.jar` | tidak ada | **+15** | Unduhan langsung dari link yang dibagikan adalah vektor malware. |
| `.mobileconfig` (profil iOS) | tidak ada | **+25** | Bisa memasang profil di iPhone. Prior sangat tinggi untuk link yang dibagikan. |
| Ekstensi ganda (`invoice.pdf.html`, `foto.jpg.php`, `resi.pdf.apk`) | tidak ada | **+12** | Menyamar sebagai dokumen. |
| Nama file bait | +10 (`free_file_bait`, hanya free host) | **sesuai grup bagian 1** (G1 +8, G2 +6, G3 +3, G4 +1), semua host | `dhl123.html`: kurir G4 +1 + angka (+3) + `.html` di CDN (+8). |
| Nama file acak (≥ 20 huruf/angka, entropi tinggi, ada digit) | +15 (`random_name`) | **+15** | Dataset id 21. Tetap. |
| Slash setelah file (`file.html/`) | +8 | **+8** | Dataset id 21. Tidak ada alasan sah. |

---

## 11. Query, fragment, panjang URL, shortener

| Komponen | Sekarang | Usulan | Prior & alasan |
|---|---|---|---|
| Parameter redirect ke URL lain (`?url=http://…`) | +12 | **+12** | Open redirect dipakai membungkus link jahat. |
| Email di query | +5 | **+5** | Prefill korban. Lemah. |
| Query panjang > 150 | +5 | **+5**, **> 300 +8** | Tracking sah juga panjang. |
| `http(s):` di fragment | +8 | **+8** | |
| Panjang URL > 120 | +4 | **+4**, **> 200 +6** | Lemah. |
| **Shortener** (`bit.ly`, `s.id`, `tinyurl.com`, `cutt.ly`, `rb.gy`, `t.ly`, `shorturl.at`, `is.gd`) | tidak ada | **+6** | Tujuan akhir tersembunyi. Banyak link scam di WA lewat sini, tapi marketing sah juga. Kecil, dibantu layer lain (redirect chain belum ada). |

---

## 12. Interaksi (bonus kombinasi)

Dihitung setelah cap per bagian. Total bonus maksimum **+15**.

| Kombinasi | Bonus | Alasan |
|---|---|---|
| Bait di **dua bagian berbeda** (host + path/file) | **+6** | Penyerang menaruh umpan di banyak tempat. `regs-…/code.php`, `shopeeofficial-refund…/otp.html`. |
| Free host (P2/P3) + bait G1/G2 di label | **+4** | Platform gratis + umpan uang/kredensial. |
| TLD T3 + bait G1/G2 | **+4** | `.xyz` / `.top` + "verifikasi / bansos". |
| `http` + bait G2 | **+5** | Bagian 4. |
| Brand (part A) + free host / TLD T3 | sudah **+15** di part A, jangan tambah | |
| Tiga atau lebih bagian URL punya sinyal | **+4** | Banyak sumber lemah bertumpuk lebih mencurigakan daripada satu sumber kebetulan. |

---

## 13. Contoh hitung ulang (perkiraan manual, bukan hasil menjalankan kode)

| URL | Komponen usulan | Skor sekarang | Skor usulan |
|---|---|---|---|
| `https://regs-apps14.regnows-dfg.com/code.php` | kata-angka +8, hyphen registrable +3, bait G3 `regs` 4×1.5=+6, `.php` +5, `code.php` +8, interaksi 2 bagian +6 | 21 | **≈ 36, popup** |
| `https://shopeeofficial-refund.vercel.app/otp.html` | P1 +2, label G1 `refund` 15 + `official` +2, `otp.html` G2 +7, `.html` di free host +8, interaksi +6 | ≈ 15 | **≈ 40** (belum termasuk brand part A) |
| `https://kodepembatalanbybni.pages.dev/` | P2 +4, label G1 `pembatalan` 15 + `kode` +2, interaksi free host + G1 +4 | ≈ 13 | **≈ 25** (+ brand bni part A ≈ 35) |
| `https://gratiskuota60gb.blogspot.com/` | P2 +4, G3 6+2, angka +4 | ≈ 21 | **≈ 16** (turun, umpan G3 memang lemah) |
| `https://bantuannbansos2026.blogspot.com/` | P2 +4, G1 15+2, tahun +4, interaksi +4 | ≈ 26 | **≈ 29** |
| `https://m-pajak.top/` | T3 +8, hyphen +3, awalan 1 huruf +3, G1 `pajak` 15 | ≈ 5 | **≈ 29** |
| `https://cusbsi.com/` | brand pendek tepi label +8 (kandidat) | 0 | **8, tidak emit.** Tetap butuh umur domain + isi halaman. |
| `https://x.vercel.app/` | P1 +2 | 3 | **2, tidak emit** |
| `https://vercel.com/`, `github.com`, 23 URL `dataset-legit.md` | tidak ada komponen | 0 | **0** |

Yang akan tertangkap dengan usulan: pola `kata-kata+angka` + `code.php`, free host dengan umpan G1/G2, domain T3 dengan umpan. Yang tetap lolos: domain polos baru (`cusbsi.com`, `qlolla-bybri.com`, `bni-diirect.com`). Itu batas analisis URL, bukan kelalaian rule.

---

## 14. Yang perlu dilakukan sebelum masuk kode

1. Jalankan `analyze.mjs` terhadap `dataset.md` dan `dataset-legit.md` setelah bobot diubah. Syarat: legit tetap 0 (23/23), scam yang emit naik dari 48%.
2. Korpus legit **belum mewakili** UMKM / toko lokal / blog personal (sudah dicatat di `dataset-legit.md`). Tambah minimal 50 URL: toko online `.co.id`, blogspot sah, github.io portofolio, `.my.id` UMKM. Tanpa itu FP rule gibberish, hyphen, dan bait G3 tidak bisa diukur.
3. Rule berstatus **kandidat** (gibberish, brand substring pendek, awalan 1 huruf, `code` di path): jangan masuk sebelum FP diuji.
4. Tambah test di `detector/test/detector.test.mjs` untuk dua sisi: scam tertangkap, legit tetap `[]`.
5. Data (`brandProducts`, tier `freeHosts`, grup bait) ada di `detector/data/`, bobot dan logika di `detector/src/detector.js`. Keputusan ambang (`LINK_MIN_EMIT`, `LINK_PART_CAP`, bonus interaksi) dan tambahan data brand: tanya Umar lewat issue (CLAUDE.md rule 7).
6. Umur domain (RDAP) tetap di luar scope dokumen ini; lihat `consider.md`.
