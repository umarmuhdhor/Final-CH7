# Fase 07 — Kalibrasi bobot (M6)

| Field | Nilai |
|---|---|
| Branch | `feat/AI-M6-calibration` |
| Prasyarat | Fase 03, 04, 06 |
| Requirement | M6: bobot semua sinyal sampai target tercapai di eval set |
| Fase berikutnya | 08 |

## Tujuan

Mengatur bobot sampai: situs resmi < 30, ≥ 90% scam ≥ 50, ≥ 70% scam ≥ 80.

## Bacaan wajib

- `docs/mandates/imelda.md` (Definisi sukses), `PROGRESS.md` (tabel metrik)
- Bobot saat ini di `detector/src/detector.js` dan `ai/`; level kecurigaan M1 (0–3, maks layer 2 = 54)

## Langkah kerja

1. Jalankan eval apa adanya dan simpan sebagai "Sebelum".
2. Urutan prioritas: **nol salah blokir dulu** (situs resmi < 30), baru naikkan deteksi.
3. Ubah bobot satu per satu, catat tiap perubahan + alasan di log fase; jangan mengejar angka dengan menghafal sampel (pisahkan sampel tuning dan sampel uji bila data cukup).
4. Ukur kecepatan: `analyzeLocal` < 50 ms, `/analyze` p95 < 8 s.
5. Kalau target tidak tercapai: **laporkan angkanya ke Umar**, jangan menurunkan target diam-diam.
6. Isi tabel "Sebelum/Sesudah" di PROGRESS dan di PR. Jalankan `detector/scripts/sync-to-extension.sh` bila bobot detector berubah.

## Verifikasi

```bash
node ai/eval/run.mjs
node --test detector/test ai/ ai/eval/test ios/ShooExtension/Tests
```

## Kriteria selesai (DoD)

- [ ] Tabel metrik terisi (sebelum/sesudah), target tercapai atau dilaporkan jelas.
- [ ] Semua domain `brands.json` + 100 situs populer ID < 30.
- [ ] Test lama tetap hijau (tidak ada test yang dilemahkan).
- [ ] Perubahan bobot tercatat satu per satu.
