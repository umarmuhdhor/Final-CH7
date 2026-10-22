# Fase 04 — Data eval set 50+50 (M2)

| Field | Nilai |
|---|---|
| Branch | `feat/AI-M2-eval-data` |
| Prasyarat | Kerangka `ai/eval/` merged (PR #26) |
| Requirement | M2: ≥ 50 scam + ≥ 50 legit mirip, data pribadi disamarkan |
| Sifat | **Banyak LANGKAH MANUAL** (sumber data); status `[m]` sampai sampel terkumpul |
| Fase berikutnya | 05 |

## Tujuan

Data yang cukup untuk mengukur target mandat. Tanpa ini fase 06 dan 07 tidak bermakna.

## Bacaan wajib

- `ai/eval/README.md`, `ai/eval/lib.mjs`, `ai/eval/tools/{capture,snapshot}.mjs`
- `ai/eval/data/{scam,legit}/seed.json` (13 sampel: 1 nyata `lphone-login`, sisanya sintetis)

## Langkah kerja

1. Agent menyiapkan daftar kebutuhan: kategori scam (bank palsu, e-wallet, paket/kurir, hadiah, pemerintah, iCloud/Apple) dan legit yang mirip (login bank, checkout e-commerce, halaman pemerintah, 100 situs populer Indonesia).
2. **LANGKAH MANUAL (Imelda):** tentukan sumber (laporan publik, daftar phishing berlisensi, situs resmi). Cek lisensi. Jangan membuka URL scam di browser; ambil lewat `tools/capture.mjs` atau sumber arsip.
3. Agent menjalankan `capture.mjs` → `snapshot.mjs` untuk menormalkan dan **menyamarkan** data pribadi (nama, nomor, email, NIK).
4. Seimbangkan kelas; beri label dan sumber di tiap sampel.
5. Jalankan `node ai/eval/run.mjs` dan tempel hasilnya (angka per kelas) di PR.
6. Sampel mentah yang berisi data pribadi tidak boleh ter-commit.

## Verifikasi

```bash
node ai/eval/run.mjs
node --test ai/eval/test
```

## Kriteria selesai (DoD)

- [ ] ≥ 50 scam dan ≥ 50 legit; setiap sampel punya label, sumber, tanggal.
- [ ] Penyamaran terbukti (test atau skrip pemeriksa tanpa pola email/nomor/NIK).
- [ ] `run.mjs` satu perintah; hasil ditempel di PR.
- [ ] Lisensi sumber dicatat di `ai/eval/README.md`.

## Catatan handoff

- Metrik "target hanya dinilai dengan layer 3–4 dan 50+ sampel per kelas" (kerangka sudah menerapkannya).
