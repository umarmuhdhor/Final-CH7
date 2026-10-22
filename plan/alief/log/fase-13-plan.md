# Rencana fase 13 — ApiRepository + sesi App Group

> Ditulis agent track c (22 Okt 2026, mode auto). Branch `feat/APP-api-repository` dari `origin/main` `b91f2a1`.
> Sumber: `fase-13-api-repository.md`, `contracts/api.md`, `contracts/app-group-keys.md`, `ref/R3` §1–§4, `ref/R5` §6, SECURITY T3 + §3 P1–P13, D-alief-10/21/A20/A32/A40.

| # | Langkah | Test dulu |
|---|---|---|
| 1 | `Data/APIClient.swift`: URLSession ephemeral tanpa cache/cookie (P9/P13), Bearer dari `SessionStore`, `JSONEncoder.shoo`/`JSONDecoder.shoo`, `{ error: { code, message } }` → `RepositoryError.api`; status tanpa body kontrak → kode umum dari status; 401 (atau tidak ada token) → `onUnauthorized` (sesi rusak); offline → `.network`; batal → `CancellationError` | `APIClientTests` (stub `URLProtocol` per host, paralel aman) |
| 2 | `Data/Keychain.swift` + `Data/SessionStore.swift`: token di Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (P4), key kontrak App Group (`AppGroup.Key`), `device.name` ditulis ulang, `guardian.name` dihapus/diisi; guardian lengkap hanya di memori (D-alief-C02) | `SessionStoreTests` (suite uji, service Keychain per test, cek atribut) |
| 3 | `Data/ApiRepository.swift`: semua operasi `ShooRepository`; efek sesi: `updateMe(name)`, `me()` (guardian null → hapus), `joinFamily`, `leaveGuardian` (ok/404), `deleteMe` (ok/404/401 → hapus sesi, tanpa layar "Session expired") | `ApiRepositoryTests` (path + method setiap endpoint, efek sesi) |
| 4 | `AppEnvironment`: `-UITestMock YES` → `MockRepository`, selain itu `ApiRepository`; `register` → `SessionStore.save` → `chooseMode` → `PATCH language=id` kalau bahasa ID; `sessionExpired` + `restartOnboarding()`; `sceneBecameActive()` → `updateMe(extensionLastSeenAt:)` + `me()` | `AppEnvironmentTests` |
| 5 | `Features/Main/SessionExpiredView.swift` (layar baru, EN/ID) di `RootView`; `ProfileModel` TODO dihapus (pembersihan pindah ke `ApiRepository`) | UI test `SessionUITests` |
| 6 | Screenshot 404 → `GET /scans/{id}` sekali lagi untuk link baru sebelum "tidak tersedia" (D-alief-C04) | `DetailModelTests` |
| 7 | `AppConfig`: Release = `https://shoo-api.afindo-mi01.workers.dev`, `aiBaseURL = nil` sampai Imelda (`TODO(sync:imelda)`) | `AppConfigTests` |
| 8 | UI test lama + `-UITestMock YES`; uji manual simulator ↔ `wrangler dev`; gerbang UI layar baru; review swift + security (berurutan); log + PR | – |
