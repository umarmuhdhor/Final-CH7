# Log fase 15 — Push tap + validasi: GD-06, GD-07 (+ ON-05 token, EX-06 bagian app)

- **Status:** [r] — PR #54 `feat/GD-06-07-push-validation`, reviewer @umarmuhdhor. **Bertumpuk di atas #52** (fase 14) yang bertumpuk di atas #42 (fase 13): base PR = `main`, jadi diff PR ikut menampilkan commit #42 dan #52 sampai keduanya di-merge.
- **Model:** Claude Opus 5.5, mode auto. 22 Okt 2026.
- **Rencana:** `log/fase-15-plan.md` (ditulis langsung; subagent satu per satu untuk dua review).

## Ringkasan rencana

1. `NotificationRouter` (scanId dari payload, token hex) + `DeliveredPushes`.
2. `AppDelegate` lewat `@UIApplicationDelegateAdaptor`: token APNs, banner foreground, tap → Detail (juga cold start).
3. `Router.openDetail` / `openActivity`; `AppEnvironment.open` untuk `shoo://scan/{id}` + `shoo://activity`.
4. Token Guardian saja (`PATCH /devices/me {apnsToken}`), registrasi tiap app aktif.
5. Uji: unit, `DeepLinkUITests` (mock), `LivePushUITests` + `qa/push-e2e.sh` (tiga kondisi app, backend lokal).

## Checklist langkah (file fase "Langkah kerja")

- [x] 1. Registrasi APNs setelah izin (ON-05), token hex via `PATCH /devices/me` — Guardian saja (C14). Di simulator token tidak pernah datang (lihat Deviasi); jalur PATCH teruji unit, uji token asli = D7.
- [x] 2. Tap push (foreground, background, terminated) → Detail `scanId`; `shoo://scan/<id>` → Detail yang sama (Protected tanpa tombol), `shoo://activity` → Activity, lainnya → Shield.
- [x] 3. GD-07: It's safe / Not safe tanpa konfirmasi (tombol fase 03, `POST /verdicts` asli lewat `ApiRepository` fase 13).
- [x] 4. Uji ujung-ke-ujung lokal pakai UDID (bukan `booted`): `POST /scans` (curl, Protected) → `push_log` → `xcrun simctl push` → tap → Detail → It's safe → `GET /verdicts` sebagai Protected = `safe`.
- [ ] 5. Uji perangkat (dua iPhone, push sandbox nyata) → menunggu B6/B7 + D7 (LANGKAH MANUAL). Bukan blocker kode (PROMPT 6h).
- [x] 6. `ecc:security-reviewer`, lalu `ecc:swift-reviewer` (berurutan).

## File dibuat/diubah

- Baru: `App/AppDelegate.swift`, `Support/NotificationRouter.swift` (`NotificationRouter`, `DeliveredPushes`), `Tests/PushTests.swift`, `UITests/DeepLinkUITests.swift`, `UITests/LivePushUITests.swift` (opt-in), `plan/alief/qa/{push-blocked,push-warning}.apns`, `plan/alief/qa/push-e2e.sh`, `plan/alief/qa/img/push-15/*.png`.
- Diubah: `ShooApp.swift` (delegate adaptor, environment dari delegate), `App/{AppEnvironment,Router,DeepLink}.swift`, `Support/NotificationPermission.swift` (registrasi pindah ke `registerForPushIfAllowed`, TODO fase 15 hilang), `Features/Onboarding/OnboardingModel.swift` + `Features/Shield/FamilyShieldView.swift` (registrasi setelah izin), `Features/Profile/ProfileView.swift` + `Features/Pairing/FamilyCodeModel.swift` (hapus notifikasi tampil, C18), `Features/Pairing/ConnectView.swift` (perbaikan fase 14: placeholder "4-digit code" tembus di kotak kosong), `Tests/AppEnvironmentSessionTests.swift`.
- Tidak disentuh: `contracts/`, `ios/project.yml`, `ios/ShooShared/`, `ios/ShooExtension/`, `ios/ShooLiveActivity/`, `detector/`, `ai/`, `.github/`, Info.plist/entitlements (`aps-environment` sudah dari C3, PR #27).

## Hasil verifikasi (22 Okt 2026, Xcode, simulator iPhone 17 Pro iOS 27.0)

| Uji | Hasil |
|---|---|
| Unit (`ShooAppTests`, Guardian sim) | 281/281 lulus (Swift Testing, 29 suite; +19 baru di `PushTests`) |
| UI penuh (`ShooAppUITests`, Protected sim) | 51 dijalankan: 43 lulus, 8 opt-in dilewati (live/gate), 0 gagal. Run sebelumnya (paralel dengan e2e) 1 gagal di `OnboardingUITests` (layar mode tidak muncul dalam 5 s), lulus di run tunggal → beban mesin, bukan regresi |
| `DeepLinkUITests` | 3/3: link scan saat sheet Profile terbuka → Detail + tombol verdict (Guardian); Protected → Detail tanpa tombol; `shoo://activity` → daftar |
| Ujung-ke-ujung `LivePushUITests` + `qa/push-e2e.sh` | Lulus tiga kondisi (foreground, background, terminated); `push_log` = `logged` untuk tiap scan; `GET /verdicts` Protected = `safe` (`byName` Rina). Lulus 4× berturut-turut setelah perbaikan crash + review |

Waktu e2e (run terakhir, `push-host.log`):

| Kondisi | `POST /scans` → `push_log` | `simctl push` → Detail (termasuk tap) | tap It's safe → Protected `safe` |
|---|---|---|---|
| foreground | 178 ms | 7221 ms | 546 ms |
| background | 145 ms | 5508 ms | 194 ms |
| terminated | 216 ms | 6629 ms | 551 ms |

- "push to Detail" = dari `simctl push` sampai Detail tampil, **termasuk** XCUITest menunggu banner lalu men-tap (bukan latensi app).
- "GET /verdicts" = dari verdict tampil di Detail (catatan "Marked safe by you") sampai Protected menerima `safe`. Target ≤ 1 s terpenuhi di ketiga kondisi.
- `push_log` = `logged`: wrangler dev lokal tanpa kunci APNs memakai `LogSender` (fase 11). Token APNs Guardian di DB lokal diisi dummy oleh script karena simulator tidak menerima token (Deviasi).
- Target end-to-end ≤ 10 s (layar blokir Protected terbuka, polling extension 5 s) dicatat untuk QA-E2E (fase 16) di iPhone.

Bukti: `qa/img/push-15/push-{foreground,background,terminated}-{2-detail,3-safe}.png` (Detail dari tap push, lalu "Marked safe by you"). Screenshot banner tidak disimpan: tangkapan layar XCUITest jatuh setelah animasi banner (elemennya ada dan di-tap, terbukti dari Detail).

## Bug ditemukan saat uji

- **Crash tap push dari background** (`NSInternalInconsistencyException`, `-[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]` dari `@objc closure #1 in AppDelegate.userNotificationCenter(_:didReceive:)`): bentuk `async` delegate. Diganti bentuk completion handler (C17), uji tiga kondisi lulus.
- **Placeholder Connect tembus** (fase 14): teks "Kode 4 angka" terlihat di sela kotak kosong. `TextField("")` + `accessibilityLabel` tetap.

## DoD + bukti

- [x] `NotificationRouter` teruji unit (payload blocked/warning, tanpa/rusak `scanId`, hex); tap push membuka Detail yang benar di tiga kondisi (XCUITest + `simctl push`, screenshot).
- [x] Verdict langsung berlaku; Protected `GET /verdicts?domain=` = `safe` ≤ 1 s setelah tap (tabel waktu). Target ≤ 10 s end-to-end → QA-E2E.
- [~] README §7 butir 2–3 terbukti di simulator; perangkat fisik → D7 / QA-E2E.

## Temuan review

| Review | Ringkas | Tindakan |
|---|---|---|
| `ecc:security-reviewer` | 0 CRITICAL, 0 HIGH, 2 MEDIUM, 5 LOW. Path injection `scanId` tidak bisa (gerbang `isPlainSegment` dua lapis); link/push tidak pernah mengubah state tanpa tap; token tidak pernah di-log; Protected tidak mengirim token | MEDIUM diperbaiki: delegate `nonisolated` + kerja di MainActor; cache token direset saat `register()`. LOW diperbaiki: registrasi APNs hanya lewat `registerForPushIfAllowed` (Guardian); banner foreground hanya untuk Guardian di tab utama; tap push diabaikan di Protected; script e2e dikeraskan (cek localhost + container, path dikutip, `SP` tidak boleh `/`/`$HOME`, nilai ke Python lewat argv, id scan divalidasi). LOW diterima: link `shoo://scan` di Protected membuka Detail (kontrak: layar blokir extension memakainya; server memeriksa kepemilikan); tap saat cold start sebelum sesi diketahui habis → Detail sebentar lalu layar "Session expired" |
| `ecc:swift-reviewer` | 0 CRITICAL, 1 HIGH, 7 MEDIUM, 6 LOW | HIGH diperbaiki: race token (ditandai sebelum request + `pushTokenEpoch` dinaikkan `register()`), dua test race baru. MEDIUM diperbaiki: `springboard` computed `@MainActor`; tulis file test `throws`; test e2e dipecah (`AppState` enum + helper); predikat Guardian satu tempat (`isGuardianInMainScreen`) + anotasi `@MainActor`; `Router.reset()` memakai `closeSheets()`. LOW diperbaiki: default `launchOptions` dihapus; komentar `DeepLink` diperbarui; UIKit keluar dari `AppEnvironment` (closure registrasi dari `AppDelegate`); `Calls` private `@MainActor`; test sesi habis. Ditolak dengan alasan: `@Sendable` di completion handler (header SDK tidak memberi anotasi itu; tanda tangan harus sama dengan protokol, ditinjau ulang saat pindah Swift 6); polling file di test e2e (proses host tidak bisa memberi sinyal ke runner; sama dengan fase 14); ganti nama `NotificationRouter` (nama dari dokumen fase); UI test tambahan sheet "Turn on"/alert di atas Detail (`closeSheets` teruji unit untuk semua sheet Router); suite `UserDefaults` test (pola sama di semua test env) |

## Cek privasi Apple (SECURITY §3)

| # | Hasil |
|---|---|
| P1 | Manifest tidak berubah; API notifikasi/APNs bukan required-reason API. OK |
| P2 | Data baru di server: token APNs **Guardian saja** (sudah di kontrak + label fase 11). Protected tidak mendaftar APNs. OK |
| P3 | Tidak berubah; hapus data juga menghapus notifikasi yang tampil (C18). OK |
| P4 | Tidak ada penyimpanan baru: token terakhir terkirim hanya di memori. OK |
| P5 | Tidak berubah. OK |
| P6 | Token dan `scanId` tidak pernah di-log; hanya event "APNs registration requested" / "APNs token received" / "APNs token sync failed". OK |
| P7 | Izin notifikasi tetap di ON-05 / pengingat; registrasi APNs hanya setelah izin `authorized`. OK |
| P8 | Tidak berubah. – |
| P9 | Tidak berubah. – |
| P10 | Payload app hanya membaca `scanId`; teks push dari server = nama + kata kerja + skor, tanpa URL/domain (fase 11, `qa/*.apns`). Banner foreground hanya untuk Guardian di tab utama. OK |
| P11 | Tidak berubah (fase 16). – |
| P12 | Tidak berubah. – |
| P13 | Notifikasi yang sudah tampil dihapus saat hapus data, putus hubungan, Remove anggota, sesi habis, Start again (C18). OK |

## Deviasi

- PR bertumpuk di atas #52 (dan #42).
- `route(url:)` tidak dibuat di `NotificationRouter`: parser link sudah ada di `App/DeepLink.swift` (fase 14), dipakai ulang.
- **Token APNs di simulator:** `registerForRemoteNotifications` dipanggil ("APNs registration requested"), tetapi `apsd` simulator menjawab `found cached token … token: (null)` dan tidak memanggil `didRegister…` maupun `didFail…`. Build simulator tanpa tim penanda tangan tidak mendapat token. Jalur `PATCH apnsToken` teruji unit (`PushTests`) dan di cloud fase 11 (curl); token asli dari app → D7.
- Requirement GD-06/GD-07 belum dicentang `[x]` di tabel requirement PROGRESS (aturan: track hanya mengedit baris fasenya); mandat dicentang.

## Placeholder aktif

- `App/AppConfig.swift`: `TODO(sync:imelda)` URL layanan AI (D-alief-C05).
- Deferred deep link setelah install (PR-03 P1): TODO E4.

## LANGKAH MANUAL

Uji push nyata di iPhone (langkah 5 file fase, D7). Butuh tim Apple berbayar Umar ("umar muhdhor") — keputusan koordinator.

1. **Umar (B7):** buat kunci APNs `.p8` Sandbox di tim "umar muhdhor" (developer.apple.com → Keys → Apple Push Notifications service). Bagikan ke Alief lewat password manager (bukan chat), bersama Key ID, Team ID, bundle ID + App Group yang terdaftar di tim itu (draf pesan: TODO C23).
   **Alief** memasang di Worker cloud (nilai ditempel di prompt, tidak pernah sebagai argumen):
   ```bash
   cd backend/api
   base64 < ~/Downloads/AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | npx wrangler secret put APNS_KEY_P8_B64
   npx wrangler secret put APNS_KEY_ID
   npx wrangler secret put APNS_TEAM_ID
   ```
   Lalu set `"APNS_TOPIC": "<bundle ID dari Umar>"` di `wrangler.jsonc`, deploy (agent bisa membuat commit-nya kalau diminta), dan hapus file `.p8` dari Downloads.
2. **Alief (B6):** `cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig`, isi `DEVELOPMENT_TEAM` = Team ID "umar muhdhor", `SHOO_BUNDLE_ID` + `SHOO_APP_GROUP` sesuai App ID di tim itu; `(cd ios && xcodegen)`.
3. **Alief (D7):** build Debug menunjuk `localhost` (tidak terjangkau dari iPhone), jadi di Xcode: Product → Scheme → Edit Scheme → Run → Build Configuration **Release** (menunjuk Worker cloud; tetap ditandatangani profil development → APNs Sandbox), pilih iPhone Alief, Run. Onboarding sebagai Guardian + izinkan notifikasi. Cek token sampai: `cd backend/db && supabase db query --linked "select length(apns_token) from devices where name='<nama>'"` = 64.
4. **Alief:** iPhone kedua (atau simulator) sebagai Protected yang join kode keluarga; `POST /scans` (curl dengan token Protected, resep log fase 11 butir 4) → notifikasi "… hit a blocked site · 92%" muncul di iPhone → tap → Detail → It's safe. `push_log.result` = `sent`. Catat waktu notifikasi → layar blokir terbuka (target ≤ 10 s) untuk QA-E2E.
5. Ketik lagi: `Saya Alief, track c. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).`

## Catatan handoff

- Uji e2e lokal: `wrangler dev` (`pnpm -C backend/api dev`) + Supabase lokal; `xcodebuild build-for-testing … -derivedDataPath $SP/dd` lalu `SP=<dir> GUARD_UDID=<udid> zsh plan/alief/qa/push-e2e.sh`. Hasil di `$SP/push-host.log`, screenshot di `$SP/pushshots`.
- Payload manual: `xcrun simctl push "$GUARD_UDID" "$BUNDLE_ID" plan/alief/qa/push-blocked.apns` (scanId fixture `…4e03`; untuk backend lokal pakai scanId asli dari `POST /scans`).
- Swift 6: tinjau ulang `@Sendable` completion handler di `AppDelegate` saat pindah mode bahasa.
