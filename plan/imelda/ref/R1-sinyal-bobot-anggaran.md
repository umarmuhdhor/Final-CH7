# R1 — Sinyal, bobot, anggaran latensi dan biaya

Kontrak menang kalau ada beda: `contracts/detector-interface.md` (tabel Known signal ids), `contracts/scan-result.schema.json`.
Ambang (milik Umar, `pipeline.js`): **30** popup pertama · **50** popup kedua + form dicoret · **80** blokir. Skor = `min(100, jumlah bobot)`. `db_match` → 100 langsung.

## 1. Tabel sinyal

Bobot **layer 2 = nilai di kode** (`detector/src/detector.js:15`). Bobot layer 1, 3, 4 = **usulan awal**, belum diuji, dikalibrasi di fase 07 (M6).

| id | Layer | Dibuat di | Bobot | Kapan menyala | `evidence` | Fase |
|---|---|---|---|---|---|---|
| `db_match` | 1 | detector (`ShooLists.match`) | 100 | hostname/induknya ada di daftar | `shoo` atau `public` | 01 |
| `lookalike_domain` (level 3) | 2 | detector | 25 | angka↔huruf, typo token ≥ 6 huruf, homoglyph, `xn--` | brand · level · cara | M1 ✅ |
| `lookalike_domain` (level 1) | 2 | detector | 10 | nama persis brand di domain tak terdaftar | brand · level 1 | M1 ✅ |
| `brand_plus_keyword` | 2 | detector | 14 | brand + kata (`bca-verifikasi`) | brand · level 2 · kata | M1 ✅ |
| `cheap_tld` | 2 | detector | 15 dengan brand, 5 sendirian | `.xyz`, `.site`, `.click`, … | `.tld · level` | M1 ✅ |
| `new_domain` | 2 (kontrak) | **server** (RDAP) | 10–30 naik makin muda | umur domain pendek | umur dalam hari | 03 |
| `asks_pin` | 3 | server | 35 | field PIN/passcode | `name`/`id` field | 02 |
| `asks_otp` | 3 | server | 30 | field OTP/kode verifikasi | `name`/`id` | 02 |
| `asks_password` | 3 | server | 15 | field password di halaman non-resmi | `name`/`id` | 02 |
| `asks_card` | 3 | server | 30 | nomor kartu | `name`/`id` | 02 |
| `asks_cvv` | 3 | server | 30 | CVV/CVC | `name`/`id` | 02 |
| `asks_ktp` | 3 | server | 30 | NIK/KTP | `name`/`id` | 02 |
| `asks_selfie_ktp` | 3 | server | 35 | unggah selfie + KTP | `name`/`id` | 02 |
| `urgent_language` | 3 | server | 15 | frasa mendesak | teks **persis** dari halaman | 03 |
| `brand_logo_offsite` | 3 | server | 25 | brand di `imageAlts`/title, domain bukan resmi | teks **persis** | 03 |
| `unreasonable_request` | 4 | server (LLM) | 30 | data diminta tidak wajar untuk jenis halaman | teks **persis** | 06 |
| `hoax_claim` | 5 | – | – | Fase 2, bukan MVP | – | – |

Catatan:
- Kontrak menulis `new_domain` di layer **2**, tapi `pipeline.js` hanya menerima layer 3–4 dari server → sinyalnya terbuang sampai TODO C2 dijawab.
- `asks_*` memakai `name`/`id` field (bukan nilai ketik). Extension mencoret field sendiri di skor ≥ 50.
- Maks layer 2 saat ini = 54. Kasus ambigu sengaja tidak mencapai 30 sendirian (D-imelda-04).
- Sampel acuan: `lphone-login.com` skor M1 = 39; perkiraan layer 3 ≈ +65 → 100 (butuh iframe tertangkap, TODO C1).
- Setiap sinyal punya `label` (Guardian) dan `labelSimple` (Protected, tanpa istilah teknis), masing-masing `{en, id}`.

## 2. Hal yang sengaja tidak ditangkap (keputusan, bukan bug)

| Kasus | Alasan |
|---|---|
| Typo 5 huruf (`cloud` vs `icloud`) | Terlalu banyak kata umum; salah blokir lebih buruk |
| Scam di domain yang tampak normal (`clean-domain-scam`) | Layer 2 tidak bisa melihatnya; ditangkap layer 3–4 |
| TLD murah sendirian | Hanya +5; tidak pernah mencapai 30 sendirian |
| Halaman tanpa form dan tanpa teks mendesak | Tidak ada sinyal; benar bila halaman memang tidak berbahaya |

## 3. Anggaran latensi `/analyze` (total ≤ 8 s di klien; target p95 < 8 s)

Semua angka **usulan**, diukur dan disetel di fase 02, 03, 06, 08.

| Tahap | Batas | Catatan |
|---|---|---|
| Jaringan HP → server → balik | ±1,0 s | Tergantung jaringan; tidak bisa kita kendalikan |
| Validasi + layer 3 (aturan) | ≤ 0,1 s CPU | Diuji pada teks 20.000 karakter |
| RDAP (paralel dengan layer 3) | timeout 1,5 s | Gagal = tanpa sinyal |
| LLM (layer 4) | timeout 4,0 s | Mulai bersamaan layer 3 bila lolos gerbang |
| Sisa / margin | ±1,4 s | Cadangan |

Aturan: hasil layer 3 tidak boleh menunggu LLM. Bila LLM belum selesai saat total mendekati ±6,5 s, kembalikan layer 3 saja.

## 4. Gerbang dan anggaran biaya LLM

**Gerbang (usulan, D-imelda-05 menunggu persetujuan):** panggil LLM hanya bila halaman punya ≥ 1 form dengan field, **dan** skor layer 1–3 sementara ≥ 15. Halaman tanpa form tidak membayar LLM. Situs resmi (domain di `brands.json`) tidak memanggil LLM.

Perkiraan per panggilan (input ±500 token, output ±100 token; harga per 1 juta token dari halaman resmi 21 Okt 2026, **BELUM DIVERIFIKASI ulang**):

| Model | Masuk/Keluar | Per panggilan | Per 1.000 panggilan |
|---|---|---|---|
| Gemini 2.5 Flash-Lite | $0,10 / $0,40 | ±$0,00009 | ±$0,09 |
| Claude Haiku 5.5 | $0,10 / $0,50 | ±$0,00010 | ±$0,10 |
| GPT-5.4 nano (berlabel Deprecated) | $0,20 / $1,25 | ±$0,00023 | ±$0,23 |

Pemutus anggaran: batas pengeluaran harian di dashboard penyedia + penghitung di service; lewat batas → layer 3 saja, dicatat tanpa isi halaman.

## 5. Daftar `brands.json` perlu verifikasi manual

`bankbsi.co.id`, `jet.co.id`, `bpjsketenagakerjaan.go.id` (TODO C3). Domain resmi yang belum tercatat hanya terkena +10.
