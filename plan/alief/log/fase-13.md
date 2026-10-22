# Log fase 13 — ApiRepository + sesi App Group (Alief, track c)

- **Status:** [r] — branch `feat/APP-api-repository` dari `origin/main` `b91f2a1` (semua PR #1–#28 MERGED, G5 + G6 [x]).
- **Model:** Claude Opus 5.5, mode auto. Mulai 22 Okt 2026 10:20 WITA.
- **Rencana:** `log/fase-13-plan.md` (ditulis langsung oleh agent dari "Langkah kerja" file fase; tidak memakai agent planner terpisah karena aturan Alief: subagent satu per satu, dan review keamanan wajib lebih penting di slot itu).

## Ringkasan rencana

1. `APIClient` (URLSession ephemeral tanpa cache/cookie, Bearer, error kontrak, 401 → sesi rusak).
2. `KeychainItem` + `SessionStore` (token `AfterFirstUnlockThisDeviceOnly`, key kontrak App Group).
3. `ApiRepository` untuk semua operasi `ShooRepository` + efek sesi.
4. `AppEnvironment`: pemilihan repository, registrasi → sesi → mode → bahasa, sinkron foreground, sesi kedaluwarsa.
5. Layar "Session expired".
6. Screenshot: link baru sekali sebelum "tidak tersedia".
7. `AppConfig` Release = Worker cloud; `ai.baseURL` placeholder.
8. UI test lama + `-UITestMock YES`; uji manual melawan `wrangler dev`; gerbang UI; review; PR.

## Checklist langkah (file fase "Langkah kerja")

- [x] 1. `APIClient` + test stub untuk setiap endpoint (`Tests/APIClientTests.swift`, `Tests/ApiRepositoryTests.swift`).
- [x] 2. `ApiRepository` memenuhi protocol; `MockRepository` tetap untuk preview + UI test (`-UITestMock YES`, D-alief-C01).
- [x] 3. Onboarding → `registerDevice` asli → `SessionStore.save` → App Group; bahasa ID → `PATCH language=id` (D-alief-C06).
- [x] 4. 401 → layar "Session expired" + mulai ulang onboarding (D-alief-C03).
- [x] 5. Uji melawan `wrangler dev` lokal dari simulator: diotomasi sebagai `UITests/LiveBackendUITests.swift` (opt-in `TEST_RUNNER_SHOO_LIVE_BACKEND=1`), karena alat simulator agent tidak punya izin perangkat. Guardian EN + Protected ID, Activity kosong, Profile ganti nama + bahasa, foreground → heartbeat.
- [x] 6. `ecc:security-reviewer` fokus T3 (lalu `ecc:swift-reviewer`, berurutan).
- [x] 7. `updateMe(extensionLastSeenAt:)` saat `scenePhase == .active`; `me()` mengisi ulang `SessionStore` (D-alief-C06).

## File dibuat/diubah

- Baru: `Data/{APIClient,ApiRepository,SessionStore,Keychain}.swift`, `Features/Main/SessionExpiredView.swift`.
- Diubah: `App/{AppConfig,AppEnvironment,RootView}.swift`, `Features/Detail/{DetailModel,DetailView,ScreenshotView}.swift` (link screenshot baru sekali, D-alief-C04), `Features/Profile/ProfileModel.swift` (komentar TODO saja), `Resources/Localizable.xcstrings` (+3 key EN/ID), `Data/Fixtures/{activity-family,blocked-92,blocked-marked-safe}.json` (sinkron kontrak #36: `new_domain` layer 3).
- Test baru: `Tests/{APIStub,APIClientTests,ApiRepositoryTests,SessionStoreTests,AppEnvironmentSessionTests,DetailScreenshotLinkTests}.swift`, `UITests/{SessionUITests,LiveBackendUITests}.swift`. UI test lama: `-UITestMock YES` (D-alief-C01).
- Plan: `log/fase-13-plan.md`, `log/fase-13.md`, `log/DECISIONS.md` (C01–C06), `TODO.md` (C19 butir 4, C22), `PROGRESS.md` baris 13, `qa/img/ui-13/*.png` (11).

## Hasil verifikasi (22 Okt 2026, Xcode, simulator "Shoo Track C" iPhone 17 Pro iOS 27.0)

| Perintah | Hasil |
|---|---|
| `(cd ios && xcodegen)` | OK |
| `xcodebuild test … -only-testing:ShooAppTests` (setelah semua perbaikan review, di atas `origin/main` `a5d29f9`) | **233 test / 23 suite lulus** (sebelum fase 13: 166) |
| `TEST_RUNNER_SHOO_LIVE_BACKEND=1 xcodebuild test … -scheme Shoo` (semua target, run terakhir setelah semua perbaikan, backend lokal jalan) | `** TEST SUCCEEDED **` · Swift Testing 233 lulus · XCUITest **38 dijalankan, 36 lulus, 2 audit dilewati** (sama seperti main; termasuk `LiveBackendUITests` 2 + `SessionUITests` 1) |
| `TEST_RUNNER_SHOO_LIVE_BACKEND=1 … LiveBackendUITests` + `SessionUITests` melawan `pnpm -C backend/api dev` (Supabase lokal, migrasi 8/8) | 3/3 lulus |
| Cek DB lokal setelah uji live | `Rina B · guardian · id`, `Mom · protected · id · ext_last_seen_at terisi` (nama, bahasa, heartbeat sampai server) |
| `plutil -p` App Group di simulator setelah onboarding Protected | `api.baseURL`, `device.id`, `device.mode`, `device.name`, `device.token` (disensor); tanpa `ai.baseURL` (C05) dan tanpa `guardian.name` (belum join) |
| `curl -H "Authorization: Bearer <token App Group>" localhost:8787/devices/me` | `language: "id"`, `guardian: null`; header `Cache-Control: private, no-store` |
| `grep -rn "print(" ios/ShooApp --include='*.swift'` | hanya `UITests/AccessibilityAuditUITests.swift` (lama, test) |
| `grep -rn "com\.shoo\|group\.com" ios/ShooApp --include='*.swift'` | kosong |
| `git diff --stat $(git merge-base origin/main HEAD)..HEAD -- contracts ios/project.yml ios/ShooShared ios/ShooExtension ios/ShooLiveActivity detector ai .github` | kosong |
| `plutil -lint ios/ShooApp/PrivacyInfo.xcprivacy` | OK (tidak berubah) |
| Nama file terlarang di diff | tidak ada |

## DoD + bukti

- [x] Tidak ada view yang berubah karena pergantian repository: `Features/` hanya injeksi + deviasi kecil Detail (D-alief-C04) + layar baru "Session expired" (langkah 4). Semua UI test lama lulus dengan mock.
- [x] Semua key App Group terisi setelah onboarding (`SessionStoreTests.saveWritesEveryContractKey`, `AppEnvironmentSessionTests.registrationSavesTheSessionBeforeTheMode`, `plutil` simulator); `device.name` ikut berubah (`ApiRepositoryTests.renameRewritesDeviceNameInTheAppGroup`); `guardian.name` hilang setelah disconnect / 404 / `guardian: null` (`ApiRepositoryTests.leavingClears…`, `noGuardianOnTheServer…`, `profileWithoutGuardian…`).
- [x] Alur onboarding → Shield melawan backend lokal (screenshot `qa/img/ui-13/guardian-*.png`, `protected-1-shield-id.png`).
- [x] SECURITY §3: Keychain `AfterFirstUnlockThisDeviceOnly` (`SessionStoreTests.tokenIsStoredThisDeviceOnly`, P4), ATS tanpa pengecualian (localhost Debug jalan tanpa key, Release hanya HTTPS, P5), screenshot tanpa cache disk (tidak berubah + `APIClientTests.sessionKeepsNothingOnDisk`, P9), `deleteMe()` asli membersihkan Keychain + App Group (`ApiRepositoryTests.deleteClearsKeychainAndAppGroup`, P3).

## Gerbang UI

Layar baru "Session expired" memakai komponen onboarding yang sudah lolos review a11y fase 02 (`OnboardingPage`, `OnboardingHeader`, `OnboardingPrimaryButton`: judul header, tombol 50 pt, ikon disembunyikan dari VoiceOver). Screenshot EN/ID × light/dark + Dynamic Type AX-XL: `qa/img/ui-13/session-expired-*.png` — teks membungkus, tombol tetap terlihat, tidak ada potongan. Tidak ada temuan HIGH. Layar lain tidak berubah tampilannya. Re-skin saat desain final datang.

## Temuan review

| Review | Temuan | Ditangani |
|---|---|---|
| `ecc:security-reviewer` | 0 CRITICAL, 0 HIGH, 6 MEDIUM, 10 LOW | MEDIUM: token App Group tanpa Keychain selalu dihapus; 401 membuang token juga sebelum mode tersimpan; gagal simpan sesi → tidak ada sesi setengah; satu lock untuk semua tulis `SessionStore`; tidak ada tulis setelah `clear()` (P13); token App Group sebagai teks biasa = kontrak → usulan TODO C22. LOW yang diperbaiki: Keychain terkunci ≠ sesi hilang, `SecItemUpdate`, segmen path hanya id polos (T15), redirect ditolak, Release hanya URL HTTPS ke App Group. Sisa LOW (orphan device, pesan server) → handoff |
| `ecc:swift-reviewer` | 0 CRITICAL, 1 HIGH, 4 MEDIUM, 13 LOW | HIGH: 401 lama bisa menghapus sesi baru → 401 membawa token yang dipakai, hanya token saat ini yang bisa kedaluwarsa (`lateUnauthorizedForAnOldTokenIsIgnored`). MEDIUM: status 401 apa pun dihitung; `URLSession` di-invalidate; tidak ada kilasan "Session expired" saat hapus data; stub test dibersihkan. LOW yang diperbaiki: satu sinkron foreground sekaligus, pembatalan screenshot, satu flag di model, Keychain non-UTF-8 throw, `try!` di helper test |

## Cek privasi Apple (SECURITY §3)

| # | Hasil |
|---|---|
| P1 | Manifest tidak berubah; tidak ada API alasan baru (Keychain dan URLSession bukan required-reason API). OK |
| P2 | Tidak ada jenis data baru (nama, mode, bahasa, heartbeat extension sudah tercakup). OK |
| P3 | `deleteMe()` asli → Keychain + semua key App Group app dihapus, juga untuk 401/404 (sudah terhapus). OK |
| P4 | Token di Keychain `AfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false`; App Group hanya key kontrak (test `onlyContractKeysAreWritten`); salinan App Group tanpa Keychain tidak dipakai dan dihapus. OK (risiko kontrak → C22) |
| P5 | Tidak ada `NSAppTransportSecurity`; Release `https://shoo-api.afindo-mi01.workers.dev`; App Group Release hanya URL HTTPS. OK |
| P6 | Token tidak pernah di-log; log memakai `Log.*` dengan nilai `.private`; tidak ada `print`. OK |
| P7 | Tidak ada izin baru. OK |
| P8 | Tidak berubah. OK |
| P9 | Screenshot tetap sesi ephemeral tanpa cache; API juga tanpa cache/cookie/kredensial. OK |
| P10 | Tidak berubah (fase 15). OK |
| P11 | Tidak berubah (fase 16). – |
| P12 | Tidak berubah. – |
| P13 | Hapus/sesi berakhir = Keychain + App Group bersih seketika; jawaban telat tidak menulis ulang nama/guardian; respons user-data `private, no-store` (cek curl). OK |

## Deviasi

- D-alief-C04: perubahan kecil perilaku Detail (link screenshot baru sekali) di luar "hanya injeksi".
- Agent planner terpisah tidak dipakai; rencana ditulis langsung (`fase-13-plan.md`).
- Langkah 5 (uji manual) diotomasi sebagai UI test opt-in, bukan tap manual.

## Placeholder aktif

- `App/AppConfig.swift`: `TODO(sync:imelda)` URL layanan AI (D-alief-C05).
- Fase 14: `ConnectPlaceholderView`, Family code di `FamilyShieldView`/`ProfileView`/`ProtectedShieldView`.
- Fase 15: token APNs di `NotificationPermission.swift`.

## LANGKAH MANUAL

Tidak ada untuk fase 13 (tidak ada aksi cloud). Backend cloud tidak berubah.

## Catatan handoff

- Device yatim di server: kalau Keychain menolak simpan setelah `POST /devices` (sangat jarang), device server hanya berisi nama + mode dan tidak pernah dipakai. Backend belum membersihkan device tidak aktif; usulan kecil untuk retensi (fase 16 / setelah MVP).
- `RepositoryError.api(message:)` membawa teks server; tidak ada view yang menampilkannya (semua alert memakai teks lokal per kode). Pertahankan begitu.
- Jawaban `me()` telat dari sesi lama setelah "Start again" bisa menulis nama lama hanya kalau sesi baru sudah terdaftar dalam jendela milidetik itu; nama dibetulkan lagi oleh `me()` berikutnya. Diterima untuk MVP.
- Kontrak `device.token` di App Group (teks biasa, ikut backup) → TODO C22 (draf untuk Umar, belum dikirim).
- Uji live: `TEST_RUNNER_SHOO_LIVE_BACKEND=1 TEST_RUNNER_SHOO_SHOT_DIR=<dir> xcodebuild test … -only-testing:ShooAppUITests/LiveBackendUITests` dengan `pnpm -C backend/api dev` jalan dan `backend/api/.dev.vars` lokal.
