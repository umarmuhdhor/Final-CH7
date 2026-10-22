# Log fase 06 — Profile: PF-01 (Alief, track app)

- **Status:** [r] — PR #22 `feat/PF-01-profile`, reviewer @umarmuhdhor. **Stacked on #21** (fase 05) **+ merge fase 02 (#16)** di awal fase (D-alief-A18). Dengan ini rantai app berisi 01, 02, 03, 04, 05, 06.
- **Model:** Claude Opus 5.5, mode auto. Mulai dan selesai 22 Okt 2026.
- **Rencana:** `log/fase-06-plan.md`. Sumber: `fase-06-profile.md`, PRD §8.6 PF-01, §10, `contracts/api.md` (`PATCH /devices/me`, `DELETE /family/guardian`).

## Checklist langkah

- [x] 0. Merge `origin/feat/ON-01-05-onboarding` ke cabang ini + penyelesaian konflik (D-alief-A18): katalog digabung, banner pengingat Guardian di `GuardianShieldView`, satu sumber status extension (`env.extensionStatus`), Turn on di Shield = sheet ON-04, `FailingRepository` tidak ganda. 152 unit + 25 UI lulus setelah merge.
- [x] 1. Dibuka dari ikon kanan atas (semua mode); `ProfilePlaceholderView` dihapus.
- [x] 2. Nama + avatar: edit dengan aturan ON-02 (`NameRule`), Save selalu ada (nonaktif bila tidak berubah/tidak valid), pengumuman aturan/tersimpan/gagal.
- [x] 3. Bahasa English / Bahasa Indonesia (picker inline): `AppSettings.language` langsung, `updateMe(language:)`; pilihan terbaru membatalkan sinkron lama; `load()` mengirim ulang bila server belum tahu (D-alief-A19).
- [x] 4. Status extension Active/Off (teks + ikon) + "Turn on" → sheet ON-04.
- [x] 5. Protected: guardian (avatar + nama) + Disconnect dengan dialog konfirmasi standar → `leaveGuardian()` → onboarding lanjut di Connect; `notFound` (jawaban hilang) dianggap sudah putus.
- [x] 6. Guardian: daftar keluarga x/3 ringkas (Not connected), "Family code" (alert placeholder sampai fase 14, nonaktif saat penuh), baris gagal + Try again.
- [x] 7. Refine ON-04: **dilewati** — `origin/main` belum punya `docs/spikes/open-extension-settings.md` (dicek 22 Okt 2026). Tidak ada handoff 01S yang perlu ditandai.
- [x] 8. "Delete my data" (SECURITY §3 P3): dialog EN/ID → `deleteMe()` (usulan `DELETE /devices/me`) → `settings.reset()` → onboarding; di belakang `AppConfig.dataDeletionEnabled = false` sampai C19 (D-alief-A20).
- [x] 9. Gerbang UI, review `ecc:swift-reviewer` lalu `ecc:a11y-architect` (berurutan), perbaikan, cek P1–P13, verifikasi.

## File dibuat/diubah

- Baru: `Features/Profile/{ProfileModel,ProfileView}.swift`, `Features/Shield/TurnOnExtensionSheet.swift`.
- Dihapus: `Features/Profile/ProfilePlaceholderView.swift`, `Features/Shield/ShieldPlaceholderView.swift` (merge).
- Diubah: `Data/{ShooRepository,MockRepository}.swift` (`deleteMe`), `App/Router.swift` (`reset()`), `Components/ReadableSecondary.swift` (`Color.readableRed`), `Features/Main/MainTabView.swift`, `Features/Onboarding/{TurnOnExtensionView,OnboardingFlow}.swift` (closure `refreshStatus`), `Features/Shield/{ProtectedShieldView,ShieldModel,FamilyShieldView}.swift` (merge), `Resources/Localizable.xcstrings` (+24 key EN/ID setelah merge; "Guardian" di ID tetap "Guardian", konsisten dengan fase 02).
- Test: `Tests/ProfileModelTests.swift` (14), `Tests/TestDoubles.swift` (`updateFailure`, `membersFailure`, `deleteMe`), `Tests/DetailModelTests.swift` (`deleteMe` di stub), `UITests/ProfileUITests.swift` (4).
- Plan: `log/fase-06-plan.md`, `log/fase-06.md`, `log/DECISIONS.md` (A18–A20), `PROGRESS.md` baris 06, `qa/img/ui-06/*.png` (24 file, diperkecil 50 %).

## Hasil verifikasi (22 Okt 2026, Xcode 27.1, simulator "Shoo App Track" iPhone 17 Pro iOS 26.4, `-destination id=8646F92B-…`)

| Perintah | Hasil |
|---|---|
| `(cd ios && xcodegen)` | OK |
| `xcodebuild test … -scheme Shoo` (semua target, run terakhir setelah semua perbaikan) | `** TEST SUCCEEDED **` · Swift Testing **166 test / 17 suite lulus** · XCUITest **29 lulus** (Detail 6, Guardian 5, Onboarding 7, Profile 4, Protected 4, Smoke 3) |
| `-only-testing:ShooAppTests/ProfileModelTests`, `ShooAppUITests/ProfileUITests` (perintah file fase) | lulus (bagian dari run di atas) |
| `grep -rn "print(" ios/ShooApp --include='*.swift'` | kosong |
| `grep -rn "com\.shoo\|group\.com" ios/ShooApp --include='*.swift'` | kosong |
| `git diff --stat d696ad3..HEAD -- contracts ios/project.yml ios/ShooShared ios/ShooExtension docs` | kosong |
| `grep -rn "TODO(sync" ios/ShooApp` | 10 (fase 02 + fase 13/14: Keychain, ApiRepository, Family code, Connect, hapus kunci sesi) |
| `plutil -lint ios/ShooApp/PrivacyInfo.xcprivacy` | OK (tidak berubah) |

Catatan TDD: `ProfileModelTests` ditulis dulu (gagal kompilasi: `ProfileModel`, `deleteMe` belum ada). Test perbaikan review (bahasa terakhir menang, kirim ulang bahasa, putus yang sudah terjadi, keluarga gagal, error nama hilang saat diedit, reload menjaga nama yang sedang diedit) ditulis sebelum perbaikan. Satu UI test sempat gagal karena tombol dialog konfirmasi muncul ganda di pohon aksesibilitas → `firstMatch`.

## DoD + bukti

- [x] PF-01 Guardian dan Protected: `qa/img/ui-06/profile-{guardian,guardian-off,protected,protected-empty}-*.png`; `ProfileModelTests.guardianSeesNameMembersAndFamilyCode`, `protectedSeesGuardianAndDisconnectButNoFamilyCode`; `ProfileUITests.testGuardianSeesFamilyCodeNotDisconnect`, `testProtectedDisconnectGoesBackToConnect`, `testNameEditFollowsTheOnboardingRule`.
- [x] Ganti bahasa mengubah semua layar tanpa restart: `ProfileUITests.testLanguageSwitchesTheWholeAppAtOnce` (judul Profil, tab "Aktivitas", Shield "Kamu terlindungi") + screenshot `profile-*-id-*.png`.
- [x] Delete my data: `ProfileModelTests.deleteMyDataIsHiddenUntilTheContractExists`, `deleteMyDataStartsOverWithAFreshInstall`; UI tersembunyi (`AppConfig.dataDeletionEnabled = false`), jadi tanpa screenshot.

## Gerbang UI (PROMPT langkah 7)

Screenshot `qa/img/ui-06/<layar>-<en|id>-<light|dark|xl>.png` lewat `-debug.profile YES`: `profile-guardian` (Active, keluarga 2/3), `profile-guardian-off` (Off + Turn on), `profile-protected` (guardian + Disconnect), `profile-protected-empty`.

Draf pertama memperlihatkan baris extension tinggi kosong dan nama bahasa terpotong di AX-XL ("Bahasa…donesia") → `ViewThatFits` + picker inline.

Review `ecc:a11y-architect`: 3 HIGH, 6 MEDIUM, 3 LOW.

| Temuan | Sev | Tindakan |
|---|---|---|
| Teks error merah ±3,6:1 | HIGH | Diperbaiki: `Color.readableRed` (≥ 4,5:1 terang/gelap) + ikon |
| Aturan nama / tersimpan tidak diumumkan; tombol Save hilang saat fokus | HIGH | Diperbaiki: pengumuman aturan, "Name saved", gagal; Save selalu ada (nonaktif) |
| Avatar + field dan baris anggota sempit di AX | HIGH | Diperbaiki: bertumpuk di ukuran aksesibilitas, avatar `@ScaledMetric` (maks 96), field multi-baris |
| Label field "Your name" ≠ header "Name" | MEDIUM | Diperbaiki: "Name" + hint "1 to 20 characters" |
| Label picker terbaca dua kali | MEDIUM | Diperbaiki: `.labelsHidden()` |
| "Family 2/3" dibaca "2 slash 3"; 0/3 saat gagal | MEDIUM | Diperbaiki: "Family, 2 of 3 people", header trait; angka disembunyikan saat gagal, Family code nonaktif |
| Tombol destruktif merah ±3,6:1; label konfirmasi umum | MEDIUM | Diperbaiki: `readableRed`; "Disconnect from Adhella", "Delete my data" |
| Garis pemisah baris extension; hijau ±2,2:1 | MEDIUM | Diperbaiki: `listRowSeparatorLeading`; hijau diterima (teks + bentuk ikon membawa status) |
| Baris gagal keluarga tidak diumumkan, label tombol berisi error | MEDIUM | Diperbaiki: teks + tombol "Try again" terpisah, pengumuman |
| Family code penuh tanpa alasan, "Turn on" ambigu | LOW | Diperbaiki: hint "Your family is full", label "Turn on Shoo in Safari" |
| Status loading | LOW | Diterima |

## Temuan review (langkah 8)

`ecc:swift-reviewer` (merge + PF-01): 0 HIGH, 5 MEDIUM, 6 LOW. Integrasi merge dinilai benar.

| # | Temuan | Tindakan |
|---|---|---|
| M1 | Jalur navigasi + tab tersisa setelah putus/hapus (Detail scan lama terbuka lagi) | Diperbaiki: `Router.reset()` lewat `onSessionEnd` **sebelum** settings berubah |
| M2 | Jawaban hilang → retry `notFound` macet | Diperbaiki: `notFound` (dan `unauthorized` untuk hapus) = selesai; test `disconnectThatAlreadyHappenedCountsAsDone` |
| M3 | Error putus/hapus muncul di footer Nama | Diperbaiki: `nameError` (footer) vs `actionError` (alert); error nama hilang saat diedit |
| M4 | `familyMembers()` gagal → seluruh Profile gagal | Diperbaiki: profil dulu, keluarga terpisah (`membersFailed`); test |
| M5 | Balapan picker bahasa | Diperbaiki: `chooseLanguage` sinkron + batalkan task lama; `load()` kirim ulang; test |
| L | Urutan teardown, reload menimpa draf, Try again tanpa spinner | Diperbaiki (`retry()`, draf dijaga) |
| L | Draf nama hilang saat sheet ditutup; `reset()` menulis bahasa sistem; jalur `-UITestExtensionActive` hanya lewat `env` | Diterima (dicatat) |

## Cek SECURITY §3 P1–P13 (diff fase 06 + merge)

| # | Hasil |
|---|---|
| P1 | Tidak berubah; `UserDefaults` hanya preferensi app (CA92.1) |
| P2 | Tidak ada jenis data baru (nama, bahasa sudah ada) |
| P3 | "Delete my data" selalu tampil sejak PR #10 (kontrak `DELETE /devices/me`, D-alief-A40); setelah hapus: server dulu, lalu reset lokal; `TODO(sync:alief)` Keychain + kunci sesi App Group di fase 13 |
| P4, P5 | Tidak disentuh (Keychain/ATS fase 13) |
| P6 | `Log.ui.error(StaticString, error)` → `.private`; nama tidak pernah di-log; `print(` kosong |
| P7 | Izin notifikasi tetap just-in-time (fase 02); banner pengingat hanya Guardian |
| P8–P12 | Tidak disentuh |
| P13 (usulan PR #12) | Hapus = langsung hilang di mock (scan sendiri, keluarga, guardian) lalu sesi lokal bersih; penutup privasi di Profile |

## Catatan handoff

- 06Q (QA-A) berikutnya: rantai lengkap 01–06 ada di cabang ini.
- Fase 13: `deleteMe()` → `DELETE /devices/me` (ada di kontrak sejak PR #10) + hapus token Keychain dan kunci App Group; `updateMe(language:)` ke API.
- Fase 14: Family code (Profile + Shield Family), Connect sungguhan.
- L9 fase 05 (kartu basi setelah hapus anggota di Profile): Profile belum punya hapus anggota (GD-04 fase 14) → tidak relevan sekarang.
