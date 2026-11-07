# Log fase 23 — Keandalan test + CI (C2)

- **Model:** Claude Opus 5.5. Sesi track app fase 19–26 (D-alief-C29), 1 Nov 2026.
- **Plan:** `fase-23-ci-reliability.md` (PR #207, branch `docs/alief-plan-19-26`).
- **Keputusan K:** rekomendasi R8 §c (D-alief-C29): K1 (c) retry hanya UI (usulan ke Umar), K2 (a) `-UITestReduceMotion`, K3 (a) batas 5 s + rasio, K4 (a) `WebKitTests` serial, K6 (a), K7 (a).
- **Pertanyaan ke Umar:** tidak lewat issue (D-alief-C29), tetapi di isi PR 23a bagian `## Questions for Umar` (= K5 butir 1–5, R8 §b no. 3).

## Status per sub-fase

| Sub-fase | Branch | PR | Status |
|---|---|---|---|
| 23a-0 repro | – | – | [x] (ringkas, lihat bawah) |
| 23a | `fix/C2-test-flakes` | lihat PR | [r] PR terbuka |
| 23b usulan CI | – | di PR 23a (`## Questions for Umar`) | [r] menunggu Umar |
| 23c live replica UI | `feat/DT-04-live-replica-ui` | #317 | [r] PR terbuka |

## 23a-0 — repro (S1, ringkas)

Simulator sendiri "Shoo Track App 19-26" (iPhone 17, iOS 26.5, `D0936FB9-5C36-49B1-B57F-9D71814DC090`). Dari `origin/main` aa976af, `build-for-testing` sekali lalu `test-without-building -test-iterations N`, sekali normal dan sekali dengan beban CPU (`yes > /dev/null` × 6). Skrip sesi (tidak di-commit).

Deviasi dari plan: 10 iterasi (bukan 20) untuk "sebelum" karena waktu sesi; "sesudah" juga di bawah beban. S2/S4/S5 tidak dijalankan di sesi ini (lihat Catatan handoff).

| Run | Kode | Normal | Beban CPU |
|---|---|---|---|
| Sebelum | `origin/main` aa976af | 20/20 lulus, 421 s | 20/20 lulus, 428 s |
| Sesudah | `fix/C2-test-flakes` 30bec00 | 20/20 lulus, 409 s | 20/20 lulus, 413 s |

F3 (`OnboardingUITests.testGuardianInviteSheetShowsCodeThenGoesToExtension`) + F4 (`DeepLinkUITests.testScanLinkOpensDetailWithVerdictButtonsForTheGuardian`), 10 iterasi masing-masing. **Flake tidak muncul secara lokal**, sebelum maupun sesudah, juga di bawah beban: penyebab di CI (runner GitHub lebih lambat) tidak bisa dibuktikan di Mac ini. Perbaikan 23a menutup penyebab yang terbaca dari log CI (animasi, popup GD-01, tap sebelum hittable, state sisa tanpa reset); bukti akhirnya DoD "3 run CI hijau berturut-turut".

## 23a — perubahan

### App (flag DEBUG saja)

- `App/AppEnvironment.swift`: `-UITestReduceMotion YES` (di blok `#if DEBUG`) → `reducesMotionForUITests = true` + `UIView.setAnimationsEnabled(false)` (transisi push/sheet UIKit).
- `App/RootView.swift`: `shooReduceMotion` = setelan "Kurangi gerakan" ∨ Reduce Motion iPhone ∨ flag UI test.
- `Features/Shield/GlowingShield.swift`, `Components/HalftoneShield.swift`: membaca `\.shooReduceMotion` (sebelumnya `\.accessibilityReduceMotion` langsung). Efek samping yang benar: setelan app "Kurangi gerakan" (PF-01) sekarang juga menghentikan napas/gelombang kedua shield, sama dengan layar lain yang sudah memakai `shooReduceMotion` (Splash, Onboarding, Connect, Detail). Tampilan default tidak berubah.
- `Features/Detail/ReplicaSnapshot.swift`: `render` sekarang membungkus `attempt(…) -> Result<PageCopy, RenderFailure>`; `RenderFailure` = `cancelled` / `load` / `place` / `snapshot`. `nil` dicatat ke `Log.replica` (kategori baru `replica`, `Support/Log.swift`) dengan nama tahap saja (`StaticString`, tanpa HTML/URL).

### Test

- Baru `UITests/UITestSupport.swift`: `UITestTimeout.screen = 10` / `.optional = 3`, `XCUIApplication.mock(_:reset:)` (selalu `-UITestMock YES -UITestReduceMotion YES`, plus `-UITestReset YES` kecuali `reset: false`), `dismissNotificationsReminder()`, `tap(_:until:retries:)` (tap ulang hanya kalau elemen masih ada, tiap tap ulang = `XCTContext.runActivity("Retap …")` di xcresult), `XCUIElement.tapWhenHittable()` (tunggu `isHittable` 2 s, lalu tetap tap: tombol toolbar iOS 26 seperti `profileButton` menerima tap tetapi tidak pernah melapor hittable).
- Launch mock diganti `mock(_:)` di 10 file: Onboarding, DeepLink, Profile, QALayout, Pairing, Guardian, Protected, Detail, Smoke, Session. `reset: false` hanya untuk relaunch di test yang sama: `GuardianUITests.testFamilyModeIsRememberedAfterRelaunch` (`launch(familyMode: nil)`) dan `OnboardingUITests.testExtensionOffStaysOnTurnOnScreenAndRelaunchNeverReturnsToModeChoice`. Tidak diubah: `AccessibilityAuditUITests`, `PairingGateUITests` (screenshot/audit butuh tampilan asli), `Live*`.
- F3: `OnboardingUITests` Back → `tap(_:until: invite.open)`. F4: `DeepLinkUITests` sekarang dengan reset (bug d7, R8 §d) + `tap(profileButton, until: profile.back)`. F5/F6: popup GD-01 lewat `dismissNotificationsReminder()` (Profile + QALayout ×2).
- K3: `ReplicaHTMLTests.unclosedMetaFloodStaysFast` < 5 s + baru `unclosedMetaFloodScalesLinearly` (median 3 run, 1 600 000 / 400 000 < 8×). `cancelledRenderLeavesNothing` < 5 s dan memeriksa `RenderFailure.cancelled`; baru `renderCancelledMidwayStopsAsCancelled` (batal setelah 50 ms).
- K4: baru `Tests/WebKitTests.swift` (`@Suite(.serialized)`); `ReplicaSnapshotTests` dan `ReplicaViewTests` jadi `extension WebKitTests` (ID test sekarang `ShooAppTests/WebKitTests/ReplicaSnapshotTests/…`).
- K2: `AppEnvironmentSessionTests.uiTestReduceMotionIsOnlyForTheArgument`.

### Hasil (1 Nov 2026, simulator sendiri, iPhone 17 iOS 26.5)

| Cek | Hasil |
|---|---|
| Scheme penuh `Shoo` (`build-for-testing` + `test-without-building`) | **TEST EXECUTE SUCCEEDED**, 801 s. Unit: 465 test di 44 suite lulus. UI: 72 dijalankan, 8 di-skip (Live*/opt-in), 0 gagal |
| Scheme penuh sebelum perbaikan `tapWhenHittable` (commit a922136) | 1351 s, 16 UI gagal: 15 `ProfileUITests` + F4, semua di `tapWhenHittable` karena `profileButton` (toolbar iOS 26) tidak pernah melapor `isHittable`. Diperbaiki di 30bec00 (tunggu 2 s, lalu tetap tap) |
| S1 sesudah | lihat tabel 23a-0 (40/40 lulus) |
| Tap ulang (`Retap …`) | 0 di scheme penuh dan di S1 sesudah |
| "not reported hittable, tapping anyway" | 18 di scheme penuh, 10 + 10 di S1: semua `profileButton`, tap pertama berhasil |

Durasi tidak dibandingkan ke `main`: baseline scheme penuh `main` tidak diukur di sesi ini (hanya S1).

### Review

- `ecc:swift-reviewer`: MEDIUM `tapWhenHittable` gagal dua kali → `guard` + satu `XCTFail`; MEDIUM `dismissNotificationsReminder` → selalu assert alert hilang; MEDIUM tap ulang bisa menekan dua kali → didokumentasikan (tap ulang hanya kalau elemen masih ada, tiap tap ulang tercatat di xcresult); MEDIUM rasio ukuran terlalu kecil → 400 000 / 1 600 000; catatan perubahan perilaku shield → ditulis di PR.
- `ecc:pr-test-analyzer`: MEDIUM batal di tengah render tidak dites → `renderCancelledMidwayStopsAsCancelled`. Celah yang tersisa: propagasi `shooReduceMotion` dari `RootView` ke shield tidak punya test (hanya flag di `AppEnvironmentSessionTests`); belum dites (satu baris `.environment` di `RootView`).

## 23c — `feat/DT-04-live-replica-ui` (7 Nov 2026)

Dari `origin/main` ce137f9. Simulator sendiri "Shoo 23c" (iPhone SE 3rd gen, iOS 26.5, `B3D21DB9-8F40-4A91-A9C0-6D7825619A90`), DerivedData sendiri. Worker lokal `pnpm -C backend/api dev` (port 8787, `.dev.vars` disalin dari checkout utama, tidak di-commit) + Supabase lokal `shoo` (dipakai bersama sesi lain; tidak ada vitest yang jalan saat run).

### Checklist

- [x] `UITests/LiveReplicaUITests.swift`: `testGuardianSeesThePageCopyOfALiveScan` (K6 a).
- [ ] Opsional `testWorstCaseReplicaStillRenders`: tidak dikerjakan (waktu + batas `POST /devices` 10/jam).
- [x] `plan/alief/qa/replica-ui.sh` (K7 a).
- [x] Tanpa variabel: test di-skip.
- [x] `replica-ui.sh` PASS 3× berturut-turut (malah 4×, lihat tabel).
- [x] Jumlah device sebelum = sesudah tiap run yang lulus.
- [x] Screenshot `plan/alief/qa/img/fase-23/live-replica-se.png`.
- [x] `plan/alief/qa/README.md`: satu baris perintah + prasyarat.
- [x] Tidak ada perubahan kode produksi (C12 terbukti: Debug simulator ke `http://localhost:8787`, `ReplicaLoader.isAllowed` menerima `http://localhost/replicas/…`).
- [ ] Review `ecc:swift-reviewer` → `ecc:security-reviewer` (Alief).

### File

| File | Isi |
|---|---|
| `ios/ShooApp/UITests/LiveReplicaUITests.swift` | Baru. Opt-in `SHOO_LIVE_BACKEND == "1" && SHOO_LIVE_REPLICA == "1" && SHOO_REPLICA_DIR != nil`. Onboarding Guardian lewat UI (`POST /devices` sungguhan) → kode keluarga dari sheet Invite ke `code.txt` → tunggu `scan.txt` (gagal cepat bila skrip menulis `error.txt`) → `shoo://scan/<id>` → `detail.pageCopy` berisi "Copy of the page" dan bukan "No copy of this page" / "Saving a copy of the page…" ≤ 30 s → `webViews.count == 0` → screenshot → Shield → Profile → hapus data (`DELETE /devices/me` dari app) → splash. `tearDown` mencoba hapus sekali lagi (best effort) bila test gagal di tengah |
| `plan/alief/qa/replica-ui.sh` | Baru. Cek `healthz` + kontainer `supabase_db_shoo`, `xcodegen`, `build-for-testing`, lalu `test-without-building -only-testing:ShooAppUITests/LiveReplicaUITests` di latar dengan `TEST_RUNNER_SHOO_LIVE_BACKEND=1 TEST_RUNNER_SHOO_LIVE_REPLICA=1 TEST_RUNNER_SHOO_REPLICA_DIR=$W TEST_RUNNER_SHOO_SHOT_DIR=…`; tunggu `code.txt` ≤ 120 s; Protected `POST /devices` + `POST /family/join` + replica `replica-input.mjs sample` + `POST /scans` (domain acak, fixture `blocked-92.json`); tunggu `pageReplicaUrl` sebagai pemilik ≤ 20 s; tulis `scan.txt`; tunggu xcodebuild; `trap` hapus Protected + direktori sementara (`chmod 700`). Env `SHOO_SIM` (default "Shoo QA SE" `483B28B6-…` dari plan), `SHOO_DD`, `SHOO_SHOT_DIR`. Exit = exit xcodebuild |
| `plan/alief/qa/README.md` | Satu bagian "Live replica UI (fase 23c)" |
| `plan/alief/qa/img/fase-23/live-replica-se.png` | Kartu Detail dengan "Copy of the page" + kartu bukti dengan gambar salinan (run 7) |

### Hasil

Skip (tanpa variabel): `xcodebuild test … -only-testing:ShooAppUITests/LiveReplicaUITests` → "Test skipped - needs replica-ui.sh …", `Executed 1 test, with 1 test skipped and 0 failures`, **TEST SUCCEEDED** (7 s).

| Run | Kode | Hasil | Total skrip | Kode di layar / scan siap | Device sebelum → sesudah |
|---|---|---|---|---|---|
| 1 | versi awal | FAIL: `app.open(url)` meluncurkan ulang app dengan `-UITestReset YES` → kembali ke splash | ±210 s | 78 s / 80 s | 0 → 1 (Guardian tertinggal) |
| 2 | `XCUIDevice.shared.system.open` | FAIL: salinan tampil, tapi Back dari Detail mendarat di Activity tanpa `profileButton`; xcodebuild lalu menggantung 2 j 40 m setelah test selesai (simulator ikut mati), dihentikan manual | – | 94 s / 98 s | 1 → 2 (Guardian tertinggal) |
| 3 | + tap tab Shield, + watchdog | PASS (screenshot terlalu jauh di-scroll) | 137 s | 85 s / 86 s | 2 → 2 |
| 4 | + drag 0.78→0.22 | PASS | 101 s | 52 s / 52 s | 2 → 2 |
| 5 | sama | PASS | 100 s | 49 s / 49 s | 2 → 2 |
| 6 | sama | PASS | 92 s | 43 s / 44 s | 2 → 2 |
| 7 | drag 0.78→0.40 (hanya posisi screenshot) | PASS | 99 s | 50 s / 50 s | 2 → 2 |

"Total skrip" termasuk `build-for-testing` inkremental (±3–10 s). Test case sendiri ±50 s (run 3: 71 s). Run 3–7 = 5× PASS berturut-turut; run 4–6 = 3× dengan kode yang sama. Run 7 hanya mengubah titik drag sebelum screenshot. Total 14 device dibuat (7 run × 2); setelah run 7 batas 10/jam sudah terpakai penuh, jadi tidak ada run ke-8.

Sisa: 2 device Guardian dari run 1 dan 2 (test gagal sebelum langkah hapus; token-nya hanya di Keychain simulator, jadi tidak bisa dihapus dari host tanpa menulis ke DB). Hilang dengan `supabase db reset` lokal (tidak dijalankan: DB dipakai bersama sesi lain). Protected tiap run terhapus (`DELETE /devices/me` 200).

### Deviasi dari plan

- Onboarding sudah didesain ulang setelah plan (#279–#282, #293, #307). Test memakai id hari ini: `splash.skip` → (`-settings.dataConsent granted` sebagai argumen launch, sehingga layar consent ON-01 tidak muncul; tanpa `-UITestMock` app live menanyakannya) → `name.field`/`name.continue` → `mode.guardian`/`mode.continue` → `invite.open` (tap pertama = `POST /devices`) → sheet `invite.code` → `invite.done` → `safariDefault.alreadyUsing` → `extensionOn.continue` → Shield + popup GD-01 (`dismissNotificationsReminder`). `splash.demo` (#307) tidak disentuh. Kode dibaca dari sheet Invite onboarding, bukan dari Profile seperti `LivePairingUITests` (lebih pendek, sama-sama `POST /family/code`).
- `openLink` memakai `XCUIDevice.shared.system.open(url)`, bukan `app.open(url)` seperti `DeepLinkUITests`: `app.open` meluncurkan ulang app dengan argumen launch, dan `-UITestReset YES` menghapus Guardian yang baru onboarding (test mock tidak terpengaruh karena state-nya datang dari argumen).
- Back dari Detail (dibuka lewat link) mendarat di tab Activity; Profile dibuka dari tab Shield, jadi test mengetuk Shield dulu.
- Skrip: `build-for-testing` di depan (tidak dihitung), baru `test-without-building` di latar, supaya batas 120 s untuk `code.txt` hanya mencakup test, bukan build.
- Skrip menunggu `pageReplicaUrl` sebagai pemilik scan (Protected) sebelum menulis `scan.txt`, supaya Detail tidak bergantung pada jendela retry app (`DetailModel.copyRetryDelays` 3 s + 12 s). Kegagalan sisi host ditulis ke `error.txt` agar test gagal cepat.
- Watchdog di skrip: 180 s setelah "Test Suite 'Selected tests' passed/failed", atau 15 menit sejak mulai, xcodebuild dihentikan dan hasil diambil dari log (run 2).
- Screenshot diambil setelah drag (tanpa momentum) supaya baris "Copy of the page" dan gambar salinan sama-sama terlihat di SE; `webViews.count == 0` dicek sebelum dan sesudah drag.
- Tanggal di kartu ("Opened October 21", "Copy of the page · Oct 21, 2026") berasal dari `detectedAt` fixture `blocked-92.json` dan `capturedAt` replica; tidak memengaruhi test.

### Review (berurutan, 7 Nov 2026)

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:swift-reviewer` | HIGH: PASS palsu: test yang di-skip (variabel hilang) atau gagal di sisi host tetap `PASS` exit 0. MEDIUM: watchdog 900 s dihitung dari sebelum build; tanpa `error.txt` saat kode tidak muncul; teardown dari Detail tidak sampai Profile (Guardian tertinggal); alert "Open" hanya 3 s; `curl` tanpa `--max-time`. LOW: `mktemp`/`devices` tanpa cek, `scan.txt` tidak atomik, token di argv, UDID tidak dicek, `URL(...)!`, `XCTFail` + `return`, `swipeDown()` tak perlu | Semua diperbaiki kecuali dua LOW gaya (predikat NOT berlebih, `assumeIsolated`) (2a1f78d): `HOST_FAIL` memaksa gagal, test case live wajib `passed`, watchdog dari mulai test, `--max-time`, token lewat `-H @file`, `scan.txt` lewat `mv`, cek simulator, teardown mundur dari Detail ke Shield, tunggu "Open" 10 s, error dilempar |
| `ecc:security-reviewer` | MEDIUM: tidak ada cek bahwa Worker dev memakai DB/Storage lokal (`.dev.vars` atau `--remote` bisa mengarah ke cloud). LOW: kode keluarga di argv; log DerivedData bisa world-readable kalau `SHOO_DD` di luar `$TMPDIR`; `REPO` kosong; Guardian tertinggal tanpa petunjuk. Token, trap, `rm -rf`, skip CI, `psql` baca saja, screenshot (data fixture saja): OK | Preflight: `localConnectionString` 127.0.0.1, `SUPABASE_URL` `.dev.vars` lokal, tolak `wrangler dev --remote`; body join dari file; `chmod 700` DerivedData; cek `REPO`; peringatan sisa Guardian + petunjuk `supabase db reset` (26b9514) |

Setelah review: tanpa variabel → "1 test skipped, 0 failures". Satu run live 22:51 WITA: `POST /devices` 429 (kuota lokal 10/jam/IP habis oleh sesi lain, 12 hit 14:38–14:46 UTC) → skrip melapor `FAIL` dengan exit 65, jalur gagal baru terbukti. Run live ulang setelah jendela kuota: lihat di bawah.

### Privasi (SECURITY §3)

| Butir | Hasil |
|---|---|
| Token | Tidak pernah dicetak. Token Guardian hanya di Keychain simulator (dihapus app lewat `DELETE /devices/me`); token Protected hanya di variabel shell, `dev.json` langsung dihapus, direktori sementara `chmod 700` dihapus di `trap` |
| Data uji | Hanya Supabase/R2 lokal; device dihapus di akhir (kecuali 2 sisa di atas) |
| Log / screenshot | Log xcodebuild di DerivedData (di luar repo); screenshot hanya data uji (domain acak, nama "Rina"/"Mom") |
| CI | Test di-skip tanpa variabel (±0 s), tidak ada secret di env job |
| Kode produksi | Tidak berubah |

## Privasi Apple (D-alief-40, SECURITY §3)

| Butir | Hasil |
|---|---|
| P6 log | `Log.replica` hanya nama tahap (`StaticString`), tanpa HTML, URL, atau id scan |
| Flag | `-UITestReduceMotion` hanya di `#if DEBUG`; Release tidak membacanya |
| Lainnya | Test saja; tidak ada data/izin/jaringan baru |

## Catatan handoff

- Bentrok file: 22b mengubah `PageCopyTests.swift` (`ReplicaSnapshotTests`, sekarang di dalam `extension WebKitTests` dan berindentasi +4). 26a memakai `XCUIApplication.mock(_:)` dan menambah flag di `AppEnvironment.swift` dekat `-UITestReduceMotion`. 20d mengubah launch `DetailUITests` (sekarang `mock(_:)`).
- Belum dijalankan: S2 (retry Swift Testing di Xcode lokal), S4 (UI paralel), S5 (Swift Testing paralel di scheme). Penyebab F2 tetap dugaan; log tahap `Log.replica` sekarang memberi bukti di run CI berikutnya.
- DoD "3 run CI hijau berturut-turut" dicek dari PR (Auto-fix aktif di sesi); dicatat di sini setelah ada.
