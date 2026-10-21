# Log fase 03 — Detail DT-01..06 + tombol GD-07 (Alief, track app)

- **Status:** [r] — PR #PR_NO `feat/DT-detail`, reviewer @umarmuhdhor. **Stacked on #14** (fase 01), tidak di atas fase 02 (sesi paralel `feat/ON-01-05-onboarding`).
- **Model:** Claude Opus 5.5, sesi paralel dengan fase 02. Mulai dan selesai 22 Okt 2026.
- **Rencana lengkap:** `log/fase-03-plan.md`. Sumber requirement: PRD v1.5 §5 Validasi, §8.3 GD-07, §8.4 DT-01..06 (dibaca dari Google Drive 22 Okt 2026).

## Ringkasan planner

Satu layar Detail untuk semua mode dan sumber (Activity, kartu Shield, push di fase 15), dibuka dengan `scanId`. `DetailModel` memuat `scan(id:)` + `me()`, menurunkan label (DT-02), bukti (DT-04), catatan verifikasi (DT-06), dan hak validasi (DT-05). Verdict optimistic dengan rollback. Screenshot bukti dari link Worker (D-alief-B08) dimuat tanpa cache dan tanpa share/simpan (P9, P13). Konflik dengan sesi fase 02 dijaga kecil: file baru di `Features/Detail/`, file fase 01 hanya disentuh di `MainTabView.destination` dan satu blok DEBUG di `AppEnvironment.live`, string baru hanya untuk Detail. Planner dijalankan inline (tanpa subagent `ecc:planner`) karena "Langkah kerja" fase sudah rinci.

## Checklist langkah

- [x] 1. DT-01 ring besar (`ScoreRing` 160 pt) + header VoiceOver "Risk score, 92%, Blocked, …" (menutup MEDIUM fase 01: level tidak hanya lewat warna).
- [x] 2. DT-02 label via `ScanBadge` (Warning / Blocked / Verified scam / Marked safe).
- [x] 3. DT-03 link lengkap (teks, tidak pernah dibuka, Copy link `.localOnly` + kedaluwarsa 5 menit), waktu lokal EN/ID + relatif, "Opened by" untuk Guardian (D-alief-A31, A33).
- [x] 4. DT-04 maks 3 bukti, bobot terbesar dulu, `label` (Guardian) / `labelSimple` (Protected), "+30%"; screenshot besar, tap → zoom (pinch, ketuk dua kali, geser terbatas); `nil` → blok hilang (D-alief-A32, A34).
- [x] 5. DT-05 / GD-07 tombol hanya Guardian + item `blocked`, tanpa dialog, optimistic + rollback + pesan, tap ganda diabaikan, reload tidak menimpa verdict baru (D-alief-A30).
- [x] 6. DT-06 "Verified scam by X" / "Marked safe by X" / "… by you".
- [x] 7. Gerbang UI 5 fixture × Guardian + 3 fixture × Protected × EN/ID × light/dark/XL.
- [x] Review a11y + Apple design, `ecc:swift-reviewer`, `ecc:security-reviewer` (berurutan, satu per satu), perbaikan, cek P1–P13, verifikasi.

## File dibuat/diubah

- Baru `ios/ShooApp/Features/Detail/`: `DetailModel`, `DetailView`, `EvidenceList` (+ `Evidence`), `VerdictButtons`, `VerdictNote`, `ScreenshotView` (+ `URLSessionScreenshotLoader`, `ScreenshotDecoder`, `FixtureScreenshotLoader` DEBUG), `LinkCopy`, `PrivacyCover`.
- Diubah (fase 01, minimal): `Features/Main/MainTabView.swift` (placeholder → `DetailView` + `.id(scanId)`), `App/AppEnvironment.swift` (`-debug.detail`, DEBUG), `Resources/Localizable.xcstrings` (+32 kunci Detail, EN + ID).
- Test: `Tests/DetailModelTests.swift` (+ `StubRepository`), `Tests/DetailPrivacyTests.swift` (`LinkCopyTests`, `ScreenshotLoaderTests`), `UITests/DetailUITests.swift`.
- Plan: `log/fase-03-plan.md`, `log/fase-03.md`, `log/DECISIONS.md` (A30–A36), `PROGRESS.md` baris 03, `qa/img/ui-03/*.png` (37 file, diperkecil 50 %).

## Hasil verifikasi (22 Okt 2026, Xcode 27.1, simulator khusus sesi "Shoo DT iPhone 17 Pro" iOS 26.4, `-destination id=1017BA6C-…`)

| Perintah | Hasil |
|---|---|
| `(cd ios && xcodegen)` | OK |
| `xcodebuild test … -scheme Shoo` (semua target, 76 s) | `** TEST SUCCEEDED **` · Swift Testing **91 test / 10 suite lulus** (fase 01: 53 → +38: `DetailModelTests` 27 kasus termasuk argumen, `LinkCopyTests` 1, `ScreenshotLoaderTests` 10) · XCUITest **9/9** (`SmokeUITests` 3 + `DetailUITests` 6, 69 s) · 0 warning compiler di `ios/ShooApp` |
| `-only-testing:ShooAppTests/DetailModelTests` / `ShooAppUITests/DetailUITests` (perintah file fase) | lulus (bagian dari run di atas) |
| `grep -rn "print(" ios/ShooApp --include='*.swift'` | kosong |
| `grep -rn "com\.shoo\|group\.com" ios/ShooApp --include='*.swift'` | kosong (bundle ID untuk `simctl` dibaca dari `Info.plist` hasil build) |
| `git diff --stat 9c49d8e..HEAD -- contracts ios/project.yml ios/ShooShared ios/ShooExtension docs` | kosong |
| `grep -rn "TODO(sync" ios/ShooApp` | 2 (placeholder `DetailView` fase 01 sudah diganti) |
| `plutil -lint ios/ShooApp/PrivacyInfo.xcprivacy` | OK (tidak berubah) |
| Snapshot app switcher di disk (`Library/SplashBoard/Snapshots/*.ktx` → PNG) | hanya penutup privasi, tanpa URL/nama/screenshot |

Catatan TDD: test ditulis dulu dan gagal kompilasi (tipe belum ada); test race reload/verdict dan `.gone` ditulis sebelum perbaikan review.

## DoD + bukti

- [x] DT-01..06 sesuai "Selesai kalau" PRD untuk kelima fixture — `qa/img/ui-03/<fixture>-guardian-*.png` (5 fixture × en-light, id-light, en-dark, id-xl), bagian bawah `blocked-92-guardian-en-bottom.png` (3 bukti + screenshot), zoom `…-zoom.png`, setelah Not safe `…-after-not-safe.png`; `DetailModelTests.badgeFollowsStatusAndVerdict`, `guardianEvidenceIsTopThreeByWeightWithFullLabels`, `ownVerdictSaysByYou`.
- [x] Protected: tanpa tombol, bukti memakai `labelSimple` — `DetailModelTests.onlyGuardianValidatesBlockedItems`, `protectedEvidenceUsesSimpleLabels`, `protectedNeverSendsAVerdict`; `DetailUITests.testProtectedSeesSimpleWordsAndNoButtons`; `qa/img/ui-03/*-protected-*.png`.
- [x] Verdict langsung berlaku tanpa dialog, rollback saat error — `DetailModelTests.verdictIsOptimistic`, `failedVerdictRollsBackToNoVerdict`, `failedVerdictRollsBackToPreviousVerdict`, `secondTapWhileSendingIsIgnored`, `reloadDuringVerdictKeepsTheNewVerdict`; `DetailUITests.testGuardianMarksNotSafeAtOnce` (tanpa alert).

## Gerbang UI (PROMPT langkah 7)

Screenshot `plan/alief/qa/img/ui-03/<fixture>-<guardian|protected>-<en|id>-<light|dark|xl>.png` (`xl` = AX-XL), diambil `simctl` (status bar 09:41) + lampiran XCUITest `testBelowTheFoldScreens` untuk bagian bawah/zoom/setelah tap (tool iOS Simulator tidak diberi akses ke perangkat sesi ini). Protected memakai 3 fixture milik Mom; 2 lainnya memang 404 untuknya (D-alief-A35).

Review `ecc:a11y-architect` + checklist Apple HIG: **0 HIGH**, 6 MEDIUM, 7 LOW.

| Temuan | Sev | Tindakan |
|---|---|---|
| Teks hijau/merah di atas tint pucat ≈ 2:1 (ditemukan sendiri di gerbang) | HIGH | Diperbaiki sebelum review: `VerdictButtonStyle` teks `.primary`, warna di ikon + latar, pilihan = isian kuat + garis tepi + `isSelected` |
| Tombol bersebelahan pecah per huruf di AX-XL | MEDIUM | Diperbaiki: `VStackLayout` di ukuran aksesibilitas (`blocked-92-guardian-id-xl.png`) |
| Verdict/gagal tidak diumumkan VoiceOver | MEDIUM | Diperbaiki: `AccessibilityNotification.Announcement` per hasil (`saved`/`rolledBack`/`gone`) |
| Tidak ada petunjuk "langsung berlaku"; `.disabled` saat kirim menghilangkan status terpilih | MEDIUM | Diperbaiki: hint "Applies right away. You can change it later."; `.disabled` dibuang, model mengabaikan tap ganda |
| Layar zoom tanpa escape VoiceOver | MEDIUM | Diperbaiki: `.accessibilityAction(.escape)`, tombol tutup diprioritaskan |
| Aksi "Zoom" statis, geser tak terbatas | MEDIUM | Diperbaiki: "Zoom in"/"Zoom out", offset dijepit |
| Bobot dan waktu `.secondary` < 4,5:1 | MEDIUM | Diperbaiki: `.primary` |
| VoiceOver membaca "·" dan "+30%" | LOW | Diperbaiki: "…, adds 30 percent to the risk score" (EN/ID) |
| Copy tanpa pengumuman, label+URL dua stop, gambar tanpa trait image, reduce motion, ukuran pesan error, header trait | LOW | Diperbaiki |
| Bar tombol menempel tetap ±25 % layar di AX-XL | LOW | Diterima (tombol harus selalu terjangkau); re-skin |

Perbandingan PRD §7/§8.4: semua butir DT ada; wireframe hanya coretan Crazy 8. **Re-skin saat desain final datang** (warna tombol, ilustrasi, ring).

## Temuan review (langkah 8)

`ecc:swift-reviewer`: 2 HIGH, 6 MEDIUM, 4 LOW.

| # | Temuan | Tindakan |
|---|---|---|
| H1 | Reload (`.task` saat muncul lagi) bisa menimpa verdict optimistic / yang baru disimpan | Diperbaiki: `verdictEpoch`; reload yang selesai saat/ setelah verdict mempertahankan verdict terbaru; test `reloadDuringVerdictKeepsTheNewVerdict` |
| H2 | `URLError.cancelled` dari URLSession asli dianggap gagal | Diperbaiki: diperlakukan sebagai pembatalan + `Task.isCancelled` |
| M | Pengumuman/haptic juga saat tap diabaikan atau rollback; 404 saat verdict = "Couldn't save"; cache memori 8 MB menahan screenshot sepanjang umur proses (melawan P13); body dibaca utuh sebelum cek ukuran; static stub test tanpa lock | Diperbaiki: `VerdictOutcome`, haptic dari `verdictSaves`, 404 → layar "This item is gone", `urlCache = nil`, baca streaming + batas, `StubURLProtocol` dengan `NSLock` |
| L | Model terikat id pertama; nama `async let` membayangi properti; gambar lama saat URL berganti; tanpa Try again | Diperbaiki: `.task(id:)` + `.id(scanId)`, nama baru, reset gambar, tombol Try again |
| L12 | Pemilihan loader bergantung `repository is MockRepository` | Ditunda (by design): di fase 13 repository asli → loader asli otomatis; UI test tetap memakai Mock |

`ecc:security-reviewer` (sukarela untuk fase 03, fokus P8/P9/P13): 0 CRITICAL/HIGH, 3 MEDIUM, 5 LOW.

| # | Temuan | Tindakan |
|---|---|---|
| M1 | Decompression bomb: PNG kecil dengan header 30000 × 30000 | Diperbaiki: header dibaca dulu (sisi > 4096 ditolak), dekode sekali dengan downsampling 2048 px; test `hugeDimensionsAreRefused`, `decodeDownsamplesLargeImages` |
| M2 | Host apa pun lewat HTTPS diambil, redirect diikuti | Diperbaiki: hanya host `AppConfig.apiBaseURL` + path `/screenshots/`, redirect ditolak; test `otherHostsAreRefused`, `redirectsAreNotFollowed` |
| M3 | Snapshot app switcher di disk memuat URL/nama/screenshot | Diperbaiki: `.privacyCover()` (D-alief-A36), dicek pada file snapshot |
| L4 | Pasteboard tanpa kedaluwarsa | Diperbaiki: 5 menit |
| L5 | Baca per byte lambat | Diterima: ≤ 150 KB nyata, batas tetap berlaku |
| L7 | `scanId` tidak divalidasi sebelum request (T15) | Fase 15 (`NotificationRouter`) / fase 13 (`ApiRepository`) |
| L6, L8 | Log `.private`, pengumuman tanpa URL | Tidak perlu tindakan |

### SECURITY §3 P1–P13 (diff fase ini)

| # | Status |
|---|---|
| P1 | – manifest tidak berubah (lint OK); tidak ada API alasan baru (pasteboard tulis tidak butuh alasan) |
| P2 | – tidak ada jenis data baru (URL, nama, screenshot sudah tercatat) |
| P3 | – tidak menyentuh hapus data; 404 → "This item is gone" |
| P4 | ✅ tidak ada tulisan baru ke `UserDefaults`/App Group/Keychain di `Features/Detail` |
| P5 | ✅ screenshot HTTPS saja ke host API, HTTP hanya `localhost` di DEBUG, redirect ditolak |
| P6 | ✅ `Log` (`os.Logger`, nilai `.private`); kegagalan screenshot dicatat tanpa nilai (link bertanda tangan tidak pernah di-log); tanpa `print` |
| P7 | – tidak ada izin |
| P8 | ✅ Copy link: teks biasa, `.localOnly`, kedaluwarsa 5 menit (`LinkCopyTests`) |
| P9 | ✅ sesi ephemeral tanpa `URLCache`/cookie/kredensial/`Authorization`, tidak ada file; tanpa share/simpan/context menu (UI test zoom); snapshot app switcher tertutup; favicon tidak dimuat (A03) |
| P10–P12 | – push/export/kebijakan di fase lain |
| P13 | ✅ setiap tampilan meminta Worker lagi (cek akses per request), 404 → "isn't available anymore"; tanpa salinan cache/snapshot |
| SDK pihak ketiga | ✅ tidak ada |

## Deviasi

- Link tidak bisa dibuka untuk **semua** status (file fase: "untuk scan blocked") → D-alief-A31.
- Tombol tetap tampil setelah verdict (bisa diganti) → D-alief-A30.
- Bobot "+NN%" juga untuk Protected; `Signal.evidence` tidak ditampilkan → D-alief-A34.
- Gerbang UI Protected 3 fixture, bukan 5 → D-alief-A35.
- Checkbox mandat DT-01..06 di `docs/mandates/alief.md` **tidak** dicentang di PR ini: sesi ini hanya boleh mengubah `ios/ShooApp/` dan `plan/alief/`; dicentang di PR berikutnya atau oleh Alief. Tabel requirement P0 di PROGRESS juga tidak diubah (hanya baris fase 03, supaya tidak bentrok dengan sesi fase 02).

## Placeholder aktif

- `App/AppConfig.swift` — `TODO(sync:alief)` URL Worker cloud (fase 13).
- `App/AppEnvironment.swift` — `TODO(sync:alief)` `ApiRepository` (fase 13).
- Tombol verdict memanggil `ShooRepository.setVerdict` → `MockRepository` sampai fase 13/15 (`POST /verdicts` asli).

## LANGKAH MANUAL

Tidak ada.

## Catatan handoff

- **Fase 13:** `URLSessionScreenshotLoader` hanya menerima host `AppConfig.apiBaseURL`; `screenshotUrl` dari Worker memakai origin `INVITE_BASE_URL` (D-alief-B08 c). Pastikan keduanya host yang sama saat `AppConfig` diganti ke URL cloud, kalau tidak screenshot selalu "not available". `ApiRepository` sebaiknya memetakan `URLError.cancelled` ke `CancellationError` (model sudah menangani keduanya).
- **Fase 15:** validasi `scanId` (UUID) di `NotificationRouter` sebelum `showDetail` (T15, review keamanan L7). Detail dibuka lewat `Router.showDetail(scanId:)`; `.id(scanId)` membuat model baru per scan.
- **Fase 04/05:** Activity dan kartu Shield menampilkan URL + nama juga → pakai `.privacyCover()` (D-alief-A36) di layar itu. `Router.showDetail` sudah siap untuk tap kartu/baris.
- `Localizable.xcstrings`: fase 02 menambah kunci di file yang sama; kalau ada konflik saat rebase, gabungkan kedua set kunci (file diurutkan alfabetis, format `json.dumps(indent=2, sort_keys=True)`).
- Simulator sesi ini: "Shoo DT iPhone 17 Pro" (`1017BA6C-10ED-477F-BC60-166A97686474`) dibuat supaya tidak bentrok dengan sesi fase 02; boleh dihapus (`xcrun simctl delete 1017BA6C-10ED-477F-BC60-166A97686474`).
