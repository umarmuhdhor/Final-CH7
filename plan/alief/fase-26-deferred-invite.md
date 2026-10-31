# Fase 26 — Undangan setelah install: tempel link undangan (TODO E4, PR-03 P1)

| Field | Nilai |
|---|---|
| Track | c (app dulu; backend hanya teks + link store) |
| Branch | 26-0 tanpa branch (spike S1–S4, hasil ke `log/fase-26.md`) · 26a `feat/PR-03-deferred-invite-app` (app: kartu tempel di ON-01 + baris tempel di Connect + perbaikan tempel link ke kolom kode) · 26b `feat/PR-03-deferred-invite-page` (backend: teks petunjuk halaman `/j/<kode>`, `APP_STORE_URL` setelah Q1 dijawab) |
| Prasyarat | 26a: tidak ada (Universal Link #129 sudah live, alur `pendingJoinCode` sudah di `main`). 26b teks: tidak ada. 26b `APP_STORE_URL`: jawaban issue Umar Q1 (link publik TestFlight / App Store) |
| Urutan | 26-0 spike → 26a (TDD, UITest, screenshot sebelum/sesudah) → 26b teks → issue Umar Q1 → 26b `APP_STORE_URL` (CI deploy) → uji manual M1–M6 |
| Requirement | PR-03 P1 (`docs/mandates/alief.md:64`), TODO E4 (`TODO.md:104`), SECURITY §3 P8 (pasteboard), T11 (link hanya mengisi kode), PRD persona 45–65 |
| Model + reviewer ECC | Opus 5.5 · 26a: `ecc:swift-reviewer` → `ecc:security-reviewer` · 26b: `ecc:typescript-reviewer` (satu per satu, tidak paralel) |
| Fase berikutnya | Tidak ada yang menunggu. TODO E6 (domain sendiri) nanti mengubah host di `DeepLink.inviteHosts` + AASA; fase ini tidak mengunci host |

## Tujuan

**Masalah.** Orang tua menerima link `https://shoo-api.afindo-mi01.workers.dev/j/<kode>` di WhatsApp, belum punya Shoo, tap "Install", pasang dari App Store/TestFlight, lalu tap "Buka" di App Store. Link asli hilang: app mulai dari splash tanpa kode, dan orang tua harus kembali ke WhatsApp dan mengetik 6 digit.

**Yang sudah ada (diverifikasi di `main` 2720b13, 31 Okt 2026):**

- Halaman undangan: `backend/api/src/routes/join-page.ts:96` `GET /j/:code`. Tombol "Install" (`:107`) membawa `data-invite="<INVITE_BASE_URL>/j/<kode>"`; skrip (`:60-61`) memanggil `navigator.clipboard.writeText(l)` di handler klik lalu `location.href = store` di `.finally` (jadi gagal salin tetap pindah ke store). Tanpa `navigator.clipboard` → navigasi biasa, tidak menyalin. Petunjuk: "We copy the invite, so Shoo can paste it after you install." (`:18`, ID `:29`). Test: `test/join-page.test.ts:31-41`.
- Link store: `storeUrl()` (`join-page.ts:39-47`) hanya menerima `https` ke `testflight.apple.com` / `apps.apple.com`. **Live sekarang `APP_STORE_URL` kosong** (`wrangler.jsonc:26`) → tombol menuju `https://apps.apple.com/` (beranda App Store, bukan halaman Shoo). Dicek `curl` 31 Okt: `href="https://apps.apple.com/"`.
- Universal Link **sudah live**: entitlement `applinks:shoo-api.afindo-mi01.workers.dev` (`ios/project.yml:59-60`, `ShooApp/Shoo.entitlements:7-10`), AASA `routes/app-site-association.ts:17-22` dengan `APPLINKS_APP_IDS = DWTZNGA7Y8.com.umarmuhdhor.shoo` (`wrangler.jsonc:29`). CDN Apple (`app-site-association.cdn-apple.com/a/v1/shoo-api.afindo-mi01.workers.dev`) sudah menyajikan `"/j/*"` (dicek 31 Okt). Issue #129 closed 26 Okt. Jadi kalau app terpasang, tap link `/j/<kode>` membuka app langsung.
- App: `RootView.swift:32` `.onOpenURL { env.open($0) }` → `AppEnvironment.swift:287-306` `open(_:)` → `DeepLink(url:)` (`App/DeepLink.swift:18-36`, `/j/<6 digit>` persis di `:59-63`, host di `:16`). `.join` mengisi `router.pendingJoinCode` (`Router.swift:51`), dibuang saat app ke background (`RootView.swift:35`). Di onboarding: `OnboardingModel.opensWithInvite` (`OnboardingModel.swift:102`) → ON-03 dilewati, mode Protected, Connect terisi (`:107-116`, `OnboardingFlow.swift:169-177`). Setelah onboarding: `router.showConnect()`.
- Grep `ios/ShooApp`: **tidak ada** `UIPasteControl`, `PasteButton`, `detectPatterns`. Satu-satunya akses pasteboard = menulis (`LinkCopy.swift:20`, `FamilyCodeModel.swift:173`).

**Bug kecil yang ditemukan.** Kolom kode memfilter digit dari seluruh teks (`ConnectModel.swift:60-65`). Menempel link `https://shoo-api.afindo-mi01.workers.dev/j/482193` ke kolom → digit `01` dari `mi01` ikut → kode jadi `014821` → `code_invalid`. Sama untuk seluruh pesan WhatsApp yang disalin Guardian ("… Open https://…/j/482193 or enter code 482193 in Shoo.", `FamilyCodeModel.swift:185-187`): digit `01482193482193` → `014821`. Diperbaiki di 26a (U6).

**Kode basi.** Kode berlaku 30 menit (`contracts/api.md:34`, `Models.swift:128`). Baris kedaluwarsa dihapus cron retensi harian `0 19 * * *` (`wrangler.jsonc:48`, `src/index.ts:8`) bila sudah lewat 1 jam dari `expires_at` (`cron/retention.ts:121`), jadi baris bertahan 1–25 jam setelah kedaluwarsa. Selama itu → `code_expired`; setelah dihapus → `code_invalid` ("That code doesn't match a family", `ConnectModel.swift:43`). `code_invalid` juga muncul seketika kalau Guardian membuat kode baru (`refresh: true`, `contracts/api.md:34`). Untuk link yang ditempel, pesan "cek 6 digit" membingungkan. Kedua error dihitung sebagai percobaan gagal (`services/family.ts:54`; 5/device dan 20/IP per 600 s, `db/repo/joinAttempts.ts:3-6`).

**Hasil akhir.**
1. App baru, clipboard berisi link undangan → splash menampilkan kartu "Punya undangan keluarga?" dengan tombol Tempel sistem. Satu tap → masuk ke Nama → Connect dengan kode terisi → tap Hubungkan. Tidak ada dialog "Izinkan tempel".
2. Clipboard tanpa URL → tidak ada kartu. App tidak pernah membaca isi clipboard tanpa tap.
3. Isi yang bukan link undangan → pesan ramah, tidak ada yang dikirim.
4. Kode basi → "Undangan ini sudah kedaluwarsa. Minta link baru ke keluargamu."
5. Tidak ada fingerprinting, tidak ada identifier baru, tidak ada perubahan kontrak.

## Bacaan wajib

- App: `App/{DeepLink,Router,RootView,AppEnvironment,AppConfig}.swift`, `Features/Onboarding/{SplashView,OnboardingFlow,OnboardingModel}.swift`, `Features/Pairing/{ConnectModel,ConnectView}.swift`, `Features/Detail/LinkCopy.swift` (pola protocol pasteboard + test), `Tests/PairingTests.swift:11-36` (tabel link valid/tidak), `UITests/PairingUITests.swift:100-120` (alur link di instal baru), `Resources/Localizable.xcstrings`
- Backend: `src/routes/join-page.ts`, `src/routes/app-site-association.ts`, `src/routes/terms.ts:78` (`/get` memakai `storeUrl` juga), `test/join-page.test.ts`, `wrangler.jsonc:22-30`
- Kontrak (baca saja): `contracts/api.md:40` (error join), `contracts/app-group-keys.md` "Deep links"
- Plan: `SECURITY.md` §3 P8, `log/DECISIONS.md:633-637` (D-alief-C11: salin undangan `.localOnly` + kedaluwarsa), fase 14 (pairing), `fase-23-ci-reliability.md:83-87` (helper UITest 23a), memori "UI PR screenshots"
- Apple (baca saat spike): `UIPasteboard.detectedPatterns(for:)` + `UIPasteboard.DetectedValues.probableWebURL` (iOS 15+; varian `detectPatterns(for: Set<DetectionPattern>)` iOS 14 sudah deprecated sejak iOS 15 di SDK 27.1), SwiftUI `PasteButton`, `UIPasteControl`, WWDC22 "What's new in privacy" (bagian paste)

## Cek kelayakan

| # | Butir | Bisa? | Temuan (`file:baris` / dokumen) | Tindakan |
|---|---|---|---|---|
| C1 | Halaman menyalin link sebelum ke store | Ya | `join-page.ts:60-61`: `writeText` dipanggil sinkron di handler klik (aktivasi pengguna ada), navigasi di `.finally`. Safari iOS ≥ 13.4 mendukung Async Clipboard di konteks aman (https; `localhost` juga aman) | Tetap. Uji perangkat M1 |
| C2 | Salin dari browser dalam app (WhatsApp, Instagram, Telegram) | Belum terverifikasi | Bergantung WKWebView pihak lain. Gagal → `.finally` tetap ke store, tidak ada salinan | M2: matriks manual; kalau gagal, jalur cadangan = ketik 6 digit (sudah ada) |
| C3 | Link store benar | **Tidak (sekarang)** | `APP_STORE_URL` kosong (`wrangler.jsonc:26`) → `https://apps.apple.com/` | Q1 ke Umar; 26b mengisi var |
| C4 | Universal Link live | Ya | Entitlement (`project.yml:59-60`), AASA live + CDN Apple, #129 closed | Jalur tempel hanya untuk instal pertama; link yang di-tap lagi setelah instal sudah membuka app |
| C5 | Deteksi URL tanpa dialog izin | Ya, belum diuji di repo | `try await UIPasteboard.general.detectedPatterns(for: [\.probableWebURL])` (iOS 15+). Docs Apple: hanya memberi tahu pola, "the system doesn't notify the user". `detectPatterns(for: [.probableWebURL])` (set `DetectionPattern`) deprecated sejak iOS 15 (swiftinterface SDK 27.1) → jangan dipakai. `detectValues`/`detectedValues` mengembalikan isi → dilarang. `changeCount` tanpa izin. Membaca `string`/`url`/`itemProviders` memicu dialog izin (iOS 16+) | S1; app tidak pernah membaca isi clipboard di luar `PasteButton` |
| C6 | Tombol tempel tanpa dialog | Ya | `PasteButton` SwiftUI (`init(payloadType:onPaste:)` iOS 16+, target app iOS 17, `project.yml:7-8`) = `UIPasteControl`: "paste without a user prompt" (docs Apple). Tombol "automatically validates and invalidates based on changes to the pasteboard on iOS" (nonaktif kalau isi tidak cocok tipe). Perilaku saat Settings "Paste from Other Apps" = Deny belum terverifikasi | `PasteButton(payloadType: String.self)` (K2); Deny → M4 |
| C7 | Label tombol mengikuti bahasa app (PF-01) | Belum terverifikasi | Label `PasteButton` dari sistem ("Paste"/"Tempel"), bukan `L10n.string(_:language:)` (`ConnectView.swift:122,130`). `.environment(\.locale)` (`RootView.swift:24`) mungkin tidak berlaku untuk kontrol UIKit aman | S3. Teks kartu kita tetap ikut bahasa app; label tombol sistem diterima apa adanya |
| C8 | Isi clipboard dari Safari bisa dibaca sebagai `String` | Belum terverifikasi | `writeText` menulis `public.utf8-plain-text`. Link yang disalin dari WhatsApp bisa bertipe `public.url` | S3: uji `String.self`; kalau `public.url` tidak masuk, tambah `PasteButton(supportedContentTypes: [.url, .plainText])` |
| C9 | Parser ketat `https://<host>/j/<6 digit>` | Ya | `DeepLink(url:)` sudah ketat (tes `PairingTests.swift:11-36`). Tapi juga menerima `shoo://join?code=` dan `http` localhost di Debug (`DeepLink.swift:21-23,32,40-43`) | `InvitePaste.code(from:)` memakai `DeepLink`, lalu hanya menerima skema `https` (+ `isLocalWorker` di Debug) |
| C10 | Gabung ulang alur yang ada | Ya | `router.pendingJoinCode` + `skipSplash()` (`OnboardingModel.swift:94-98`) → Nama → Connect terisi; tidak ada join otomatis (T11, `ConnectModel.swift:5,79-82`) | Kartu splash hanya mengisi `pendingJoinCode` |
| C11 | Pesan kode basi | Sebagian | `code_expired` punya pesan (`ConnectModel.swift:44`); setelah cron harian menghapus baris (1–25 jam setelah kedaluwarsa, `retention.ts:121`, `wrangler.jsonc:48`) atau setelah `refresh` → `code_invalid`. Keduanya dihitung rate limit join (`services/family.ts:54`) | K5: kode dari link/tempel → `invalid`/`expired` keduanya tampil "Undangan kedaluwarsa". Tempel tidak pernah join otomatis, jadi tidak menambah percobaan tanpa tap |
| C12 | Mock pasteboard di UITest | Ya, dua cara | (a) runner XCUITest menulis `UIPasteboard.general.string` (simulator berbagi pasteboard) lalu tap `PasteButton` asli — belum terverifikasi bahwa XCUITest bisa men-tap kontrol aman (S2). (b) Pola launch argument yang ada (`AppEnvironment.swift:55-62`, `-UITestMock`). Fase 23a menambah `UITests/UITestSupport.swift` (`XCUIApplication.mock`, `tapWhenHittable`) dan flag `-UITestReduceMotion` di `AppEnvironment` (`fase-23-ci-reliability.md:83-87`) | K6; pakai helper 23a kalau sudah merge |
| C13 | Perlu perubahan Umar | Tidak untuk app | Entitlement sudah ada (#129). `POST /family/join` tidak berubah. Pasteboard bukan "required reason API" → `ShooApp/PrivacyInfo.xcprivacy` (folder Alief) tidak berubah | Hanya Q1 (link store, pemilik App Store Connect) |

## Peta dampak (semua sisi)

| Sisi | Dampak |
|---|---|
| Backend | 26b: teks `installHint` EN/ID (`join-page.ts:18,29`) menyebut "buka Shoo lalu ketuk Tempel"; `APP_STORE_URL` di `wrangler.jsonc:26` diisi link dari Q1 (ikut mengubah `GET /get` "Bagikan Shoo", `terms.ts:78`). Tidak ada route baru, tidak ada DB |
| DB / migrasi | Tidak ada |
| App | Baru: `Features/Pairing/InvitePaste.swift` (parser + protocol `InvitePasteboard`), `Features/Pairing/InvitePasteCard.swift` (kartu + `PasteButton`). Ubah: `SplashView.swift` (kartu di atas kontrol slide), `OnboardingModel.swift` (`acceptPastedInvite(_:)`, karena `environment` `private`, `:69`), `ConnectView.swift` + `ConnectModel.swift` (baris tempel, `Problem.notAnInvite`, sumber kode, perbaikan tempel link ke kolom), `AppEnvironment.swift` (injeksi `InvitePasteboard`, Debug `-UITestPasteboard`), `Localizable.xcstrings` |
| Extension / kontrak | Tidak ada. Tidak ada usulan kontrak |
| `project.yml` / entitlements | Tidak ada (sudah diputuskan di #129) |
| CI | Test unit + UITest baru masuk `ios-app.yml` (scheme `Shoo` menjalankan `ShooAppUITests`, `project.yml:164-174`). Backend test di `backend.yml` |
| Privasi | Baca clipboard hanya saat tap `PasteButton`. Deteksi hanya jenis (`probableWebURL`), tanpa isi. Isi tidak dicatat di log, tidak disimpan, tidak dikirim; hanya kode 6 digit hasil parse yang pergi ke `POST /family/join` setelah tap Hubungkan. Clipboard dikosongkan setelah join berhasil bila `changeCount` belum berubah (K7) |
| Biaya Free | Nol. Tidak ada request baru |
| Dokumen | `SECURITY.md` §3 P8 ditambah kalimat baca-clipboard (di PR 26a), `backend/API.md` (catatan `APP_STORE_URL`), `TODO.md` E4, `PROGRESS.md`, `log/fase-26.md`, `log/DECISIONS.md` |

## Keputusan

| # | Pilihan | Rekomendasi | Alasan | Butuh jawaban |
|---|---|---|---|---|
| K1 | Di mana tombol tempel: (a) splash ON-01 saja, (b) Connect saja, (c) keduanya | **(c)** satu komponen `InvitePasteCard` | Instal pertama mendarat di splash: tap paling awal, mode Protected otomatis (`opensWithInvite`). Connect (onboarding, sheet Shield, "Punya kode undangan?" di Profil) menangkap orang yang melewatkan splash. Satu komponen, dua tempat | Alief |
| K2 | `PasteButton` SwiftUI vs `UIPasteControl` di-wrap `UIViewRepresentable` | **`PasteButton(payloadType: String.self)`** | Native SwiftUI, iOS 16+ cukup (target 17). Wrap UIKit hanya kalau S3 menunjukkan gaya/label tidak bisa diatur | — |
| K3 | Kapan mendeteksi (`detectedPatterns(for: [\.probableWebURL])`, error → anggap tidak ada) | `.task` saat kartu muncul + `scenePhase == .active` + `UIPasteboard.changedNotification`; ulang hanya kalau `changeCount` berubah | Pengguna bisa pindah ke WhatsApp lalu kembali. `changeCount` mencegah deteksi berulang | — |
| K4 | Isi yang diterima | **Ketat**: seluruh teks (trim, ≤ 512 byte, satu item) harus link `https://<inviteHosts>/j/<6 digit>`. `shoo://`, teks pesan berisi link, kode 6 digit polos → ditolak | Sumber jalur ini hanya `writeText` dari halaman kita (isi persis link). Ketat = permukaan serangan kecil. Kode polos tetap bisa diketik/ditempel di kolom kode | Alief (opsi longgar: ambil link dari dalam teks) |
| K5 | Pesan kode basi | Kode dari link/tempel + server `code_invalid` atau `code_expired` → pesan baru `staleInvite` | Pengguna tidak mengetik kode itu; "cek 6 digit" menyesatkan | — |
| K6 | UITest | (a) jalur utama: runner menulis `UIPasteboard.general.string`, tap `PasteButton` asli. (b) kalau S2 gagal: Debug `-UITestPasteboard <teks>` mengganti `InvitePasteboard` dengan palsu dan merender `Button` biasa dengan id yang sama yang memanggil handler yang sama | (a) menguji kontrol nyata. (b) tetap menguji seluruh alur setelah tap | — |
| K7 | Kosongkan clipboard setelah join berhasil | **Ya**, hanya bila `changeCount` == nilai saat tempel (`setItems([])` tanpa membaca) | Kode tidak tinggal di clipboard (halaman web tidak bisa set `.localOnly`/kedaluwarsa, berbeda dengan P8). Menulis tidak memicu dialog. Tidak menghapus isi baru milik pengguna | Alief |
| K8 | Link Install: TestFlight publik vs App Store | Isi `APP_STORE_URL` dengan link yang Umar berikan; App Store setelah rilis | `storeUrl` sudah menerima keduanya (`join-page.ts:39-47`). TestFlight publik butuh grup tester eksternal + Beta App Review | **Umar (Q1)** |
| K9 | Guardian dan tempel | Kartu splash hanya sebelum mode dipilih. Baris tempel di Connect tampil di ketiga tempat K1, **termasuk** Guardian yang membuka "Have an invite code?" di Profil (`ProfilePages.swift:203-211,345-353`, PF-01, `join:` override): itu niat eksplisit untuk bergabung. Link `/j/` yang dibuka Guardian tetap dibuang `open()` (`AppEnvironment.swift:289,299`) | Konsisten dengan T11 dan alur #175; tempel hanya mengisi kolom | — |

## Output

- `ios/ShooApp/Features/Pairing/InvitePaste.swift`: `enum InvitePaste { static func code(from items: [String]) -> String?; static func code(inText: String) -> String? }` (yang kedua longgar, hanya untuk kolom kode, U6) + `protocol InvitePasteboard { var changeCount: Int { get }; func hasProbableWebURL() async -> Bool; func clear(ifChangeCount: Int) }` + `extension UIPasteboard: InvitePasteboard` (`hasProbableWebURL` = `(try? await detectedPatterns(for: [\.probableWebURL]))?.contains(\.probableWebURL) ?? false`).
- `ios/ShooApp/Features/Pairing/InvitePasteCard.swift`: kartu (teks + `PasteButton`), id `invite.paste.card`, `invite.paste.button`, `invite.paste.error`.
- Perubahan `SplashView.swift`, `OnboardingModel.swift`, `ConnectView.swift`, `ConnectModel.swift`, `AppEnvironment.swift`, `Localizable.xcstrings`.
- Test: `Tests/InvitePasteTests.swift` (suite `InvitePasteTests`), tambahan suite `ConnectModelTests` di `Tests/PairingTests.swift:61`, `UITests/InvitePasteUITests.swift`.
- Backend 26b: `join-page.ts` teks, `wrangler.jsonc` `APP_STORE_URL`, `test/join-page.test.ts`.
- Screenshot sebelum/sesudah: `plan/alief/qa/img/PR-03-deferred-invite/` (di branch PR).
- `log/fase-26.md` (hasil spike + uji manual), entri `log/DECISIONS.md` (K1, K4, K7).

### Status UI dan teks (EN / ID)

| Status | Kapan | EN | ID |
|---|---|---|---|
| U0 tersembunyi | Tidak ada URL di clipboard, `pendingJoinCode` sudah ada, mode sudah dipilih, brand splash 1,5 s masih tampil, atau kode di Connect sudah 6 digit | — | — |
| U1 kartu splash | `hasProbableWebURL` = true | Judul "Got a family invite?" · isi "Paste the invite link you copied before installing. Shoo only looks at it when you tap Paste." | "Punya undangan keluarga?" · "Tempel link undangan yang kamu salin sebelum install. Shoo hanya membacanya saat kamu ketuk Tempel." |
| U2 baris Connect | Sama, kolom kode kosong; di Connect onboarding, sheet Shield, dan Profil "Have an invite code?" (K9) | "Copied an invite link?" + `PasteButton` | "Sudah menyalin link undangan?" + `PasteButton` |
| U3 berhasil | Link valid | VoiceOver: "Invite added." Splash → layar Nama; Connect → kode terisi | "Undangan ditambahkan." |
| U4 bukan undangan | Teks tidak lolos `InvitePaste.code` | "That isn't a Shoo invite link. Ask your family to send it again, or type the 6-digit code." | "Itu bukan link undangan Shoo. Minta keluargamu mengirim ulang, atau ketik 6 digit kodenya." |
| U5 basi | Kode dari link/tempel, server `code_expired`/`code_invalid` | "This invite has expired. Ask your family for a new link." | "Undangan ini sudah kedaluwarsa. Minta link baru ke keluargamu." |
| U6 kolom kode menerima link | Pengguna menempel link atau seluruh pesan undangan ke kolom kode | Teks berisi non-digit → token pertama yang `DeepLink` terima sebagai `/j/<kode>` (`InvitePaste.code(inText:)`); tidak ada → filter digit lama. Longgar di sini aman: hanya mengisi kolom (T11) | — |

Kartu: latar `OnboardingTheme.card`, ikon `link`, teks ≥ 17 pt Dynamic Type, tombol ≥ 44 pt, satu elemen VoiceOver untuk teks + tombol terpisah. Tidak ada Figma frame untuk kartu ini → tabel screenshot menulis "no Figma frame".

### Backend 26b teks

- EN `installHint`: "We copy the invite for you. After installing, open Shoo and tap Paste."
- ID: "Undangan sudah kami salin. Setelah install, buka Shoo lalu ketuk Tempel."

## Langkah kerja

### 26-0 Spike (tanpa branch, ±1 jam, hasil ke `log/fase-26.md`)

- S1: di simulator "Shoo QA SE" iOS 26.5 (`483B28B6-913A-4C3A-8A4C-0C7219022682`; ada dua dengan nama sama, pakai UDID), iPhone 17 iOS 27.0 (`3D780C26-2170-46A7-8EF9-59FB7C4597C5`) + iPhone Alief: salin link dari Safari, buka app Debug, panggil `detectedPatterns(for: [\.probableWebURL])`. Catat: tidak ada dialog/banner paste, hasil berisi `\.probableWebURL`. Ulangi dengan clipboard teks biasa (hasil kosong). Runtime iOS 17 tidak terpasang lokal (runtime: 26.3, 26.4, 26.5, 27.0): unduh (`xcodebuild -downloadPlatform iOS -buildVersion 17.5`, beberapa GB) kalau Alief mau, atau catat "iOS 17 tidak diuji" (ketersediaan API iOS 15/16 dicek compiler).
- S2: UITest kecil: runner `UIPasteboard.general.string = "https://shoo-api.afindo-mi01.workers.dev/j/482193"`, app menampilkan `PasteButton`, `app.buttons["invite.paste.button"].tap()`. Catat apakah closure dipanggil. Gagal → K6 (b).
- S3: label `PasteButton` dengan bahasa sistem EN + app ID (dan sebaliknya); payload `String.self` dari Safari `writeText` dan dari "Salin link" WhatsApp.
- S4 (perangkat): halaman `/j/<kode>` live di Safari → Install → kembali ke Home → buka app Debug → kartu muncul.

### 26a App (`feat/PR-03-deferred-invite-app`, dari `main`)

1. **Merah** `Tests/InvitePasteTests.swift`: tabel `InvitePaste.code(from:)`:
   - valid: `["https://shoo-api.afindo-mi01.workers.dev/j/482193"]`, dengan spasi/baris baru di ujung, host huruf besar.
   - ditolak: `shoo://join?code=482193`, `http://shoo-api…/j/482193` (Release), `https://evil.example/j/482193`, `/j/48219`, `/j/482193/x`, `/j/482193?x=1` (dicek: `DeepLink` hanya melihat path; K4 menolak query/fragment), teks pesan berisi link, `482193` polos, dua item, string > 512 byte, array kosong.
2. **Merah** `ConnectModelTests` (`Tests/PairingTests.swift:61`): `ConnectModel.code = "https://shoo-api.afindo-mi01.workers.dev/j/482193"` → `"482193"` (sekarang `"014821"`); seluruh pesan `FamilyCodeModel.inviteText` EN dan ID → `"482193"`; `"https://evil.example/j/111111"` → bukan link undangan, jatuh ke filter digit lama (perilaku sama dengan `main`); token diambil per spasi/baris baru, tanda baca di ujung token dibuang sebelum `URL(string:)`. Kode dari `prefill`/tempel + `code_invalid` → `problem == .staleInvite`; kode diketik + `code_invalid` → tetap `.invalid`. `pasted(["bukan link"])` → `.notAnInvite`, tidak memanggil join.
3. **Merah** test `InvitePasteboard` palsu: `hasProbableWebURL` dipanggil sekali per `changeCount`; `clear(ifChangeCount:)` tidak mengosongkan kalau `changeCount` berubah; join berhasil → `clear` dipanggil dengan nilai saat tempel.
4. **Hijau**: `InvitePaste.swift` (pakai `DeepLink(url:)`, lalu cek skema `https` atau `DeepLink.isLocalWorker`, tolak `query`/`fragment`), `ConnectModel` (`codeSource`, `Problem.notAnInvite`, `.staleInvite`, `pasted(_:)`, setter `code` mencoba `InvitePaste.code(inText:)` dulu bila ada non-digit), `InvitePasteCard`, kartu di `SplashView` (`controls` di `safeAreaInset`, hanya `!showsBrand && model.mode == nil && !model.opensWithInvite`), baris di `ConnectView`. Tempel di splash → `model.acceptPastedInvite(code)` (baru di `OnboardingModel`: `environment.router.pendingJoinCode = code` lalu `skipSplash()`; test unit di `OnboardingModelTests`, `Tests/OnboardingTests.swift:58`).
5. Log: hanya `Log.ui.info("Invite paste accepted")` / `Log.ui.info("Invite paste rejected")` (overload `StaticString` saja, `Support/Log.swift:22`), tidak pernah isi clipboard atau kode.
6. `Localizable.xcstrings`: semua string tabel U1–U5 EN + ID.
7. **Merah → hijau** `UITests/InvitePasteUITests.swift` (`-UITestMock YES -UITestReset YES`; kalau fase 23a sudah merge, pakai `XCUIApplication.mock(_:)` + `tapWhenHittable` dari `UITestSupport.swift`, dan rebase `AppEnvironment.swift` di atas flag `-UITestReduceMotion`):
   - `testPastedInviteOnNewInstallFillsConnect`: clipboard link `482193` → kartu splash → tap → Nama "Mom" → Connect `connect.code == "482193"`, `mode.protected` tidak ada → Hubungkan → `protectedBy.title`.
   - `testNoCardWithoutURL`: clipboard teks "halo" → `invite.paste.card` tidak ada (memastikan deteksi tidak membuka isi).
   - `testForeignLinkShowsError`: `https://evil.example/j/482193` → `invite.paste.error`, tetap di splash.
   - `testExpiredPastedInvite`: kode mock `999999` (`PairingUITests.swift:4`) → pesan "expired".
   - `testConnectSheetPaste`: Protected sudah onboarding, buka Connect dari Shield, tempel → kode terisi, tidak join sebelum tap (T11).
8. Screenshot sebelum (`main`) / sesudah (branch) di worktree terpisah, simulator "Shoo QA SE" lewat UDID (`483B28B6-…`, pastikan tidak dipakai sesi lain): splash U0, splash U1 (EN, ID), splash U4, Connect U2, Connect U5. Simpan di `plan/alief/qa/img/PR-03-deferred-invite/`, tabel Before | After | Expected di body PR.
9. Reviewer satu per satu: `ecc:swift-reviewer` → `ecc:security-reviewer` (fokus: tidak ada baca clipboard tanpa tap, tidak ada isi di log).

### 26b Backend (`feat/PR-03-deferred-invite-page`, dari `main`)

1. **Merah** `test/join-page.test.ts`: hint EN/ID baru. `APP_STORE_URL` sudah dicakup test `storeUrl` (`:113-121`); `call()` (`test/helpers/seed.ts:7-17`) tidak bisa mengganti env, jadi kasus halaman dengan link TestFlight memakai `joinPage.request("/j/482193", {}, { ...env, APP_STORE_URL: "https://testflight.apple.com/join/AbCd1234" })` (`env` dari `cloudflare:test`) → `href` sama.
2. **Hijau**: teks `TEXT.en.installHint` / `TEXT.id.installHint`.
3. Setelah Q1 dijawab: isi `APP_STORE_URL` di `wrangler.jsonc:26` (var publik, bukan secret), PR terpisah kecil atau commit di PR yang sama kalau belum merge. Deploy hanya lewat CI `backend.yml` setelah merge.

## LANGKAH MANUAL

- [ ] Buka issue Umar (template question, label `question`, assign `umarmuhdhor`), judul `PR-03: store link for the invite page Install button`:
  1. Q1: Link mana yang dipakai tombol "Install" di `/j/<code>` sekarang: link publik TestFlight (`https://testflight.apple.com/join/…`, butuh grup tester eksternal + Beta App Review) atau belum ada? Sekarang `APP_STORE_URL` kosong dan tombol membuka beranda App Store.
  - Tautkan issue #55 (TestFlight QA, App Store Connect) di body; topik tetap terpisah.
  2. Q2 (info, tidak memblokir): fase 26 tidak mengubah `project.yml`, entitlements, atau `contracts/`. Mohon koreksi kalau ada aturan App Review tentang `PasteButton` yang perlu dicek.
  - Sampai dijawab: 26a tetap jalan dan diuji dengan simulator + build Debug; `APP_STORE_URL` tetap kosong.
- [ ] Setelah 26b merge: cek run `backend.yml` hijau, lalu `curl -s https://shoo-api.afindo-mi01.workers.dev/j/482193 | grep -o 'id="install" href="[^"]*"'` dan `curl -sI https://shoo-api.afindo-mi01.workers.dev/get | grep -i '^location'` (link store sama).
- [ ] M1 iPhone, Safari: buka `/j/<kode aktif>` (Guardian buat kode di app), app **tidak** terpasang → Install → clipboard berisi link (tempel di Notes).
- [ ] M2 matriks browser dalam app: WhatsApp, Telegram, Instagram → catat apakah link tersalin.
- [ ] M3 instal TestFlight (kalau Q1 ada link) → tap "Buka" → kartu muncul → tempel → join berhasil, PR-02 menampilkan nama Guardian.
- [ ] M4 Settings → Apps → Shoo → Paste from Other Apps = Deny → catat apakah tombol tetap bekerja tanpa dialog (belum terverifikasi di docs). Gagal → kartu tetap menyebut "ketik 6 digit" (U4).
- [ ] M5 tunggu > 30 menit, tempel → pesan U5.
- [ ] M6 app sudah terpasang: tap link di WhatsApp → app terbuka langsung (Universal Link), tanpa kartu.

## Verifikasi

```bash
# dari root repo; SIM_ID = "Shoo QA SE" iOS 26.5 (ada dua dengan nama sama, jadi pakai id)
SIM_ID=483B28B6-913A-4C3A-8A4C-0C7219022682
# 26a
(cd ios && xcodegen)
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -only-testing:ShooAppTests/InvitePasteTests -only-testing:ShooAppTests/ConnectModelTests \
  -only-testing:ShooAppTests/DeepLinkTests -only-testing:ShooAppTests/OnboardingModelTests \
  -only-testing:ShooAppUITests/InvitePasteUITests -only-testing:ShooAppUITests/PairingUITests
# tidak ada baca isi clipboard di luar PasteButton (harus kosong)
/opt/homebrew/bin/rg -n 'UIPasteboard\.general\.(string|strings|url|urls|items|itemProviders|image|images)\b|detectValues|detectedValues|detectPatterns\(for: \[\.' ios/ShooApp --glob '!**/Tests/**' --glob '!**/UITests/**'
# log tempel hanya StaticString (tidak ada argumen kedua; harus kosong)
/opt/homebrew/bin/rg -n 'Log\.ui\.(info|error|debug)\("Invite paste[^"]*",' ios/ShooApp

# 26b
(cd backend/api && npx vitest run test/join-page.test.ts && npx tsc --noEmit)
```

## Kriteria selesai (DoD)

- [ ] Grep `ios/ShooApp` (di luar test) tidak menemukan `UIPasteboard.general.string|strings|url|urls|items`.
- [ ] `InvitePasteTests` ≥ 14 kasus, semua hijau; di `ConnectModelTests` link dan pesan undangan EN/ID yang ditempel ke kolom jadi `482193` (bukan `014821`).
- [ ] 5 UITest `InvitePasteUITests` hijau di CI `ios-app.yml`; `PairingUITests` tetap hijau.
- [ ] S1 tercatat: tidak ada banner/dialog paste saat deteksi (Shoo QA SE 26.5 + iOS 27.0 + satu iPhone; iOS 17 diuji atau dicatat "tidak diuji").
- [ ] PR 26a berisi tabel screenshot sebelum/sesudah EN + ID untuk U0, U1, U4, U2, U5.
- [ ] Join hanya setelah tap Hubungkan (T11), dibuktikan `testConnectSheetPaste`.
- [ ] Clipboard dikosongkan setelah join berhasil hanya bila `changeCount` tetap (unit test).
- [ ] 26b: hint EN/ID baru di halaman live; `APP_STORE_URL` terisi (atau issue Q1 masih terbuka dan ditautkan di TODO E4).
- [ ] TODO E4 dicentang dengan nomor PR; `SECURITY.md` P8 menyebut aturan baca-clipboard.

## Risiko & rollback

| Risiko | Mitigasi | Rollback |
|---|---|---|
| XCUITest tidak bisa tap `PasteButton` (S2) | K6 (b): tombol Debug pengganti dengan handler sama | — |
| Label `PasteButton` beda bahasa dengan app (C7) | Teks kartu kita yang menjelaskan; label sistem pendek | Terima |
| Browser dalam app tidak menyalin (C2) | Halaman tetap menampilkan kode besar; ketik manual | — |
| Kode basi milik keluarga lain (kode kedaluwarsa bisa dipakai ulang, `codes.ts:28`) | Peluang ≈ jumlah kode aktif / 1 000 000; join tetap butuh tap; PR-02 menampilkan nama Guardian dan bisa diputus di Profil. Risiko sama dengan mengetik kode lama | — |
| Clipboard web tidak `.localOnly` (tersinkron Universal Clipboard ±2 menit) | Isi hanya link + kode 30 menit, tanpa nama; K7 mengosongkan setelah join | — |
| Kode basi yang ditempel berulang menghabiskan jatah percobaan join (5/device per 600 s, `joinAttempts.ts:3`) | Join hanya setelah tap; pesan U5 menyuruh minta link baru, bukan mencoba lagi | — |
| Kartu muncul untuk URL apa pun (deteksi hanya tahu "ada URL") | Teks kartu bertanya, tidak menuduh; isi dicek hanya setelah tap | — |
| Regresi onboarding | UITest `PairingUITests` lama tetap jalan | Revert PR 26a (app saja, tanpa migrasi). 26b: revert teks, CI deploy ulang |

## Catatan handoff

- Tidak butuh perubahan dari Umar selain Q1 (link store). Entitlement Associated Domains sudah ada sejak #129 (`project.yml:59-60`); kontrak `POST /family/join` tidak berubah; pasteboard bukan required-reason API.
- Belum terverifikasi: S1 (tanpa banner di perangkat; docs Apple menyatakan `detectedPatterns` tidak memberi notifikasi), S2 (tap `PasteButton` di XCUITest), S3 (bahasa label, tipe payload), C2 (browser dalam app), M4 (tombol saat Deny), iOS 17 (runtime tidak terpasang). Hasil spike menentukan K6 dan kemungkinan `supportedContentTypes`.
- Universal Link live berarti jalur tempel hanya penting untuk instal pertama dari App Store/TestFlight. Jangan menambah fingerprinting atau layanan deferred-link pihak ketiga (melanggar SECURITY dan aturan "tanpa SDK pihak ketiga", `ios/ShooApp/CLAUDE.md`).
- Kalau domain pindah (TODO E6): `DeepLink.inviteHosts` (`DeepLink.swift:16`) + AASA + `INVITE_BASE_URL`; `InvitePaste` ikut otomatis karena memakai `DeepLink`.

## Riwayat verifikasi

- Ronde 1 (31 Okt 2026): 13 temuan (0 kritis, 0 tinggi, 5 sedang, 8 rendah); diperbaiki: `detectPatterns(for: [.probableWebURL])` deprecated sejak iOS 15 (swiftinterface SDK 27.1) → `detectedPatterns(for: [\.probableWebURL])` (docs Apple: tanpa notifikasi), `detectValues`/`detectedValues`/`itemProviders` dilarang di grep; Verifikasi bisa dijalankan (subshell dari root, suite nyata `ConnectModelTests`/`DeepLinkTests`/`OnboardingModelTests`, `id=` Shoo QA SE, bukan "iPhone 16" yang tidak ada); S1/DoD tanpa simulator iOS 17 (runtime lokal 26.3–27.0) → 26.5 + 27.0 + iPhone, iOS 17 opsional; K9 vs K1 (baris tempel juga untuk Guardian di Profil "Have an invite code?"); U6 juga menangani seluruh pesan undangan yang ditempel ke kolom (`FamilyCodeModel.swift:185-187` → tetap `014821`); rendah: cron retensi harian (kode basi 1–25 jam, bukan ±90 menit) + rate limit join, nomor baris (`join-page.ts:18,39-47`, `Models.swift:128`, `contracts/api.md:34` menggantikan "contracts C24", D-alief-C11 `:633-637`), `OnboardingModel.acceptPastedInvite` (`environment` private), test 26b tanpa override env di `call()`, `GET /get` ikut `APP_STORE_URL`, C6 "Deny" belum terverifikasi + validasi otomatis `PasteButton`, helper UITest fase 23a, tautan #55 di Q1; dicatat tanpa diubah: tidak ada. Tidak ada fase lain yang merujuk baris fase 26.
- Ronde 2 (31 Okt 2026): bagian yang diubah dibaca ulang; 1 temuan rendah (harapan test `"https://evil.example/j/111111 482193"` salah: filter digit lama menghasilkan `111111`) → kasus diganti + aturan token/tanda baca; dicek: `joinPage.request(path, init, env)` (Hono), HEAD `/get` dijawab route GET, teks undangan EN/ID diikuti spasi setelah link, grep Verifikasi kosong di `main`. 0 kritis/tinggi/sedang. Belum terverifikasi: S2 (XCUITest men-tap `PasteButton`), S3 (bahasa label, tipe payload WhatsApp), C2 (browser dalam app), M4 (Deny), iOS 17 (runtime tidak terpasang), Q1 (link store, Umar).
- Cek lintas fase (1 Nov 2026): nomor baris file yang sama disamakan (`storeUrl` = `join-page.ts:39-47` di K8, sama dengan Tujuan/C3; scheme = `project.yml:164-174`, sama dengan fase 23). 26a dan fase 23a sama-sama mengubah `AppEnvironment.swift` (flag `-UITestPasteboard` vs `-UITestReduceMotion`) dan UITest helper: yang merge belakangan rebase (sudah di langkah 7). Bug U6 (`ConnectModel.swift:60-65`) bisa diperbaiki lebih dulu sebagai PR kecil terpisah tanpa menunggu spike. Q1 tetap issue sendiri; terkait issue E6 fase 24 (pemegang akun App Store Connect, #55). Tidak ada fase lain yang merujuk baris fase 26.
