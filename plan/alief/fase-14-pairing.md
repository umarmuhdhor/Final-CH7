# Fase 14 — Pairing: GD-04, PR-01, PR-02, PR-03

| Field | Nilai |
|---|---|
| Track | c |
| Branch | `feat/GD-04-PR-01-03-pairing` |
| Prasyarat | 13 |
| Requirement | GD-04, PR-01, PR-02, PR-03 (P0 link; deferred deep link = P1) |
| Model | Opus 5.5 · `apple-design`, `ecc:swiftui-patterns`, `ecc:swift-concurrency-6-2` |
| Fase berikutnya | 15 |

## Tujuan

Keluarga terhubung lewat QR, kode 4 digit, atau link undangan WhatsApp.

## Bacaan wajib

- PRD §8.2 PR-01..03, §8.3 GD-04, §10 risiko kode 4 digit
- `ref/R4` §1–§2, `ref/R3` §4 (`/join` page), `SECURITY.md` T2, T11
- `ios/project.yml` (URL scheme `shoo` sudah ada; kamera butuh `NSCameraUsageDescription` di `ShooApp/Info.plist` — file kita)

## Output

- `Features/Pairing/FamilyCodeView` (Guardian): QR (`CoreImage.CIQRCodeGenerator` berisi `inviteUrl`), kode besar, hitung mundur 60 s lalu kode baru otomatis, "Copy invite link" (teks undangan EN/ID + `inviteUrl`), daftar terhubung x/3 + hapus
- `Features/Pairing/ConnectView` (Protected): tab Scan QR (`AVCaptureSession` / `DataScannerViewController`) dan Enter code (4 kotak digit), pesan error jelas per kode error kontrak + coba lagi
- `Features/Pairing/ProtectedByView`: "You're protected by [nama]" + avatar → lanjut (ON-04 placeholder, lalu Home)
- `onOpenURL` untuk `shoo://join?code=` → ConnectView dengan kode terisi + konfirmasi (T11)
- Test: hitung mundur + refresh, parsing URL/QR (`https://…/join?code=` dan `shoo://join?code=`), pemetaan error ke pesan EN/ID, daftar x/3

## Langkah kerja

1. GD-04 dibuka dari Profile (fase 06) dan tombol "Invite your family" (fase 05).
2. PR-01 dua tab, PR-02 setelah join sukses (tulis `guardian.name` ke App Group).
3. PR-03 link: QR dan link sama-sama berisi `inviteUrl` https (D-alief-03); halaman `/join` membuka `shoo://join?code=`. Gagal → ketik kode manual. Deferred deep link (P1) → TODO E4.
4. Gerbang UI + uji dua simulator (Guardian membuat kode, Protected memasukkan) melawan backend lokal.
5. `ecc:security-reviewer` fokus T11 (link tidak pernah join tanpa konfirmasi pengguna).

## Verifikasi

```bash
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppTests/PairingTests
xcrun simctl openurl booted "shoo://join?code=1234"
```

## Kriteria selesai (DoD)

- [ ] GD-04, PR-01, PR-02, PR-03 (P0) sesuai "Selesai kalau" (screenshot + test).
- [ ] Dua simulator terhubung lewat kode dan lewat link (bukti di log).
- [ ] Semua 4 error join + `already_connected` punya pesan EN/ID yang jelas.
