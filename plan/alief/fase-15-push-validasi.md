# Fase 15 — Push tap + validasi live: GD-06, GD-07

| Field | Nilai |
|---|---|
| Track | c |
| Branch | `feat/GD-06-07-push-validation` |
| Prasyarat | 14; 11 (relay); C3 (`aps-environment` + capability Push + Team ID di `project.yml`, oleh Umar) untuk uji perangkat |
| Requirement | GD-06, GD-07, ON-05 (token APNs ke server), EX-06 (bagian app) |
| Model | Opus 5.5 · `ecc:swift-concurrency-6-2` |
| Fase berikutnya | 16 |

## Tujuan

Guardian menerima push, tap membuka Detail yang benar, dan It's safe / Not safe langsung berlaku sehingga layar blokir Protected terbuka (EX-06 lewat polling extension Umar).

## Bacaan wajib

- PRD §8.3 GD-06, GD-07, §9; `contracts/api.md` Push payloads, Verdicts
- `ref/R4` §3–§4, fase 03 (tombol + optimistic update), fase 11

## Output

- `UIApplicationDelegateAdaptor` di `ShooApp.swift`: `didRegisterForRemoteNotificationsWithDeviceToken` → `updateMe(apnsToken:)`; `UNUserNotificationCenterDelegate` → baca `scanId` → `Router.openDetail(scanId)` (juga saat app cold start)
- Tidak ada edit `Shoo.entitlements`/Info.plist (di-generate XcodeGen dari `project.yml` milik Umar). `aps-environment` = permintaan C3; tanpa itu registrasi APNs di simulator tetap jalan dan `simctl push` tetap bisa diuji
- `Support/NotificationRouter.swift`: fungsi murni `route(userInfo:) -> Route?` (dibaca `scanId`), dipakai delegate dan test
- `plan/alief/qa/push-blocked.apns` dan `push-warning.apns`: payload kontrak + `"Simulator Target Bundle": "com.shoo.app"`
- Detail: tombol memanggil `POST /verdicts` asli; error → rollback + pesan
- Test (Swift Testing): `NotificationRouter` untuk payload blocked/warning/tanpa `scanId`/`scanId` rusak, token hex encoding, optimistic verdict + rollback, Detail dimuat dari `scanId` yang belum ada di cache

## Langkah kerja

1. Registrasi APNs setelah izin (ON-05), kirim token hex via `PATCH /devices/me`.
2. Tap push (foreground, background, terminated) → Detail `scanId`.
3. GD-07: It's safe / Not safe tanpa konfirmasi untuk item keluarga dan milik sendiri.
4. Uji ujung-ke-ujung lokal: `POST /scans` (curl dengan token Protected meniru extension) → `push_log` → `xcrun simctl push` dengan payload yang sama ke simulator Guardian di tiga kondisi (foreground, background, terminated) → Detail → It's safe → `curl GET /verdicts?domain=` sebagai Protected mengembalikan `safe`. Bukti manual: screenshot tiap kondisi + waktu (XCUITest tidak bisa memicu `simctl push` sendiri).
5. Uji perangkat (kalau B6, B7, C3 siap): dua iPhone, push sandbox nyata lewat relay cloud. Target: notifikasi + tap + verdict → layar blokir terbuka ≤ 10 s end-to-end (polling extension 5 s); `GET /verdicts` sudah `safe` ≤ 1 s setelah POST.
6. `ecc:security-reviewer`.

## Verifikasi

```bash
source plan/alief/ref/sim.sh
(cd ios && xcodegen)
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM"
xcrun simctl push booted com.shoo.app plan/alief/qa/push-blocked.apns   # dibuat di fase ini, berisi payload kontrak
git diff origin/main --stat -- ios/ShooApp/Info.plist ios/ShooApp/*.entitlements   # harus kosong
```

## Kriteria selesai (DoD)

- [ ] `NotificationRouter` teruji (unit); tap push membuka Detail yang benar di tiga kondisi app (bukti manual `simctl push` + screenshot).
- [ ] Verdict langsung berlaku; Protected `GET /verdicts?domain=` mengembalikan `safe` ≤ 1 s setelah tap (log); target end-to-end ≤ 10 s dicatat untuk QA-E2E.
- [ ] Definisi selesai README §7 butir 2–3 terbukti di simulator; di perangkat fisik → QA-E2E.
