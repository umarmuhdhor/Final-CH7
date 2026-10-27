# Testing 01: layer 2 v2 sebagai tambahan input layer 4

> Tanggal: 27 oct 2026, 09.01 · folder `27-oct-2026/01-testing-09.01` · branch `docs/AI-llm-latency-testing` @ `b0e0bca` · runner `tools/run-l2-compare.mjs`
> Visualisasi: `conclusions.html` · data mentah: `results.json` · request/jawaban: `llm-response.md`

## 1. Setelan

| Item | Nilai |
|---|---|
| Penyedia / model | `bandelbanget.xyz` / `deepseek-v4-flash`, `deepseek-v4.1-flash`, `deepseek-v4-flash-0731` |
| Thinking | **off** (`chat_template_kwargs: {thinking: false}`) di semua panggilan |
| Arm "tanpa L2" | input dan prompt produksi (`reality-check.v3`) |
| Arm "dengan L2 v2" | input + `link: {score, hints}` dari prototipe `dissect2.mjs` + satu paragraf tambahan di prompt (eksperimen, tidak ada perubahan di `ai/src`) |
| Batas / parameter | 6000 ms per panggilan, `temperature` 0, `max_tokens` 200, `json_object`; "flagged" = aturan `reality.js` (tidak wajar, confidence ≥ 0.6, ada `asks`) |
| Gerbang LLM | **dilewati**: semua sampel dinilai (produksi memanggil LLM hanya bila skor layer 3 ≥ 15) |
| Run | 4 putaran × 17 sampel × 6 konfigurasi |
| Catatan | L2 v2 + compare model, thinking off |

Paragraf tambahan di prompt (arm "dengan L2 v2") ada di `llm-response.md`. Hanya nama pemeriksaan (`hints`) dari daftar tetap yang dikirim, bukan teks URL.

## 2. Sampel

| Jenis | id | skor layer 3 | skor L2 v2 | hints |
|---|---|---|---|---|
| scam-real | `07-testing-15.58` | 15 | 18 | path-ext, freehost, free-path |
| scam-real | `08-testing-16.06` | 40 | 24 | freehost, free-label, free-number |
| scam-syn | `syn-linkaja-hadiah` | 35 | 0 | - |
| scam-syn | `syn-anteraja-alamat` | 20 | 0 | - |
| scam-syn | `syn-tiki-nomor-resi` | 25 | 6 | tld |
| scam-syn | `syn-telkomsel-poin` | 25 | 0 | - |
| scam-syn | `syn-etilang-denda` | 20 | 0 | - |
| scam-syn | `syn-apple-pay-tagihan` | 20 | 6 | tld |
| legit-trap | `trap-toko-logo-bank-checkout` | 20 | 0 | - |
| legit-trap | `trap-blog-cek-saldo-bca` | 12 | 24 | path-ext, path-bait, freehost, free-path |
| legit-trap | `trap-github-pages-dokumentasi` | 15 | 19 | path-bait, freehost, free-path |
| legit-trap | `trap-sign-in-google-facebook` | 15 | 6 | path-bait |
| legit-trap | `trap-fintech-kyc-sah` | 85 | 6 | path-bait |
| legit-trap | `trap-portal-orang-tua-sekolah` | 15 | 0 | - |
| legit-trap | `trap-asuransi-klaim-resmi` | 25 | 6 | path-bait |
| legit-trap | `trap-toko-kopi-kartu-native` | 20 | 0 | - |
| legit-trap | `trap-batik-card-checkout-en` | 20 | 6 | tld |

## 3. Hasil per konfigurasi

| Konfigurasi | scam nyata flagged | scam sintetis flagged | **false positive (sah)** | timeout | bad_schema | http_error | selesai: median |
|---|---|---|---|---|---|---|---|
| deepseek-v4-flash · tanpa L2 | 6/8 | 18/24 | **0/36** | 12 | 1 | 0 | 1,82 s |
| deepseek-v4-flash · dengan L2 v2 | 7/8 | 23/24 | **3/36** | 6 | 2 | 0 | 1,73 s |
| deepseek-v4.1-flash · tanpa L2 | 6/8 | 18/24 | **4/36** | 11 | 1 | 0 | 1,66 s |
| deepseek-v4.1-flash · dengan L2 v2 | 5/8 | 19/24 | **5/36** | 10 | 2 | 0 | 1,55 s |
| deepseek-v4-flash-0731 · tanpa L2 | 5/8 | 20/24 | **2/36** | 8 | 1 | 0 | 1,54 s |
| deepseek-v4-flash-0731 · dengan L2 v2 | 6/8 | 18/24 | **4/36** | 13 | 3 | 0 | 1,54 s |

## 4. Per sampel (flagged/timeout, tiap kolom satu konfigurasi)

| Jenis | id | v4-flash – | v4-flash +L2 | v4.1-flash – | v4.1-flash +L2 | v4-flash-0731 – | v4-flash-0731 +L2 |
|---|---|---|---|---|---|---|---|
| scam-real | `07-testing-15.58` | 2/1 | 3/0 | 2/1 | 3/1 | 1/1 | 3/0 |
| scam-real | `08-testing-16.06` | 4/0 | 4/0 | 4/0 | 2/2 | 4/0 | 3/1 |
| scam-syn | `syn-linkaja-hadiah` | 3/1 | 4/0 | 2/2 | 3/1 | 4/0 | 2/2 |
| scam-syn | `syn-anteraja-alamat` | 4/0 | 4/0 | 4/0 | 2/2 | 3/1 | 3/1 |
| scam-syn | `syn-tiki-nomor-resi` | 4/0 | 4/0 | 3/1 | 4/0 | 4/0 | 4/0 |
| scam-syn | `syn-telkomsel-poin` | 3/1 | 4/0 | 3/1 | 3/1 | 3/1 | 4/0 |
| scam-syn | `syn-etilang-denda` | 2/2 | 4/0 | 4/0 | 3/0 | 2/2 | 2/2 |
| scam-syn | `syn-apple-pay-tagihan` | 2/2 | 3/1 | 2/2 | 4/0 | 4/0 | 3/1 |
| legit-trap | `trap-toko-logo-bank-checkout` | 0/0 | 0/0 | 0/1 | 0/3 | 0/1 | 0/0 |
| legit-trap | `trap-blog-cek-saldo-bca` | 0/0 | 0/1 | 0/0 | 0/0 | 0/0 | 0/1 |
| legit-trap | `trap-github-pages-dokumentasi` | 0/0 | 0/1 | 0/0 | 2/0 | 0/0 | 0/1 |
| legit-trap | `trap-sign-in-google-facebook` | 0/2 | 0/0 | 0/1 | 0/0 | 0/1 | 0/0 |
| legit-trap | `trap-fintech-kyc-sah` | 0/0 | 3/0 | 3/0 | 3/0 | 2/0 | 2/1 |
| legit-trap | `trap-portal-orang-tua-sekolah` | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/2 |
| legit-trap | `trap-asuransi-klaim-resmi` | 0/2 | 0/1 | 1/0 | 0/0 | 0/1 | 2/0 |
| legit-trap | `trap-toko-kopi-kartu-native` | 0/0 | 0/1 | 0/1 | 0/0 | 0/0 | 0/0 |
| legit-trap | `trap-batik-card-checkout-en` | 0/1 | 0/1 | 0/1 | 0/0 | 0/0 | 0/1 |

## 5. Kesimpulan otomatis

- deepseek-v4-flash: scam nyata flagged 6/8 → 7/8; scam sintetis 18/24 → 23/24; **false positive pada halaman sah 0/36 → 3/36**; timeout 12/68 → 6/68 (tanpa L2 → dengan L2 v2).
- deepseek-v4.1-flash: scam nyata flagged 6/8 → 5/8; scam sintetis 18/24 → 19/24; **false positive pada halaman sah 4/36 → 5/36**; timeout 11/68 → 10/68 (tanpa L2 → dengan L2 v2).
- deepseek-v4-flash-0731: scam nyata flagged 5/8 → 6/8; scam sintetis 20/24 → 18/24; **false positive pada halaman sah 2/36 → 4/36**; timeout 8/68 → 13/68 (tanpa L2 → dengan L2 v2).
- n kecil (4 putaran), 2 scam nyata dan 9 halaman sah; scam sintetis berurl buatan. Selisih satu dua run bukan bukti, dan timeout membuat banyak run tidak punya jawaban.

## 6. Analisis (ditulis Claude setelah membaca `results.json`)

**Cara membaca angka.** Tabel bagian 3 dan grafik HTML menghitung timeout sebagai "tidak ditandai", dan timeout acak berubah antar-konfigurasi (mis. `deepseek-v4-flash` 12 → 6). Itu menyamarkan efek L2. Di bawah ini saya hitung hanya dari run yang **selesai** (flagged atau reasonable), digabung ketiga model.

| | scam nyata | scam sintetis | halaman sah ditandai (false positive) | sah, tanpa `trap-fintech-kyc-sah` | timeout |
|---|---|---|---|---|---|
| tanpa L2 | 17/19 | 56/56 | **6/95 (6%)** | 1/83 | 31/204 |
| dengan L2 v2 | 18/18 | 60/61 | **12/89 (13%)** | 4/78 | 29/204 |

**1. L2 v2 membantu sedikit di scam nyata, dan harganya false positive naik.**
- Scam nyata: 2 yang lolos tanpa L2 (keduanya DHL, satu `reasonable: true`, satu `reasonable: false` dengan confidence 0,55 < 0,6) jadi 0 yang lolos dengan L2. DHL: flagged 2/2/1 → 3/3/3 per model. Ini pola yang diharapkan: petunjuk `path-ext, freehost, free-path` (skor 18) memberi LLM alasan untuk curiga.
- False positive naik dari 6% ke 13%. Selisih ini belum meyakinkan (6 vs 12 kejadian, 2 sampel scam nyata saja), tetapi arahnya konsisten di ketiga model (0→3, 4→5, 2→4).
- Scam sintetis sudah penuh (56/56) tanpa L2, jadi tidak ada ruang untuk membaik. URL sintetisnya buatan; skor L2 v2 di 4 dari 6 sampel itu 0.

**2. Dari mana false positive baru?** Bukan semuanya akibat URL.
- `trap-github-pages-dokumentasi`: 0 → 2 (keduanya `deepseek-v4.1-flash` dengan L2). Ini **akibat langsung L2**: skor L2 19 (`freehost`, `path-bait`, `free-path`) pada panduan login yang sah. Persis false positive yang diperingatkan PROPOSAL.md.
- `trap-fintech-kyc-sah`: 5 → 8. Skor L2-nya hanya 6, jadi L2 bukan penyebab utama; halaman itu meminta KYC selfie + KTP + OTP, dan semua model menandainya di kedua arm (confidence 0,6–0,85). Itu memang tampak seperti scam di level form. Layer 3 sendiri memberi skor 85 untuk halaman itu, jadi produksi tetap menandainya walau LLM diam.
- `trap-asuransi-klaim-resmi`: 1 → 2. Skor L2 hanya 6; sebagian besar kemungkinan variasi acak model.

**3. Perbandingan model tidak lagi bisa dipisahkan.** Semalam `deepseek-v4.1-flash` unggul tipis. Pagi ini (hanya yang selesai, tanpa L2): `deepseek-v4-flash` scam nyata 6/6, sintetis 18/18, false positive 0/31; `deepseek-v4.1-flash` 6/7, 18/18, 4/31; `deepseek-v4-flash-0731` 5/6, 20/20, 2/33. Urutannya terbalik dari semalam. Kesimpulan jujur: dua model pertama setara, `-0731` sedikit lebih lemah di scam nyata, dan selisihnya masih di dalam kebisingan.

**4. Timeout jauh lebih rendah daripada semalam.** Gabungan 15% (31 dan 29 dari 204) vs 50–55% semalam, di batas 6 s dan thinking off yang sama. Median selesai 1,5–1,8 s. Jadi keterlambatan semalam memang sebagian berasal dari penyedia pada jam itu, bukan murni dari model.

**5. Rekomendasi.**
- Jangan kirim skor L2 v2 ke LLM dulu. Keuntungannya (DHL, 2 sampel) kecil dan belum kokoh, sedangkan false positive naik di arah yang bisa diduga (hosting gratis + kata umum). Bobot v2 juga belum dikalibrasi.
- Kalau DHL tetap jadi masalah, perbaikan yang lebih terarah dan murah: tambahkan DHL dan kurir lain ke daftar brand (`brands.json` / detektor), sehingga LLM mendapat `brands` untuk halaman itu tanpa mengirim sinyal URL ke LLM.
- Layer 3 (skor 85 untuk KYC fintech) tetap menjadi pengaman terakhir untuk false positive LLM di halaman form-berat.

**6. Belum terbukti.**
- Hanya 2 scam nyata dan 9 halaman sah (satu halaman, `trap-fintech-kyc-sah`, ambigu menurut desainnya). 4 putaran per sampel.
- Satu pagi, penyedia sedang cepat. Hasil bisa berbeda saat beban tinggi.
- Paragraf tambahan di prompt dan petunjuk L2 diuji bersama, jadi efek dua hal itu tidak terpisah.
- Tidak ada pengujian thinking default di run ini (semua thinking off).

## 7. Batasan

- Prototipe L2 v2 belum dikalibrasi: kata umpan dan daftar hosting gratis ditulis setelah melihat sebagian sampel (lihat `06-testing-14.57/PROPOSAL.md`). Skor sampel nyata di sini bukan ukuran akurasi.
- Scam sintetis punya URL buatan; hanya 2 scam nyata. Satu malam, satu mesin, penyedia berubah menurut beban.
- Layer 1 dan RDAP tidak ikut. Tidak ada perubahan kode produksi.
