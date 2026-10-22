# Log fase 14 — Pairing: GD-04, PR-01, PR-02, PR-03 (Alief, track c)

- **Status:** [r] — PR `feat/GD-04-PR-01-03-pairing`, reviewer @umarmuhdhor. **Bertumpuk di atas #42** (fase 13, belum di-merge): base PR = `main`, jadi diff PR ikut menampilkan commit #42 sampai #42 di-merge.
- **Model:** Claude Opus 5.5, mode auto. 22 Okt 2026.
- **Rencana:** `log/fase-14-plan.md` (ditulis langsung; subagent satu per satu dipakai untuk dua review).

## Ringkasan rencana

1. `DeepLink` (join/scan/activity, host undangan).
2. `ConnectModel` + `ConnectView` + `QRScannerView` + `ProtectedByView` (PR-01/02).
3. `FamilyCodeModel` + `FamilyCodeView` + `QRCode` (GD-04).
4. `AppEnvironment.open` + `RootView.onOpenURL` + Router (PR-03).
5. Wiring: onboarding Connect, sheet Connect di Shield, Family code dari Profile dan "Invite your family"; placeholder fase 02/05/06 dihapus.
6. String EN/ID, test, gerbang UI, uji dua simulator, review, PR.

## Checklist langkah (file fase "Langkah kerja")

- [x] 1. GD-04 dibuka dari Profile (`profile.familyCode`) dan "Invite your family" (`family.invite`, keluarga kosong) — sheet `FamilyCodeView`, alert placeholder dihapus.
- [x] 2. PR-01 dua tab (default Enter code, D-alief-C08), PR-02 setelah join sukses (`SessionStore` menulis `guardian.name` lewat `ApiRepository.joinFamily`, fase 13). Disconnect Profile → `leaveGuardian()` (fase 13, tidak berubah).
- [x] 3. PR-03: QR dan link sama-sama `inviteUrl` https (D-alief-03); `shoo://join?code=` dan `https://<host>/join?code=` hanya mengisi kode (T11, D-alief-C07). Gagal → ketik manual. Deferred deep link → TODO E4 (tetap terbuka).
- [x] 4. Gerbang UI (`qa/img/ui-14`) + uji dua simulator melawan backend lokal: `GUARD_UDID=1E36AEA3-98CB-4712-A4C1-224FA22D2462` ("Shoo Track C"), `PROT_UDID=4806EF91-BAF3-44F3-8A0A-6300B9C13B4B` ("Shoo Track C Prot", dibuat fase ini); semua perintah memakai UDID.
- [x] 5. `ecc:security-reviewer` fokus T11, lalu `ecc:swift-reviewer` (berurutan).

## File dibuat/diubah

- Baru: `App/DeepLink.swift`, `Features/Pairing/{ConnectModel,ConnectView,QRScannerView,QRCode,FamilyCodeModel,FamilyCodeView}.swift`.
- Dihapus: `Features/Onboarding/ConnectPlaceholderView.swift`.
- Diubah: `App/{AppConfig,AppEnvironment,RootView,Router}.swift`, `Data/MockRepository.swift` (link undangan mock memakai host Worker), `Features/Main/MainTabView.swift` (sheet Connect), `Features/Onboarding/OnboardingFlow.swift` (langkah Connect asli), `Features/Profile/ProfileView.swift`, `Features/Shield/{FamilyShieldView,ProtectedShieldView}.swift`, `Resources/Localizable.xcstrings` (+41 key EN/ID, −2 placeholder).
- Test baru: `Tests/PairingTests.swift` (`DeepLinkTests`, `ConnectModelTests`, `FamilyCodeModelTests`, `DeepLinkRoutingTests`), `UITests/{PairingUITests,PairingGateUITests,LivePairingUITests}.swift`. Diubah: `UITests/{OnboardingUITests,LiveBackendUITests}.swift` (`connect.continue` → `connect.skip`), `UITests/GuardianUITests.swift` (Invite membuka Family code, bukan alert).
- Plan: `log/fase-14-plan.md`, `log/fase-14.md`, `log/DECISIONS.md` (C07–C12), `PROGRESS.md` baris 14, `docs/mandates/alief.md` (GD-04, PR-01/02, PR-03), `qa/img/ui-14/*.png`.

## Hasil verifikasi (22 Okt 2026, Xcode, simulator iPhone 17 Pro iOS 27.0)

| Perintah | Hasil |
|---|---|
| `(cd ios && xcodegen)` | OK |
| `xcodebuild build-for-testing` | OK, tanpa warning baru dari file fase 14 |
| `xcodebuild test … -only-testing:ShooAppTests` | **262 test / 27 suite lulus** (fase 13: 233) |
| `xcodebuild test … -only-testing:ShooAppUITests` (mock) | RESULT_UI |
| `TEST_RUNNER_SHOO_SHOT_DIR=… PairingGateUITests` light + AX-XL, lalu dark | RESULT_GATE |
| `scratchpad/pair.sh` — `LivePairingUITests` di dua simulator bersamaan, `pnpm -C backend/api dev` (Supabase lokal) | 2/2 lulus: Guardian "Rina" menampilkan kode; Protected "Mom" join dengan **mengetik kode**; Protected "Dad" (install bersih) join lewat **`xcrun simctl openurl $PROT_UDID shoo://join?code=5446`** → iOS "Open in Shoo?" → kode terisi, tidak join sendiri (T11, dicek 2 s), tap Connect → "You're protected by Rina"; Guardian melihat "Connected 2/3" (anggota dibaca ulang tiap 5 s) |
| `psql` lokal: `family_links` 10 menit terakhir | `Mom → Rina 04:26:18`, `Dad → Rina 04:26:37` (UTC) |
| `git diff --stat $(git merge-base origin/main HEAD)..HEAD -- ios/ShooApp/Info.plist ios/ShooApp/*.entitlements` | kosong |
| `git diff --stat … -- contracts ios/project.yml ios/ShooShared ios/ShooExtension ios/ShooLiveActivity detector ai .github` | kosong |
| `grep -rn "print(" ios/ShooApp/Features/Pairing ios/ShooApp/App` | kosong |

Catatan uji: simulator tidak punya kamera, jadi tab Scan QR hanya teruji jalur "tidak tersedia" (`testScanTabExplainsWhenTheCameraCannotScan`) + parsing payload (`ConnectModelTests.scannedInviteFillsTheCode`). Pemindaian QR sungguhan diuji ulang di iPhone fisik pada fase 16 (QA-E2E).

## DoD + bukti

- [x] GD-04, PR-01, PR-02, PR-03 (P0) sesuai "Selesai kalau": screenshot `qa/img/ui-14/{connect,connect-error,protected-by,family-code}-*.png` + `pair-*.png`; test `PairingUITests` (6) + `PairingTests`.
- [x] Dua simulator terhubung lewat kode dan lewat link (tabel di atas + `qa/img/ui-14/pair-*.png` + `family_links`).
- [x] Semua error join punya pesan EN/ID jelas: `code_invalid`, `code_expired`, `family_full`, `too_many_attempts`/`rate_limited`, `already_connected`, offline, lainnya (`ConnectModelTests.everyJoinErrorHasItsMessage`, `messagesExistInBothLanguages`). Pesan error ada di footer, di atas tombol Connect, supaya tidak tertutup keyboard (gerbang UI).
- [x] Tidak ada edit di Info.plist/entitlements. Tab Scan QR aktif karena C3 (`NSCameraUsageDescription`) sudah masuk lewat #27.
- [x] Kamera diminta hanya saat tab Scan QR dibuka, tidak ada foto disimpan (P7, D-alief-C08). "Copy invite link" memakai pasteboard `.localOnly` + `.expirationDate` = umur kode (P8, `FamilyCodeModelTests.inviteCopyStaysLocalAndExpiresWithTheCode`).

## Gerbang UI

24 screenshot (`qa/img/ui-14/`): Connect, Connect + error, "You're protected by …", Family code × EN/ID × light/dark + AX-XL (light). Temuan dan perbaikan:

- HIGH (diperbaiki): dengan keyboard terbuka, footer + keyboard menutup kotak kode dan pesan error. Pesan error pindah ke footer; kotak kode digulir ke atas footer saat fokus dan saat error muncul (`ConnectView.showCodeField`). Terlihat di `pair-protected-2-link-filled.png`.
- Kotak kode dan kode besar ikut Dynamic Type (`@ScaledMetric`, dibatasi supaya 4 kotak muat di lebar iPhone SE).
- AX-XL: semua layar bisa digulir, tombol tetap ≥ 44 pt; teks tidak terpotong.
- VoiceOver: kotak kode = satu elemen "4-digit code"; error, "Invite link copied", dan QR yang ditolak diumumkan; QR punya label "QR code to join your family"; kode dibacakan per digit.

## Temuan review

| Review | Temuan | Ditangani |
|---|---|---|
| `ecc:security-reviewer` (T11) | 0 CRITICAL, 0 HIGH, 3 MEDIUM, 7 LOW. T11 lolos di semua jalur (cold launch, saat onboarding, saat Connect terbuka, Guardian, link rusak/asing, digit non-ASCII, `code` ganda) | MEDIUM: `http` hanya untuk Worker lokal yang sama host + port (`DeepLink.isLocalWorker`); "Not now" dan swipe-down dimatikan selama join; link saat sheet lain terbuka (lihat C12). LOW diperbaiki: kode tertunda dibuang saat background / registrasi Guardian; `isAvailable` + gagal `startScanning` → catatan; payload QR > 512 byte ditolak, catatan QR ditolak hilang saat ganti tab; jawaban anggota yang telat setelah Remove dibuang; kode yang datang setelah layar ditutup tidak dipakai; `inviteUrl` dari server dipakai untuk QR/salin hanya kalau link kita untuk kode itu. LOW diterima: rekam layar kode keluarga (pengguna merekam layarnya sendiri; kode berumur 60 s), pembedaan pesan error = kontrak + batas `too_many_attempts` di backend (fase 08) |
| `ecc:swift-reviewer` | 0 CRITICAL, 1 HIGH, 10 MEDIUM, 10 LOW | HIGH: jeda 700 ms sebelum Connect → urutan dari state (`Router.showConnect` / `sheetDismissed`, D-alief-C12). MEDIUM diperbaiki: refresh anggota tidak membekukan hitung mundur; `secondsLeft` ≤ 60; "Copied" di model (hilang saat kode baru); status kamera dibaca ulang setelah Settings; fokus setelah animasi; Dynamic Type kotak kode + kode besar; UI test tanpa `sleep`; jam test di balik lock + `timeLimit`. LOW diperbaiki: batal Remove tanpa alert; judul dialog stabil ("Remove from your family?"); `Scanner` → `QRScannerRepresentable`; QR yang sama hanya dijawab sekali + pengumuman VoiceOver; test routing `open()`. Ditolak dengan alasan: kode < 1 s dianggap 60 s (jam iPhone yang lebih cepat dari server akan meminta kode tiap detik); polling file di `LivePairingUITests` (uji opt-in lintas simulator); `UIPasteboard.general` sebagai default (test menyuntik fake); model sementara di `State(initialValue:)` (murah, tanpa efek samping sampai `.task`); kode dari link menimpa ketikan (link = aksi pengguna sendiri, tetap butuh tap) |

## Cek privasi Apple (SECURITY §3)

| # | Hasil |
|---|---|
| P1 | Manifest tidak berubah; tidak ada required-reason API baru (VisionKit, AVFoundation, UIPasteboard bukan kategori required-reason). OK |
| P2 | Tidak ada jenis data baru di server (kode keluarga + relasi keluarga sudah tercakup fase 08). Gambar kamera tidak dikumpulkan. OK |
| P3 | Remove anggota → `DELETE /family/members/{id}` seketika, daftar diperbarui; disconnect tidak berubah (fase 13). OK |
| P4 | Tidak ada penyimpanan baru: kode tertunda hanya di memori `Router`, dibuang saat background. OK |
| P5 | Link `http` hanya untuk Worker lokal Debug (host + port sama); Release hanya https. OK |
| P6 | Kode/token tidak pernah di-log; `Log.ui.error` dengan `.private`; tidak ada `print`. OK |
| P7 | Kamera diminta tepat waktu (tab Scan QR), hanya QR, tanpa rekam/simpan frame; ditolak → "Open Settings" + Enter code. OK |
| P8 | Salin undangan `.localOnly` + `.expirationDate` ≤ 60 s. OK |
| P9 | Tidak berubah. OK |
| P10 | Tidak berubah (fase 15). – |
| P11 | Tidak berubah (fase 16). – |
| P12 | Tidak berubah. – |
| P13 | Layar kode memakai `.privacyCover()`; Remove langsung hilang dari daftar dan server; jawaban telat tidak mengembalikan anggota yang dihapus. OK |

## Deviasi

- PR bertumpuk di atas #42 (fase 13 belum di-merge).
- "Invite your family" di Family Shield hanya muncul saat keluarga kosong (desain fase 05); dengan anggota, Family code dibuka dari Profile.
- Status sheet "Turn on" Shield pindah ke `Router` (D-alief-C12) — perubahan kecil di layar fase 04.

## Placeholder aktif

- `App/AppConfig.swift`: `TODO(sync:imelda)` URL layanan AI (D-alief-C05).
- Fase 15: `shoo://scan/{id}` dan `shoo://activity` sudah di-parse tapi masih mendarat di Shield; token APNs di `NotificationPermission.swift`.
- Deferred deep link setelah install (PR-03 P1): TODO E4.

## LANGKAH MANUAL

Tidak ada untuk fase 14 (tidak ada aksi cloud). Backend tidak berubah.

## Catatan handoff

- Uji dua simulator: `TEST_RUNNER_SHOO_LIVE_BACKEND=1 TEST_RUNNER_SHOO_PAIR_DIR=<dir> TEST_RUNNER_SHOO_SHOT_DIR=<dir>`; jalankan `LivePairingUITests/testGuardianShowsTheFamilyCode` di `GUARD_UDID` dan `testProtectedJoinsByCodeThenByLink` di `PROT_UDID` bersamaan; host menunggu `link-ready` lalu `xcrun simctl openurl $PROT_UDID "shoo://join?code=$(cat <dir>/code.txt)"`. `INVITE_BASE_URL` lokal = `http://localhost:8787` (diterima hanya di Debug).
- Gerbang UI: `xcrun simctl ui <udid> appearance light|dark` lalu `TEST_RUNNER_SHOO_SHOT_DIR=<dir> TEST_RUNNER_SHOO_GATE_APPEARANCE=… [TEST_RUNNER_SHOO_GATE_AXXL=1] … -only-testing:ShooAppUITests/PairingGateUITests`.
- `xcodebuild test-without-building` kadang menggantung setelah test selesai di Xcode ini; hasil sudah tertulis di log, proses boleh dihentikan.
- Refactor setelah MVP: satu `enum ActiveSheet` untuk semua sheet (C12).
