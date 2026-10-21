# Fase 15 — Push tap + validasi live: GD-06, GD-07

| Field | Nilai |
|---|---|
| Track | c |
| Branch | `feat/GD-06-07-push-validation` |
| Prasyarat | 14; 11 (sender), C3 (capability Push) untuk uji perangkat |
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
- `aps-environment` di `ShooApp/Shoo.entitlements` (file kita) — capability tetap butuh Umar (C3)
- Detail: tombol memanggil `POST /verdicts` asli; error → rollback + pesan
- Test: parsing payload push → route, token hex encoding, optimistic verdict + rollback, Detail dimuat dari `scanId` yang belum ada di cache

## Langkah kerja

1. Registrasi APNs setelah izin (ON-05), kirim token hex via `PATCH /devices/me`.
2. Tap push (foreground, background, terminated) → Detail `scanId`.
3. GD-07: It's safe / Not safe tanpa konfirmasi untuk item keluarga dan milik sendiri.
4. Uji ujung-ke-ujung lokal: simulator Protected kirim `POST /scans` (curl dengan token Protected meniru extension) → `push_log` → `xcrun simctl push` dengan payload yang sama ke simulator Guardian → Detail → It's safe → `curl GET /verdicts?domain=` sebagai Protected mengembalikan `safe`.
5. Uji perangkat (kalau B6, B7, C3 siap): dua iPhone, push sandbox nyata.
6. `ecc:security-reviewer`.

## Verifikasi

```bash
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM"
xcrun simctl push booted com.shoo.app plan/alief/qa/push-blocked.apns   # dibuat di fase ini, berisi payload kontrak
```

## Kriteria selesai (DoD)

- [ ] Tap push membuka Detail yang benar di tiga kondisi app (UI test dengan `simctl push` + screenshot).
- [ ] Verdict langsung berlaku; Protected `GET /verdicts?domain=` mengembalikan `safe` ≤ 1 s setelah tap (log).
- [ ] Definisi selesai README §7 butir 2–3 terbukti di simulator; di perangkat fisik → QA-E2E.
