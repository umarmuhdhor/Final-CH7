# Log fase 05 — Guardian & Family mode: GD-01, GD-02, GD-03, GD-05 (Alief, track app)

- **Status:** [r] — PR `feat/GD-family-mode`, reviewer @umarmuhdhor. **Stacked on #19** (fase 04) → #18 → #14. Fase 02 (#16) belum di rantai (digabung ke cabang fase 06 sebelum 06Q).
- **Model:** Claude Opus 5.5, mode auto. Mulai dan selesai 22 Okt 2026.
- **Rencana:** `log/fase-05-plan.md`. Sumber: `fase-05-guardian-family.md`, PRD §8.3, fixture `family-members.json`, `activity-family.json`.

## Checklist langkah

- [x] 1. GD-01: Shield Guardian dengan Family mode Off = layar sendiri (`ProtectedShieldView(perspective: .guardian)`): "You're protected" / "You're not protected" + Turn on (Settings, `TODO(sync:alief)` sheet fase 02), kartu blokir terakhir milik sendiri, tanpa "Protected by".
- [x] 2. GD-02: tombol toolbar kiri atas "Family: On/Off" (hanya Guardian, kedua tab), diingat di `AppSettings.familyModeOn`, diumumkan VoiceOver; Safari Guardian tetap dilindungi (hanya tampilan) (D-alief-A15).
- [x] 3. GD-03: `FamilyShieldModel` + `FamilyShieldView`: kepala "You look after Mom and Dad" + jumlah tidak terhubung, kartu ramping per orang (maks 3) dengan status, host+path, waktu; "Not connected" hanya bila `extensionActive == false`; tap → Detail scan yang ditampilkan (D-alief-A16); kosong → "Invite your family" (alert placeholder sampai fase 14).
- [x] 4. GD-05: Family Activity `owner=family` dengan chip orang Everyone / You / nama + chip status, nama pemilik di baris, catatan "Only your own history? Set Family to Off."; Off → Activity sendiri (D-alief-A17).
- [x] 5. Mock: skenario `oneMember`, `threeMembers` (`-mock.scenario`).
- [x] 6. Gerbang UI, review `ecc:swift-reviewer` lalu `ecc:a11y-architect` (berurutan), perbaikan, cek P1–P13, verifikasi.

## File dibuat/diubah

- Baru: `Features/Shield/{FamilyShieldModel,FamilyShieldView}.swift` (`GuardianShieldView`, `FamilyShieldView`, `FamilyMemberCard`).
- Dihapus: `Features/Shield/ShieldPlaceholderView.swift`.
- Diubah: `Features/Shield/ProtectedShieldView.swift` (`ShieldPerspective`), `Features/Activity/{ActivityModel,ActivityView}.swift` (`ActivityPerson`, `people`, `ChoiceChips`/`PersonChips`), `Features/Main/MainTabView.swift` (toggle, akar tab Guardian), `Components/StatusChip.swift` (`ScanBadge(status:)`), `Data/MockRepository.swift` (skenario), `Resources/Localizable.xcstrings` (+25 key EN/ID).
- Test: `Tests/FamilyShieldModelTests.swift`, `Tests/ActivityModelTests.swift` (+5), `Tests/TestDoubles.swift` (`failingOwner`), `UITests/GuardianUITests.swift` (5).
- Plan: `log/fase-05-plan.md`, `log/fase-05.md`, `log/DECISIONS.md` (A15–A17), `PROGRESS.md` baris 05, `qa/img/ui-05/*.png` (48 file, diperkecil 50 %).

## Hasil verifikasi (22 Okt 2026, Xcode 27.1, simulator "Shoo App Track" iPhone 17 Pro iOS 26.4, `-destination id=8646F92B-…`)

| Perintah | Hasil |
|---|---|
| `(cd ios && xcodegen)` | OK |
| `xcodebuild test … -scheme Shoo` (semua target) | Swift Testing **127 test / 13 suite lulus** (fase 04: 115 → +12) · XCUITest 18: 17 lulus di run penuh, 1 gagal (`familyModeToggle` tidak ditemukan sebagai `buttons` setelah trait `.isToggle`) → query diganti identifier, `-only-testing:ShooAppUITests/GuardianUITests` **5/5 lulus** |
| `grep -rn "print(" ios/ShooApp --include='*.swift'` | kosong |
| `grep -rn "com\.shoo\|group\.com" ios/ShooApp --include='*.swift'` | kosong |
| `git diff --stat 5fa2eda..HEAD -- contracts ios/project.yml ios/ShooShared ios/ShooExtension docs` | kosong |
| `grep -rn "TODO(sync" ios/ShooApp` | 5 (baru: Family code fase 14; Shield Guardian fase 05 selesai, dihapus) |
| `plutil -lint ios/ShooApp/PrivacyInfo.xcprivacy` | OK (tidak berubah) |

Catatan TDD: `FamilyShieldModelTests` dan test filter orang ditulis dulu (gagal kompilasi: `FamilyShieldModel`, `ActivityPerson`, skenario mock belum ada). Test perbaikan review (satu anggota gagal, anggota dihapus) ditulis sebelum perbaikan.

## DoD + bukti

- [x] GD-01: `qa/img/ui-05/self-{active,off}-*.png`; `GuardianUITests.testFamilyModeIsRememberedAfterRelaunch` (tanpa "Protected by").
- [x] GD-02 toggle diingat setelah app ditutup: `GuardianUITests.testFamilyModeIsRememberedAfterRelaunch` (terminate + launch tanpa argumen).
- [x] GD-03: `qa/img/ui-05/family-{0,1,2,3}-*.png` (0/1/2/3 anggota; Dad = Not connected di 2 dan 3); `FamilyShieldModelTests` (anggota per skenario, Not connected, scan yang dibuka, gagal); `GuardianUITests.testFamilyCardOpensDetailWithVerdictButtons`, `testEmptyFamilyOffersInvite`.
- [x] GD-05: `qa/img/ui-05/activity-{family,own}-*.png`; `ActivityModelTests.personFilterShowsOnlyThatPerson`, `personAndStatusFiltersCombine`, `removedPersonFallsBackToEveryone`; `GuardianUITests.testFamilyActivityFiltersByPerson`, `testFamilyModeOffShowsOwnActivityOnly`.
- [x] Tombol validasi tampil di Detail untuk item keluarga: `GuardianUITests.testFamilyCardOpensDetailWithVerdictButtons` (+ `DetailUITests` fase 03 untuk item sendiri).

## Gerbang UI (PROMPT langkah 7)

Screenshot `qa/img/ui-05/<layar>-<en|id>-<light|dark|xl>.png`: `self-active`, `self-off`, `family-0`, `family-1`, `family-2`, `family-3`, `activity-family`, `activity-own`.

Review `ecc:a11y-architect`: 1 HIGH, 3 MEDIUM, 3 LOW.

| Temuan | Sev | Tindakan |
|---|---|---|
| Toggle toolbar hanya ikon, status hanya warna | HIGH | Diperbaiki: tombol "Family: On/Off" + ikon terisi/garis, VoiceOver "Family mode, On/Off", trait toggle, hint (D-alief-A15) |
| Beralih mode tanpa pengumuman, judul sama | MEDIUM | Diperbaiki: pengumuman + judul "Family" / "Family activity" |
| Ikon peringatan terbaca ganda | MEDIUM | Diperbaiki: ikon `accessibilityHidden` |
| Chevron hilang di AX → kartu tombol tidak terlihat beda | MEDIUM | Diterima: VoiceOver punya hint + trait tombol; kartu tanpa tautan tidak lagi diredupkan. Re-skin |
| Oranye ±2,2:1 | LOW | Diperbaiki: oranye gelap `#B85400` |
| Hint kosong / trait `.isButton` ganda | LOW | Diterima (tidak berdampak) |
| Header setelah `.combine` | LOW | Diterima; cek di 06Q dengan Accessibility Inspector |

## Temuan review (langkah 8)

`ecc:swift-reviewer`: 1 HIGH, 4 MEDIUM, 4 LOW. Privasi bersih.

| # | Temuan | Tindakan |
|---|---|---|
| H1 | Kartu tanpa situs = tombol `.disabled` → diredupkan | Diperbaiki: hanya kartu dengan scan yang jadi tombol |
| M2 | Satu anggota gagal → seluruh keluarga gagal | Diperbaiki: task group tanpa throw; test `oneMembersScansFailingDoesNotHideTheFamily` |
| M3 | Tap bisa membuka scan berbeda dari yang ditampilkan | Diperbaiki: cocokkan `url` + `detectedAt`; usulan `lastScan.id` ke kontrak (PR) |
| M4 | Chip orang basi setelah anggota dihapus | Diperbaiki: dibaca ulang tiap load/refresh, fallback Everyone; test `removedPersonFallsBackToEveryone` |
| M5 | `try?` menelan pembatalan | Diperbaiki: `do/catch` + `Task.isCancelled` |
| L6 | Toggle me-reset tab Activity | Diterima (Activity memang berganti owner); layar Protected tidak lagi ikut reset |
| L7 | `ToolbarItem` kosong untuk Protected | Diperbaiki: `if` di luar `ToolbarItem` |
| L8 | Refresh terbaru dibatalkan → state lama | Diterima: `.task(id: scenePhase)` berikutnya memulihkan |
| L9 | Kartu basi setelah anggota dihapus di Profile | Ditunda ke fase 06 (PF-01 hapus anggota → refresh) |

## Cek SECURITY §3 P1–P13 (diff fase 05)

| # | Hasil |
|---|---|
| P1 | Tidak berubah; `familyModeOn` di `UserDefaults` standar (preferensi tampilan, CA92.1 sudah ada) |
| P2–P5 | Tidak ada data/jaringan/penyimpanan baru (mock) |
| P6 | `Log.ui.error(StaticString, error)` → `.private`; `print(` kosong |
| P7, P8, P10–P12 | Tidak disentuh |
| P9 | Kartu keluarga hanya host+path (D-alief-A11); tidak ada fetch favicon/screenshot; penutup app switcher di `FamilyShieldView` |
| P13 (usulan PR #12) | Tidak ada salinan baru di disk |

## Catatan handoff

- Fase 06 (PF-01): setelah hapus anggota, Shield Family dan Activity membaca ulang (L9).
- Fase 14: "Invite your family" → Family code (`TODO(sync:alief)` di `FamilyShieldView`).
- Merge 02 sebelum 06Q: tombol Turn on (Guardian juga) → sheet `TurnOnExtensionView`; banner pengingat notifikasi Guardian (D-alief-A08) dipasang di `GuardianShieldView`.
- Usulan kontrak (untuk Umar, tidak blocker): `lastScan.id` di `GET /family/members`.
