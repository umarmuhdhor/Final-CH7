# Rencana fase 03 — Detail DT-01..06 (+ tombol GD-07)

Sumber: `fase-03-detail.md`, PRD v1.5 §5 Validasi + §8.3 GD-07 + §8.4 DT-01..06 (dibaca dari Google Drive 22 Okt 2026), `contracts/api.md` (`GET /scans/{id}`, `POST /verdicts`), D-alief-B08/B09 (`screenshotUrl` = link Worker, `no-store`), SECURITY §3 P1–P13.
Branch `feat/DT-detail` ditumpuk di atas fase 01 (`feat/APP-foundation`, PR #14), **bukan** di atas fase 02 (sesi lain, paralel).

## Batas konflik dengan sesi fase 02 (paralel)

- File baru semua di `ios/ShooApp/Features/Detail/`, test di `Tests/Detail*`, `UITests/DetailUITests.swift`.
- File fase 01 yang disentuh hanya: `MainTabView.destination` (placeholder → `DetailView`), satu baris DEBUG `-debug.detail <scanId>` di `AppEnvironment.live`, string baru di `Localizable.xcstrings`.
- `MockRepository`, `Router`, `ScoreRing`, `StatusChip` tidak diubah. Keputusan memakai ID `D-alief-A30…`.

## Langkah (TDD: test merah dulu)

1. `DetailModel` (`@MainActor @Observable`): `load()` = `scan(id:)` + `me()` bersamaan; state `loading / loaded / failed(notFound|other)`; `badge` (DT-02, `ScanBadge`); `canValidate` = mode Guardian ∧ status `blocked` (DT-05); `setVerdict(_:)` optimistic → hasil server, gagal → rollback + `verdictError`; tombol dikunci selama request.
   Test: `DetailModelTests` dengan `MockRepository(latency: .zero)` + stub repository yang gagal / menahan request.
2. `Evidence.top(_:mode:language:)` (DT-04): urut bobot turun (seri = urutan asli), maks 3; teks `label` (Guardian) / `labelSimple` (Protected) lewat `text(for:)`; baris "Domain age 3 days · +30%".
3. `VerdictNote` (DT-06): "Verified scam by X" / "Marked safe by X", "by you" kalau `byDeviceId == me`.
4. DT-03: link lengkap sebagai teks (tidak pernah dibuka dari app) + tombol Copy link ke pasteboard `.localOnly` (P8); waktu `Formatters.dateTime` + relatif; pemilik untuk Guardian bila scan milik orang lain atau Family mode menyala.
5. `ScreenshotView` (DT-04, P9): `ScreenshotLoader` dengan `URLSession` ephemeral + `URLCache` memori saja (disk 0), tanpa header Authorization, cek HTTP 200 + batas ukuran; `nil` → blok disembunyikan; gagal → pesan; tap → layar zoom (pinch + ketuk dua kali), tanpa share/simpan/context menu.
6. `DetailView` + `VerdictButtons` + wiring `MainTabView`; `-debug.detail` untuk screenshot/UI test.
7. `DetailUITests`: Guardian Not safe → label "Verified scam" + "Verified scam by you" tanpa dialog; Protected tanpa tombol + teks sederhana; screenshot ada/tidak ada.
8. Gerbang UI: 5 fixture × Guardian (+ 3 fixture yang terlihat oleh Protected) × EN/ID + light/dark/XL → `qa/img/ui-03/`; review `apple-design` + `ecc:a11y-architect`.
9. Review `ecc:swift-reviewer` (+ `ecc:security-reviewer` untuk P9/P8), perbaikan, cek P1–P13, verifikasi, log, PR.
