# Fase 23 — Keandalan test + CI (UI test iOS flaky) dan UI test live salinan halaman (C2, QA-A, DT-04)

| Field | Nilai |
|---|---|
| Track | b (app, test saja) + usulan CI ke Umar |
| Branch | 23a `fix/C2-test-flakes` (perbaikan test di `ios/ShooApp/Tests` + `ios/ShooApp/UITests`, plus satu flag DEBUG di `ios/ShooApp/App`) · 23b tanpa branch (issue usulan workflow ke Umar, K5) · 23c `feat/DT-04-live-replica-ui` (UI test live opt-in + skrip `plan/alief/qa/replica-ui.sh`). Semua dari `origin/main` saat mulai |
| Prasyarat | **PR #204** (`fix/DT-04-replica-hardening`, gerbang `passesGate` jadi satu lintasan memchr) merge dulu (**terpenuhi**: MERGED 31 Okt 15:40 UTC, `main` 8fd9751): tanpa itu `ReplicaHTMLTests.unclosedMetaFloodStaysFast` di `main` tetap 1,02–1,31 s di CI. 23c: `pnpm -C backend/api dev` + `supabase start` jalan lokal, `backend/api/.dev.vars` ada, simulator "Shoo QA SE" (pakai UDID, lihat LANGKAH MANUAL 1) |
| Urutan | 23a-0 (repro lokal, S1–S5) → jawaban K1–K4 → 23a (TDD: test helper dulu, lalu ganti pemakaian) → 23b issue (K5, paralel dengan 23a, tidak memblokir) → 23c (K6, K7) |
| Requirement | TODO C2 (CI), D-alief-12 (test app di PR), fase 18 langkah 7 "UI test opt-in live `SHOO_LIVE_REPLICA=1`" (`fase-18-page-replica.md:175`, `log/fase-18.md:128` di 2720b13, `:129` di `main` sejak #205, belum dibuat), aturan repo "UI PR = screenshot before/after", memori "No direct push to main" (#39) |
| Model + reviewer ECC | Opus 5.5 · 23a: `ecc:swift-reviewer` → `ecc:pr-test-analyzer`; 23c: `ecc:swift-reviewer` → `ecc:security-reviewer` (skrip memegang token device uji). Berurutan, tidak paralel |
| Fase berikutnya | Tidak ada yang menunggu fase 23. Fase 22b (`DetailPerfTests`, opt-in `TEST_RUNNER_SHOO_PERF=1`) memakai pola K3 (b) (opt-in), bukan K3 (a). Bentrok file: 22b juga mengubah `PageCopyTests.swift:230-231` (`fase-22-performance.md:168`), 20d mengubah `DetailUITests` (`fase-20-screenshot-sunset.md:115`, dijalankan di `:295`); lihat Catatan handoff |

## Tujuan

**Masalah.** CI iOS (`.github/workflows/ios-app.yml`) merah tanpa perubahan kode yang salah. Pada 31 Okt saja: tiga run gagal di test perf jam dinding, satu di render WKWebView di unit test, dua di UI test yang lolos 10/10 lokal dan lolos saat rerun. Rerun satu run memakan 29 menit lagi (run 41190546465 total 62 menit). Akibatnya PR menunggu, dan merah "biasa" mulai diabaikan, padahal di jendela yang sama CI juga menangkap kegagalan sungguhan (compile `TestDoubles.swift:88`, fixture kontrak basi).

**Masalah kedua.** Langkah `Test` sudah 1501–1758 s, sementara `timeout-minutes: 30` (1800 s) (`ios-app.yml:20`). UI test saja 72 test, 8 di-skip, 1383 s (log run 41190546465). Dua atau tiga UI test baru lagi, atau satu test yang menunggu 10–15 s lebih lama, membuat job dipotong timeout tanpa ringkasan assertion.

**Masalah ketiga.** UI test salinan halaman yang ada (`DetailUITests.testPageCopyShowsWithItsLine`) hanya memakai fixture mock (`-debug.replicaFixture YES`). Jalur nyata (ekstensi → `POST /scans` → R2 → `GET /scans/{id}` → `ReplicaLoader` → `ReplicaSnapshot`) hanya diuji per potong: `replica-e2e.sh` berhenti di curl, app tidak pernah memuat replica dari Worker lokal. Fase 18 merencanakan `SHOO_LIVE_REPLICA=1`, tapi belum dibuat.

**Hasil akhir yang diinginkan.**
- Tabel flake di bawah lengkap, tiap baris punya penyebab yang dibuktikan (repro lokal) atau ditandai "dugaan".
- Test yang flaky diperbaiki di sumbernya (tunggu kondisi, bukan tidur; batas waktu yang masuk akal; WebKit tidak berbarengan), bukan disembunyikan dengan retry.
- Usulan CI ke Umar (issue): pisah job, timeout, xcresult sebagai artifact, retry sementara yang dilaporkan.
- UI test live salinan halaman opt-in, satu perintah lokal, tidak jalan di CI secara default.

## Bacaan wajib

- `.github/workflows/ios-app.yml` (runner `macos-26`, simulator = iPhone pertama dari `simctl list`, satu `xcodebuild test` untuk unit + UI, tanpa retry, tanpa paralel, log di-grep `": error: |\] failed \(|recorded an issue|Expectation failed"`, `timeout-minutes: 30`) dan `.github/workflows/backend.yml`.
- `ios/project.yml:164-174` (scheme `Shoo`: test `ShooAppTests` + `ShooAppUITests`, tanpa test plan, tanpa `parallelizable`). File Umar, hanya dibaca.
- `ios/ShooApp/App/AppEnvironment.swift:48-100` (`-UITestMock`, `-UITestReset`, `-UITestNotifications`, `-UITestExtensionActive`, `-mock.scenario`, `-debug.replicaFixture`).
- `ios/ShooApp/UITests/{OnboardingUITests,DeepLinkUITests,ProfileUITests,QALayoutUITests,PairingUITests,LiveBackendUITests,LivePairingUITests,DetailUITests}.swift`.
- `ios/ShooApp/Tests/{ReplicaHTMLTests,PageCopyTests,ReplicaViewTests}.swift`.
- `ios/ShooApp/Features/Detail/{ReplicaSnapshot,ReplicaLoader}.swift`, `Features/Shield/GlowingShield.swift`, `Components/HalftoneShield.swift`.
- `plan/alief/qa/replica-e2e.sh`, `plan/alief/qa/replica-input.mjs`, `plan/alief/ref/sim.sh`.
- Commit perbaikan flake sebelumnya: `3230a1e` / `0e471ef` (QALayout, popup GD-01), `2e0cdd1` (Profile, popup GD-01), `0404136` (Pairing, tunggu tiap layar onboarding), `7a274a1` (backend favicon ke R2).

## Cek kelayakan (diverifikasi terhadap `origin/main` 2720b13 dan riwayat CI, 31 Okt 2026)

Sumber: `gh run list -R umarmuhdhor/Final-CH7 --limit 60` (22 Okt–31 Okt; 23 run iOS sukses/gagal, 17 dibatalkan oleh `concurrency`), lalu `gh run view <id> [--attempt 1] --log-failed | grep -E "✘|: error: |XCTAssert"` untuk 15 run iOS gagal + 4 run backend gagal.

### Tabel flake

| # | Test (file:baris) | Gagal di CI | Pertama / terakhir | Dugaan penyebab | Perbaikan |
|---|---|---|---|---|---|
| F1 | `ReplicaHTMLTests.unclosedMetaFloodStaysFast` (`ReplicaHTMLTests.swift:99`) | 3: 41182728142 (1,05 s), 41183333268 (1,02 s), 41186620135 (1,31 s) | 31 Okt 07:59 / 31 Okt 08:56 | Batas jam dinding 1 s di runner 3 vCPU yang juga menjalankan simulator. Gerbang lama memindai ulang per `<meta`. (Dugaan "suite Swift Testing lain berebut CPU" lemah: scheme `parallelizable = "NO"`, lihat C8/S5) | PR #204: gerbang memchr satu lintasan (0,012 s lokal). Lalu K3: batas longgar + test rasio skala |
| F2 | `ReplicaSnapshotTests.rendersTheLockedPage` (`PageCopyTests.swift:228`, `ReplicaSnapshot.render` → `nil`) | 1: 41183333268 | 31 Okt 08:07 / sama | **Dugaan, belum terbukti.** WKWebView di host unit test; proses WebContent dingin di runner lambat, `loadTimeout` 10 s / `snapshotTimeout` 5 s (`ReplicaSnapshot.swift:30,32`) habis → `nil` tanpa alasan. `ReplicaSnapshotTests` (`PageCopyTests.swift:186`) tidak `.serialized`, `ReplicaViewTests` (`ReplicaViewTests.swift:64`) iya; tumpang tindih keduanya hanya mungkin kalau Swift Testing jalan paralel, padahal scheme `parallelizable = "NO"` (C8). S5 + log tahap `nil` memastikan | `render` mencatat tahap yang gagal (load / place / snapshot) supaya `nil` bisa dibaca; K4 suite induk `.serialized` sebagai pencegahan |
| F3 | `OnboardingUITests.testGuardianInviteSheetShowsCodeThenGoesToExtension` (`OnboardingUITests.swift:68`, `invite.open` tidak kembali dalam 5 s setelah Back dari layar ekstensi) | 1: 41190546465 attempt 1 (lolos di attempt 2, 10/10 lokal) | 31 Okt 09:54 / sama | Tap `onboarding.back` langsung setelah `extension.turnOn` muncul, saat transisi push masih jalan: tap bisa hilang, atau transisi balik > 5 s di runner lambat | Helper `tapWhenHittable` + `waitForExistence(timeout: 10)`; kalau layar tidak berganti, tap sekali lagi (aman karena Back idempoten) |
| F4 | `DeepLinkUITests.testScanLinkOpensDetailWithVerdictButtonsForTheGuardian` (`DeepLinkUITests.swift:42`, `profile.back` setelah tap `profileButton`) | 1: 41186620135 | 31 Okt 08:56 / sama | (1) Tap `profileButton` langsung setelah tab Shield ada, sebelum mock selesai memuat. (2) Shield punya animasi terus-menerus: `repeatForever` (`GlowingShield.swift:75`) dan `TimelineView(.animation)` (`HalftoneShield.swift:16`); XCUITest menunggu app idle sebelum tiap tap/query, jadi runner lambat kehabisan waktu. (3) `launch` tanpa `-UITestReset` (`DeepLinkUITests.swift:14-24`): setelan dari test sebelumnya di simulator yang sama ikut terbawa | Helper yang sama; K2 (reduce motion untuk UI test); tambah `-UITestReset YES` |
| F5 | `QALayoutUITests.testInviteButtonIsAboveTabBar` / `…ReachableAtAccessibilitySizes` (`QALayoutUITests.swift:42,62`, assertion `:52,:72`) | 3: 40802180378, 40885478096, 40902853971 (attempt 2) | 29 Okt 01:44 / 29 Okt 15:33 | Popup GD-01 "Notifications are off" (sekali per launch untuk Guardian dengan notifikasi `denied`) menelan tap | **Sudah diperbaiki** `3230a1e`/`0e471ef`. Dipindah ke helper bersama di 23a |
| F6 | `ProfileUITests` helper (`ProfileUITests.swift:28`) | 1: 40998376287 | 30 Okt 03:37 / sama | Popup GD-01 yang sama | **Sudah diperbaiki** `2e0cdd1`. Dipindah ke helper bersama di 23a |
| F7 | `PairingUITests.testOnboardingConnectShowsErrorsThenWhoProtectsMe` (`PairingUITests.swift:64`) | 2: 40802180378, 40870704637 | 29 Okt 01:44 / 29 Okt 12:07 | Tidak menunggu tiap layar onboarding sebelum tap berikutnya | **Sudah diperbaiki** `0404136` |
| F8 | `PairingUITests.testInviteLinkOnNewInstallSkipsModeChoice` (`PairingUITests.swift:116`) | 1: 41011928740 | 30 Okt 06:04 / sama | Belum diketahui. Run yang sama juga merah karena fixture basi (bukan flake), branch tidak dijalankan ulang | Pantau. Repro di S1; kalau lolos 20/20, tandai "sekali, tanpa bukti" dan tutup |
| F9 | backend `favicons.test.ts:375` (baris saat run; di `main` test `:374`, assertion `objectExists` `:379`) "downloads once in waitUntil and stores …" (`expected false to be true`) | 4: 40645416474, 40645434933 (main), 40825397625, 40903496403 (attempt 3 pada 30 Okt 03:21, commit tanpa `7a274a1`) | 28 Okt 06:41 / 29 Okt 15:37 | `objectExists` lama membaca Supabase Storage `/object/info` satu kali tepat setelah `favicon_path` terisi; objek belum terlihat. Tidak memakai `until()` | **Hilang dengan sendirinya** sejak `7a274a1` (favicon baru ke R2/Miniflare, 29 Okt); 3 run backend berikutnya hijau. Aturan 23a: tiap cek setelah `waitUntil` pakai `until()` |

**Bukan flake (CI benar).** `TestDoubles.swift:88` "type 'CountingScansRepository' does not conform to protocol 'ShooRepository'" di 5 run (40655484600, 40805884811, 40825390666, 40884451026, 40987728492): branch tertinggal dari perubahan protokol, gagal dalam ±1 menit saat build. `FixtureTests.appFixtureMatchesContract` (`FixtureTests.swift:49`, salinan 26 byte lebih pendek) di 40998376287 dan 41011928740: fixture app belum disalin ulang setelah `pageReplicaUrl` masuk kontrak (diperbaiki `6a7c8b0`/#177). Keduanya tidak boleh tertutup oleh retry (K1).

**Backend CI.** `backend.yml` hanya punya F9 sebagai flake. Kegagalan lain di jendela 22–26 Okt (`feat/PR-03-invite-token` ×3, `main` 22 Okt) di luar 60 run terakhir, tidak diperiksa. pgTAP tidak pernah gagal di jendela ini. Tidak ada tindakan selain aturan `until()`.

### Butir lain

| # | Butir | Bisa? | Temuan (file:baris) | Tindakan |
|---|---|---|---|---|
| C1 | Durasi job vs timeout | Ya, mendesak | Langkah `Test`: 1501 s (40805784775), 1572 s (41002718234), 1722 s (41182165883), 1758 s (41190546465 attempt 2). Batas job 1800 s (`ios-app.yml:20`). UI: 72 test, 1383 s ⇒ ±19 s per test (launch app baru tiap test) | K5: pisah job unit/UI, timeout 45 menit. 23a: tidak menambah UI test baru ke jalur default; test live 23c di-skip (±0 s) |
| C2 | Batas `waitForExistence` | Ya | Di `UITests/` (`grep -rhoE 'timeout: [0-9]+'`): 148× `timeout: 5`, 82× `10`, 15× `15`, 4× `3`, 3× `2`, 1× `1`, 1× `30`, 4× `60`, 1× `120`. `waitForExistence` kembali begitu elemen ada, jadi menaikkan batas tidak memperlambat test yang lolos | 23a: batas default lewat konstanta `UITestTimeout.screen = 10`; `2`/`3` hanya untuk "pastikan tidak muncul" (popup opsional) |
| C3 | Tap sebelum elemen bisa ditekan | Ya | Tidak ada helper bersama; pola `waitForExistence` lalu `tap()` di tiap file. `isHittable` hanya dipakai untuk scroll (`PairingGateUITests.swift:39,69,92`, `ProfileUITests.swift:45`, `SmokeUITests.swift:48`, `LiveBackendUITests.swift:76,88`, `LivePushUITests.swift:138`) dan assertion layout (`QALayoutUITests.swift:35-36,57,77`), tidak sebelum tap | 23a: `UITests/UITestSupport.swift` (baru): `tapWhenHittable`, `tap(_:until:)`, `dismissNotificationsReminder` |
| C4 | Animasi | Sebagian | App tidak punya flag mematikan animasi. `GlowingShield` dan `HalftoneShield` sudah menghormati `\.accessibilityReduceMotion` (`GlowingShield.swift:70`, `HalftoneShield.swift:10,16`). `EnvironmentValues.accessibilityReduceMotion` **tidak bisa di-set**: hanya `get` (SDK iPhoneSimulator 27.1, `SwiftUICore.swiftinterface:23720-23722`; `_accessibilityReduceMotion` yang bisa di-set adalah API privat, jangan dipakai). `UIView.setAnimationsEnabled(false)` tidak menghentikan `withAnimation(.repeatForever)` / `TimelineView` SwiftUI | K2: kunci environment sendiri |
| C5 | Reset state | Ya | `-UITestReset YES` menghapus `AppSettings` (`AppEnvironment.swift:56-58`). Dipakai di 8 file UI test; **tidak** di `DeepLinkUITests`, `DetailUITests`, `GuardianUITests`, `ProfileUITests`, `ProtectedUITests`, `SessionUITests`, `SmokeUITests` (mereka set `-settings.*` lewat argumen, tapi kunci lain tetap dari run sebelumnya) | 23a: semua `launch` mock memakai satu helper yang menambah `-UITestReset YES` secara default (`reset: false` hanya untuk relaunch di test yang sama: `GuardianUITests.swift:27-37` `testFamilyModeIsRememberedAfterRelaunch` menguji setelan yang bertahan setelah `terminate()`) |
| C6 | Test jam dinding di unit test | Ya | `ReplicaHTMLTests.swift:97-99` (< 1 s), `PageCopyTests.swift:249-253` (`cancelledRenderLeavesNothing` < 2 s, belum pernah gagal) | K3 |
| C7 | Unit test bergantung WKWebView | Ya | `ReplicaSnapshotTests` (`PageCopyTests.swift:186`, `@MainActor struct`, tidak serial), `ReplicaViewTests` (`ReplicaViewTests.swift:64`, `@Suite(.serialized)`). Kalau Swift Testing paralel, suite berbeda boleh tumpang tindih (`.serialized` hanya berlaku di dalam suite dan suite bersarangnya); dengan scheme sekarang (C8) kemungkinan serial | K4 (pencegahan) + S5 |
| C8 | Paralel | Ya | CI tanpa `-parallel-testing-enabled`, jadi setelan scheme berlaku: XcodeGen 2.46.0 menulis `parallelizable = "NO"` untuk `ShooAppTests` dan `ShooAppUITests` (`Shoo.xcscheme` hasil `xcodegen`; `project.yml:164-174` tanpa `parallelizable`). XcodeProj memetakan `NO` → `.none` (Xcode 16+: serial, juga untuk Swift Testing) dan atribut absen → `.swiftTestingOnly` (`XCScheme+TestableReference.swift:40-43`). Jadi kemungkinan besar **tidak ada** test yang berjalan bersamaan di CI; **belum terverifikasi** di runner (log CI hanya `tail -40`, S5). Paralel UI butuh klon simulator: di runner 3 vCPU / 7 GB kemungkinan lebih flaky | Spike S4, S5 lokal; tidak diusulkan sebagai default |
| C9 | Retry | Ya (Xcode 13+) | `xcodebuild -retry-tests-on-failure -test-iterations 2`. Dukungan retry untuk test Swift Testing di Xcode 26 **belum terverifikasi** (S2) | K1 |
| C10 | Bukti saat gagal | Ya | CI hanya mencetak `tail -40` + grep; tidak ada `-resultBundlePath`, tidak ada artifact. UI test yang gagal tidak meninggalkan screenshot/hierarki | K5: xcresult sebagai artifact saat gagal |
| C11 | Simulator lokal | Ya | Dua simulator bernama "Shoo QA SE" (iOS 26.5): `483B28B6-913A-4C3A-8A4C-0C7219022682` dan `516DCC10-B989-4F69-8906-D3FFB9FDF4FC`. `-destination name=` ambigu | Pakai `id=`; hapus satu (LANGKAH MANUAL 1) |
| C12 | Live replica: app ke Worker lokal | Ya | Debug: `AppConfig.apiBaseURL = http://localhost:8787` (`AppConfig.swift:8`); `ReplicaLoader.isAllowed` menerima `http` hanya untuk `localhost`/`127.0.0.1` di DEBUG dan path `/replicas/` (`ReplicaLoader.swift:69-77`). Simulator berbagi jaringan host | 23c tanpa perubahan kode app |
| C13 | Live replica: pola koordinasi | Ya | `LivePairingUITests` sudah memakai direktori bersama (`SHOO_PAIR_DIR`, `code.txt`, `link-ready`) dan `XCTSkipUnless(SHOO_LIVE_BACKEND == "1")` (`LivePairingUITests.swift:13-17`). Variabel lewat `TEST_RUNNER_` (`LiveBackendUITests.swift:5`) | 23c memakai pola yang sama |
| C14 | Live replica: membangun replica | Ya | `replica-input.mjs` membangun `pageReplicaBase64` dengan `replica.js` + `replica-build.js` ekstensi; `replica-e2e.sh` punya `register`, `post_scan`, cleanup `DELETE /devices/me`. `POST /devices` dibatasi 10/jam per IP | 23c: skrip baru memakai ulang `replica-input.mjs`; 1 device dari app + 1 dari skrip per run |

## Peta dampak (semua sisi)

| Sisi | File | Ubah | Sub-fase | Isi |
|---|---|---|---|---|
| App test | `ios/ShooApp/UITests/UITestSupport.swift` | Baru | 23a | `UITestTimeout`, `XCUIElement.tapWhenHittable(timeout:)`, `XCUIApplication.tap(_:until:retries:)`, `dismissNotificationsReminder()`, `XCUIApplication.mock(_ extra: [String], reset: Bool = true)` (selalu `-UITestMock YES -UITestReduceMotion YES`, plus `-UITestReset YES` kecuali `reset: false` untuk relaunch di test yang sama) |
| App test | `UITests/{OnboardingUITests,DeepLinkUITests,ProfileUITests,QALayoutUITests,PairingUITests,GuardianUITests,ProtectedUITests,DetailUITests,SmokeUITests,SessionUITests}.swift` | Ganti | 23a | Pakai helper; perilaku yang diuji tidak berubah |
| App test | `Tests/ReplicaHTMLTests.swift` | Ganti | 23a | K3 |
| App test | `Tests/PageCopyTests.swift`, `Tests/ReplicaViewTests.swift` | Ganti | 23a | K4: suite induk `WebKitTests` `.serialized` |
| App | `ios/ShooApp/App/AppEnvironment.swift` (+ `RootView` atau tempat environment dipasang), `Features/Shield/GlowingShield.swift`, `Components/HalftoneShield.swift` | Ganti (flag DEBUG saja) | 23a | K2: `-UITestReduceMotion YES` → kunci environment `shooReduceMotion`; kedua shield membaca `reduceMotion \|\| shooReduceMotion` |
| App | `Features/Detail/ReplicaSnapshot.swift` | Ganti kecil | 23a | Alasan `nil` dicatat (`Logger` subsystem app, kategori `replica`, tanpa isi HTML/URL) |
| App test | `UITests/LiveReplicaUITests.swift` | Baru | 23c | K6 |
| QA | `plan/alief/qa/replica-ui.sh` | Baru | 23c | K7 |
| CI | `.github/workflows/ios-app.yml` | **Usulan** (bukan di tabel pemilik CLAUDE.md, diputuskan Umar) | 23b | K5 lewat issue |
| Ekstensi / backend / kontrak | — | Tidak ada | — | — |
| Privasi | — | Netral | — | Log alasan `nil` tanpa HTML/URL. Skrip 23c memakai device uji lokal, menghapusnya di akhir, tidak mencetak token. Repo publik: xcresult artifact (K5 butir 2) bisa diunduh siapa pun, jadi hanya boleh berisi data mock (test live di-skip di CI, tanpa secret di env job) |
| Biaya Free | GitHub Actions | — | 23b | Repo publik: runner macOS standar gratis, artifact gratis (retensi 7 hari). Pisah job unit/UI memakai 2 dari 5 job macOS bersamaan (batas paket Free) |
| Dokumen | `plan/alief/log/fase-23.md`, `plan/alief/qa/README.md` | Baru/ubah | semua | Hasil S1–S4, run CI sebelum/sesudah, cara menjalankan 23c |

## Keputusan

**K1 — Retry di CI (butuh Alief, lalu Umar di issue K5).** (a) Tanpa retry. (b) `-retry-tests-on-failure -test-iterations 2` sementara, ditambah langkah yang mendaftar test yang "lolos setelah retry" di `$GITHUB_STEP_SUMMARY`; dicabut setelah 2 minggu hijau tanpa retry. (c) Retry hanya untuk target UI (`xcodebuild test-without-building -only-testing:ShooAppUITests -retry-tests-on-failure`), unit tetap tanpa retry. Kelemahan retry: race nyata di app (bukan di test) ikut tertutup; test yang gagal dijalankan dua kali (UI ±19–60 s per test) mendorong job ke timeout C1; compile error dan fixture basi tidak terpengaruh (gagal sebelum test). Rekomendasi **(c)** setelah 23a merge, dengan daftar retry di summary: unit test tidak boleh flaky sama sekali, dan K3/K4 menghapus sumbernya.

**K2 — Animasi saat UI test (butuh Alief).** (a) Flag DEBUG baru `-UITestReduceMotion YES`: kunci environment sendiri `shooReduceMotion` (C4: `accessibilityReduceMotion` hanya `get`) yang dibaca `GlowingShield`/`HalftoneShield` bersama `reduceMotion`, ditambah `UIView.setAnimationsEnabled(false)` untuk transisi UIKit (push, sheet; tidak berpengaruh ke animasi SwiftUI). (b) Diikat ke `-UITestMock`. (c) Tidak ada; hanya helper tunggu. Rekomendasi **(a)**, dipasang oleh helper `mock(_:)` untuk semua UI test mock, **tidak** untuk `AccessibilityAuditUITests` dan screenshot before/after (tampilan harus asli). (b) ditolak karena screenshot PR juga memakai `-UITestMock`.

**K3 — Test perf jam dinding (butuh Alief).** (a) Batas longgar yang tetap menangkap bug kuadratik: banjir 500 000 `<meta ` < 5 s, ditambah test rasio: waktu 400 000 / 100 000 < 8× (linear ≈ 4×, kuadratik ≈ 16×), median dari 3 ukuran. (b) Pindah ke test perf opt-in `TEST_RUNNER_SHOO_PERF=1` (pola fase 22b). (c) Tetap 1 s. Rekomendasi **(a)**: bug aslinya (H1) membekukan main thread bermenit-menit, bukan 1,3 s; rasio tidak bergantung kecepatan runner. `cancelledRenderLeavesNothing` (< 2 s) naik ke < 5 s: yang diuji "tidak menunggu `loadTimeout` 10 s".

**K4 — Unit test WKWebView (butuh Alief).** (a) Satu `@Suite(.serialized) struct WebKitTests` induk yang berisi `ReplicaSnapshotTests` dan `ReplicaViewTests` sebagai suite bersarang (`extension WebKitTests { struct … }` di file masing-masing; ID test jadi `ShooAppTests/WebKitTests/…`), sehingga tidak ada dua WebContent berbarengan walau paralel dinyalakan nanti; ditambah alasan `nil` di log. Dengan scheme sekarang (C8) suite kemungkinan sudah serial, jadi (a) adalah pencegahan; perbaikan F2 yang sebenarnya menunggu S5 + log tahap. (b) Pindah test render ke UI test. (c) `XCTSkip`/`.disabled` di CI. Rekomendasi **(a)**. (c) ditolak: test ini satu-satunya bukti otomatis bahwa salinan terkunci benar-benar tergambar.

**K5 — Usulan workflow ke Umar (issue, file Umar).** Isi issue, satu topik "iOS CI: keandalan + waktu" (hanya `ios-app.yml`; usulan CI backend fase 21 K7 + fase 22 K11 sudah digabung di satu issue lain, `backend.yml` + `ops-watch.yml`):
1. Pisah job `unit` (`-only-testing:ShooAppTests`) dan `ui` (`-only-testing:ShooAppUITests`), keduanya `build-for-testing` sekali lalu `test-without-building`, atau dua job paralel; `timeout-minutes: 45` untuk `ui`.
2. `-resultBundlePath xcresult` + `actions/upload-artifact` dengan `if: failure()`, retensi 7 hari (screenshot + hierarki elemen UI test yang gagal).
3. K1 (c) dengan daftar test yang lolos setelah retry di step summary.
4. `-test-timeouts-enabled YES -default-test-execution-time-allowance 300` supaya test yang macet dipotong per test, bukan per job.
5. Simulator: pilih dengan UDID dari `simctl list -j` (seperti `plan/alief/ref/sim.sh`), bukan nama.
Yang dilakukan sampai dijawab: 23a tetap jalan; flake yang muncul lagi dicatat di log fase 23 dengan id run.

**K6 — Desain UI test live salinan halaman (butuh Alief).** (a) Satu simulator. App onboarding sebagai Guardian lewat UI (`POST /devices` sungguhan), membaca `invite.code` di layar dan menulisnya ke `$SHOO_REPLICA_DIR/code.txt`. Skrip host mendaftarkan Protected dengan curl, `POST /family/join`, membangun replica dengan `replica-input.mjs`, `POST /scans`, menulis id scan ke `scan.txt`. Launch tanpa `-UITestMock`, dengan argumen seperti `LivePairingUITests.swift:22-27` (`-UITestReset YES`, `-UITestNotifications denied`, `-UITestExtensionActive YES`) supaya ON-04/ON-05 tidak menghalangi. Test menunggu `scan.txt`, membuka `shoo://scan/<id>` (pola `openLink`, `DeepLinkUITests.swift:32-36`), menunggu label `detail.pageCopy` berisi "Copy of the page" ≤ 30 s (state `.shown`, `PageCopyCaption.swift:60-63`) dan tidak berisi "No copy of this page" / "Saving a copy of the page…", tidak ada `webViews` di layar, screenshot ke `SHOO_SHOT_DIR`. **Bukan** "Copied from …": baris itu hanya muncul bila `meta.url` ≠ `scan.url` dengan host domain scan (`ReplicaMeta.swift:104-109`), sedangkan `replica-input.mjs:32` memakai `bca-verifikasi.site` dan scan memakai domain acak (`replica-e2e.sh:63`). (b) Seed langsung lewat `psql` (device, family, scan, objek R2) dengan app memakai token yang ditanam: melewati API, tidak membuktikan jalur nyata. (c) Dua simulator (Protected lewat app): ekstensi Safari tidak bisa digerakkan XCUITest, jadi replica tetap dari skrip. Rekomendasi **(a)**. Opt-in: `XCTSkipUnless(SHOO_LIVE_BACKEND == "1" && SHOO_LIVE_REPLICA == "1" && SHOO_REPLICA_DIR != nil)`; tanpa variabel itu test di-skip di CI (±0 s, tidak menambah C1).

**K7 — Skrip 23c (butuh Alief).** (a) Skrip baru `plan/alief/qa/replica-ui.sh` (menjalankan `xcodebuild test -only-testing:ShooAppUITests/LiveReplicaUITests` di latar dengan `TEST_RUNNER_*`, lalu sisi host menunggu `code.txt`, membuat scan, menulis `scan.txt`, menunggu hasil, membersihkan device). (b) Flag `--ui` di `replica-e2e.sh`. Rekomendasi **(a)**: `replica-e2e.sh` membuat Guardian sendiri dan sudah 180+ baris; fungsi bersama (`register`, pembangun replica) dipindah ke `plan/alief/qa/lib.sh` hanya kalau duplikasinya > 20 baris.

## Output

**23a-0 (tanpa kode produksi).** `plan/alief/log/fase-23.md`: tabel flake di atas (disalin + diperbarui), hasil S1–S4.

- S1 — repro: tiap test F2–F4, F8: `xcodebuild test-without-building -only-testing:<test> -test-iterations 20` (tanpa `-run-tests-until-failure`, yang berhenti di kegagalan pertama) di "Shoo QA SE" (UDID), sekali normal dan sekali di bawah beban CPU (`for i in 1 2 3 4 5 6; do yes > /dev/null & done`, matikan setelahnya). Catat jumlah gagal / 20.
- S2 — `-retry-tests-on-failure` di Xcode lokal: apakah test Swift Testing ikut di-retry, dan bagaimana xcresult menandai "lolos setelah retry" (untuk K1/K5 butir 3).
- S3 — terjawab saat verifikasi (C4): `accessibilityReduceMotion` hanya `get`, jadi kunci environment sendiri. Sisa spike: pastikan `UIView.setAnimationsEnabled(false)` memangkas waktu push/sheet di F3 (ukur dengan/tanpa flag).
- S5 — apakah Swift Testing berjalan paralel di scheme hasil `xcodegen` (`parallelizable = "NO"`): `xcodebuild test-without-building -only-testing:ShooAppTests` lalu lihat urutan baris `◇ Test … started` / `✔ Test … passed` di log (tumpang tindih = paralel); ulangi dengan `-parallel-testing-enabled YES`. Hasil menentukan apakah F1/F2 bisa disebabkan suite lain.
- S4 — waktu UI target lokal serial vs `-parallel-testing-enabled YES -parallel-testing-worker-count 2` dan jumlah flake dalam 3 run (data untuk issue K5, bukan untuk diubah sekarang).

**23a `fix/C2-test-flakes`.**
- `UITestSupport.swift`: helper di Peta dampak. `tap(_:until:retries:)` = tap, tunggu kondisi `UITestTimeout.screen`, tap ulang maksimal `retries` kali kalau elemen masih hittable dan kondisi belum terpenuhi; gagal dengan `app.debugDescription`.
- F3: `OnboardingUITests.swift:66-68` memakai `tap(app.buttons["onboarding.back"], until: invite.open)`. F4: `DeepLinkUITests` memakai `mock(_:)` (dengan reset), `tapWhenHittable` untuk `profileButton`, `tap(_:until: profile.back)`. F5/F6: logika popup GD-01 dipindah ke `dismissNotificationsReminder()` dan dipakai di tiga tempat.
- K2: argumen `-UITestReduceMotion YES` (DEBUG). Test unit di `AppEnvironmentSessionTests`: argumen menghasilkan flag; tanpa argumen flag mati; Release tidak membacanya (`#if DEBUG`, pola `AppEnvironment.swift:55-62`).
- K3: `ReplicaHTMLTests` batas 5 s + `floodScalesLinearly` (rasio < 8×). K4: `WebKitTests` induk `.serialized`; `cancelledRenderLeavesNothing` < 5 s.
- `ReplicaSnapshot.render`: log `replica_snapshot_nil` dengan `stage` (`load_timeout`, `place`, `snapshot_timeout`, `cancelled`), tanpa HTML/URL. Test: tahap terbaca di log untuk render yang dibatalkan (kalau `Logger` sulit diuji, cukup enum `RenderFailure` internal yang diuji, log memakai enum itu).
- Bukti: 3 run CI berturut-turut hijau di PR tanpa rerun run merah, plus S1 ulang 20/20 untuk F2–F4 di bawah beban.

**23b (issue).** Issue K5 ke Umar, nomornya ditulis di log fase 23, PR 23a, dan `TODO.md` butir C2 (lewat PR docs).

**23c `feat/DT-04-live-replica-ui`.**
- `UITests/LiveReplicaUITests.swift`: `testGuardianSeesThePageCopyOfALiveScan` (K6 a). Opsional kedua: `testWorstCaseReplicaStillRenders` dengan replica `--bench` terbesar dari `replica-input.mjs` (salinan muncul ≤ 30 s, app tidak crash).
- `plan/alief/qa/replica-ui.sh`: `(cd ios && xcodegen)`, cek `localhost:8787/healthz` dan kontainer `supabase_db_shoo` (sama dengan `replica-e2e.sh:44-47`), direktori sementara `chmod 700`, `xcodebuild … -destination "platform=iOS Simulator,id=$SHOO_SIM"` di latar dengan `TEST_RUNNER_SHOO_LIVE_BACKEND=1 TEST_RUNNER_SHOO_LIVE_REPLICA=1 TEST_RUNNER_SHOO_REPLICA_DIR=$W TEST_RUNNER_SHOO_SHOT_DIR=<dir>`, tunggu `code.txt` ≤ 120 s, buat Protected + join + scan, tulis `scan.txt`, tunggu proses xcodebuild, `trap` cleanup `DELETE /devices/me` untuk Protected. Token Guardian tidak pernah keluar dari app: test menghapus device Guardian di akhir lewat alur hapus data di Profile (`DELETE /devices/me` dari app); kalau test gagal di tengah, device itu tertinggal di Supabase lokal (dibersihkan `supabase db reset`). Exit code = exit xcodebuild.
- Screenshot `plan/alief/qa/img/fase-23/live-replica-se.png` (kartu Detail dengan salinan) di PR.
- `plan/alief/qa/README.md`: satu baris perintah + prasyarat.

## Langkah kerja

### 23a-0 — repro (tanpa perubahan kode)
1. `source plan/alief/ref/sim.sh`; tetapkan `SHOO_SIM=483B28B6-913A-4C3A-8A4C-0C7219022682` (atau sisa setelah LANGKAH MANUAL 1).
2. `(cd ios && xcodegen)` (proyek tidak di-commit, `project.yml:1-2`; ulangi tiap kali file test ditambah), lalu `xcodebuild build-for-testing` sekali, lalu S1 untuk F2, F3, F4, F8 (normal + beban). Catat di log.
3. S2, S3, S4, S5. Isi tabel di log. Tanya K1–K4 ke Alief (di chat sesi; K5 lewat issue).

### 23a — `fix/C2-test-flakes`
1. TDD: test unit untuk flag `-UITestReduceMotion` (merah) → implementasi DEBUG → hijau.
2. `UITestSupport.swift` (lalu `cd ios && xcodegen`) + ganti F3, F4 dulu, jalankan S1 ulang (20/20 di bawah beban). Lalu file lain satu per satu, tiap file `-only-testing` hijau sebelum lanjut.
3. K3, K4 di unit test; `ShooAppTests` penuh hijau 3× lokal.
4. Seluruh scheme lokal sekali; catat durasi UI target sebelum/sesudah (harus tidak naik; dengan K2 diharapkan turun).
5. PR, 3 run CI hijau berturut-turut (push commit kosong tidak boleh; run dari commit review, dan `gh run rerun` atas run yang **hijau** dihitung sampel baru; rerun run merah tidak dihitung dan dicatat sebagai flake). Reviewer berurutan.

### 23b — issue K5
Template "Question / proposal", label `question`, assign @umarmuhdhor, judul `C2: iOS CI — pisah job unit/UI, xcresult, retry UI, timeout`. Pertanyaan bernomor = butir K5 1–5. "Sampai dijawab": 23a jalan, flake baru dicatat dengan id run.

### 23c — `feat/DT-04-live-replica-ui`
1. `pnpm -C backend/api dev` (dengan `.dev.vars`), `supabase start`.
2. Tulis `LiveReplicaUITests`, `cd ios && xcodegen` (skip tanpa variabel; cek `xcodebuild … -only-testing:ShooAppUITests/LiveReplicaUITests` tanpa variabel → skipped).
3. Tulis `replica-ui.sh`; jalankan 3× berturut-turut (rate limit `POST /devices` 10/jam/IP: 2 device per run, aman).
4. Screenshot, README, PR.

## LANGKAH MANUAL

- [ ] 1. (Alief, lokal) Hapus satu dari dua simulator "Shoo QA SE": `xcrun simctl delete 516DCC10-B989-4F69-8906-D3FFB9FDF4FC` (setelah cek tidak ada data uji yang dibutuhkan di sana). Sesudahnya `-destination name="Shoo QA SE"` tidak ambigu lagi, tapi skrip tetap memakai UDID.
- [ ] 2. (Alief, GitHub) Buat issue K5 (23b), tulis nomornya di log + PR 23a.
- [ ] 3. (Alief, GitHub) Setelah 23a merge: amati 5 run iOS berikutnya di PR mana pun; tiap merah dicatat di `log/fase-23.md` dengan id run dan hasil `--log-failed | grep -E "✘|: error: |XCTAssert"`.
- [ ] 4. (Alief, lokal) 23c dijalankan sebelum tiap PR yang menyentuh `Features/Detail/Replica*` atau `backend/api/src/{routes/replicas,services/replicas}.ts`; hasil (PASS + screenshot) ditulis di deskripsi PR.

## Verifikasi

```bash
source plan/alief/ref/sim.sh
SHOO_SIM=483B28B6-913A-4C3A-8A4C-0C7219022682
D="platform=iOS Simulator,id=$SHOO_SIM"
(cd ios && xcodegen)   # Shoo.xcodeproj tidak di-commit; wajib setelah file test baru

# repro / bukti flake hilang (sebelum 23a: tanpa -run-tests-until-failure supaya x/20 terhitung)
xcodebuild build-for-testing -project ios/Shoo.xcodeproj -scheme Shoo -destination "$D"
xcodebuild test-without-building -project ios/Shoo.xcodeproj -scheme Shoo -destination "$D" \
  -only-testing:ShooAppUITests/OnboardingUITests/testGuardianInviteSheetShowsCodeThenGoesToExtension \
  -only-testing:ShooAppUITests/DeepLinkUITests/testScanLinkOpensDetailWithVerdictButtonsForTheGuardian \
  -test-iterations 20 -run-tests-until-failure
xcodebuild test-without-building -project ios/Shoo.xcodeproj -scheme Shoo -destination "$D" \
  -only-testing:ShooAppTests/ReplicaHTMLTests -only-testing:ShooAppTests/WebKitTests \
  -test-iterations 20 -run-tests-until-failure

# seluruh scheme (sama dengan CI)
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "$D" > /tmp/shoo-test.log 2>&1; \
  grep -E ": error: |\] failed \(|recorded an issue|Expectation failed|Executed .* tests" /tmp/shoo-test.log

# live (23c), wrangler dev + supabase start dulu
bash plan/alief/qa/replica-ui.sh

# riwayat CI setelah merge
gh run list -R umarmuhdhor/Final-CH7 --workflow ios-app.yml --limit 20 --json databaseId,headBranch,conclusion,createdAt
```

## Kriteria selesai (DoD)

- [ ] `log/fase-23.md` berisi tabel flake (F1–F9) dengan hasil S1 sebelum/sesudah per test (x/20, normal dan di bawah beban) dan hasil S5 (serial/paralel).
- [ ] F2, F3, F4: 20/20 lolos di bawah beban CPU lokal setelah 23a.
- [ ] F1: PR #204 merge; test rasio + batas 5 s hijau 20/20.
- [ ] Launch pertama tiap UI test mock memakai `mock(_:)` dengan reset; `reset: false` hanya untuk relaunch di test yang sama (`GuardianUITests.testFamilyModeIsRememberedAfterRelaunch` tetap hijau); semua popup GD-01 lewat satu helper.
- [ ] 3 run CI berturut-turut hijau di PR 23a (rerun run hijau boleh sebagai sampel, rerun run merah tidak); durasi langkah `Test` tidak naik (angka di PR).
- [ ] Issue K5 dibuat dan nomornya di log, PR, dan TODO C2.
- [ ] 23c: `LiveReplicaUITests` di-skip di CI (terlihat "skipped" di log run PR), `replica-ui.sh` PASS 3× lokal, screenshot di PR, device uji terhapus (cek `select count(*) from devices` sebelum = sesudah, kecuali Guardian app kalau K6 memilih dibiarkan).

## Risiko & rollback

| Risiko | Dampak | Mitigasi | Rollback |
|---|---|---|---|
| Helper tap-ulang menutupi bug navigasi nyata (tap pertama memang hilang di app) | Bug UX lolos | Retry hanya untuk tap yang idempoten (Back, buka sheet); tiap retry di-log `XCTContext.runActivity("retap …")` sehingga terlihat di xcresult; F3/F4 dicoba manual di SE | Hapus retry dari helper, sisakan `tapWhenHittable` |
| `-UITestReduceMotion` membuat UI test tidak lagi menguji jalur animasi | Bug animasi tak terdeteksi | Screenshot/accessibility test tetap tanpa flag; flag hanya DEBUG | Hapus flag dari helper `mock(_:)` |
| `.serialized` untuk suite WebKit memperlambat unit test | Job lebih lama | Hanya ±10 test render; ukur di PR | Kembali ke dua suite terpisah |
| Batas perf longgar tidak menangkap regresi 2–4× | Regresi kecil lolos | Test rasio menangkap perubahan orde kompleksitas; perf halus di fase 22 (opt-in) | Turunkan batas |
| Retry di CI (K1) menutupi race nyata | Flake app ke produksi | Daftar retry di summary; dicabut setelah 2 minggu | Hapus flag retry (keputusan Umar) |
| Job tetap mendekati 30 menit sebelum K5 dijawab | Job dipotong tanpa ringkasan | 23a tidak menambah UI test di jalur default; K2 diharapkan memangkas waktu idle | — |
| 23c membuat device sungguhan di Supabase lokal | Data uji tertinggal | `trap` cleanup; rate limit 10/jam diperhitungkan | `supabase db reset` lokal |

## Catatan handoff

- Data mentah grep log CI ada di scratchpad sesi perencana; angka yang dipakai sudah disalin ke tabel flake. Run yang dibatalkan (`cancelled`, 17 dari 40 run iOS) berasal dari `concurrency.cancel-in-progress` saat push beruntun, bukan flake.
- 41190546465 tercatat `success` di `gh run list` karena attempt 2 lolos; kegagalan F3 hanya terlihat dengan `--attempt 1`. Untuk statistik flake berikutnya selalu cek `attempt` > 1.
- #204 merge 31 Okt 15:40 UTC: gerbang lama hilang dari `main`; PR iOS dari commit sebelum 8fd9751 tetap berisiko merah di F1 (rebase dulu). Batas 1 s tetap sampai K3.
- Penjelasan F4 (animasi `repeatForever` / `TimelineView` menahan idle XCUITest) masih dugaan; S1 dengan dan tanpa K2 membuktikannya. Kalau tidak terbukti, K2 tetap berguna untuk waktu, tapi jangan klaim sebagai penyebab di PR.
- Bentrok file dengan fase lain: 22b mengubah `PageCopyTests.swift:230-231` (K4 memindah `ReplicaSnapshotTests` ke bawah `WebKitTests`), 20d menyentuh Detail/`DetailUITests` (`-debug.replicaFixture YES`; 23a mengganti launch-nya ke `mock(_:)`), 26a menambah `InvitePasteUITests` + flag `-UITestPasteboard` di `AppEnvironment.swift` (sama dengan flag K2). Yang merge belakangan rebase dan menjalankan ulang `-only-testing` suite yang bentrok.
- Penyebab F1/F2 "suite paralel" ditulis sebagai dugaan karena scheme `parallelizable = "NO"` (C8); jangan klaim di PR sebelum S5.
- Usulan TODO baru (tidak diubah di fase ini): "C2-b: iOS CI di bawah 20 menit (pisah job / paralel)".

## Riwayat verifikasi

- Ronde 1 (31 Okt 2026): 16 temuan (0 kritis, 0 tinggi, 4 sedang, 12 rendah); diperbaiki: penyebab "suite Swift Testing paralel" di F1/F2/C7/C8/K4 jadi dugaan (scheme `parallelizable = "NO"` hasil XcodeGen 2.46.0 = serial menurut XcodeProj) + spike S5, K4 (a) jadi pencegahan; K6 tidak lagi mengecek "Copied from" (tidak muncul untuk domain acak, `PageCopyCaption.swift:60-66`, `ReplicaMeta.swift:104-109`, `replica-input.mjs:32`) tapi "Copy of the page" + argumen launch live; helper `mock(_:reset:)` agar `testFamilyModeIsRememberedAfterRelaunch` tidak patah, DoD ikut; `(cd ios && xcodegen)` di langkah, skrip, dan Verifikasi; rendah: S3 terjawab (`accessibilityReduceMotion` hanya `get`, kunci environment sendiri, shield masuk Peta), hitungan `timeout` C2, 8 file reset, `isHittable` C3, baris + waktu F5, baris F9, S1 tanpa `-run-tests-until-failure` untuk x/20, baris Biaya Free + privasi xcresult publik, branch `feat/DT-04-live-replica-ui`, "Fase berikutnya" = K3 (b) + bentrok file dengan 20b/22b, rujukan log fase 18 "di `main`", aturan rerun run hijau; dicatat tanpa diubah: tidak ada. Tidak ada nomor baris file ini yang dirujuk fase lain (fase 22 hanya merujuk "fase 23 LANGKAH MANUAL 1", tetap).
- Ronde 2 (31 Okt 2026): bagian yang diubah dibaca ulang (C4, C7, C8, F1, F2, K2, K4, K6, S1, S3, S5, Peta, Langkah, Verifikasi, DoD, handoff) + run CI F9/"bukan flake" dicek; 1 temuan rendah (kegagalan F9 terakhir 40903496403 adalah attempt 3 tanggal 30 Okt pada commit tanpa `7a274a1`, jadi klaim "hilang sejak `7a274a1`" tetap benar tapi perlu disebut), diperbaiki; 0 kritis/tinggi/sedang. Belum terverifikasi: Swift Testing serial/paralel di runner CI (S5; bukti hanya pemetaan XcodeProj + scheme lokal), retry Swift Testing di Xcode 26 (S2), penyebab F2/F3/F4/F8 (S1), idle XCUITest karena animasi, waktu UI paralel (S4).
- Cek lintas fase (1 Nov 2026): #204 MERGED 31 Okt 15:40 UTC (Prasyarat terpenuhi, Catatan handoff F1); rujukan log fase 18 `:128` → `:129` di `main`; bentrok `DetailUITests` dari fase 20 adalah sub-fase **20d** (app), bukan 20b (Fase berikutnya, handoff), plus bentrok `AppEnvironment.swift`/UITest dengan fase 26a; K5 tetap issue iOS CI sendiri, sedangkan usulan `.github/` lain (fase 21 K7 ops-watch + `backend.yml`, fase 22 K11 ukuran bundle) digabung ke satu issue CI backend fase 21. Baris `:83-87` (dirujuk fase 26) tetap.
