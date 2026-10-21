# Log fase 02 — Onboarding ON-01 … ON-05 (Alief, track app)

- **Status:** [r] — PR dibuka (nomor di PROGRESS), stacked on #14 (`feat/APP-foundation`).
- **Model:** Claude Opus 5.5. 22 Okt 2026. Rencana: `log/fase-02-plan.md`.

## Ringkasan

Pengguna baru menyelesaikan onboarding sampai Home: 3 slide + Skip, nama 1–20 karakter, pilih mode permanen (registrasi `MockRepository.registerDevice` → avatar acak), Connect (placeholder Protected), ON-04 nyalakan extension (langkah per versi iOS, `SFSafariSettings` di iOS 26.2+, cek status saat kembali ke app, video tutorial dengan PiP), ON-05 izin notifikasi (Guardian wajib menjawab, Protected boleh lewati) + banner pengingat di Shield.

## Checklist langkah

- [x] 1. ON-01 Splash: `TabView(.page)` 3 slide, titik indikator, Skip/Next/Get started.
- [x] 2. ON-02 Nama: `NameRule` (trim, grapheme, tolak nama yang hanya karakter tak terlihat), tombol nonaktif sampai valid, pesan error EN/ID + diumumkan VoiceOver.
- [x] 3. ON-03 Mode: dua kartu, peringatan permanen, `AppEnvironment.register` → `settings.chooseMode` (sekali). Sapaan "Hi, [nama]" + avatar acak (bukan inisial).
- [x] 4. ON-04: `ExtensionSetup` + `TurnOnExtensionView` + `TutorialVideoPlayer` (D-alief-A06, A07). Off → tetap; Active (saat `scenePhase == .active`) → ON-05.
- [x] 5. ON-05: `NotificationPermission` (D-alief-A08); `NotificationReminderBanner` di Shield.
- [x] 6. Connect placeholder Protected (`TODO(sync:alief)` fase 14).
- [x] 7. Gerbang UI, review, verifikasi.

## File dibuat/diubah

- Baru: `Features/Onboarding/{OnboardingModel, OnboardingFlow, SplashView, NameView, ModeView, GreetingView, ConnectPlaceholderView, TurnOnExtensionView, ExtensionSetup, TutorialVideoPlayer, NotificationPermissionView}.swift`, `Support/NotificationPermission.swift`, `Components/NotificationReminderBanner.swift`, `Resources/onboarding-tutorial-placeholder.mp4`, `Tests/OnboardingTests.swift`, `UITests/OnboardingUITests.swift`.
- Diubah: `App/AppEnvironment.swift` (`register`, `finishOnboarding`, `notifications`, `extensionStatus`, hook DEBUG), `App/AppSettings.swift` (`chooseMode`, `onboardingConnectPassed`, `clear`), `App/RootView.swift`, `Features/Shield/ShieldPlaceholderView.swift`, `Data/MockRepository.swift` (hapus `switching(to:)`, digantikan registrasi), `Resources/Localizable.xcstrings` (+48 key EN/ID), `Tests/{AppSettings,Localization}Tests.swift`.
- Dihapus: `Features/Onboarding/OnboardingPlaceholderView.swift`.
- Plan: `log/fase-02-plan.md`, `log/fase-02.md`, `log/DECISIONS.md` (A04–A08), `PROGRESS.md` baris 02, `qa/img/ui-02/*.png`.

## Hasil verifikasi (22 Okt 2026, Xcode 27.1, simulator khusus "Shoo App Track" iPhone 17 Pro iOS 26.4)

| Perintah | Hasil |
|---|---|
| `xcodebuild test … -scheme Shoo` (semua target) | `** TEST SUCCEEDED **` · Swift Testing **78 test / 10 suite lulus** · XCUITest **10/10 lulus** (`OnboardingUITests` 7, `SmokeUITests` 3) · 0 warning compiler |
| `grep -rn "print(" ios/ShooApp --include='*.swift'` | kosong |
| `grep -rn "App-prefs\|com\.shoo\|group\.com" … --include='*.swift'` | hanya komentar "Never uses `App-prefs:`" |
| `git diff origin/main...HEAD -- ios/project.yml contracts ios/ShooShared` | kosong |

Catatan: run pertama memakai simulator yang sama dengan job screenshot → 2 UI test gagal karena app diluncurkan ulang oleh job lain. Sejak itu test dan screenshot memakai simulator khusus `8646F92B-…` dan tidak berjalan bersamaan.

## DoD + bukti

- [x] ON-01: 3 slide, bisa digeser, indikator titik, Skip ke ON-02 — `OnboardingUITests.testSplashHasThreeSwipeableSlidesAndSkip`.
- [x] ON-02: 0 dan 21 karakter ditolak, 1 dan 20 diterima — `NameRuleTests` (+ trim, emoji, karakter tak terlihat) + `testNameLongerThanTwentyCharactersIsRejected`.
- [x] Avatar acak tampil setelah registrasi (bukan inisial) — `OnboardingModelTests.guardianPath` + `greeting-*.png`.
- [x] ON-03: mode tersimpan dan tidak bisa diganti — `modeIsPermanentAfterRegistration`, `AppSettingsTests.modeCanBeChosenOnlyOnce`, UI test tanpa tombol Back + relaunch tidak kembali ke ON-03.
- [x] ON-04: Off → tetap, Active → lanjut; Turn on membuka Settings; link video membuka player — `extensionOffStaysActiveContinues`, `testExtensionOffStays…`, `testTurnOnOpensSettings` (app Settings ke foreground), `testVideoLinkOpensPlayer`, `extension-*.png`. Uji di iPhone nyata: 01S / QA-E2E #17.
- [x] ON-05: izin diminta; ditolak → banner pengingat di Home — `guardianFinishesEvenWhenPermissionIsDenied`, `testGuardianOnboardingEndsOnHomeWithReminderWhenNotificationsDenied`, `shield-reminder-*.png`. Reset izin simulator diganti jawaban izin palsu DEBUG (D-alief-A05).
- [x] Screenshot EN + ID di `qa/img/ui-02/` (9 layar × EN/ID × light/dark/AX-XL = 54).

## Gerbang UI

Screenshot `plan/alief/qa/img/ui-02/<layar>-<en|id>-<light|dark|xl>.png`: `splash`, `name`, `mode`, `greeting`, `connect`, `extension`, `notifications-guardian`, `notifications-protected`, `shield-reminder`. `xl` = Dynamic Type AX-XL. Diambil dengan `simctl` + `-debug.onboardingStep`.

Review `apple-design` + `ecc:a11y-architect` (22 Okt): **0 HIGH**, 4 MEDIUM, 8 LOW.

| Temuan | Sev | Tindakan |
|---|---|---|
| Tombol tutup video bisa hampir tak terlihat (glyph gelap di atas hitam), satu-satunya jalan keluar | MEDIUM | Diperbaiki: glyph putih di lingkaran hitam 60 % |
| Video tutorial tanpa teks/caption (pengguna 45–65) | MEDIUM | Syarat ditambahkan ke permintaan video PM (TODO C15) |
| ON-04 di AX-XL: footer (Turn on + link video) menutupi langkah 2–3 | MEDIUM | Diperbaiki: di ukuran aksesibilitas link video ikut scroll, hanya Turn on yang dipin |
| Peringatan "tidak bisa diganti" `.secondary` kecil | MEDIUM | Diperbaiki: `.body` semibold `.primary` |
| Batas 20 karakter baru disebut setelah dilanggar | LOW | Diperbaiki: subjudul "… Up to 20 characters." |
| Tombol banner hanya "Turn on" di luar konteks; judul banner bukan header | LOW | Diperbaiki: label "Turn on notifications", `.isHeader` |
| Lingkaran kartu mode tidak terpilih ±3:1; auto-focus keyboard saat VoiceOver; avatar dibaca dua kali; ikon lonceng oranye ±2:1 (dekoratif); indikator halaman menimpa teks di AX-XL; status "Shoo is off." tidak diumumkan saat berubah | LOW | Ditunda ke re-skin / QA-A 06Q (layar berpindah otomatis saat Active, jadi perubahan status terlihat sebagai pindah layar) |

Perbandingan PRD: urutan ON-01 → ON-05 dan Protected lewat Connect sesuai fase 02; teks pendek untuk persona 45–65. **Re-skin saat desain final datang** (ilustrasi ON-01/ON-04 masih SF Symbols, video PM C15).

## Temuan review

`ecc:swift-reviewer` (22 Okt): 2 HIGH, 8 MEDIUM, 10 LOW.

| # | Temuan | Tindakan |
|---|---|---|
| H1 | `register` di `AppEnvironment` (bukan MainActor) mengubah state `@Observable` di luar main actor | Diperbaiki: `register`/`finishOnboarding` `@MainActor` |
| H2 | Protected yang menutup app di Connect tidak pernah melihat Connect lagi | Diperbaiki: `onboardingConnectPassed`; test `protectedRelaunchResumesAtConnectUntilPassed` |
| M | Token registrasi di model; audio session tidak dilepas; video hilang = layar hitam; nama hanya zero-width; error tanpa pengumuman VoiceOver; Reduce Motion; badge langkah tidak ikut Dynamic Type | Diperbaiki (token tidak lagi di model + `TODO(sync:alief)` Keychain fase 13) |
| M | PiP di luar app butuh `UIBackgroundModes: audio` | Permintaan Umar (TODO C3 butir 4), D-alief-A07 |
| M | Konfirmasi tambahan sebelum mode permanen | Tidak ditambah (PRD: teks peringatan saja), D-alief-A08; cek ulang di QA-A |
| L | Banner `notDetermined` membuka Settings; `FixedNotificationPermission` ikut Release | Diperbaiki |
| L | `registerForRemoteNotifications` saat izin sudah ada sebelumnya; langkah ON-04 tidak berganti saat `SFSafariSettings` gagal; override `-settings.*` lewat domain argumen | Ditunda: fase 15 (token APNs), 01S/06Q, dicatat di D-alief-A05 |

### SECURITY §3 P1–P13 (diff fase ini)

| # | Status |
|---|---|
| P1 | ✅ tidak ada API required-reason baru (UserDefaults sudah `CA92.1`); manifest tidak berubah |
| P2 | – fase 16 (nama sudah dideklarasikan di manifest) |
| P3 | – fase 06/13; `AppSettings.clear` ikut menghapus key onboarding baru |
| P4 | ✅ token registrasi tidak disimpan di `UserDefaults` maupun model; hanya preferensi non-sensitif (mode, flag onboarding) |
| P5 | ✅ tidak ada jaringan baru |
| P6 | ✅ `Log` `.private`, tanpa `print`, token tidak di-log |
| P7 | ✅ izin notifikasi just-in-time di ON-05 dengan alasan jujur, ditolak tetap jalan; kamera tidak disentuh |
| P8–P12 | – |
| P13 | ✅ tidak ada data pengguna yang disalin/di-cache |
| Lain | ✅ tanpa `App-prefs:`, ID extension dari bundle ID, tanpa SDK pihak ketiga, video lokal (tidak ada unduhan) |

## Placeholder aktif

- `ConnectPlaceholderView.swift` — `TODO(sync:alief)` PR-01 (fase 14).
- `TutorialVideoPlayer.swift` — `TODO(sync:umar)` video PM (C15).
- `AppEnvironment.swift` — `TODO(sync:alief)` simpan token di Keychain + App Group (fase 13); `ApiRepository` (fase 13).
- `NotificationPermission.swift` — `TODO(sync:alief)` kirim token APNs (fase 15).
- Dari fase 01: `AppConfig.swift` (URL Worker), `MainTabView.swift` (DetailView, fase 03).

## LANGKAH MANUAL

Tidak ada. Pending pihak luar (bukan [m]): C3 butir 2 (push capability) dan butir 4 (`UIBackgroundModes: audio` untuk PiP), C15 (video PM), uji ON-04 di iPhone (01S / QA-E2E #17).

## Catatan handoff

- `TurnOnExtensionView` dipakai ulang sebagai sheet "Turn on" di PR-04/GD-01 (fase 04/05): komponen butuh `OnboardingModel` sekarang; fase 04 sebaiknya mengekstrak langkah + tombol jadi view tanpa model.
- Fase 13: `AppEnvironment.register` menyimpan token di Keychain + key App Group sebelum `chooseMode`.
- Fase 15: kirim token APNs; panggil `registerForRemoteNotifications()` juga saat izin sudah `authorized` dari awal.
- Simulator khusus track app: `Shoo App Track` (`8646F92B-5080-4C5A-8506-C2F06C5AD508`).
