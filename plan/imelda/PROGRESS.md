# Progress — Shoo · Imelda (Team AI)

Legenda status: `[ ]` belum · `[~]` sedang dikerjakan · `[m]` berhenti di LANGKAH MANUAL (log fase berisi checklist) · `[r]` PR terbuka, menunggu review Umar · `[x]` PR **sudah di-merge** ke `main` · `[!]` terblokir (hanya Imelda yang membukanya kembali)

Waktu dalam WITA. Setiap fase hanya mengedit barisnya sendiri. Aturan push/PR: agent bertanya dulu.

| Fase | Judul | Mandat | Branch | Status | Mulai | Selesai | PR | Ringkasan satu kalimat | Log |
|---|---|---|---|---|---|---|---|---|---|
| – | Layer 2 nama link | M1 | feat/AI-M1-link-name | [x] | 21 Okt 2026 | 22 Okt 2026 | #25 (merged) | `cheap_tld`, `brand_plus_keyword`, `lookalike_domain`, level kecurigaan 0–3, 26 test | – |
| – | Kerangka eval set | M2 | feat/AI-M2-eval-set | [x] | 22 Okt 2026 | 22 Okt 2026 | #26 (merged) | `run.mjs`, `capture.mjs`, `snapshot.mjs`, 13 sampel seed; data 50+50 belum | – |
| 00 | Plan | – | docs/imelda-plan | [r] | 22 Okt 2026 | | #29 | Folder `plan/imelda/` lengkap (SECURITY, ARCHITECTURE, VERIFY, ref R1–R2, fase 01–08); menunggu review Umar | log/fase-00.md |
| 01 | db_match di detector | M5-B | feat/AI-M5-detector | [x] | 22 Okt 2026 | 22 Okt 2026 | #30 (merged) | `db_match` dari `ShooLists.match` (layer 1), 141 test hijau, tanpa request jaringan | log/fase-01.md |
| 02 | /analyze + sinyal form | M3 | feat/AI-M3-forms | [x] | 22 Okt 2026 | 22 Okt 2026 | #44 (merged) | `POST /analyze` + 7 sinyal form, 62 test (204 total hijau); lphone-login 39 sampai snapshot diambil ulang dengan form iframe (#75, #79) | log/fase-02.md |
| 03 | Konten + new_domain | M3 | feat/AI-M3-content | [x] | 22 Okt 2026 | 22 Okt 2026 | #50 (merged) | `urgent_language`, `brand_logo_offsite`, `new_domain` (RDAP, layer 3), 133 test ai/; warning-63 +11 dari fixture (bobot R1) | log/fase-03.md |
| 04 | Data eval set 50+50 | M2 | feat/AI-M2-eval-data | [x] | 22 Okt 2026 | 23 Okt 2026 | #57 (merged) | 50 scam + 51 legit, 194 test hijau; scam nyata hanya 1, jadi target M6 belum bisa dinilai (#73) | log/fase-04.md |
| 05 | /public-blocklist | M5-A | feat/AI-M5-server | [x] | 22 Okt 2026 | 23 Okt 2026 | #58 (ke wip/AI-overnight-base), #67 (merged) | Endpoint + 19 test, di-deploy 23 Okt 2026; daftar kosong sampai sumber + lisensi dipilih (A3) | log/fase-05.md |
| 06 | Reality check LLM | M4 | feat/AI-M4-reality-check | [x] | 22 Okt 2026 | 23 Okt 2026 | #59 (merged) | Layer 4 + 374 test hijau (penyedia palsu), mati di produksi; model, key, eval dengan LLM menunggu A2, A5, A6 | log/fase-06.md |
| 07 | Kalibrasi bobot | M6 | feat/AI-M6-calibration | [x] | 22 Okt 2026 | 23 Okt 2026 | #60 (merged) | Legit >=30: 4 -> 1/51; scam >=50 66%, >=80 32%: target belum bisa dinilai (1 scam nyata, #73); 385 test hijau | log/fase-07.md |
| 08 | Deploy | M7 | feat/AI-M7-deploy | [x] | 22 Okt 2026 | 23 Okt 2026 | #61 (merged) | Deploy ke `https://shoo-ai.uumaarrrrr22.workers.dev` (23 Okt 2026, Umar), smoke test hijau dengan p95 `/analyze` 171 ms; layer 4 mati (tanpa secret) dan daftar publik masih kosong (A3) | log/fase-08.md |

## Gate

| Titik | Syarat | Status | Catatan |
|---|---|---|---|
| G0 · Jawaban Umar | (1) snapshot menangkap iframe? (2) `new_domain` layer 2 atau 3? Lihat TODO C1–C2 | [ ] | Blokir sebagian akurasi fase 02 dan fase 03, bukan kodenya |
| G1 · Stack service | D-imelda-01 dikonfirmasi Imelda | [x] | Sebelum fase 02 |
| G2 · Data eval | ≥ 50 scam + ≥ 50 legit tersamarkan | [ ] | Fase 04; syarat fase 07 |
| G3 · Model + key LLM | Model dipilih setelah eval, key di `.env` | [ ] | Fase 06 |
| G4 · URL publik | `/analyze` + `/public-blocklist` di HTTPS, URL dikirim ke Umar dan Alief | [ ] | Fase 08 |
| G5 · MVP Imelda | Definisi selesai README §6 tercapai di eval | [ ] | |

## Status requirement mandat

| ID | Fase | Status | Bukti |
|---|---|---|---|
| M1 Layer 2 | – | [x] | `detector/test/`, PR #25 |
| M2 Kerangka eval | – | [x] | `ai/eval/test/`, PR #26 |
| M2 Data 50+50 | 04 | [~] | PR #57; scam nyata hanya 1 dari 50 (#73) |
| M3 `/analyze` + sinyal form | 02 | [x] | PR #44 |
| M3 `urgent_language`, `brand_logo_offsite`, `new_domain` | 03 | [x] | PR #50 |
| M4 Reality check | 06 | [~] | PR #59; model belum dipilih (A2, A6) |
| M5 Server `/public-blocklist` | 05 | [~] | PR #58, #67; sumber daftar belum dipilih (A3) |
| M5 Detector `db_match` | 01 | [x] | PR #30 |
| M6 Kalibrasi | 07 | [~] | PR #60; target belum bisa dinilai (#73) |
| M7 Deploy | 08 | [x] | PR #61, deploy 23 Okt 2026 (log/fase-08.md) |
| Label EN + ID semua sinyal | 01–03, 06 | [ ] | |

## Metrik eval (diisi fase 07)

| Metrik | Target | Sebelum | Sesudah |
|---|---|---|---|
| Situs resmi skor < 30 | 100% | 47/51 legit < 30 (nyata 39/39) | 50/51 legit < 30 (nyata 39/39); semua domain brands.json + populer < 30 (test) |
| Scam skor ≥ 50 | ≥ 90% | 66% (33/50; nyata 0/1) | 66% (33/50; nyata 0/1) |
| Scam skor ≥ 80 | ≥ 70% | 40% (20/50) | 32% (16/50) |
| `analyzeLocal` | < 50 ms | – | p95 1,0 ms |
| `/analyze` p95 | < 8 s | – | p95 171 ms dari URL publik (30 run, 23 Okt 2026, termasuk jaringan, tanpa LLM); lokal 2,5 ms |
