# Laporan pagi — fase 05-08 (22 Okt 2026)

Dasar: `wip/AI-overnight-base` (= #50 + #57, test 327 hijau). Semua cabang bertumpuk (stacked). Tidak ada merge, deploy, atau key.

## 1. Status
| Fase | Status | Cabang | Commit terakhir | Test (semua hijau) |
|---|---|---|---|---|
| 05 /public-blocklist | [m] | feat/AI-M5-server | b6d50a3 | 351 |
| 06 Layer 4 LLM | [m] | feat/AI-M4-reality-check | 8a6e7e5 | 374 |
| 07 Kalibrasi | [m] | feat/AI-M6-calibration | b6e8f97 | 385 |
| 08 Deploy | [m] | feat/AI-M7-deploy | 9c83fe0 | 395 |
Test dijalankan dengan `--test-concurrency=1` (tes performa NFKC bisa gagal bila paralel dengan `ai/eval/test`).

## 2. Eval (service lokal, layer 4 mati)
| | Target | Sebelum | Sesudah |
|---|---|---|---|
| Legit skor >= 30 | 0 | 4/51 | 1/51 (nyata 0/39) |
| Scam >= 50 | 90% | 66% | 66% |
| Scam >= 80 | 70% | 40% | 32% |
**Target belum tercapai dan belum bisa dinilai resmi** (scam nyata hanya 1). Sisa false positive: KYC fintech sah (F-04-1). Total holdout terlihat di tiap run, jadi holdout tidak sepenuhnya bersih. analyzeLocal p95 1 ms; /analyze lokal p95 2,5 ms.

## 3. Tugas manual untuk kamu (berurutan)
1. A3 sumber daftar publik: tabel lisensi di `ai/README.md`; belum ada yang jelas boleh. Rekomendasi: tanya PhishTank, baca EULA-nya. Lalu tulis `BlocklistSource` (satu file).
2. A2/B1 model + key LLM: isi `ai/.env`, jalankan eval dengan dan tanpa LLM (log/fase-06.md).
3. A5 gerbang LLM (pakai skor aturan server saja, 15) dan C5 kabari Alief/Umar soal privasi (host, title, label field ke penyedia LLM).
4. B2 akun hosting Cloudflare + paket (Free = CPU 10 ms; disarankan Paid), deploy, aturan rate limit, smoke test, kirim URL ke Umar+Alief (C4). Checklist: log/fase-08.md.
5. C6 laporkan angka eval ke Umar; tambah scam nyata (min. 50) + holdout baru.

## 4. Keputusan baru untuk disetujui
D-imelda-23..26 (blocklist: PSL milik extension, daftar kosong di produksi, apex platform, rate limit/ISO since), 27-29 (layer 4: input minimal, penyedia generik, evidence hanya dari title), 30-31 (bobot kalibrasi), 32 (CORS `*`, batas rate). D-imelda-29 bertentangan sebagian dengan SECURITY A5 (sinyal tetap tanpa evidence, bukan dibuang).

## 5. PR dibuka (semua reviewer umarmuhdhor)
- #58 fase 05, base wip/AI-overnight-base: https://github.com/umarmuhdhor/Final-CH7/pull/58
- #59 fase 06, base feat/AI-M5-server: https://github.com/umarmuhdhor/Final-CH7/pull/59
- #60 fase 07, base feat/AI-M4-reality-check: https://github.com/umarmuhdhor/Final-CH7/pull/60
- #61 fase 08, base feat/AI-M6-calibration: https://github.com/umarmuhdhor/Final-CH7/pull/61
Ubah base ke main setelah #44, #50, #57 dan PR sebelumnya merged. Semua fase di-PR-kan; tidak ada fase [!].
Catatan: baris PROGRESS fase 05-08 diedit di cabang masing-masing, jadi akan konflik kecil saat merge berurutan (gabungkan dua sisi).
