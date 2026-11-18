# Layer 3: model impersonation (PR `feat/L3-impersonation-model-v9`)

_Draft 2026-11-18. Host scam ditulis dengan `[.]`. Semua kode baru ada di belakang flag `SHOO_L3_MODEL=impersonation`; tanpa flag, server menjawab persis seperti `main`._

## 0. Jawaban singkat: bisa switch arsitektur lama/baru di build lokal?

**Bisa, tanpa build ulang app iOS.** Arsitektur dipilih di server AI (`ai/`), bukan di app.

| Arsitektur | Cara jalan lokal | Isi layer 3 |
|---|---|---|
| Lama (rules, = `main`) | `cd ai && node src/dev-server.mjs` | `forms.js` + `content.js` + umur domain |
| Baru (rules + model) | `cd ai && SHOO_L3_MODEL=impersonation node src/dev-server.mjs` | sama + signal `impersonation_model` |

- App Debug di iPhone/simulator diarahkan ke server itu dengan argumen `-debug.aiBaseURL http://<IP Mac>:8787` (iPhone fisik: tambah `SHOO_DEV_HOST=<IP Wi-Fi Mac>`).
- Ganti arsitektur = matikan server, jalankan lagi dengan/tanpa flag. App tidak perlu di-build ulang.
- Worker yang di-deploy: var `SHOO_L3_MODEL` di Cloudflare. Tidak di-set = lama. Belum pernah di-set di mana pun.
- Dijamin oleh tes `ai/test/impersonation-model.test.mjs` → "flag off: no model signal, same answer as before".

## 1. Analisis input – proses – output

### Input

Hanya yang sudah dikirim ekstensi ke `POST /analyze`. Tidak ada HTML mentah, tidak ada screenshot.

| Input | Asal | Dipakai untuk |
|---|---|---|
| `snapshot.url` | ekstensi (origin + path, tanpa query) | host, TLD, subdomain hosting gratis, brand/kata umpan di alamat |
| `snapshot.title`, `snapshot.text` | ekstensi (`innerText` halaman) | TF-IDF kata dan huruf, deteksi bahasa Indonesia, kata pancingan |
| `snapshot.forms[].fields[]` | ekstensi (`snapshot.js`) | kolom password, jumlah input |
| `ruleIds` | rules layer 3 yang sudah jalan (`asks_*`, `brand_logo_offsite`, `urgent_language`) | fitur tambahan model, saringan klaim, aturan login |
| `ageDays` | RDAP (umur domain) | aturan domain muda |
| `detector/data/brands.json` | data bersama layer 2 dan 3 | daftar 27 brand, TLD murah, kata kunci URL |

### Proses (`ai/src/layer3/model/impersonation.js`, sinkron, tanpa jaringan, < 50 ms per halaman)

1. **Fakta halaman** (`pageRow`): brand di judul/teks/host, domain resmi, hosting gratis, TLD murah, kolom password.
2. **Dua juri TF-IDF + regresi logistik**: satu membaca teks (kata + n-gram huruf), satu membaca alamat (n-gram huruf).
3. **Dua penggabung gradient boosting** (2×300 pohon): satu pakai alamat, satu tidak. Skor akhir = rata-rata keduanya.
4. **Tier dari ambang**: ambang bahasa Indonesia dikalibrasi terpisah (warn 0,298, block 0,500; bahasa lain 0,612 / 0,873). Domain resmi, Tranco top-1000, dan `mandirikartukredit.com` selalu `safe`.
5. **Saringan klaim v3g**: warn/block turun ke `gate` kalau halaman tidak membuat klaim (tidak ada form/permintaan data, tidak ada kata pancingan, brand hanya di footer).
6. **Aturan tambahan (minimal `warn`)**: domain sendiri berumur < 30 hari; brand di domain orang lain; kata umpan Indonesia di alamat (hadiah, undian, bansos, pemenang, klaim, pencairan, bantuan).
7. **Aturan `block`**: meniru brand (brand di host orang lain atau logo brand di luar situs resmi) **dan** minta login (kolom password atau `asks_password/otp/pin/card/cvv`).

Angka model ada di `impersonation-data.js` (3,6 MB, dibuat `shoo-impersonation-lab/export_js.py --coef16`). Paritas dengan model Python: selisih skor maks 0,0018, tier sama di 4.283 halaman.

### Output

| Tier model | Yang dikirim ke app | Efek |
|---|---|---|
| `safe` / `gate` | tidak ada signal | skor sama seperti tanpa model |
| `warn` | `impersonation_model`, layer 3, bobot **40** | total 30–79 → layer 4 (LLM) boleh menambah; popup peringatan |
| `block` | `impersonation_model`, layer 3, bobot **80** | total ≥ 80 → diblokir tanpa LLM |

Label: "Halaman ini mirip tiruan situs lain" / "Terlihat seperti situs palsu". Tanpa `evidence` (skor model bukan teks di halaman). Kalau model error, signal dibuang dan jawaban rules tetap jalan.

## 2. Yang berubah di PR ini

| File | Perubahan | Pemilik area |
|---|---|---|
| `ai/src/layer3/model/impersonation.js`, `impersonation-data.js` | model baru | Imelda (L3) |
| `ai/src/analyze.js` | opsi `model`: tambah signal sebelum gate layer 4 dihitung | Imelda |
| `ai/src/app.js` | opsi `l3Model` / env `SHOO_L3_MODEL` | Alief, Imelda |
| `ai/src/dev-server.mjs` | `SHOO_L3_MODEL`, `SHOO_DEV_HOST`, log bentuk snapshot `SHOO_DEV_LOG_HITS` (tanpa teks halaman) | Alief, Imelda |
| `ai/src/signal-ids.js`, `contracts/detector-interface.md` | id baru `impersonation_model` | Alief, Umar |
| `ios/ShooExtension/Resources/snapshot.js` | input di luar `<form>` dikumpulkan sebagai form virtual (`action: null`) | **Umar** |
| `ios/ShooExtension/Resources/content.js` | `MutationObserver` juga memantau `style/class/hidden/open`: langkah form yang muncul belakangan dicek ulang | **Umar** |
| `ios/ShooApp/Data/SessionStore.swift` | Debug saja: `http://` ke IP privat (10.x, 172.16–31.x, 192.168.x) | **Alief** |
| `ios/ShooApp/App/AppEnvironment.swift` | Debug saja: `-debug.aiBaseURL` disimpan supaya tidak hilang saat app dibuka dari ikon | **Alief** |
| `ios/project.yml` | tidak berubah: IP Mac di argumen scheme dibuang dari PR. Pakai `-debug.aiBaseURL` lewat Edit Scheme lokal | Umar |
| tes: `ai/test/impersonation-model.test.mjs`, `Tests/snapshot.test.mjs`, `Tests/dom.test.mjs` | tes baru | |
| `ai/archive/l3-rules-2026-11-18/` | backup rules layer 3 dari `main` 2b9bf6c1 (tidak di-import) + tag `l3-rules-2026-11-18` | Imelda |
| `ai/test-layer3/v2…v7` | laporan + skrip analisis saja, tanpa data | Imelda |
| `ai/test-layer3/v10…/lab/` | skrip lab `shoo-impersonation-lab` (latih, eval, export ke JS, paritas) + `RISET-PAPER.md`; `RISET-model-l3.md` = prompt riset | Imelda |

## 3. Yang sudah dicoba

### Kita (Imelda)

| Versi | Isi | Scam segar tertangkap | Legit salah tanda | Status |
|---|---|---|---|---|
| rules (`main`) | form + konten | 2,0% | 0,2% Kaggle | arsitektur lama |
| v1 | TF-IDF + LR | 63,6% | 4,2% Kaggle | diganti |
| v2 | + 2 penggabung boosting + fakta | 67,9% | 4,1% | **dipakai** |
| v2 + umur < 30 hari | | 69,4% | 4,2% | dipakai |
| v3g + umur | saringan klaim | 66,5% | **0,25%** Kaggle | dipakai |
| + brand di host | | 76,3% | +1 (warn, tanpa input) | dipakai |
| + kata umpan di host (Indonesia saja) | | **87,6%** | +0 | dipakai |
| + tiruan & login = block | | block 274 → 275 | 0 baru | dipakai |
| latih ulang + legit bisnis kecil | | 49% | | **ditolak** |
| kata umpan Inggris di host | | +5 scam | semua FP (nobelprize, giveawayoftheday) | **ditolak** |
| brand di judul + login = block | | | 5 legit diblokir ("Masuk dengan Google") | **ditolak** |
| pangkas istilah TF-IDF | ukuran turun | | 469 tier berubah | **ditolak** |
| koefisien float16 | bundle 3,7 → 2,3 MB gzip | 0 tier berubah | | **dipakai** |

Riset paper (`shoo-impersonation-lab/RISET-PAPER.md`): 29 paper, 39 kandidat, shortlist C1–C4. C1 (basis brand besar) paling banyak +1,4 poin. C3 (teks field form) terhalang data.

### Alief (`aliefauzan/shoo-layer3-lab`)

- Layer 3 dibangun ulang: `BAAI/bge-m3` (embedding 1.024 dimensi) + 5 model kecil + 2 penggabung, plus prompt layer 4 baru `scam-judge.v1` dan aturan keputusan strict/judge/balanced.
- Hasil Alief, 500 URL live: rules 23,1% tertangkap; rebuilt balanced 94,8% tertangkap, 5,8% legit ditandai (ambang umur domain dipilih di data yang sama).
- Banding di sampel yang sama (`v5-2026-11-13-compare-alief-l3`): AUC rules 0,528, Alief 0,842. Laporan v7 menyimpulkan model ringan kita lebih baik di feed segar.
- **Tidak bisa jalan di Worker**: `bge-m3` 2,3 GB. Butuh layanan embedding terpisah. Karena itu PR ini memakai model ringan kita.
- Temuan Alief yang dipakai: prompt layer 4 lama (`reality-check.v4`) menjawab "reasonable" untuk 353 dari 373 scam; halaman login dengan sedikit teks sumber utama salah tanda.

## 4. Irisan dengan pekerjaan orang lain

| # | Irisan | Siapa | Tindakan |
|---|---|---|---|
| 1 | `snapshot.js` / `content.js` diubah (form virtual, observer atribut) | Umar (EX-*) | issue + minta review |
| 2 | `SessionStore` / `AppEnvironment` Debug-only | Alief | issue + minta review |
| 3 | Kartu Detail (DT-04, `EvidenceCard.swift`) tidak kenal `impersonation_model` → jatuh ke `.other` | Alief | issue: tambah kasus/teks |
| 4 | `brands.json` dipakai layer 2 dan model layer 3. Usulan layer 2 (Telkomsel, Indosat, TikTok) menggeser fitur model | Umar | issue (`v9…/ISSUE-layer2.md`), ukur ulang `eval_v3.py` kalau brand ditambah |
| 5 | `contracts/detector-interface.md` + `signal-ids.js`: id baru | Umar, Alief | disebut di PR |
| 6 | Alief membangun layer 3 pengganti sendiri (bge-m3) | Alief | issue: sepakati arsitektur mana yang lanjut |
| 7 | `ai/test/fixtures.test.mjs` "warning-63" **sudah gagal di `main`** (bukan dari PR ini) | pemilik #590 / DT-04 | issue terpisah |

## 5. Masalah yang diketahui

- 87,6% kemungkinan terlalu optimis: scam segar didominasi kit blogspot "hadiah/undian", dan aturan dirancang di data yang sama. Perlu sampel scam baru.
- Phishing global berbahasa Inggris masih 19,2%.
- ±85% dari 107 scam yang lolos tidak membawa sinyal peniruan apa pun. Penilaian ini belum dicek manusia.
- Bundle Worker 2,3 MB gzip, di bawah batas Workers Free 3 MB. Sisa ruang 0,7 MB.

## 6. Tidak ikut di-push

- Data: `detail.csv`, `fresh/`, `snapshots/`, `.hasil/`, `*.jsonl`, model `.joblib`, `out/` lab, fixture paritas (berisi teks halaman).
- `HASIL.md` per-halaman v2–v6 (berisi potongan teks halaman scam; v4 30 MB): sudah dikecualikan `.gitignore` folder masing-masing.
- Host scam di laporan v7 disamarkan `[.]` sebelum commit.
- `__pycache__`, `ios/Config/Local.xcconfig`, `Localizable.xcstrings` hasil build.

## 7. Tes (setelah merge `origin/main` 2b9bf6c1)

- `cd ai && node --test`: 433 tes, 432 lulus. 1 gagal = "warning-63", juga gagal di `main` bersih.
- `node --test ios/ShooExtension/Tests/*.test.mjs`: 366 lulus.
- `xcodebuild` Debug simulator: BUILD SUCCEEDED.
