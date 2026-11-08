# Rencana: dump lokal `admin.ai_dataset` untuk eval LLM

Status: **draf, menunggu review Imelda**. Belum ada yang dijalankan. 4 Nov 2026.

## Tujuan

Membuat salinan lokal tabel `admin.ai_dataset` (D-imelda-53, #241) yang diisi data tes yang sudah kita punya, supaya prompt `/review` dan layer 4 bisa dievaluasi dan dituning (precision/recall) sebelum tabel asli ada di backend.

Yang disepakati (grilling 4 Nov):
1. "Train" = eval + tuning prompt dan bobot, bukan fine-tune.
2. Sumber: corpus `ai/eval/data` + live test `ai/test-layer-live`. Seed DB lokal (`contoh-*.test`) tidak dipakai.
3. Tabel dibuat hanya di DB Supabase lokal lewat skrip di `ai/eval/dataset/`, bukan migration. Hasil juga diekspor ke JSONL. Skrip di-commit, dump tidak.

## Data yang ada

| Sumber | Jumlah | Label | URL | Hasil layer |
|---|---|---|---|---|
| `ai/eval/data/scam/*.json` | 2 real + 45 sintetis (+ `seed.json`) | `label: scam` | Ada (`snapshot.url`) | Belum ada: dihitung dengan detector |
| `ai/eval/data/legit/*.json` | `real` 35 + `seed`, `traps`, `url-shapes` | `label: legit` | Ada | Belum ada: dihitung dengan detector |
| `ai/test-layer-live/{v1,retest11}/.raw/calls.jsonl` | 57 panggilan `/analyze` produksi (3 Nov) | Dari id tes (`scam-NN`, `smoke`) | Hanya host | Ada: `localSignals` (L1–2) + `signals` (L3–4) asli |

Belum ada data dari Guardian asli. Semua baris adalah data tes, dan ditandai begitu (§Keputusan terbuka K1).

## Tabel yang terpengaruh

### Diubah atau dibuat

| Objek | Di mana | Perubahan |
|---|---|---|
| `admin.ai_dataset` | **DB lokal saja** (`supabase_db_shoo`) | **Dibuat** dari DDL spec L5 (`layer-5-feedback.md`), plus kolom tambahan lokal (K1). Diisi ulang (truncate + insert) setiap kali skrip jalan |

### Hanya dibaca, tidak diubah

| Objek | Untuk apa |
|---|---|
| File `ai/eval/data/**` | Snapshot + label corpus |
| File `ai/test-layer-live/*/.raw/calls.jsonl` | Hasil live test |
| `ai/src/blocklist/allowlist.js` (`SHARED_HOSTS`), `ai/src/layer3/official.js` (`USER_CONTENT`) | Isi kolom `shared_host` |

### Tidak disentuh

- Semua tabel lain di DB lokal: `public.*`, `admin.domain_labels`, `domain_intel`, `domain_intel_label`, `domain_review`, `case_library`, `ai_lessons`.
- Database cloud (tidak ada akses, dan tidak perlu).
- `backend/`, `contracts/`, `ios/`.

### File baru di repo

| File | Isi | Di-commit |
|---|---|---|
| `ai/eval/dataset/schema.sql` | `create table admin.ai_dataset` (salinan DDL spec + kolom lokal) | Ya |
| `ai/eval/dataset/build.mjs` | Baca sumber, hitung layer, tulis ke DB lokal + JSONL | Ya |
| `ai/eval/dataset/README.md` | Cara pakai, batasan data | Ya |
| `ai/eval/dataset/test/*.test.mjs` | Tes pemetaan (pecah per layer, skor, shared host) | Ya |
| `ai/eval/dataset/out/ai_dataset.jsonl` | Dump | **Tidak** (`ai/.gitignore` ditambah `eval/dataset/out/`) |

## Pemetaan kolom

| Kolom | Corpus (A) | Live test (B) |
|---|---|---|
| `url` | `snapshot.url`, query dibuang | `https://<host>/` (path tidak ada di log, K3) |
| `domain` | Registrable domain (PSL extension, seperti eval) | Sama, dari host |
| `rdap_registered_at`, `rdap_age_days` | `null` (K4) | `rdap_age_days` dari label `new_domain` bila ada, selain itu `null` |
| `layer1`, `layer2` | Dari `detector.analyzeLocal` | Dari `localSignals` (dipisah per `layer`) |
| `layer3`, `layer4` | Dari `POST /analyze` dev server lokal (K2) | Dari `signals` (dipisah per `layer`) |
| `layerN_score` | Jumlah bobot sinyal layer itu | Sama |
| `score`, `status` | Total dibatasi 100; `status` dari ambang 30/80 (`null` di bawah 30) | Sama |
| `thresholds_version` | `0` | `0` |
| `scanned_at` | Waktu skrip jalan | `at` di log |
| `is_scam` | `label == "scam"` | `scam-*` = true; `smoke` dan lainnya dibuang |
| `note` | `notes` sampel | `null` |
| `decided_at` | `collectedAt` | `at` |
| `anonymous` | `true` | `true` |
| `domain_*`, `families_*` | Dihitung dari baris dataset per domain (`families_*` = 0) | Sama |
| `final_label` | `scam` → `scam_strong`, `legit` → `safe` (label buatan kita) | Sama |
| `shared_host` | Cocok `SHARED_HOSTS` / `USER_CONTENT` | Sama |
| `review_*` | `null` (belum ada `/review`) | `null` |

`evidence` disimpan apa adanya dari detector. Corpus sudah redacted, dan live test hanya punya `evidence` dari sinyal teks.

## Langkah

1. Tulis `schema.sql` dan `build.mjs` beserta tesnya. Tes jalan tanpa DB dan tanpa jaringan (`node --test ai/eval/dataset/test`).
2. Pastikan Supabase lokal hidup (`~/shoo-main`, CLI 2.114.0).
3. Jalankan `ai` dev server lokal (`npm run dev`) untuk layer 3–4 corpus (K2).
4. `node ai/eval/dataset/build.mjs`:
   - membuat tabel bila belum ada (`schema.sql`);
   - menghitung baris dari A dan B;
   - `truncate` + `insert` ke `admin.ai_dataset` lokal;
   - menulis `out/ai_dataset.jsonl`;
   - mencetak ringkasan: jumlah baris per sumber, scam/legit, sintetis/real, shared host.
5. Cek di Studio (`admin.ai_dataset`) dan cocokkan beberapa baris dengan output `node ai/eval/run.mjs --json`.

## Verifikasi

- Jumlah baris = sampel corpus yang dipakai + panggilan live yang berlabel.
- Untuk tiap baris: `layer1_score + … + layer4_score` sama dengan jumlah bobot, dan `score` = `min(100, total)`.
- Tidak ada sinyal yang masuk kolom layer yang salah (dicek dari field `layer`).
- Tidak ada `url` yang membawa query string.
- Skor corpus sama dengan output `ai/eval/run.mjs` untuk sampel yang sama.

## Keputusan terbuka (perlu jawabanmu)

| # | Pertanyaan | Usulan |
|---|---|---|
| K1 | Tambah kolom lokal `source` (`corpus`/`live`), `sample_id`, `synthetic`, yang tidak ada di DDL spec? | **Ya**. Tanpa itu sampel sintetis tidak bisa dipisah dari real, padahal D-imelda-22 melarang klaim recall dari data sintetis. Kolom ini lokal saja, tidak diminta ke Alief |
| K2 | Layer 3–4 corpus: jalankan dev server dengan LLM sungguhan (berbiaya, ±100 panggilan) atau tanpa LLM (`layer4` kosong)? | **Tanpa LLM** untuk dump pertama. Layer 4 justru yang mau dievaluasi; mengisinya dari LLM yang sama membuat eval melingkar. Live test (B) sudah membawa hasil L4 asli |
| K3 | URL live test hanya host. Cocokkan id `scam-NN` ke URL lengkap dari daftar uji di `plan/alief/qa/img/figma-parity/` (ada `qlolla-bybri.com` di sana)? | **Coba cocokkan**. Kalau tidak ketemu, pakai `https://<host>/` |
| K4 | RDAP corpus: lookup RDAP hari ini untuk tiap domain? | **Tidak**. Umur hari ini ≠ umur saat sampel dikumpulkan, dan banyak domain sintetis tidak ada. Biarkan `null` sampai #270 |
| K5 | Sampel sintetis (45 scam) ikut masuk? | **Ya, ditandai `synthetic = true`**. Laporan eval memisahkan real dan sintetis |
| K6 | Shared host ikut masuk dump? | **Ya, ditandai `shared_host = true`**. Skrip eval yang memutuskan membuangnya |
