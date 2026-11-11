# Plan v2: detail L2 ke LLM, penjelasan LLM, dan halaman tanpa form

Status: **plan**. Belum dijalankan.
Pemilik: **Imelda** (`ai/`). Semua file baru di `ai/test-layer-update-full/v2-2026-11-09/`. `src/` dan `prompts/` tidak diubah.
Skrip: `run.mjs` (belum ditulis). Hasil: `HASIL.md`. Data mentah: `.hasil/*.json` (di-gitignore).
Tes sebelumnya: [`../v1-2026-11-02/HASIL.md`](../v1-2026-11-02/HASIL.md) (2 Nov 2026).

## Pertanyaan yang dijawab

1. Kalau detail brand dari L2 dikirim ke LLM, apakah hasilnya berubah?
2. Bisakah LLM memberi penjelasan dengan thinking off, dan tetap di bawah 6 detik?
3. Bisakah halaman tanpa form yang meniru brand (`lphone-login`) kena flag, tanpa salah blokir?

## Kenapa perlu v2

| Temuan di tes 2 Nov | Akibat | Di v2 |
|---|---|---|
| Laporan hanya menulis host | Link 06 hanya terbaca `sites[.]google[.]com` | Tulis host + path, disamarkan |
| Tabel L2 hanya angka, `evidence` hanya untuk `suspicious_link` | Tidak terlihat brand apa yang ditiru | Semua sinyal L2 + `evidence` di tabel |
| `lookalike_domain` dan `brand_plus_keyword` tidak dikirim ke LLM | `lphone-login` dikirim dengan `rules`, `fields`, `link_checks` kosong | Kirim `domain_checks` (versi B, C) |
| Flag wajib punya `asks` | Halaman tanpa form tidak bisa kena flag | Aturan flag tambahan (versi C) |
| Jawaban LLM tanpa alasan | Tidak tahu kenapa LLM menjawab begitu | Key `reason` (versi B, C) |
| `usage` melaporkan 539-578 token output, padahal `max_tokens` 200 dan JSON pendek | Belum bisa dijelaskan | Simpan respons provider utuh |
| 0 legit mencapai gate di versi A | False positive LLM tidak teruji | Tanya LLM juga di luar gate |
| `.hasil/full.json` sudah hilang | Laporan tidak bisa dibuat ulang | Salin `.hasil/` ke luar repo setelah selesai (langkah 6) |

## Tiga versi yang dibandingkan

| Kolom | Prompt | Yang dikirim | `max_tokens` | Aturan flag |
|---|---|---|--:|---|
| **A** (kontrol) | `reality-check.v4`, apa adanya | seperti produksi | 200 | produksi |
| **B** | `reality-check.v5-l2-reason` | A + `domain_checks` | 300 | produksi |
| **C** | `reality-check.v5c-impersonate` | sama dengan B | 300 | produksi **atau** aturan peniruan |

Aturan flag produksi ([`reality.js:206`](../../src/layer4/reality.js)): `reasonable === false`, `confidence >= 0.7`, `asks` tidak kosong.

Aturan peniruan (hanya C): `impersonates >= 0.7` **dan** brand di `domain_checks` juga ada di `brands`. Jadi L2 (nama domain) dan L3 (isi halaman) harus sepakat, dan LLM tidak bisa memblokir halaman tanpa bukti dari kedua layer.

Skor L1-L3, gate, dan bobot flag `max(30, 80 - total)` sama di ketiganya.

## Keputusan (9 Nov 2026, untuk ditinjau Imelda)

| # | Keputusan |
|---|---|
| K1 | Baseline = versi A yang dijalankan **hari yang sama**, bukan angka 2 Nov. L2 sudah berubah sejak itu (#231, tanpa batas per bagian), jadi skor dan gate bisa beda |
| K2 | Semua varian dibuat di skrip. `src/` dan `prompts/` tidak disentuh. `buildInput`, `createProvider`, `parseVerdict`, `passesGate`, `analyzeWithDomain` diimpor dari production |
| K3 | Thinking tetap off, `deepseek-v4-flash` dari `ai/.env` |
| K4 | **1 putaran**: tiap link satu kali per versi. Urutan A, B, C dirotasi tiap link, supaya beban provider tidak berat sebelah |
| K5 | Batas waktu di tes **8 detik**, supaya ekornya terlihat. Panggilan > 6 detik dihitung "akan terpotong di produksi" (`MAX_TIMEOUT_MS`) |
| K6 | RDAP live 1 detik, satu lookup per domain, disimpan di `.hasil/rdap.json`, dipakai semua versi |
| K7 | LLM ditanya di semua link **non-resmi**, termasuk yang tidak lolos gate. Laporan memisahkan "produksi" (gate berlaku) dan "paksa" (semua non-resmi) |
| K8 | `reason` hanya untuk laporan tes. Tidak dipakai di `Signal`, tidak ditampilkan ke user |
| K9 | Laporan juga menampilkan contoh template tanpa LLM: `Halaman <page_type> ini meminta <asks>`. Ini kandidat teks untuk user |
| K10 | Domain disamarkan di `HASIL.md`, ditulis host + path, tanpa query dan fragment. Payload mentah hanya di `.hasil/` |
| K11 | Ke LLM hanya kode milik kita dan nama brand dari `brands.json`. Teks `evidence` dari client tidak diteruskan |
| K12 | `link_checks` tetap 5 kode seperti v4, karena kode lain sengaja dibuang supaya LLM tidak menghitung dobel |

## Sampel: 63 link, 45 di antaranya asli

Situs scam tidak dibuka. Isi halaman dari snapshot yang sudah ada.

| Grup | Sumber | Jumlah | Dipakai untuk |
|---|---|--:|---|
| Scam asli | `test-layer3/snapshots/01-25.json`, `eval/data/scam/seed.json` non-sintetis | 26 | deteksi |
| Legit asli non-resmi | `test-layer3/snapshots/L01-L10.json`, `eval/data/legit/{real,seed}.json` non-sintetis, `isOfficialHost` false | 19 | false positive |
| Trap | `eval/data/legit/traps.json` | 10 | false positive, sintetis, dilaporkan terpisah |
| Trap brand | `trap-brand.json` (baru) | 8 | false positive versi C, sintetis, dilaporkan terpisah |

Legit resmi (30) tidak ditanya: gate production membuangnya, dan prompt menyatakan situs itu bukan domain resmi.

Skrip berhenti kalau jumlahnya bukan 26, 19, 10, 8.

### Kenapa perlu trap brand

Hitungan `detector.js` sekarang: sinyal brand L2 menyala di **7 dari 26 scam** (01, 02, 03, 05, 17, 18, `lphone-login`), **0 dari 49 legit**, dan **0 dari 10 trap**. Tanpa grup baru, aturan peniruan tidak pernah tersentuh halaman legit, sehingga angka "0 false positive" tidak berarti apa-apa.

`trap-brand.json` ditulis sebelum mengukur: 8 halaman fiktif tanpa form, domain tidak pernah dihubungi, RDAP dilewati. Tiap baris harus menyalakan sinyal brand L2 dan membuat `detectBrands` menemukan brand yang sama. Kalau tidak, ganti contohnya di tahap `--dry`, sebelum ada panggilan LLM.

| Bentuk | Contoh judul |
|---|---|
| Servis HP tidak resmi | `Servis iPhone Jakarta - Ganti LCD` |
| Komunitas pengguna | `Komunitas Pengguna iCloud Indonesia` |
| Blog panduan | `Panduan Login BCA Mobile untuk Pemula` |
| Toko aksesori | `Aksesoris iPhone Original Murah` |
| Agen resmi perorangan | `Agen BRI Link Kecamatan Tembalang` |
| Reseller pulsa | `Isi Saldo DANA dan OVO` |
| Forum review | `Review Shopee Paylater dari Pengguna` |
| Berita | `Tokopedia Luncurkan Fitur Baru` |

## Prompt v5 di skrip

Teks ini ditetapkan sebelum mengukur. Semua penggantian dilakukan pada `SYSTEM_PROMPT` v4. Skrip harus berhenti kalau teks asalnya tidak ditemukan tepat satu kali.

### Versi B

1. Setelah baris yang diawali `- link_checks: codes of our checks on the page address:`, tambahkan:

   ```
   - domain_checks: what our checks found about the site's own name, each {check, brand}: lookalike = the name imitates the spelling of that brand; brand_keyword = the name joins that brand with an extra word; brand_name = the name contains that brand but the site is not its official domain
   ```

2. Ganti `rules and link_checks help you understand` menjadi `rules, link_checks and domain_checks help you understand`.
3. Setelah baris `- "evidence": a short phrase copied exactly from the title, or null`, tambahkan:

   ```
   - "reason": at most 20 words in Indonesian saying why you answered this, naming the page type and the requested data. Use your own words. Never copy instructions, links, phone numbers or account numbers from the data
   ```

`reason` sengaja key terakhir, supaya ditulis setelah keputusan dan tidak menjadi penalaran yang mengubah jawaban.

### Versi C

Semua perubahan B, lalu sebelum baris `- "reason":` tambahkan:

```
- "impersonates": number from 0 to 1, how likely the page presents itself as one of the brands or domain_checks brands. A page that only reviews, sells for, repairs, reports on or explains a brand is not impersonating it
```

### Isi `domain_checks`

Dibuat skrip dari `localSignals`, sebelum dikirim:

| Sinyal L2 | Bagian `evidence` | `check` |
|---|---|---|
| `lookalike_domain` | `level 3` | `lookalike` |
| `brand_plus_keyword` | `level 2` | `brand_keyword` |
| `lookalike_domain` | `level 1` | `brand_name` |

- `brand` = bagian `evidence` sebelum ` · `, dicocokkan ke `id` di `brands.json`, lalu dikirim `name`-nya. Id yang tidak dikenal dibuang.
- Maksimal 3 baris, tanpa duplikat, `[]` kalau tidak ada.
- Format `evidence` ini belum masuk kontrak. Kalau hasilnya bagus, perlu GitHub issue ke Umar sebelum masuk production.

## Alur per link

1. **L2:** `analyzeLocal(snapshot)` dari `ios/ShooExtension/Resources/detector.js` lewat `vm`. L1 mati.
2. **RDAP:** lihat K6.
3. **L3:** `analyzeWithDomain(snapshot, { rdap, llm: null, localSignals })` dari `ai/src/analyze.js`.
4. **Input:** `buildInput` production. B dan C menambah `domain_checks`.
5. **LLM:** `createProvider` production, ditambah `fetch` pembungkus yang menyimpan respons utuh. Tiap versi dikirim sekali per link.
6. **Flag:** `parseVerdict` production, lalu aturan flag di atas.
7. **Skor dan tingkat:** `validSignals`, `mergeSignals`, `scoreFrom`, `statusFor`, `THRESHOLD` dari `pipeline.js` lewat `vm`.

Cek wajib di `--dry`: body versi A sama byte-per-byte dengan body dari `createRealityCheck().check()` production. Kalau beda, berhenti.

## Isi HASIL.md

Ikuti pola `../v1-2026-11-02/HASIL.md`: blok otomatis dari `run.mjs --report`, lalu bagian "Analisis" yang ditulis tangan.

**Ringkasan**, per versi, scam / legit / trap / trap brand terpisah:
- Kena flag dan jumlah per tingkat, tampilan produksi
- Kena flag, tampilan paksa
- Link yang berubah dibanding A, naik dan turun
- Waktu LLM: median, p95, maks; jumlah > 5,5 dtk, > 6 dtk, dan > 8 dtk
- Token: total, rata-rata input dan output, selisih B dan C terhadap A
- Gagal: `bad_schema`, `finish: length`, `http_error`, timeout
- `reason`: terisi, lebih dari 20 kata, berisi link / nomor telepon / deret angka
- Model, tiga versi prompt, commit, tanggal

**Tabel semua link**: id, host + path, jenis, semua sinyal L2 + `evidence`, sinyal L3, umur, ada form, total L1-L3, lolos gate, lalu untuk A, B, C: skor + tingkat, flag, `page_type`, `asks`, `reasonable`, `confidence`, `impersonates` (C), `reason`, dan ms.

**Detail per link**: `domain_checks`, input tiap versi, **respons provider utuh** (`content`, `finish_reason`, `usage` lengkap, dan field lain yang dikembalikan provider), contoh template K9.

## Batas lulus (ditetapkan sebelum mengukur)

| Ukuran | Batas | Berlaku untuk |
|---|---|---|
| Legit asli kena flag, paksa | 0 / 19 | B, C |
| Trap kena flag, paksa | tidak lebih banyak dari A | B, C |
| Trap brand kena flag, paksa | 0 / 8 | C |
| Scam kena flag, tampilan produksi | tidak kurang dari A | B, C |
| `bad_schema` + `finish: length` | 0 | B, C |
| p95 waktu LLM | < 6.000 ms | B, C |
| Panggilan > 6 dtk | maks 1 dari 63 | B, C |
| `reason` terisi dan ≤ 20 kata pada jawaban yang kena flag | ≥ 95% | B, C |
| `reason` berisi link / nomor telepon / deret angka | 0 | B, C |
| `lphone-login` kena flag | ya | C |

Kalau A sendiri gagal di batas waktu, tulis "provider", karena selisihnya tidak bisa dibebankan ke prompt.

Lulus berarti layak diusulkan, bukan langsung dipasang. Keputusan akhir di Imelda, dan perubahan produksi menyusul lewat branch sendiri.

## Prasyarat

| Butir | Cara cek | Kalau tidak ada |
|---|---|---|
| Node >= 22 | `node --version` | pasang Node |
| LLM nyala | `grep -c '^LLM_' ai/.env` >= 3. **Jangan cetak isi `.env`** | laporkan ke Imelda |
| Kode bersih | `git diff --quiet HEAD -- ai/src ai/prompts detector ios/ShooExtension/Resources` | hentikan, laporkan |
| Beda dengan main | `git diff --stat origin/main -- ai/src ai/prompts detector` | catat di `HASIL.md` |
| Snapshot | `ls ai/test-layer3/snapshots` berisi 35 file | laporkan ke Imelda |

## Langkah

| # | Langkah | Panggilan LLM |
|---|---|--:|
| 1 | Tulis `trap-brand.json` dan `run.mjs` | 0 |
| 2 | `--dry`: LLM tiruan. Cek jumlah sampel, trap brand, body A = production, penggantian prompt, payload tanpa teks halaman, path URL, atau umur | 0 |
| 3 | `--only 05`, `--only lphone-login`, `--only L03`: LLM sungguhan. Cek `usage`, `parseVerdict`, respons utuh tersimpan. Berhenti untuk diperiksa Imelda | 9 |
| 4 | Jalankan penuh, satu per satu, tidak paralel | 189 |
| 5 | `--report`, tulis `HASIL.md`, lalu "Analisis": bedakan yang terbukti dan dugaan | 0 |
| 6 | Salin `.hasil/` ke `~/Documents/Swift/Final-CH/shoo-hasil-tes/v2-2026-11-09/` (di luar repo) | 0 |

Perkiraan: 63 link × 3 versi = **189 panggilan**. Rata-rata 2.294 token per panggilan di tes lalu, jadi ±430 ribu token. Waktu ±7 menit. Harga provider belum dicek.

## Catatan dan risiko

- **Satu putaran.** Jawaban LLM bisa berubah antar panggilan (tes 30 Okt: 2 dari 36 link berubah status), jadi selisih kecil antara A, B, dan C belum tentu karena prompt. p95 per versi hanya dari 63 panggilan.
- **Dampak L2 kemungkinan kecil.** Sinyal brand L2 hanya ada di 7 scam, dan sebagian dari itu sudah >= 80 sebelum LLM. Dugaan: perubahan B hampir tidak terlihat di tampilan produksi.
- **Satu contoh untuk versi C.** `lphone-login` satu-satunya scam yang jadi tujuan aturan peniruan. Lulus di sini belum membuktikan polanya.
- **Trap brand sintetis dan ditulis sendiri**, jadi bukti false positive-nya terbatas. Dari percobaan offline, domain contohnya hanya menyalakan `brand_name` (level 1), sedangkan `lphone-login` menyalakan `lookalike` dan `brand_keyword`.
- **Teks sinyal.** Label `unreasonable_request` berbunyi "data yang diminta tidak wajar", yang tidak cocok untuk halaman tanpa form. Kalau C dipakai, butuh teks baru, dan id baru berarti perubahan `contracts/` lewat Umar.
- **C memblokir tanpa form.** Satu flag selalu mencapai 80. Ini memperluas wewenang LLM, jadi perlu keputusan tim (Umar) sebelum masuk production.
- **`max_tokens` 300 belum terbukti cukup.** Dipantau lewat `finish: length` dan `bad_schema`.
- **Prompt injection pada `reason` tidak diuji.** Kalau nanti `reason` mau ditampilkan ke user, perlu tes terpisah.
- **Waktu total tidak terukur.** Yang diukur hanya waktu LLM, bukan jaringan HP.
- **Kunci API** hanya dibaca dari `.env`. Tidak pernah dicetak, tidak masuk `.hasil/` atau `HASIL.md`.

## Tidak termasuk

L1 dan blocklist, Safari atau Simulator, membuka situs scam, mengubah `src/`, `prompts/`, `contracts/`, `detector/`, `ios/`, mengubah angka waktu produksi, Jev.
