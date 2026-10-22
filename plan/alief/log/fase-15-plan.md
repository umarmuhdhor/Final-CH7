# Rencana fase 15 — Push tap + validasi: GD-06, GD-07 (+ ON-05 token, EX-06 bagian app)

> Ditulis agent track c (22 Okt 2026, mode auto). Branch `feat/GD-06-07-push-validation` dari `feat/GD-04-PR-01-03-pairing` (PR #52, belum di-merge): PR fase 15 bertumpuk di atas #52.
> Sumber: `fase-15-push-validasi.md`, PRD §8.3 GD-06/07, `contracts/api.md` (Push payloads, Verdicts, Deep links), `ref/R4` §3–§4, fase 03 + 11, SECURITY §3 P1–P13.

| # | Langkah | Test dulu |
|---|---|---|
| 1 | `Support/NotificationRouter.swift`: `scanId(userInfo:)` (segmen aman saja, sama dengan `APIClient.isPlainSegment`), `hex(token:)` | `NotificationRouterTests` |
| 2 | `App/AppDelegate.swift` lewat `@UIApplicationDelegateAdaptor`: memegang `AppEnvironment.live()`, delegate `UNUserNotificationCenter` (banner saat foreground, tap → `openPush`), token → `pushTokenReceived` | `PushRoutingTests` |
| 3 | `Router.openDetail(scanId:)` / `openActivity()`: tutup semua sheet, tab Activity, Detail di atas list | `PushRoutingTests` |
| 4 | `AppEnvironment`: `open(url)` untuk `shoo://scan/{id}` + `shoo://activity` (fase 14 hanya `join`), link rusak → Shield, tidak ada navigasi selama onboarding/sesi habis; `pushTokenReceived` (Guardian saja, sekali per token, ulang saat gagal); `registerForPushIfAllowed` setiap app aktif | `PushRoutingTests` |
| 5 | `qa/push-blocked.apns`, `qa/push-warning.apns` (payload kontrak, fixture `blocked-92` / `warning-41`) | `simctl push` |
| 6 | UI: `DeepLinkUITests` (mock) + `LivePushUITests` opt-in (Guardian asli, izin sistem, tiga kondisi app, host script `simctl push` + curl `GET /verdicts`) | UI |
| 7 | Review security lalu swift (berurutan), keputusan C13+, log + PR | — |

Deviasi dari dokumen fase: `route(url:)` tidak dibuat di `NotificationRouter`; parsing link sudah ada di `App/DeepLink.swift` (fase 14) dan dipakai ulang (satu parser untuk `onOpenURL`, test dan push).
