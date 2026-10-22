# Progress — Shoo · Imelda (Team AI)

Legenda status: `[ ]` belum · `[~]` sedang dikerjakan · `[m]` berhenti di LANGKAH MANUAL (log fase berisi checklist) · `[r]` PR terbuka, menunggu review Umar · `[x]` PR **sudah di-merge** ke `main` · `[!]` terblokir (hanya Imelda yang membukanya kembali)

Waktu dalam WITA. Setiap fase hanya mengedit barisnya sendiri. Aturan push/PR: agent bertanya dulu.

| Fase | Judul | Mandat | Branch | Status | Mulai | Selesai | PR | Ringkasan satu kalimat | Log |
|---|---|---|---|---|---|---|---|---|---|
| – | Layer 2 nama link | M1 | feat/AI-M1-link-name | [x] | 21 Okt 2026 | 22 Okt 2026 | #25 (merged) | `cheap_tld`, `brand_plus_keyword`, `lookalike_domain`, level kecurigaan 0–3, 26 test | – |
| – | Kerangka eval set | M2 | feat/AI-M2-eval-set | [x] | 22 Okt 2026 | 22 Okt 2026 | #26 (merged) | `run.mjs`, `capture.mjs`, `snapshot.mjs`, 13 sampel seed; data 50+50 belum | – |
| 00 | Plan | – | docs/imelda-plan | [r] | 22 Okt 2026 | | #29 | Folder `plan/imelda/` lengkap (SECURITY, ARCHITECTURE, VERIFY, ref R1–R2, fase 01–08); menunggu review Umar | log/fase-00.md |
| 01 | db_match di detector | M5-B | feat/AI-M5-detector | [ ] | | | | | log/fase-01.md |
| 02 | /analyze + sinyal form | M3 | feat/AI-M3-forms | [ ] | | | | | log/fase-02.md |
| 03 | Konten + new_domain | M3 | feat/AI-M3-content | [ ] | | | | | log/fase-03.md |
| 04 | Data eval set 50+50 | M2 | feat/AI-M2-eval-data | [ ] | | | | | log/fase-04.md |
| 05 | /public-blocklist | M5-A | feat/AI-M5-server | [ ] | | | | | log/fase-05.md |
| 06 | Reality check LLM | M4 | feat/AI-M4-reality-check | [ ] | | | | | log/fase-06.md |
| 07 | Kalibrasi bobot | M6 | feat/AI-M6-calibration | [ ] | | | | | log/fase-07.md |
| 08 | Deploy | M7 | feat/AI-M7-deploy | [ ] | | | | | log/fase-08.md |

## Gate

| Titik | Syarat | Status | Catatan |
|---|---|---|---|
| G0 · Jawaban Umar | (1) snapshot menangkap iframe? (2) `new_domain` layer 2 atau 3? Lihat TODO C1–C2 | [ ] | Blokir sebagian akurasi fase 02 dan fase 03, bukan kodenya |
| G1 · Stack service | D-imelda-01 dikonfirmasi Imelda | [ ] | Sebelum fase 02 |
| G2 · Data eval | ≥ 50 scam + ≥ 50 legit tersamarkan | [ ] | Fase 04; syarat fase 07 |
| G3 · Model + key LLM | Model dipilih setelah eval, key di `.env` | [ ] | Fase 06 |
| G4 · URL publik | `/analyze` + `/public-blocklist` di HTTPS, URL dikirim ke Umar dan Alief | [ ] | Fase 08 |
| G5 · MVP Imelda | Definisi selesai README §6 tercapai di eval | [ ] | |

## Status requirement mandat

| ID | Fase | Status | Bukti |
|---|---|---|---|
| M1 Layer 2 | – | [x] | `detector/test/`, PR #25 |
| M2 Kerangka eval | – | [x] | `ai/eval/test/`, PR #26 |
| M2 Data 50+50 | 04 | [ ] | |
| M3 `/analyze` + sinyal form | 02 | [ ] | |
| M3 `urgent_language`, `brand_logo_offsite`, `new_domain` | 03 | [ ] | |
| M4 Reality check | 06 | [ ] | |
| M5 Server `/public-blocklist` | 05 | [ ] | |
| M5 Detector `db_match` | 01 | [ ] | |
| M6 Kalibrasi | 07 | [ ] | |
| M7 Deploy | 08 | [ ] | |
| Label EN + ID semua sinyal | 01–03, 06 | [ ] | |

## Metrik eval (diisi fase 07)

| Metrik | Target | Sebelum | Sesudah |
|---|---|---|---|
| Situs resmi skor < 30 | 100% | | |
| Scam skor ≥ 50 | ≥ 90% | | |
| Scam skor ≥ 80 | ≥ 70% | | |
| `analyzeLocal` | < 50 ms | | |
| `/analyze` p95 | < 8 s | | |
