# Log fase 04 — Protected: Shield (PR-04) + Activity (PR-05) (Alief, track app)

- **Status:** [r] — PR #19 `feat/PR-04-05-shield-activity`, reviewer @umarmuhdhor. **Stacked on #18** (fase 03) → #14 (fase 01). Fase 02 (#16) belum ada di rantai ini; digabung ke cabang fase 06 sebelum 06Q (instruksi koordinator).
- **Model:** Claude Opus 5.5, mode auto. Mulai dan selesai 22 Okt 2026.
- **Rencana:** `log/fase-04-plan.md`. Sumber: `fase-04-protected.md`, PRD §8.2 PR-04/PR-05.

## Checklist langkah

- [x] 1. `ShieldModel`: status extension dari heartbeat App Group (`ExtensionStatus.current()`, `AppGroup.extensionActiveWindow`, tanpa konstanta sendiri) + `-UITestExtensionActive` (DEBUG); guardian dari `me()`; blokir terakhir = item pertama `scans(owner: .me, status: .blocked)`; alasan = 1–2 `labelSimple` bobot tertinggi.
- [x] 2. `ProtectedShieldView`: lingkaran Active/Off, "Turn on" saat Off (buka Settings, D-alief-A14), baris "Protected by Adhella", kartu "Blocked!" (skor, domain, alasan, waktu) → Detail, kosong "Nothing blocked yet", error + "Try again", refresh saat kembali ke foreground (`.task(id: scenePhase)`) dan pull to refresh.
- [x] 3. `ActivityModel` (dipakai ulang GD-05): filter All/Warning/Blocked, terbaru di atas, `nextCursor`, refresh, respons basi dibuang (D-alief-A12).
- [x] 4. `ActivityView` + `FilterChips` + `ActivityRow` (monogram, domain tebal, host+path, waktu relatif, chip status), endless scroll, Retry halaman berikut, empty state per filter, tap → Detail.
- [x] 5. `MainTabView`: Protected → Shield/Activity baru; Guardian → Activity `.family` (D-alief-A10), Shield placeholder sampai fase 05.
- [x] 6. Penutup privasi app switcher di Shield dan Activity (lanjutan D-alief-A36).
- [x] 7. Gerbang UI `qa/img/ui-04/` (7 layar × EN/ID × light/dark/AX-XL), review `ecc:swift-reviewer` lalu `ecc:a11y-architect` (berurutan), perbaikan, cek P1–P13, verifikasi.

## File dibuat/diubah

- Baru: `Features/Shield/{ShieldModel,ProtectedShieldView}.swift`, `Features/Activity/{ActivityModel,ActivityView}.swift`, `Components/ReadableSecondary.swift`, `Support/Cancellation.swift`.
- Dihapus: `Features/Activity/ActivityPlaceholderView.swift`.
- Diubah (fase 01, minimal): `Features/Main/MainTabView.swift` (akar tab per mode + `.id(repository)`), `Resources/Localizable.xcstrings` (+22 key EN/ID).
- Test: `Tests/{ShieldModelTests,ActivityModelTests,TestDoubles}.swift`, `UITests/ProtectedUITests.swift`.
- Plan: `log/fase-04-plan.md`, `log/fase-04.md`, `log/DECISIONS.md` (A10–A14), `PROGRESS.md` baris 04, `qa/img/ui-04/*.png` (42 file, diperkecil 50 %).

## Hasil verifikasi (22 Okt 2026, Xcode 27.1, simulator khusus "Shoo App Track" iPhone 17 Pro iOS 26.4, `-destination id=8646F92B-…`)

| Perintah | Hasil |
|---|---|
| `(cd ios && xcodegen)` | OK |
| `xcodebuild test … -scheme Shoo` (semua target) | `** TEST SUCCEEDED **` · Swift Testing **115 test / 12 suite lulus** (fase 03: 91 → +24: `ShieldModelTests` 10, `ActivityModelTests` 14 termasuk argumen) · XCUITest **13 lulus** (`ProtectedUITests` 4, `DetailUITests` 6, `SmokeUITests` 3) |
| `-only-testing:ShooAppTests/ShieldModelTests`, `ActivityModelTests`, `ShooAppUITests/ProtectedUITests` (perintah file fase) | lulus (bagian dari run di atas) |
| `grep -rn "print(" ios/ShooApp --include='*.swift'` | kosong |
| `grep -rn "com\.shoo\|group\.com" ios/ShooApp --include='*.swift'` | kosong |
| `git diff --stat 342676d..HEAD -- contracts ios/project.yml ios/ShooShared ios/ShooExtension docs` | kosong |
| `grep -rn "TODO(sync" ios/ShooApp` | 5 (baru: sheet Turn on fase 02, Shield Guardian fase 05) |
| `plutil -lint ios/ShooApp/PrivacyInfo.xcprivacy` | OK (tidak berubah) |

Catatan TDD: `ShieldModelTests`/`ActivityModelTests` ditulis dulu (gagal kompilasi, tipe belum ada). Test perbaikan review (refresh gagal, halaman basi, retry halaman, `URLError.cancelled`, chip aktif, link baris) ditulis sebelum perbaikan.

## DoD + bukti

- [x] PR-04 "Selesai kalau": `qa/img/ui-04/shield-active-*.png`, `shield-off-*.png`, `shield-empty-*.png` (kartu blokir ada di `shield-active-*`); `ProtectedUITests.testShieldShowsGuardianAndOpensLastBlocked`, `testShieldOffOffersTurnOn`, `testShieldEmptyShowsNothingBlocked`.
- [x] PR-05 filter dan urutan: `ActivityModelTests.allIsNewestFirst`, `filterShowsOnlyThatStatus`, `loadMoreFollowsTheCursorWithoutDuplicates`, `emptyStateIsPerFilter`; tap → Detail: `ProtectedUITests.testActivityFiltersAndOpensDetail`; `qa/img/ui-04/activity-{all,warning,blocked,empty}-*.png`.
- [x] Tidak ada It's safe/Not safe untuk Protected: `ProtectedUITests.testShieldShowsGuardianAndOpensLastBlocked` (Detail dari kartu Shield) + `DetailUITests` fase 03.

## Gerbang UI (PROMPT langkah 7)

Screenshot `qa/img/ui-04/<layar>-<en|id>-<light|dark|xl>.png` (`xl` = AX-XL), `simctl` status bar 09:41. Layar: `shield-active`, `shield-off`, `shield-empty`, `activity-all`, `activity-warning`, `activity-blocked`, `activity-empty`.

Review `ecc:a11y-architect`: 3 HIGH, 9 MEDIUM, 4 LOW.

| Temuan | Sev | Tindakan |
|---|---|---|
| Teks `.secondary` ±3,5:1 di mode terang | HIGH | Diperbaiki: `.readableSecondary` (D-alief-A13). `EmptyStateView` (komponen fase 01) belum → 06Q |
| Ikon putih di lingkaran hijau ±2,2:1 | HIGH | Diperbaiki: hijau/abu gelap tanpa gradient |
| Chip terpilih putih di accent ±4:1, hanya warna | HIGH | Diperbaiki: isian `#0061CC` + centang, font `.body` |
| Urutan VoiceOver kartu blokir / baris Activity (domain dua kali) | MEDIUM | Diperbaiki: satu label eksplisit, urutan apa–di mana–skor–kenapa–kapan |
| "Blocked!" merah ±3,6:1 | MEDIUM | Diperbaiki: teks `.primary`, merah di ikon |
| Lingkaran tak dibatasi di AX-XL (Turn on terdorong ke bawah) | MEDIUM | Diperbaiki: maks 160 pt |
| Kartu blokir sempit di AX-XL | MEDIUM | Diperbaiki: `AnyLayout` VStack, chevron disembunyikan |
| Chip tergulir keluar layar di AX-XL | MEDIUM | Diperbaiki: chip bertumpuk lebar penuh, grup berlabel "Filter" |
| Judul status bukan header, dua stop | MEDIUM | Diperbaiki: `.isHeader` + gabung judul/subjudul |
| Perubahan status / refresh gagal tidak diumumkan | MEDIUM | Diperbaiki: `AccessibilityNotification.Announcement` (bukan saat muat pertama) |
| Bahasa suara VoiceOver ≠ bahasa app | MEDIUM | Ditunda ke 06Q: urusan seluruh app (fase 01 memakai `AttributedString.languageIdentifier` di Profile), bukan khusus layar ini |
| `ProgressView` tanpa label, Turn on tanpa hint | LOW | Diperbaiki: "Loading", "Opens Settings" |
| `StatusChip` `.caption`, `ScoreRing` "percent risk" | LOW | Ditunda ke 06Q (komponen bersama fase 01/03) |

## Temuan review (langkah 8)

`ecc:swift-reviewer`: 2 HIGH, 5 MEDIUM, 4 LOW. Privasi bersih (tidak ada log URL/nama, tidak ada fetch host penipuan).

| # | Temuan | Tindakan |
|---|---|---|
| H1 | `loadMore` untuk daftar lama bisa mendarat setelah refresh | Diperbaiki: `generation` naik juga saat halaman pertama diterapkan; test `pageForTheOldListIsDroppedAfterARefresh` |
| H2 | Refresh gagal menghapus daftar/kartu yang tampil | Diperbaiki: data dipertahankan + `refreshFailed`; test `failedRefreshKeepsTheList`, `failedForegroundRefreshKeepsWhatIsShown` |
| M3 | `URLError(.cancelled)` (ApiRepository nanti) dianggap gagal | Diperbaiki: `Error.isCancellation`; test di kedua model |
| M4 | Flag `isLoadingMore` dari permintaan basi; halaman gagal tidak bisa diulang | Diperbaiki: permintaan basi tidak menyentuh flag; baris Retry; test `failedNextPageCanBeRetried` |
| M5 | Ketuk chip aktif mengosongkan daftar | Diperbaiki: no-op; test `tappingTheActiveFilterKeepsTheList` |
| M6 | `.task` tidak memuat ulang dari `.failed` | Diperbaiki: `retry()` bila `state != .loaded`; Try again menampilkan spinner |
| M7 | Model `@State` memegang repository lama | Diperbaiki: `.id(ObjectIdentifier(env.repository))` di akar tab |
| L8 | `refresh()` Shield tumpang tindih | Diperbaiki: `generation` di `ShieldModel` |
| L9 | Try again tanpa spinner | Diperbaiki (M6) |
| L10 | Identifier chip dari nama case | Diperbaiki: `rawValue` |
| L11 | URL lengkap (query) di baris | Diperbaiki: host + path (D-alief-A11) |

## Cek SECURITY §3 P1–P13 (diff fase 04)

| # | Hasil |
|---|---|
| P1 manifest | Tidak berubah. `UserDefaults` baru hanya baca argumen DEBUG (`UITestExtensionActive`, `debug.activityFilter`) → alasan CA92.1 yang sudah ada |
| P2 label App Store | Tidak ada data baru dikumpulkan |
| P3 hapus data | Tidak ada penyimpanan baru (model di memori saja) |
| P4 Keychain | Tidak disentuh |
| P5 ATS | Tidak ada jaringan baru (mock) |
| P6 log | Hanya `Log.ui.error(StaticString, error)` → error `.private`; `grep print(` kosong |
| P7 izin | Tidak ada izin baru; Turn on hanya membuka Settings |
| P8 pasteboard | Tidak dipakai |
| P9 screenshot/link | Tidak ada fetch favicon/screenshot; baris hanya host+path (A11); penutup app switcher (A36) |
| P10 push | Tidak disentuh |
| P11 export | Tidak disentuh |
| P12 kebijakan | Tidak disentuh |
| P13 (usulan PR #12, belum di `SECURITY.md` main: hapus = langsung hilang) | Tidak ada salinan baru di disk; snapshot app switcher Shield/Activity hanya penutup privasi |

## Catatan handoff

- Fase 05: Shield Guardian (GD-01) + filter per orang (GD-05) memakai `ActivityModel(owner: .device(id))`/`.family`; `ActivityView(showsOwner:)` sudah ada.
- Merge fase 02 sebelum 06Q: ganti tombol Turn on ke sheet `TurnOnExtensionView` (`TODO(sync:alief)` di `ProtectedShieldView`), samakan `ExtensionStatus.live` dengan closure `extensionStatus` di `AppEnvironment` fase 02, dedupe `FailingRepository` (`OnboardingTests` vs `TestDoubles`).
- 06Q: `EmptyStateView` deskripsi `.secondary`, `StatusChip` `.caption`, bahasa suara VoiceOver = bahasa app.
- Re-skin saat desain final datang (warna lingkaran, chip, ilustrasi empty state).
