# C6 — Tinjauan bobot layer 3–4 dan ambang 30/50/80

**Status:** `[x]` laporan selesai; **usulan menunggu keputusan Umar**. Tidak ada bobot, ambang, atau kontrak yang diubah.
**Branch:** `docs/AI-M6-c6-weight-review` dari `main` (5bca568). 24 Okt 2026.
**Bahan:** eval M2 lokal tanpa LLM dan tanpa RDAP, lalu skor ulang offline dari sinyal yang terekam (tanpa mengubah `src/`).

> **Peringatan utama.** Dari 50 sampel scam, 49 sintetis (ditulis sendiri) dan hanya 1 nyata (`lphone-login`). Setiap penyetelan pada data ini berisiko menghafal sampel kita sendiri (M6, A4/#73, D-imelda-22). Angka di bawah hanya menunjukkan **arah**, bukan bukti bahwa target mandat tercapai.

## Ringkasan
1. **Skor ≥ 50 tidak bisa dinaikkan lewat bobot.** Dari 13 scam tuning di bawah 50, 9 tidak punya sinyal layer 3 sama sekali (tanpa form, form tanpa field sensitif, atau form di iframe). 4 sisanya hanya punya satu sinyal form (20–25); untuk mencapai 50, satu sinyal ambigu harus bernilai ≥ 50 sendirian, dan itu melanggar D-imelda-04.
2. **Skor ≥ 80 bisa sedikit naik** lewat `brand_logo_offsite` 25 → 30 (+2 halaman) atau ambang blokir 80 → 70/75 (+5/+2), tanpa salah blokir baru di set ini.
3. **Salah blokir `trap-fintech-kyc-sah` (85) tidak bisa diperbaiki lewat bobot** tanpa menurunkan deteksi (sama dengan F-04-1 di fase-07).
4. **`urgent_language` tidak pernah menyala di scam** (0/38 tuning). Bobotnya tidak berpengaruh; masalahnya cakupan frasa, bukan angka.
5. **Bobot layer 4 tetap 30.** Menaikkannya tidak menambah scam yang lewat 50/80 (batas atas), tapi menambah risiko salah blokir di 5 halaman sah yang lolos gerbang.
6. **Rekomendasi:** bobot layer 3–4 **tidak diubah** sekarang. Satu-satunya perubahan yang layak dipertimbangkan Umar: `brand_logo_offsite` (penuh) 25 → 30, dan/atau ambang blokir 75 (keputusan lead, perubahan kontrak). Keduanya sebaiknya menunggu data scam nyata.

## 1. Inventaris sinyal (kode `main` 5bca568)

| id | Layer | Bobot di kode | Diatur di | Kapan menyala |
|---|---|---|---|---|
| `db_match` | 1 | 100 (skor langsung 100) | `detector/src/detector.js:230` | `ShooLists.match(hostname)` cocok (daftar Shoo / publik) |
| `lookalike_domain` level 3 | 2 | 25 | `detector/src/detector.js:15` (`WEIGHT.lookalike`), dipakai `:284` | ejaan mirip brand (angka↔huruf, typo, homoglyph, `xn--`) |
| `lookalike_domain` level 1 | 2 | 10 | `detector/src/detector.js:15` (`nameOnly`), `:290` | nama brand persis di domain tak terdaftar (bukan nama umum) |
| `brand_plus_keyword` | 2 | 14 | `detector/src/detector.js:15` (`brandKeyword`), `:288` | brand + kata umpan (`bca-verifikasi`) |
| `cheap_tld` | 2 | 15 dengan brand, 5 sendirian | `detector/src/detector.js:15`, `:294` | `.xyz`, `.site`, `.click`, … |
| `new_domain` | 3 | < 7 hari 30 · 7–30 hari 20 · 31–90 hari 10 | `ai/src/layer3/signals.js:88-93` | umur domain dari RDAP (server); gagal/lambat = tanpa sinyal |
| `asks_pin` | 3 | 35 | `ai/src/layer3/signals.js:5` | field PIN/passcode |
| `asks_otp` | 3 | 25 | `ai/src/layer3/signals.js:6` | field OTP/kode verifikasi |
| `asks_password` | 3 | 15 | `ai/src/layer3/signals.js:7` | `type=password` di situs tidak resmi |
| `asks_card` | 3 | 20 | `ai/src/layer3/signals.js:8` | nomor kartu |
| `asks_cvv` | 3 | 25 | `ai/src/layer3/signals.js:9` | CVV/CVC; **dibuang bila `asks_card` menyala** (`ai/src/layer3/forms.js:100`, D-imelda-34) |
| `asks_ktp` | 3 | 25 | `ai/src/layer3/signals.js:10` | NIK/KTP |
| `asks_selfie_ktp` | 3 | 35 | `ai/src/layer3/signals.js:11` | selfie + KTP (field yang sama atau form yang sama) |
| `urgent_language` | 3 | 15 penuh / 8 tenang | `ai/src/layer3/signals.js:58`, `:61` | frasa dari `URGENT_PHRASES` (`ai/src/layer3/content.js:10-16`); frasa umum hanya dengan kata ancaman |
| `brand_logo_offsite` | 3 | 25 penuh / 12 tenang | `ai/src/layer3/signals.js:58`, `:61` | brand di alt logo / title aksi, domain bukan resmi |
| `unreasonable_request` | 4 | 30 | `ai/src/layer4/reality.js:16` | LLM: permintaan tidak wajar, `confidence >= 0.6` (`:17`); gerbang form + skor aturan server ≥ 15 (`:18`, `:40-44`) |

Aturan penentu bobot lain:
- **Tenang vs penuh** (D-imelda-31): kata (`urgent_language`, `brand_logo_offsite`) berbobot penuh bila ada sinyal `asks_*`, atau bila layer 1–2 dari klien ≥ 10 (`ai/src/analyze.js:25-32`, `:21`). Selain itu tenang.
- **Situs resmi / populer** (D-imelda-11, -30): tanpa sinyal form dan konten.
- **Skor** = `min(100, jumlah bobot)`; `db_match` → 100 (contracts/detector-interface.md). Ambang di extension: `ios/ShooExtension/Resources/pipeline.js:6` (`30 / 50 / 80`), kontrak: `contracts/README.md` "Thresholds" dan `contracts/scan-result.schema.json` (`status`: 30–79 warning, ≥ 80 blocked).

### Beda antara kode, kontrak/fixture, dan ref/R1
| Tempat | Nilai di sana | Nilai di kode |
|---|---|---|
| `contracts/fixtures/blocked-92.json` | `asks_pin` 25, `unreasonable_request` 22, `brand_plus_keyword` 15 | 35, 30 (tetap), 14 |
| `contracts/fixtures/blocked-marked-safe.json` | `asks_card` 30, `cheap_tld` 21 | 20, 15 atau 5 |
| `contracts/fixtures/warning-41.json` | `urgent_language` 12 | 15 atau 8 |
| `contracts/fixtures/warning-63.json` | `brand_plus_keyword` 13, `urgent_language` 10 | 14, 15 atau 8 |
| `plan/imelda/ref/R1-sinyal-bobot-anggaran.md` | `asks_otp`/`asks_card`/`asks_cvv`/`asks_ktp` 30; `new_domain` layer 2; tanpa bobot tenang 8/12 | 25/20/25/25; layer 3; ada |

Fixture adalah data contoh untuk UI (jumlah bobotnya sendiri konsisten dengan skornya), jadi tidak ada yang rusak. Tapi fixture tidak lagi mencerminkan bobot nyata. `unreasonable_request` 22 tidak mungkin keluar dari kode (bobot tetap 30). Kalau fixture ingin realistis, itu perubahan kontrak (lead). R1 adalah usulan awal; nilai yang berlaku ada di DECISIONS (D-imelda-30/31/34). Laporan ini tidak mengubah keduanya.

## 2. Eval lokal tanpa LLM (24 Okt 2026)

Cara menjalankan:
- Worktree tanpa `ai/.env`. Dev server dijalankan dengan `env -u LLM_API_KEY -u LLM_MODEL -u LLM_BASE_URL -u SHOO_RDAP node src/dev-server.mjs`.
- `GET /_dev/layer4` = `{"off":true}` sebelum, di antara, dan sesudah run. Tidak ada panggilan LLM.
- RDAP mati (`SHOO_RDAP` tidak diset), jadi tidak ada domain eval yang dikirim ke registry.
- `node ai/eval/run.mjs --analyze-url http://localhost:8787` (teks) dan `--json` (untuk skor ulang). Holdout tidak dibuka per sampel (`--show-holdout` tidak dipakai).

Hasil sama dengan baseline D-imelda-36/37: tidak ada drift sejak 23 Okt.

| Metrik | Target | Semua (50 scam / 53 legit) | Tuning (38 / 39) | Holdout, total saja (12 / 14) |
|---|---|---|---|---|
| Scam ≥ 30 | – | 36/50 | 27/38 | – |
| Scam ≥ 50 | ≥ 90% | 31/50 = 62% | 25/38 = 66% | 6/12 |
| Scam ≥ 80 | ≥ 70% | 13/50 = 26% | 10/38 = 26% | 3/12 |
| Legit ≥ 30 | 0 | 1/53 (`trap-fintech-kyc-sah`, 85) | 1/39 | 0/14 |
| Scam nyata (1) | – | `lphone-login` 39 | | |
| `analyzeLocal` | < 50 ms | rata-rata 0,20 ms, maks 0,45 ms | | |
| `/analyze` lokal | p95 < 8 s | p95 2 ms (tanpa RDAP/LLM/jaringan HP) | | |

### Skor per halaman (tuning; holdout disembunyikan oleh `run.mjs`)
"Gerbang" = halaman yang akan memanggil layer 4 (ada form dengan field dan skor aturan server ≥ 15).

| Scam | Skor | Sinyal | Form | Gerbang |
|---|---|---|---|---|
| `syn-bri-token-expired` | 100 | bpk 14, tld 15, pin 35, otp 25, logo 25 | ya | ya |
| `syn-bsi-sharia-bonus` | 100 | look1 10, tld 15, pin 35, ktp 25, logo 25 | ya | ya |
| `syn-ovo-upgrade-premier` | 100 | look1 10, tld 15, pin 35, ktp 25, logo 25 | ya | ya |
| `syn-gopay-driver-refund` | 100 | bpk 14, tld 15, pin 35, otp 25, logo 25 | ya | ya |
| `syn-kemensos-bansos-pkh` | 99 | bpk 14, pin 35, ktp 25, logo 25 | ya | ya |
| `syn-gopay-later-pinjam` | 90 | tld 5, selfie 35, ktp 25, logo 25 | ya | ya |
| `syn-bri-cashback-survey` | 85 | look1 10, tld 15, pin 35, logo 25 | ya | ya |
| `syn-mandiri-kyc-update` | 85 | selfie 35, ktp 25, logo 25 | ya | ya |
| `syn-prakerja-gelombang` | 85 | selfie 35, ktp 25, otp 25 | ya | ya |
| `syn-dukcapil-ktp-digital` | 85 | selfie 35, ktp 25, otp 25 | ya | ya |
| `syn-dana-kaget-bonus` | 79 | bpk 14, tld 15, otp 25, logo 25 | ya | ya |
| `syn-bukalapak-voucher` | 79 | bpk 14, tld 15, otp 25, logo 25 | ya | ya |
| `syn-bpjs-bonus-iuran` | 74 | bpk 14, tld 15, logo 25, card 20 | ya | ya |
| `syn-jne-paket-tertahan` | 70 | look1 10, tld 15, logo 25, card 20 | ya | ya |
| `syn-lazada-giveaway` | 70 | look1 10, tld 15, logo 25, card 20 | ya | ya |
| `syn-shopeepay-limit` | 69 | bpk 14, tld 15, logo 25, password 15 | ya | ya |
| `syn-pajak-djp-sptp` | 69 | bpk 14, tld 15, logo 25, password 15 | ya | ya |
| `syn-icloud-terkunci` | 69 | bpk 14, tld 15, otp 25, password 15 | ya | ya |
| `syn-pinjol-cair-cepat` | 65 | tld 5, selfie 35, ktp 25 | ya | ya |
| `syn-bca-klikbca-clean` | 60 | pin 35, logo 25 | ya | ya |
| `syn-pertamina-subsidi` | 60 | selfie 35, ktp 25 | ya | ya |
| `syn-ovo-undian-grab` | 54 | bpk 14, tld 15, logo 25 | tidak | tidak |
| `syn-shopee-flash-undian` | 54 | bpk 14, tld 15, logo 25 | ya | ya |
| `syn-jnt-tarif-selisih` | 50 | look1 10, tld 15, logo 25 | ya | ya |
| `syn-pos-kiriman-luar-negeri` | 50 | look3 25, logo 25 | tidak | tidak |
| `lphone-login` (nyata) | 39 | look3 25, bpk 14 | tidak (iframe) | tidak |
| `syn-tiki-nomor-resi` | 30 | tld 5, otp 25 | ya | ya |
| `fixture-bca-verifikasi` | 29 | bpk 14, tld 15 | tidak (hanya URL) | tidak |
| `fixture-promo-shopee` | 29 | bpk 14, tld 15 | tidak (hanya URL) | tidak |
| `fixture-bansos-kemensos` | 29 | bpk 14, tld 15 | tidak (hanya URL) | tidak |
| `synthetic-p0stindonesia` | 25 | look3 25 | tidak (hanya URL) | tidak |
| `syn-find-my-iphone-hilang` | 25 | look1 10, tld 15 | tidak (iframe) | tidak |
| `syn-telkomsel-poin` | 25 | otp 25 | ya | ya |
| `syn-apple-pay-tagihan` | 25 | tld 5, card 20 | ya | ya |
| `syn-anteraja-alamat` | 20 | card 20 | ya | ya |
| `syn-sicepat-apk` | 5 | tld 5 | tidak (unduh APK) | tidak |
| `syn-loker-admin-online` | 0 | – | ya (tanpa field sensitif) | tidak |
| `syn-investasi-kripto-profit` | 0 | – | ya (tanpa field sensitif) | tidak |

Singkatan: bpk = `brand_plus_keyword`, tld = `cheap_tld`, look1/look3 = `lookalike_domain` level 1/3, logo = `brand_logo_offsite` penuh, selfie = `asks_selfie_ktp`. Semua scam di atas sintetis kecuali `lphone-login`.

| Legit dengan skor > 0 | Skor | Sinyal | Gerbang |
|---|---|---|---|
| `trap-fintech-kyc-sah` | **85** | selfie 35, ktp 25, otp 25 | ya |
| `trap-batik-card-checkout-en` | 25 | tld 5, card 20 | ya |
| `trap-toko-kopi-kartu-native` | 20 | card 20 | ya |
| `trap-berita-waspada-penipuan` | 20 | logo tenang 12, urgent tenang 8 | tidak (tanpa form) |
| `trap-sign-in-google-facebook` | 15 | password 15 | ya |
| `trap-portal-orang-tua-sekolah` | 15 | password 15 | ya |
| `trap-blog-cek-saldo-bca` | 12 | logo tenang 12 | tidak |
| 32 legit lain (semua halaman nyata + 3 trap) | 0 | – | – |

## 3. Analisis

### Sebaran skor di sekitar ambang (tuning)
| Rentang | Scam (38) | Legit (39) |
|---|---|---|
| 0–29 | 11 | 38 |
| 30–49 | 2 | 0 |
| 50–79 | 15 | 0 |
| 80–100 | 10 | 1 |

- Legit sangat terpisah: semua kecuali satu ≤ 25. Jarak ke 30 paling kecil 5 poin (`trap-batik-card-checkout-en`, 25). Bobot `asks_card` atau `cheap_tld` sendirian tidak bisa dinaikkan tanpa membuat salah popup.
- Scam terbagi dua: 13 di bawah 50 (hampir semua di 0–29), dan 15 di "warning 2" 50–79. Rentang 30–49 hampir kosong. Jadi ambang 50 bukan masalahnya: halaman scam biasanya punya beberapa sinyal sekaligus, atau hampir tidak punya sinyal.

### Apa yang membawa scam lewat 50 dan 80
- **Lewat 80 (10/38):** selalu ada minimal satu sinyal form berat (`asks_pin` 35 atau `asks_selfie_ktp` 35) **plus** dua sinyal lain. Pola: PIN/selfie + KTP/OTP + logo penuh, atau tiga sinyal form KYC.
- **Lewat 50 tapi < 80 (15/38):** pola paling umum = layer 2 (24–29) + `brand_logo_offsite` penuh 25 + satu form ringan (`asks_card` 20 / `asks_password` 15 / `asks_otp` 25), 7 dari 15 halaman. Pola ini kurang 1–11 poin dari 80. Dua halaman 79 (`syn-dana-kaget-bonus`, `syn-bukalapak-voucher`) hanya kurang 1 poin.
- `brand_logo_offsite` penuh menyala di 20 dari 38 scam tuning, dan ke-20 halaman itu semuanya ≥ 50 (20 dari 25 halaman ≥ 50). Ini sinyal layer 3 yang paling sering membawa skor.

### Scam di bawah 50: sinyal hilang vs bobot rendah
| Sebab | Halaman | Bisa diperbaiki lewat bobot? |
|---|---|---|
| Hanya URL, tanpa isi halaman | `fixture-bca-verifikasi`, `fixture-promo-shopee`, `fixture-bansos-kemensos`, `synthetic-p0stindonesia` | Tidak. Layer 3 butuh `text`/`forms` |
| Form di iframe (tak terlihat snapshot) | `lphone-login` (nyata), `syn-find-my-iphone-hilang` | Tidak (C1: hanya same-origin dibaca) |
| Tanpa form / tanpa field sensitif (minta transfer, APK, WhatsApp, Telegram) | `syn-sicepat-apk`, `syn-loker-admin-online`, `syn-investasi-kripto-profit` | Tidak. Butuh sinyal baru (F-04-5) |
| Satu sinyal form saja di domain netral | `syn-anteraja-alamat` (card 20), `syn-telkomsel-poin` (otp 25), `syn-apple-pay-tagihan` (5 + card 20), `syn-tiki-nomor-resi` (5 + otp 25) | Hanya bila satu sinyal ambigu ≥ 45–50 sendirian, melanggar D-imelda-04, dan sama dengan form sah (checkout kartu, login OTP). Layer 4 yang dirancang untuk kasus ini |

**Kesimpulan:** 9 dari 13 = sinyal hilang, 4 dari 13 = satu sinyal yang memang sengaja dibuat ringan. Tidak ada skenario bobot yang wajar yang menaikkan scam ≥ 50 (lihat bagian 4).

### Salah blokir `trap-fintech-kyc-sah`
- Skor 85 = `asks_selfie_ktp` 35 + `asks_ktp` 25 + `asks_otp` 25, semuanya layer 3. Layer 2 = 0, kata = 0.
- Isinya identik dengan `syn-prakerja-gelombang` dan `syn-dukcapil-ktp-digital` (juga 85, sinyal sama persis). Bobot tidak bisa memisahkan dua halaman dengan sinyal yang sama.
- Uji "gabungkan `asks_ktp` ke `asks_selfie_ktp`" (seperti kartu+CVV di D-imelda-34): trap turun ke 60 (tidak diblokir lagi, tapi form tetap dicoret). Biayanya: scam ≥ 50 25 → 23, ≥ 80 10 → 6. **Ditolak.**
- Yang bisa memisahkan: umur domain (`new_domain`, tidak diukur di eval), brand resmi (allowlist), atau layer 4. Di D-imelda-37 layer 4 tidak menandai halaman sah mana pun (0/53). Tapi karena halaman ini lolos gerbang, `unreasonable_request` hanya bisa menaikkan skornya (D-imelda-06), tidak pernah menurunkan.

### Sinyal yang tidak pernah menyala, atau menyala di legit
- **Tidak pernah di eval:** `db_match` (eval tidak memuat `ShooLists`; bobotnya mutlak, bukan untuk disetel), `new_domain` (RDAP sengaja mati: domain scam tidak boleh dikirim ke registry), `unreasonable_request` (LLM mati di run ini), `asks_cvv` (selalu dibuang karena `asks_card` ikut menyala; tidak ada sampel CVV saja).
- **`urgent_language` tidak menyala di scam mana pun (0/38 tuning).** Hanya menyala sekali, di legit `trap-berita-waspada-penipuan` (tenang 8). Teks scam sintetis memakai variasi yang tidak ada di `URGENT_PHRASES` (`ai/src/layer3/content.js:10-16`), misalnya "Segera lakukan aktivasi ulang", "Selesaikan verifikasi sekarang" (daftar hanya punya "verifikasi sekarang juga"), "akan dibatasi", "hangus hari ini", "Lunasi sekarang", "Klaim sebelum pukul 24.00". Fixture kontrak `warning-41` memakai "klaim dalam 1 jam", yang juga tidak ada di daftar. Jadi bobot 15/8 saat ini tidak berpengaruh apa pun di eval. Menambah frasa = perubahan aturan, dan berisiko menghafal teks sintetis kita sendiri. Itu tugas terpisah, bukan C6.
- **Menyala di legit (semua < 30 kecuali KYC):** `brand_logo_offsite` tenang 12 (2 halaman), `urgent_language` tenang 8 (1), `asks_password` 15 (2), `asks_card` 20 (2), `cheap_tld` 5 (1), dan trio KYC. Bobot tenang (D-imelda-31) bekerja seperti yang dimaksud: halaman berita/blog tetap < 30.

### Layer 4: berapa yang biasanya ditambahkan (dari D-imelda-37/39, tanpa memanggil LLM)
- `unreasonable_request` selalu bernilai tetap **+30**, maksimal satu per halaman, hanya di halaman yang lolos gerbang.
- D-imelda-37 (timeout 4 s): 45 panggilan di set penuh, 21 flagged (47%), 21 timeout, 3 reasonable. Scam ≥ 50 31 → 38 (+7), ≥ 80 13 → 21 (+8). Legit: 0/53 sinyal layer 4.
- D-imelda-39 (timeout 6 s): 24/45 flagged (53%), 13 timeout. Scam ≥ 50 39/50, ≥ 80 21/50. Legit ditandai tetap 1/53.
- Jadi rata-rata layer 4 menambah ±+16 per halaman yang lolos gerbang (30 × ±53%), dan menaikkan ±8 scam di tiap ambang. Sisanya hilang karena penyedia lambat (29% timeout).
- **Batas atas** (skor ulang offline: setiap halaman tuning yang lolos gerbang dianggap flagged):

| Bobot layer 4 | Scam ≥ 50 | Scam ≥ 80 | Legit ≥ 30 | Legit ≥ 50 |
|---|---|---|---|---|
| tanpa layer 4 | 25/38 | 10/38 | 1 | 1 |
| 30 (sekarang) | 29/38 = 76% | 23/38 = 61% | 5 | 3 |
| 35 | 29/38 | 23/38 | 5 | 5 |
| 40 | 29/38 | 23/38 | 5 | 5 |

  Bahkan bila LLM sempurna, target 90%/70% tidak tercapai di set ini (sisa 9 scam tidak lolos gerbang). Menaikkan bobot di atas 30 **tidak menambah deteksi** di batas atas. Tapi bila LLM salah menandai salah satu dari 5 halaman sah yang lolos gerbang (`trap-sign-in-google-facebook` 15, `trap-portal-orang-tua-sekolah` 15, `trap-toko-kopi-kartu-native` 20, `trap-batik-card-checkout-en` 25, KYC), dengan 30 dua di antaranya mencapai ≥ 50 (form dicoret), dengan 35 empat. **Bobot 30 sudah tepat.**

## 4. Usulan dan efek simulasi

Semua angka: skor ulang offline dari sinyal `run.mjs --json` (77 sampel tuning: 38 scam, 39 legit), dengan aturan tenang/penuh dan gerbang yang sama dengan kode. Pemeriksaan: skor ulang dengan bobot sekarang = skor terekam di 77/77 sampel. Holdout tidak dipakai untuk memilih (D-imelda-21), dan memang tidak bersih lagi (fase-07, review #60).

| # | Usulan | Scam ≥ 30 | Scam ≥ 50 | Scam ≥ 80 | Legit ≥ 30 | Halaman yang berubah kelas | Penilaian |
|---|---|---|---|---|---|---|---|
| S0 | **Tanpa perubahan** | 27/38 | 25/38 | 10/38 | 1/39 | – | **Direkomendasikan untuk sekarang** |
| S1 | `brand_logo_offsite` penuh 25 → 30 (tenang tetap 12) | 27 | 25 | **12** | 1 | `syn-dana-kaget-bonus`, `syn-bukalapak-voucher` 79 → 84 | Layak bila mau bergerak. Tanpa risiko di set ini: legit hanya punya logo tenang. Risiko nyata: toko kecil yang menampilkan logo bank **dan** punya form sensitif (`trap-toko-logo-bank-checkout` ada di holdout) |
| S2 | `asks_password` 15 → 20 | 27 | 25 | 10 | 1 | – (legit login 15 → 20, masih < 30) | Tidak berguna sendirian |
| S3 | `asks_otp` 25 → 30 (membatalkan D-imelda-30) | 28 | 25 | 12 | 1 | dana/bukalapak → 84; `syn-telkomsel-poin` 25 → 30 | Tidak disarankan: OTP saja = popup di situs tak dikenal mana pun yang login dengan OTP (alasan D-imelda-04/30) |
| S4 | `asks_card` 20 → 25 (membatalkan sebagian D-imelda-34) | 28 | 25 | 10 | **2** | `trap-batik-card-checkout-en` 25 → 30 (salah popup baru) | **Ditolak** |
| S5 | `asks_pin` 35 → 40 | 27 | 25 | 10 | 1 | – | Tidak berguna |
| S6 | `urgent_language` penuh 15 → 20 | 27 | 25 | 10 | 1 | – (tidak menyala di scam) | Tidak berguna sampai cakupan frasa diperbaiki |
| S7 | `asks_ktp` digabung ke `asks_selfie_ktp` | 27 | **23** | **6** | 1 (KYC 85 → 60, tidak diblokir) | 6 scam KYC turun 25 poin | **Ditolak** |
| S8 | S1 + S2 | 27 | 25 | 12 | 1 | sama dengan S1; shopeepay/pajak 69 → 79 | Tidak lebih baik dari S1 |
| T1 | Ambang blokir 80 → 70 (lead, kontrak) | 27 | 25 | **15** | 1 | +jne 70, lazada 70, bpjs 74, dana/bukalapak 79 | Lihat catatan ambang |
| T2 | Ambang blokir 80 → 75 (lead, kontrak) | 27 | 25 | 12 | 1 | dana/bukalapak 79 | Sama dengan S1, tanpa ubah bobot |
| T3 | Ambang popup kedua 50 → 45 | 27 | 25 | 10 | 1 | – (rentang 45–49 kosong) | Tidak berguna |
| T4 | S1 + S2 + blokir 75 | 27 | 25 | **17** | 1 | T2 + shopeepay/pajak/jne/lazada/bpjs | Paling banyak ≥ 80 tanpa salah blokir baru di set ini |

Catatan ambang (milik lead):
- Mengubah 80 berarti mengubah `ios/ShooExtension/Resources/pipeline.js:6`, `contracts/README.md` (tabel Thresholds), dan deskripsi `status` di `contracts/scan-result.schema.json` (Activity milik Alief membaca `blocked`). Layar blokir tidak bisa dilewati, jadi menurunkan ambangnya menaikkan biaya setiap salah skor di situs sah.
- Di set ini legit tertinggi selain KYC = 25, jadi 70/75 tidak menambah salah blokir. Tapi halaman sah nyata dengan form login/checkout masih sedikit (README eval, "Known limits": hanya `bank-login-klikbca` yang punya field password). Jarak legit yang lebar itu belum terbukti untuk halaman nyata.
- Layer 4 sudah menutup sebagian celah 50–79: di batas atas, semua 13 halaman form 50–79 di tuning naik ke ≥ 80 bila flagged. Dengan layer 4 hidup, manfaat T1/T2 lebih kecil dari tabel di atas.
- Ambang 30 dan 50 tidak perlu disentuh: rentang 30–49 hampir kosong di kedua kelas.

### Rekomendasi untuk Umar
1. **Bobot layer 3–4 tidak diubah sekarang (S0).** Masalah utama (≥ 50 di 66%) adalah sinyal yang hilang, bukan bobot. Setiap kenaikan yang membantu ≥ 50 akan membuat satu sinyal form ambigu mencapai ambang sendirian.
2. **Bila ingin menaikkan ≥ 80 sebelum ada data nyata**, pilih satu saja: S1 (`brand_logo_offsite` penuh 30, keputusan Team AI = Umar) atau T2 (blokir 75, keputusan lead + perubahan kontrak). Efek di tuning sama (+2), dan keduanya tidak membuat salah blokir baru. S1 lebih sempit (hanya halaman yang menyamar brand dan meminta data). T1/T4 memberi lebih banyak (+5/+7), tapi bergantung pada sampel sintetis.
3. **Layer 4 tetap 30.**
4. **Yang benar-benar menggerakkan target (di luar C6):** data scam nyata berlisensi (A4, #73) lalu kalibrasi ulang M6 dengan holdout baru; cakupan frasa `urgent_language` (diuji di sampel nyata, bukan sintetis kita); sinyal untuk scam tanpa form (minta transfer, APK, WhatsApp/Telegram; F-04-5); iframe cross-origin (C1, Fase 2); dan `new_domain` yang hanya terlihat di produksi.
5. Fixture kontrak (`blocked-92`, `blocked-marked-safe`, `warning-41`, `warning-63`) memakai bobot lama/karangan, termasuk `unreasonable_request` 22. Bila ingin diselaraskan, itu PR kontrak (lead). Tidak memblokir apa pun.

## Batasan laporan ini
- 49 dari 50 scam sintetis. Holdout 12 scam juga sintetis semua. Tidak ada angka di sini yang boleh dipakai untuk klaim target mandat (D-imelda-22).
- `new_domain` tidak diukur. Di produksi, domain scam baru (< 7 hari) mendapat +30, yang bisa mengangkat banyak halaman 50–79 ke ≥ 80, tapi juga KYC sah bila domainnya baru.
- Efek layer 4 diambil dari D-imelda-37/39 (set penuh, sekali run, penyedia lambat), bukan diukur ulang di sini.
- Simulasi hanya mengganti bobot dari sinyal yang terekam. Perubahan aturan (frasa baru, gerbang, sinyal baru) tidak bisa disimulasikan dengan cara ini.

## Verifikasi
- `GET /_dev/layer4` = `{"off":true}` sebelum dan sesudah kedua run. Tidak ada panggilan LLM, RDAP, atau registry. Tidak ada URL scam yang dibuka.
- `ai/.env` tidak ada di worktree dan tidak dibaca. Tidak ada `wrangler`/deploy.
- Hanya `plan/imelda/` yang berubah (`log/c6-weight-review.md`, `TODO.md`).
