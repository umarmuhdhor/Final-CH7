# Log fase 26 — Undangan setelah install (PR-03 P1, TODO E4)

- **Model:** Claude Opus 5.5. Sesi track app fase 19–26 (D-alief-C29), 1 Nov 2026.
- **Plan:** `fase-26-deferred-invite.md` (PR #207, branch `docs/alief-plan-19-26`).

## Status per sub-fase

| Sub-fase | Branch | PR | Status |
|---|---|---|---|
| d1 / U6 (tempel link ke kolom kode) | `fix/PR-03-invite-paste` | #208 | [r] PR terbuka |
| 26-0 spike | – | – | [x] simulator (S1, S2); S3 sebagian; S4 + iPhone = LANGKAH MANUAL |
| 26a app | `feat/PR-03-deferred-invite-app` | lihat PR (stacked di atas #208 dan 23a) | [r] PR terbuka |
| 26b backend | `feat/PR-03-deferred-invite-page` | – | bukan track app |

## d1 / U6 — `fix/PR-03-invite-paste` (1 Nov 2026)

Bug d1 di `plan/alief/ref/R8-fase-19-26-lintas.md` §d: setter `ConnectModel.code` (`ConnectModel.swift:60-65` di `main` aa976af) memfilter digit dari seluruh teks. Link `https://shoo-api.afindo-mi01.workers.dev/j/482193` yang ditempel jadi `014821` (digit `01` dari `mi01` ikut), lalu `code_invalid`. Seluruh pesan undangan dari `FamilyCodeModel.inviteText` juga jadi `014821`.

Perbaikan = U6 fase 26, dipisah jadi PR kecil (R8 §a baris 0), tanpa menunggu spike:

- Baru `Features/Pairing/InvitePaste.swift`: `InvitePaste.code(inText:)`. Teks dipecah per spasi/baris baru; tiap token ≤ 512 byte dipotong mulai dari `https://`/`http://` (untuk `Link:https://…` atau Markdown `[x](https://…)`), tanda baca/simbol di ujung dibuang, lalu `DeepLink(url:)` harus memberi `.join` dengan skema `https` (atau `http` ke Worker lokal di Debug, `DeepLink.isLocalWorker`). Token pertama yang lolos menang. `shoo://` tidak diterima di sini (hanya link halaman `/j/`).
- `ConnectModel.code`: teks yang semuanya digit tetap jalur lama. Ada non-digit → `InvitePaste.code(inText:)` dulu; tidak ada link undangan kita → filter digit lama (sama dengan `main`, juga untuk link asing; dicatat di komentar). Hasil hanya mengisi kolom, join tetap butuh tap Hubungkan (T11).
- Tidak ada perubahan tampilan (kolom yang sama, hanya isi hasil tempel yang berbeda), jadi gerbang UI/screenshot tidak berlaku. Tidak ada akses pasteboard baru, tidak ada log isi teks.
- 26a nanti menambah `InvitePaste.code(from:)` (ketat, K4) + `InvitePasteboard` ke file yang sama.

### Test

- `Tests/InvitePasteTests.swift` (baru, suite `InvitePasteTests`): 7 kasus link dalam teks → `482193`, 8 kasus tanpa link undangan → `nil`, token > 512 byte dilewati.
- `Tests/PairingTests.swift` `ConnectModelTests`: `pastedInviteLinkGivesItsCode` (4 kasus), `pastedInviteMessageGivesItsCode` (pesan EN + ID → `482193`, sebelumnya `014821`), `foreignLinkFallsBackToTheDigits`.

### Hasil verifikasi

Simulator sendiri "Shoo Track App 19-26" (iPhone 17, iOS 26.5, `D0936FB9-5C36-49B1-B57F-9D71814DC090`), Xcode lokal, 1 Nov 2026:

| Perintah | Hasil |
|---|---|
| `xcodebuild test … -only-testing:ShooAppTests/InvitePasteTests -only-testing:ShooAppTests/ConnectModelTests -only-testing:ShooAppTests/DeepLinkTests -only-testing:ShooAppTests/FamilyCodeModelTests` (sebelum perbaikan review) | 30 test / 4 suite lulus |
| `xcodebuild test … -only-testing:ShooAppTests -only-testing:ShooAppUITests/PairingUITests` (akhir) | `ShooAppTests` 468 test / 44 suite lulus (8,6 s); `PairingUITests` 6/6 lulus (92,8 s); `TEST SUCCEEDED` |

### Review

- `ecc:swift-reviewer`: 0 kritis/tinggi. Sedang 1 (link menempel teks lain, mis. `Link:https://…` → tetap `014821`) → diperbaiki (potong dari skema) + 2 kasus test. Sedang 2 (link asing jatuh ke filter digit, `https://evil.example/j/111111 482193` → `111111`) → dipertahankan sesuai U6 ("tidak ada → filter digit lama"), sekarang tertulis di komentar `InvitePaste.code(inText:)`; hanya mengisi kolom, tidak join. Rendah: kasus `http://shoo-api…` → `014821` rapuh (bergantung `AppConfig.apiBaseURL`) → dihapus.

### Privasi Apple (D-alief-40, SECURITY §3)

| Butir | Hasil |
|---|---|
| P8 pasteboard | Tidak ada baca pasteboard baru; teks sudah ditempel pengguna sendiri ke `TextField` |
| Log | Tidak ada log baru |
| Data keluar | Tidak berubah: hanya 6 digit ke `POST /family/join` setelah tap |
| P1–P7, P9–P13 | Tidak tersentuh |

## 26a — `feat/PR-03-deferred-invite-app` (1 Nov 2026)

Stacked: dibuat dari `fix/C2-test-flakes` (23a, helper `XCUIApplication.mock` + `UITestSupport`) lalu merge `fix/PR-03-invite-paste` (#208, `InvitePaste.code(inText:)`). Keputusan K memakai rekomendasi file fase (R8 §c: K1 (c), K4 ketat, K7 ya; D-alief-C29).

### 26-0 spike

Simulator sendiri "Shoo Track App 19-26" (iPhone 17, iOS 26.5), build Debug branch ini, UITest sekali pakai (tidak di-commit).

| Spike | Hasil |
|---|---|
| S1 deteksi tanpa prompt | Runner menulis `UIPasteboard.general.string = "https://shoo-api.afindo-mi01.workers.dev/j/482193"` → kartu splash muncul (`detectedPatterns(for: [\.probableWebURL])`). Tidak ada alert "Allow Paste" dan tidak ada banner "pasted from" di screenshot. Teks biasa (`halo`) → tanpa kartu (`testNoCardWithoutURL`) |
| S2 tap `PasteButton` asli dari XCUITest | **Berhasil**: `invite.paste.button` ada, hittable, enabled; tap → closure jalan → layar Nama. Tanpa alert di app maupun SpringBoard |
| S3 label bahasa | Label `PasteButton` mengikuti bahasa sistem (simulator EN → "Paste"), bukan bahasa app; lihat screenshot ID. Payload dari Safari `writeText` / WhatsApp: tidak diuji (butuh perangkat, LANGKAH MANUAL M1–M2) |
| S4 perangkat | Tidak dijalankan: tidak ada iPhone fisik di sesi ini (LANGKAH MANUAL M1, M3) |
| iOS 17 | Tidak diuji (runtime tidak terpasang); ketersediaan API dicek compiler (`detectedPatterns` iOS 15, `PasteButton` iOS 16) |

Karena S2 berhasil: **K6 (a)**. UI test menulis pasteboard simulator lalu menekan `PasteButton` asli; tidak ada tombol palsu Debug. `tearDown` mengosongkan pasteboard supaya suite lain tidak melihat kartu.

### Perubahan

- `Features/Pairing/InvitePaste.swift`: `InvitePaste.code(from:)` (ketat, K4: tepat satu item, trim, ≤ 512 byte, tanpa spasi di dalam, `https` atau Worker lokal Debug, tanpa query/fragment, lalu `DeepLink`), protocol `InvitePasteboard` (`changeCount`, `hasProbableWebURL()` = `detectedPatterns(for: [\.probableWebURL])`, `clear(ifChangeCount:)` = `setItems([])` hanya bila `changeCount` sama), `extension UIPasteboard: InvitePasteboard`, dan `InviteClipboard` (`@Observable`): `offersPaste`, `refresh()` (sekali per `changeCount`, K3), `accept(_:)` (parse + log `StaticString` saja + ingat `changeCount` saat tempel), `joined(code:)` (K7).
- `Features/Pairing/InvitePasteCard.swift`: gaya `.splash` (U1: ikon link, judul, alasan, tombol) dan `.connect` (U2: satu baris + tombol). Selalu ada di hierarki (ukuran nol saat tersembunyi) supaya `.task`, `scenePhase == .active`, dan `UIPasteboard.changedNotification` memicu `refresh()`. Tombol = `PasteButton(payloadType: String.self)`, juga di UI test (K6 a). Saat kartu tampil, gambar slide mengecil setinggi kartu (minimal ¼ layar) supaya judul dan teks slide tetap terlihat (ditemukan di screenshot spike: judul terpotong kartu).
- `App/AppEnvironment.swift`: `inviteClipboard` (default `UIPasteboard.general`; test unit memberi pasteboard palsu).
- `Features/Onboarding/OnboardingModel.swift`: `acceptPastedInvite(_:)` (kode → `router.pendingJoinCode` → `skipSplash()`; alur link yang sudah ada: Nama → Connect terisi, ON-03 dilewati), `offersInvitePaste` (`mode == nil && !opensWithInvite`).
- `Features/Onboarding/SplashView.swift`: kartu di atas Skip/Next di `safeAreaInset` (hanya setelah brand splash, karena `controls` ada di `slidesView`). U4 di bawah tombol. VoiceOver: "Invite added." / pesan U4.
- `Features/Pairing/ConnectModel.swift`: `Problem.notAnInvite` (U4), `.staleInvite` (U5, K5: kode dari link/QR/tempel + `code_invalid`/`code_expired`; kode yang diketik tetap `.invalid`/`.expired`), `pasted(_:)`, `clipboard`, `clipboard?.joined(code:)` setelah join berhasil.
- `Features/Pairing/ConnectView.swift`: baris U2 di footer yang dipin (di atas catatan salinan 14 hari dan tombol Hubungkan), hanya di tab Kode, saat `state == .entering` dan kode < 6 digit. Awalnya di bawah kolom kode: screenshot menunjukkan baris itu tergeser ke bawah footer saat keyboard muncul, dan iOS mengabaikan tap pada `PasteButton` yang tertutup (UI test `testConnectSheetPaste` gagal). Footer selalu terlihat di atas keyboard. `connect.error` sekarang punya id scroll sendiri (`connect.problem`): saat pesan muncul, target scroll berubah dan form menggulirnya ke atas footer. Tanpa itu pesan U5 menimpa catatan 14 hari (3/3 run screenshot; pesan "kode kedaluwarsa" yang diketik 2/3).
- Tiga pemakai `ConnectModel` memberi `env.inviteClipboard`: onboarding, sheet Shield (`MainTabView`), Profil "Have an invite code?" (K9).
- `Features/Onboarding/OnboardingStyle.swift` (`OnboardingFormPage`): gulir ulang ke target saat tinggi footer berubah (baris tempel muncul/hilang). Hanya bila ada target (kolom fokus atau ada pesan).
- `Resources/Localizable.xcstrings`: 6 string EN + ID (U1 judul + isi, U2, U3, U4, U5). Label tombol Paste dari iOS.

### Test

- `InvitePasteStrictTests`: 3 diterima + 16 ditolak (K4, termasuk user/password/port dari review security). `InvitePasteTests` (U6, dari #208) 16 kasus. Total kasus `InvitePaste` ≥ 14 (DoD).
- `InviteClipboardTests`: tanya sekali per `changeCount`; `clear` hanya bila `changeCount` sama; kode lain / tempel ditolak tidak pernah `clear`; deteksi tanpa jawaban ditanya lagi; jawaban untuk pasteboard lama dibuang; setelah tempel diterima kartu hilang sampai ada salinan baru.
- `ConnectModelTests`: `linkedCodeThatFailsIsAStaleInvite` (`000000`, `999999`), `typedCodeThatFailsStaysInvalid`, `pastedCodeEditedByHandThatFailsIsInvalid`, `everyJoinErrorHasItsMessage` sekarang mengetik kodenya (kode dari init = link → U5), `pasteFillsTheCodeOrSaysItIsNotAnInvite` (tidak join sebelum tap, `clear` setelah join), pesan EN/ID untuk `.notAnInvite`/`.staleInvite`.
- `OnboardingModelTests.pastedInviteOnTheSplashGoesToTheName`.
- `UITests/InvitePasteUITests.swift` (5): `testPastedInviteOnNewInstallFillsConnect`, `testNoCardWithoutURL`, `testForeignLinkShowsError`, `testExpiredPastedInvite`, `testConnectSheetPaste`. Deviasi: `testConnectSheetPaste` membuka Connect dari Profil Guardian "Have an invite code?" (K9), bukan dari Shield, karena Protected di mock selalu sudah punya Guardian (tombol `shield.connect` tidak ada).

### Verifikasi (1 Nov 2026, simulator sendiri iPhone 17 iOS 26.5)

| Cek | Hasil |
|---|---|
| Scheme penuh `Shoo` (sebelum perbaikan a11y terakhir) | **TEST EXECUTE SUCCEEDED**, 845 s. Unit 484 test di 47 suite lulus; UI 77 dijalankan, 8 di-skip (Live*/opt-in), 0 gagal |
| Run akhir (kode final) | Unit 484/47 suite lulus; UI `InvitePasteUITests` 5/5, `PairingUITests` 6/6, `OnboardingUITests` 10/10, `ProfileUITests` 17/17. **TEST EXECUTE SUCCEEDED** |
| Spike S1 + S2 | lihat 26-0 di atas |
| Screenshot U0/U1/U4/U2/U5 + kode diketik kedaluwarsa | sebelum (`origin/main` aa976af) / sesudah, EN + ID, terang + gelap: 32 file di `plan/alief/qa/img/PR-03-deferred-invite/`. Onboarding/Connect selalu terang (`colorScheme(.light)`), jadi gelap = terang |

Yang ditemukan lewat screenshot (dan diperbaiki sebelum PR): judul slide terpotong kartu; baris tempel Connect tertutup footer (tap `PasteButton` diabaikan iOS); pesan U5 menimpa catatan 14 hari. Ketiganya dicek ulang di screenshot sesudah (U5 + kode diketik: 6/6 run bersih).

### Review (berurutan, D-alief: satu per satu)

- `ecc:swift-reviewer` (tanpa CRITICAL/HIGH). Diperbaiki: `pasteRejected` di splash direset saat ada salinan baru (`checkedChangeCount` sekarang observable); jarak 16 pt di bawah kartu hanya saat kartu tampil (tanpa kartu tata letak = `main`); `InviteClipboard` `@MainActor` (+ `init` nonisolated untuk argumen default `AppEnvironment`); deteksi tanpa jawaban (`detectedPatterns` gagal) ditanya lagi (`hasProbableWebURL() -> Bool?`). Test baru: jawaban untuk pasteboard lama dibuang, tempel diterima menyembunyikan kartu sampai ada salinan baru, kode tempel yang diedit tangan lalu gagal = `.invalid`. Dibiarkan (LOW): pasteboard tetap berisi link A kalau pengguna mengedit ke kode B lalu join B; `pasted` hanya di memori.
- `ecc:security-reviewer` (tanpa CRITICAL/HIGH; P8, P6, D-alief-40 lulus). Diperbaiki MEDIUM: `code(from:)` menolak user/password dan port (kecuali Worker lokal), +3 kasus test. Dibiarkan (LOW): kartu muncul untuk link web apa pun (deteksi tanpa membaca isi tidak bisa membedakan host; link asing dijawab U4); `setItems([])` menghapus semua item, dijaga `changeCount`; `code(inText:)` (U6, #208) tanpa batas total panjang input (masukan pengguna sendiri).
- `ecc:a11y-architect`. Diperbaiki: di ukuran teks aksesibilitas kartu splash hanya judul + tombol dan gambar slide boleh mengecil sampai 0, baris Connect hanya tombol; tempel gagal berulang di Connect diumumkan lagi; gulir ulang footer mengikuti `shooReduceMotion`. Dibiarkan: footer `OnboardingFormPage` (catatan 14 hari + Hubungkan + Nanti saja) bisa melebihi layar di ukuran AX terbesar (sudah ada sebelum fase 26; usulan: footer bisa di-scroll), fokus VoiceOver setelah kartu hilang, ikon kartu ukuran tetap.

### LANGKAH MANUAL (sisa, perangkat)

M1–M6 dari plan fase 26 tetap untuk Alief (iPhone fisik, TestFlight). Pertanyaan PR-03 Q1/Q2 ada di PR 26a bagian `## Questions for Umar` (tanpa issue, D-alief-C29). `SECURITY.md` P8 perlu satu kalimat tentang kartu tempel (di luar folder sesi ini; untuk PR plan).
