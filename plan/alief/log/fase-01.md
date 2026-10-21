# Log fase 01 — Fondasi app + target test (Alief, track app)

- **Status:** [r] — PR `feat/APP-foundation` dibuka (nomor di PROGRESS). PR 1 `chore/APP-test-targets` = #8, MERGED (e980b7f).
- **Model:** Claude Opus 5.5. Mulai 21 Okt 2026 (sesi track app pertama, macet di tengah); dilanjutkan 22 Okt 2026 dari commit WIP 8ed31ba (mode LANJUT).
- **Rencana lengkap:** `log/fase-01-plan.md`.

## Ringkasan planner

Fondasi untuk semua layar Fase A: protocol `ShooRepository` (bentuk persis `contracts/api.md`) + `MockRepository` dari salinan `contracts/fixtures`, tab Shield / Activity + tombol profile, `Router`, `AppSettings` (bahasa in-app, mode, onboarding), String Catalog EN + ID, komponen (`ScoreRing`, `StatusChip`, `AvatarView`, `SiteIcon`, `EmptyStateView`), `ExtensionStatus` dari heartbeat App Group, `Log` (`os.Logger` `.private`), privacy manifest, dan draf CI. Layar fitur masih placeholder (diisi fase 02–06).

## Checklist langkah

- [x] 1. Target test (PR #8, merged). Commit duplikat `610da82` di-drop saat rebase ke `origin/main`; commit plan-sync `5345f10` di-skip (sudah ada di main lewat #7).
- [x] 2. Protocol `ShooRepository` + `Data/Models.swift` (tipe app, `APIErrorCode` set terbuka, `RepositoryError`).
- [x] 3. `MockRepository` (actor, latensi 300 ms, mode Guardian/Protected, skenario `standard`/`empty`, kode join ajaib → D-alief-A01).
- [x] 4. Navigasi: `RootView` → onboarding placeholder / `MainTabView`; `Router` (tab, path per tab, sheet profile).
- [x] 5. Lokalisasi: `Localizable.xcstrings` EN + ID; cara bahasa in-app → D-alief-A02.
- [x] 6. Avatar: 12 SF Symbol di lingkaran warna (`AvatarCatalog`). Re-skin saat desain final datang.
- [x] 7. Komponen: `ScoreRing`, `StatusChip`/`ScanBadge`, `SiteIcon` (monogram, D-alief-A03), `EmptyStateView`.
- [x] 8. Draf CI `ios/ShooApp/ci/ios-app.yml` (inert, TODO C2).
- [x] 9. Gerbang UI (lihat bawah).
- [x] Review `ecc:swift-reviewer` + cek SECURITY §3 P1–P13, perbaikan, verifikasi.

## File dibuat/diubah (semua di `ios/ShooApp/` dan `plan/alief/`)

- `App/`: `AppConfig`, `AppEnvironment`, `AppSettings`, `RootView`, `Router` · `ShooApp.swift` (memakai `RootView`) · `ContentView.swift` dihapus.
- `Data/`: `ShooRepository`, `Models`, `MockRepository`, `ExtensionStatus`, `Fixtures/*.json` (salinan byte-identik + `activity-family.json` di-inline).
- `Components/`: `ScoreRing`, `StatusChip`, `AvatarView`, `SiteIcon`, `EmptyStateView` · `Debug/ComponentGalleryView` (DEBUG saja).
- `Features/`: `Onboarding/OnboardingPlaceholderView`, `Main/MainTabView`, `Shield/ShieldPlaceholderView`, `Activity/ActivityPlaceholderView`, `Profile/ProfilePlaceholderView`.
- `Support/`: `AppLanguage`, `L10n`, `Formatters`, `ScoreLevel`, `Log`.
- `Resources/Localizable.xcstrings`, `PrivacyInfo.xcprivacy`, `ci/ios-app.yml`.
- Test: `Tests/{AppSettings,ComponentLogic,ExtensionStatus,Fixture,Formatter,Localization,MockRepository}Tests.swift`, `UITests/SmokeUITests.swift`.
- Plan: `log/fase-01-plan.md`, `log/fase-01.md`, `log/DECISIONS.md` (A01–A03), `PROGRESS.md` baris 01, `TODO.md` C1, `qa/img/ui-01/*.png`.

## Hasil verifikasi (22 Okt 2026, Xcode 27.1, simulator iPhone 17 Pro iOS 26.4.1)

| Perintah | Hasil |
|---|---|
| `(cd ios && xcodegen)` | OK |
| `xcodebuild test … -scheme Shoo` (semua target) | `** TEST SUCCEEDED **` · Swift Testing: **53 test di 7 suite lulus** (0,09 s) · XCUITest `SmokeUITests`: **3/3 lulus** (25 s) · 0 warning compiler di `ios/ShooApp` |
| `plutil -lint ios/ShooApp/PrivacyInfo.xcprivacy` | OK; ikut ter-bundle di `Shoo.app` |
| `git diff origin/main...HEAD -- ios/project.yml` | kosong (edit project.yml hanya di PR #8) |
| `grep -rn "TODO(sync" ios/ShooApp` | 3 placeholder (lihat bawah) |
| `grep -rn "print(" ios/ShooApp --include='*.swift'` | kosong |
| `grep -rn "com\.shoo\|group\.com" ios/ShooApp --include='*.swift'` | kosong |

Catatan: `source plan/alief/ref/sim.sh` memilih nama `iPhone 17 Pro`, tapi ada tiga simulator bernama sama (iOS 26.3/26.4/26.5) dan run pertama gagal `Unable to find a device matching the provided destination specifier` (exit 70). Run berikutnya memakai `-destination id=<UDID>`. Lihat Catatan handoff.

## DoD + bukti

- [x] PR target test dibuka; C1 ditulis — PR #8 MERGED, TODO C1 `[x]`.
- [x] Semua fixture terdecode ke model `ShooShared` — `FixtureTests` (5 fixture scan, `activity-family`, `family-members`, salinan == kontrak byte demi byte, inline == daftar `$ref`).
- [x] `MockRepository` memenuhi seluruh protocol termasuk error kontrak — `MockRepositoryTests` (27 test: filter owner/status, cursor, cursor salah, verdict per domain+pemilik + ganti verdict, `verdict_not_allowed`, join `code_invalid`/`code_expired`/`family_full`/`too_many_attempts`/`already_connected`, kode non-ASCII, mode salah `forbidden`, member dihapus → scan-nya hilang, `updateMe` all-or-nothing, skenario kosong).
- [x] Bahasa in-app EN ↔ ID terbukti — `LocalizationTests` + `SmokeUITests.testLanguageSwitchesLiveFromProfile` (ganti live dari Profile) + screenshot `*-id-*.png`. Cara: D-alief-A02.
- [x] `PrivacyInfo.xcprivacy` sesuai P1 — `NSPrivacyTracking=false`, domain kosong, UserDefaults `CA92.1` + `1C8F.1`, data Name / BrowsingHistory / OtherUserContent / DeviceID untuk App Functionality, tidak untuk tracking. Kode alasan dicek di docs Apple (`developer.apple.com/tutorials/data/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons.json`): `CA92.1` = hanya app itu sendiri, `1C8F.1` = anggota App Group yang sama. `Support/Log.swift` membungkus `os.Logger`, nilai `.private` (P6).
- [x] Tab Shield / Activity + tombol profile tampil di simulator — `qa/img/ui-01/shield-*`, `activity-*`, `profile-*` (EN + ID) + `SmokeUITests`.
- [x] Draf `ios-app.yml` ada — `ios/ShooApp/ci/ios-app.yml`.

## Gerbang UI (PROMPT langkah 7)

Screenshot: `plan/alief/qa/img/ui-01/<layar>-<en|id>-<light|dark|xl>.png` untuk `onboarding`, `shield`, `activity`, `profile`, `gallery` (galeri komponen DEBUG). `xl` = Dynamic Type `accessibility-extra-large` (AX3). Diambil dengan `simctl` (status bar 09:41), launch argument D-alief-A01.

Review `apple-design` + `ecc:a11y-architect` (22 Okt): **0 HIGH**, 4 MEDIUM, 8 LOW.

| Temuan | Sev | Tindakan |
|---|---|---|
| `StatusChip` teks oranye/hijau ≈ 2:1 (dari swift-reviewer H3) | HIGH | Diperbaiki: label `.primary` |
| `ScoreRing` angka ukuran tetap, tidak ikut Dynamic Type | MEDIUM | Diperbaiki: `@ScaledMetric` (maks 2×), lihat `gallery-*-xl.png`. Di galeri DEBUG tiga ring berjajar jadi terpotong di AX-XL; DT-01 hanya satu ring (cek di gerbang UI fase 03) |
| `ScoreRing` VoiceOver hanya "41%", level risiko hanya lewat warna | MEDIUM | Fase 03 (DT-01): tambah judul level terlokalisasi di nilai aksesibilitas |
| Busur kuning/oranye `ScoreRing` < 3:1 di latar putih | MEDIUM | Re-skin (warna aset dengan varian kontras tinggi); angka persen tetap membawa nilainya |
| Deskripsi `EmptyStateView` abu sekunder ≈ 3,4:1 | MEDIUM | Gaya bawaan `ContentUnavailableView`; ditinjau ulang saat re-skin |
| Pilihan bahasa dibaca dengan suara bahasa yang salah | LOW | Diperbaiki: nama bahasa sebagai `AttributedString` dengan `languageIdentifier` = kode bahasa (efek di VoiceOver BELUM DIVERIFIKASI di perangkat; cek ulang di fase 06) |
| Judul onboarding bukan heading | LOW | Diperbaiki: `.isHeader` (layar diganti fase 02) |
| Avatar putih di kuning/mint/cyan, trait `.isImage`, hint tombol profile, chip wrap di xl, monogram `.secondary`, label tab tetap kecil (batas sistem) | LOW | Fase 02 (picker avatar tidak ada di MVP; avatar acak), fase 06 (profile), re-skin |

Target sentuh ≥ 44 pt: tombol profile dan tombol onboarding lulus. Ikon dekoratif disembunyikan dari VoiceOver. Chip tidak hanya mengandalkan warna.

Perbandingan PRD §7: struktur dua tab + avatar/profile kanan atas sesuai wireframe. Isi Shield/Activity/Profile masih placeholder (fase 04–06). **Re-skin saat desain final datang** (warna, ilustrasi, avatar).

## Temuan review

`ecc:swift-reviewer` (22 Okt): 4 HIGH, 10 MEDIUM, 8 LOW.

| # | Temuan | Tindakan |
|---|---|---|
| H1 | `completeOnboarding` membuat `MockRepository` baru → skenario `-mock.scenario` dan latensi hilang | Diperbaiki: `MockRepository.switching(to:)` menyalin konfigurasi; test `completeOnboardingKeepsMockScenario` |
| H2 | Scan member yang sudah dihapus tetap terlihat (family dihitung dari pemilik fixture) | Diperbaiki: family = saya + member; test `removedMemberScansAreNoLongerVisible` |
| H3 | Teks `StatusChip` oranye/hijau di atas tint 15 % ≈ 2:1 | Diperbaiki: label `.primary`, warna di ikon + latar |
| H4 | Model `ShooShared` tidak `Sendable` | Tidak diubah: struct/enum internal di modul yang sama mendapat `Sendable` implisit; build tanpa warning. Kalau pindah ke Swift 6 / modul terpisah → usulan ke Umar |
| M | `already_connected` hanya lewat kode ajaib; `updateMe` sebagian; sort tanpa tie-break; test `throws: RepositoryError.self` terlalu longgar; celah test | Diperbaiki + 9 test baru |
| M/L | Kontras avatar putih di kuning/mint (dekoratif, `accessibilityHidden`), font `SiteIcon` tetap ukuran (`ScoreRing` sudah diperbaiki di gerbang UI), `CancellationError` dari mock, desimal detik ISO 8601 | Ditunda: avatar & font ikut re-skin / fase 03; `CancellationError` + `.iso8601` pecahan detik → fase 13 (`ApiRepository`) |

### SECURITY §3 P1–P13 (diff fase ini)

| # | Status |
|---|---|
| P1 | ✅ manifest ada, lint OK, kode alasan dicek di docs Apple |
| P2 | – fase 16; manifest sudah konsisten dengan 4 jenis data P2 |
| P3 | ✅ `AppConfig.dataDeletionEnabled = false` sampai C19; `AppSettings.reset()` siap dipakai |
| P4 | ✅ app tidak menulis App Group di fase ini; preferensi app di `UserDefaults.standard` (bahasa, mode, onboarding) tanpa data sensitif |
| P5 | ✅ tidak ada `NSAllowsArbitraryLoads`; `http://localhost:8787` hanya `#if DEBUG` dan belum dipakai (Mock) |
| P6 | ✅ `Log` → `os.Logger`, nilai `.private`, tanpa `print`, token tidak pernah di-log |
| P7 | ✅ tidak ada izin diminta; kamera di belakang `AppConfig.cameraEnabled = false` |
| P8 | – fase 14 |
| P9 | ✅ tidak ada screenshot dimuat; favicon situs penipuan tidak diunduh (D-alief-A03) |
| P10–P12 | – fase 11/15/16 |
| P13 | ✅ data mock hanya di memori; tidak ada cache/salinan data pengguna |
| SDK pihak ketiga | ✅ tidak ada |

## Deviasi

- Ukuran halaman mock + kode ajaib + launch argument: D-alief-A01.
- `navigationTitle(localized:)` alih-alih `navigationTitle(Text)`: D-alief-A02.
- `SiteIcon` tanpa favicon: D-alief-A03.

## Placeholder aktif

- `App/AppConfig.swift` — `TODO(sync:alief)` URL Worker cloud (fase 12 sudah deploy `https://shoo-api.afindo-mi01.workers.dev`; diganti di fase 13 bersama `ApiRepository`).
- `App/AppEnvironment.swift` — `TODO(sync:alief)` `ApiRepository` (fase 13).
- `Features/Main/MainTabView.swift` — `TODO(sync:alief)` `DetailView` (fase 03).

## LANGKAH MANUAL

Tidak ada.

## Catatan handoff

- Fase 02–06 memakai `MockRepository`, `AppSettings`, `Router`, `L10n`, komponen. Fase 13 menambah `ApiRepository` di protocol yang sama; tangani `CancellationError` dan tanggal ISO 8601 dengan pecahan detik di sana.
- `ref/sim.sh` memilih nama simulator yang bisa ganda (beberapa runtime). Usul untuk plan: pilih UDID (`xcrun simctl list devices available -j`) dan pakai `-destination id=$SIM_ID`.
- Launch argument DEBUG untuk screenshot: `-debug.tab activity`, `-debug.profile YES`, `-debug.gallery YES`.
