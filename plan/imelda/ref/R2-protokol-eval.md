# R2 — Protokol eval (M2, M6)

Alat: `ai/eval/` (`run.mjs`, `lib.mjs`, `tools/capture.mjs`, `tools/snapshot.mjs`). README alat: `ai/eval/README.md`. Dokumen ini adalah aturan **memakai** alat itu untuk membuktikan target mandat.

## 1. Target (docs/mandates/imelda.md)

| Metrik | Target |
|---|---|
| Halaman resmi/mirip dengan skor ≥ 30 | 0 |
| Scam skor ≥ 50 | ≥ 90% |
| Scam skor ≥ 80 | ≥ 70% |
| `analyzeLocal` | < 50 ms |
| `/analyze` | p95 < 8 s |

Target hanya dinilai dengan `--analyze-url` dan **≥ 50 sampel per kelas**. Layer 1–2 saja tidak dimaksudkan memblokir (maks 54).

## 2. Komposisi set

| Kelas | Isi | Jumlah minimum |
|---|---|---|
| scam | bank palsu, e-wallet, kurir/paket, hadiah, pemerintah, iCloud/Apple, `clean-domain-scam` | 50 (tiap kategori ≥ 5) |
| legit | domain di `brands.json`, 100 situs populer Indonesia (URL saja cukup untuk layer 1–2), login bank, checkout e-commerce, toko yang menjual iPhone, kata umum | 50 mirip + 100 populer |
| trap | `lookalike-trap`, `common-word`, halaman resmi dengan banyak form | termasuk dalam legit |

Tag: `official`, `popular`, `lookalike-trap`, `common-word`, `clean-domain-scam`, `lookalike-brand`, `credential-iframe`.

## 3. Pemisahan tuning dan uji

- ±70% sampel untuk **tuning** (boleh dilihat saat menyetel bobot), ±30% **uji** (disisihkan, dilihat sekali di akhir fase 07).
- Penetapan lewat `id` yang stabil (mis. hash `id` mod 10 < 3 → uji), dicatat di `ai/eval/README.md`, bukan dipilih manual.
- Setiap perubahan bobot yang dibuat setelah melihat set uji dianggap mencemari; set uji diganti dengan sampel baru.

## 4. Catatan untuk setiap run

Setiap run yang ditempel ke PR memuat: tanggal, commit, versi detector (`ShooDetector.version`), model + versi prompt (fase 06), jumlah sampel per kelas, jumlah sintetis, tabel metrik, dan daftar sampel yang salah (false positive dan scam yang lolos).

Sampel `synthetic: true` boleh membantu uji aturan, tapi **tidak dihitung** untuk klaim target mandat.

## 5. Membaca hasil

- Prioritas: **nol false positive dulu**, baru naikkan recall.
- Laporkan per kelas **dan** per tag. Rata-rata bisa menutupi jebakan (`lookalike-trap`).
- Hasil layer 3 dan layer 4 dilaporkan **terpisah** (dengan dan tanpa LLM) supaya manfaat LLM terbukti.
- Kalau target tidak tercapai: tulis angkanya apa adanya di PR dan beri tahu Umar. Jangan menurunkan target.

## 6. Pengumpulan data

- Jangan membuka URL scam di browser biasa. `capture.mjs`: GET statis tanpa JavaScript dan cookie, batas 500 KB; masker email, telepon, angka 13–19 digit; query value dan fragment URL diganti `REDACTED`. Batas: tidak membaca konten yang ditambahkan skrip.
- Setelah `capture`, **buka file JSON, hapus data pribadi yang tersisa, baru set `"redacted": true`**. Skrip menolak sampel scam nyata tanpa itu.
- Halaman publik saja. Tanpa halaman yang butuh login atau memuat data korban. Cek lisensi tiap feed dan tulis di `source`.
- Konten dinamis/iframe: catat di `meta.iframes`; sampel itu menunjukkan batas snapshot (TODO C1).

## 7. Temuan dari eval → perbaikan

Temuan false positive atau scam yang lolos masuk `fixbug.md` (satu temuan = satu test yang gagal dulu = satu commit).
