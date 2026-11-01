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
| 23c live replica UI | `feat/DT-04-live-replica-ui` | – | opsional, belum (urutan sesi: terakhir) |

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
