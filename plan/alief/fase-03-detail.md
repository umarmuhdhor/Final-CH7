# Fase 03 — Detail: DT-01 s.d. DT-06 (+ tombol GD-07)

| Field | Nilai |
|---|---|
| Track | app |
| Branch | `feat/DT-detail` |
| Prasyarat | 01 (02 boleh belum merge, stacked) |
| Requirement | DT-01..DT-06 (P0), tombol GD-07 (aksi live di fase 15) |
| Model | Sonnet 5.5 · `apple-design`, `ecc:swiftui-patterns` |
| Fase berikutnya | 04 |

## Tujuan

Satu layar Detail yang dipakai semua mode dan semua sumber (Activity, Shield card, push di fase 15): skor, label, link, waktu, pemilik, bukti, tombol validasi khusus Guardian, catatan verifikasi.

## Bacaan wajib

- PRD §8.4 (DT-*), §5 Validasi, §8.3 GD-07
- Fixture: `blocked-92.json`, `warning-41.json`, `warning-63.json`, `blocked-verified-scam.json`, `blocked-marked-safe.json`
- `ShooShared/ScanResult.swift` (`Signal.label`, `labelSimple`, `LocalizedText`)

## Output

- `Features/Detail/`: `DetailView`, `DetailModel` (load `scan(id:)`, `setVerdict`), `EvidenceList`, `ScreenshotView` (tap untuk zoom, pinch), `VerdictButtons`, `VerdictNote`
- Test: label per kombinasi status + verdict, urutan bukti (bobot terbesar dulu, maks 3), teks Protected memakai `labelSimple`, tombol hanya untuk Guardian, optimistic update + rollback

## Langkah kerja

1. **DT-01** ring persentase besar di atas (`ScoreRing`).
2. **DT-02** label: Warning / Blocked / Verified scam (`verdict == not_safe`) / Marked safe (`verdict == safe`).
3. **DT-03** link lengkap (bisa disalin, tidak bisa dibuka langsung dari app untuk scan blocked), waktu dibuka (format lokal EN/ID), nama pemilik saat Family mode.
4. **DT-04** 1–3 bukti, bobot terbesar dulu: alasan ringkas + sinyal dan bobot ("Domain age 3 days · +30%"). Guardian memakai `label`, Protected memakai `labelSimple`, keduanya `text(for: languageCode)`. Screenshot besar kalau ada (`screenshotUrl`), tap untuk zoom; kalau `null` → sembunyikan blok.
5. **DT-05 / GD-07** tombol It's safe / Not safe hanya untuk Guardian, hanya untuk item Blocked (kontrak: hanya item blocked bisa diberi verdict), untuk item milik sendiri dan Protected-nya. Langsung berlaku tanpa konfirmasi: optimistic update, rollback + pesan kalau gagal. Protected tidak pernah melihat tombol (test).
6. **DT-06** catatan "Verified scam by [nama]" / "Marked safe by [nama]"; "by you" kalau `byDeviceId == me`.
7. Gerbang UI untuk 5 fixture × {Guardian, Protected} × {EN, ID}.

## Verifikasi

```bash
source plan/alief/ref/sim.sh
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppTests/DetailModelTests
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppUITests/DetailUITests
```

## Kriteria selesai (DoD)

- [ ] DT-01..06 sesuai "Selesai kalau" PRD untuk kelima fixture (screenshot).
- [ ] Protected: tanpa tombol, bukti memakai `labelSimple` (test).
- [ ] Verdict langsung berlaku tanpa dialog, rollback saat error (test dengan mock yang gagal).

## Catatan handoff

- Fase 15 menyambungkan tombol ke `POST /verdicts` asli dan membuka Detail dari push.
