# Fase 14 — Pairing: GD-04, PR-01, PR-02, PR-03

| Field | Nilai |
|---|---|
| Track | c |
| Branch | `feat/GD-04-PR-01-03-pairing` |
| Prasyarat | 13; C3 (`NSCameraUsageDescription` di `project.yml` oleh Umar) untuk tab Scan QR |
| Requirement | GD-04, PR-01, PR-02, PR-03 (P0 link; deferred deep link = P1) |
| Model | Opus 5.5 · `apple-design`, `ecc:swiftui-patterns`, `ecc:swift-concurrency-6-2` |
| Fase berikutnya | 15 |

## Tujuan

Keluarga terhubung lewat QR, kode 4 digit, atau link undangan WhatsApp.

## Bacaan wajib

- PRD §8.2 PR-01..03, §8.3 GD-04, §10 risiko kode 4 digit
- `ref/R4` §1–§2, `ref/R3` §4 (`/join` page), `SECURITY.md` T2, T11, T13, `log/DECISIONS.md` D-alief-03, D-alief-21
- `ios/project.yml` (URL scheme `shoo` sudah ada). Info.plist **di-generate XcodeGen** dari `project.yml` milik Umar: jangan diedit. `NSCameraUsageDescription` = permintaan C3. Kalau belum ada saat fase ini: tab Scan QR menampilkan "Enter code" saja (feature flag `AppConfig.cameraEnabled`); selesaikan fase, buka PR, status `[r]` + "pending C3" di Ringkasan (PROMPT 6h), tab Scan QR diuji ulang di fase 16

## Output

- `Features/Pairing/FamilyCodeView` (Guardian): QR (`CoreImage.CIQRCodeGenerator` berisi `inviteUrl`), kode besar, hitung mundur 60 s lalu kode baru otomatis, "Copy invite link" (teks undangan EN/ID + `inviteUrl`), daftar terhubung x/3 + hapus
- `Features/Pairing/ConnectView` (Protected): tab Scan QR (`AVCaptureSession` / `DataScannerViewController`) dan Enter code (4 kotak digit), pesan error jelas per kode error kontrak + coba lagi
- `Features/Pairing/ProtectedByView`: "You're protected by [nama]" + avatar guardian dari respons join (disimpan `SessionStore`) → lanjut ke ON-04 → ON-05 (alur fase 02), lalu Home
- `onOpenURL` untuk `shoo://join?code=` → ConnectView dengan kode terisi + konfirmasi (T11); link lain/rusak → Shield (kontrak "Deep links"; `scan`/`activity` dirutekan di fase 15)
- Test: hitung mundur + refresh, parsing URL/QR (`https://…/join?code=` dan `shoo://join?code=`), pemetaan error ke pesan EN/ID, daftar x/3

## Langkah kerja

1. GD-04 dibuka dari Profile (fase 06) dan tombol "Invite your family" (fase 05).
2. PR-01 dua tab, PR-02 setelah join sukses (`SessionStore` menulis `guardian.name` + menyimpan avatar). Disconnect (fase 06 tombol Profile) → `leaveGuardian()` → `guardian.name` dihapus.
3. PR-03 link: QR dan link sama-sama berisi `inviteUrl` https (D-alief-03); halaman `/join` membuka `shoo://join?code=`. Gagal → ketik kode manual. Deferred deep link (P1) → TODO E4.
4. Gerbang UI + uji dua simulator (Guardian membuat kode, Protected memasukkan) melawan backend lokal. Simpan UDID tiap simulator (`GUARD_UDID`, `PROT_UDID`) dan pakai UDID, bukan `booted`, di semua perintah `simctl`.
5. `ecc:security-reviewer` fokus T11 (link tidak pernah join tanpa konfirmasi pengguna).

## Verifikasi

```bash
source plan/alief/ref/sim.sh
(cd ios && xcodegen)
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppTests/PairingTests
# dua simulator menyala: isi PROT_UDID dari `xcrun simctl list devices booted` (jangan andalkan `booted`)
xcrun simctl openurl "${PROT_UDID:-booted}" "shoo://join?code=1234"
git diff --stat origin/main...HEAD -- ios/ShooApp/Info.plist ios/ShooApp/*.entitlements   # harus kosong
```

## Kriteria selesai (DoD)

- [ ] GD-04, PR-01, PR-02, PR-03 (P0) sesuai "Selesai kalau" (screenshot + test).
- [ ] Dua simulator terhubung lewat kode dan lewat link (bukti di log).
- [ ] Semua 4 error join + `already_connected` punya pesan EN/ID yang jelas.
- [ ] Tidak ada edit di Info.plist/entitlements; tab Scan QR aktif hanya kalau C3 sudah di-merge.
- [ ] Kamera diminta hanya saat tab Scan QR dibuka, tidak ada foto disimpan (P7); "Copy invite link" pakai pasteboard `.localOnly` + `.expirationDate` (P8, test).
