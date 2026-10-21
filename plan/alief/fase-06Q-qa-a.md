# Fase 06Q — QA-A: semua layar Fase A melawan fixtures

| Field | Nilai |
|---|---|
| Track | app |
| Branch | `fix/QA-A-<ID>-<slug>` per perbaikan |
| Prasyarat | 01–06 (PR boleh belum merge; QA dijalankan di ujung branch fase 06) |
| Requirement | Semua P0 Fase A di PROGRESS |
| Model | Sonnet 5.5 · iOS Simulator tool · `ref/R7` |
| Fase berikutnya | track app selesai → menunggu 12, lalu 13 |

## Tujuan

Laporan QA berformat Catalyst (`ref/R7`, `qa/README.md`) untuk semua layar app sebelum disambung ke backend, lalu perbaiki P0/P1 dan retest.

## Bacaan wajib

- `ref/R7` (seluruhnya), `qa/README.md`, PRD §8.1–8.4, 8.6

## Langkah kerja

1. Build Debug di simulator iPhone besar dan iPhone SE. `MockRepository` mode Guardian dan Protected.
2. Jalankan matriks QA-A (`ref/R7` §5). Untuk setiap ID PRD: bandingkan dengan "Selesai kalau", catat ✓ / △ / ✗.
3. Cek aksesibilitas: VoiceOver (label setiap kontrol), Dynamic Type XL, kontras (light/dark), target sentuh.
4. Tulis `qa/QA-A-<YYYY-MM-DD>.md` dari template, bukti di `qa/img/QA-A/`.
5. Isi `fixbug.md` ronde QA-A. Perbaiki P0 lalu P1 (TDD, satu bug satu commit), PR `fix/QA-A-…`.
6. Retest dan tambahkan blok Retest di laporan. Perbarui tabel QA di PROGRESS.

## Verifikasi

```bash
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM"
ls plan/alief/qa/img/QA-A | wc -l
```

## Kriteria selesai (DoD)

- [ ] Laporan QA-A lengkap (header, ringkasan, daftar, detail, yang sudah baik, matriks).
- [ ] P0 = 0 dan P1 = 0 setelah retest.
- [ ] PROGRESS G5 `[x]`.
