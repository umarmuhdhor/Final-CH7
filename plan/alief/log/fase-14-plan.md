# Rencana fase 14 — Pairing: GD-04, PR-01, PR-02, PR-03

> Ditulis agent track c (22 Okt 2026, mode auto). Branch `feat/GD-04-PR-01-03-pairing` dari `feat/APP-api-repository` (PR #42, belum di-merge): PR fase 14 bertumpuk di atas #42.
> Sumber: `fase-14-pairing.md`, PRD §8.2 PR-01..03 + §8.3 GD-04 + §10, `contracts/api.md` (family, deep links), `ref/R4` §1–§2, `ref/R3` §4, SECURITY T2/T11/T13 + §3 P1–P13, D-alief-03/21.

| # | Langkah | Test dulu |
|---|---|---|
| 1 | `App/DeepLink.swift`: `shoo://join?code=dddd`, `https://<host API>/join?code=dddd` (host API + Worker), `shoo://scan/{id}`, `shoo://activity`; selain itu `.unknown` | `DeepLinkTests` |
| 2 | `Features/Pairing/ConnectModel.swift`: 4 digit ASCII, `prefill` tanpa join (T11), `scanned(payload)`, `join()` → PR-02; error kontrak (`code_invalid`, `code_expired`, `family_full`, `too_many_attempts`/`rate_limited`, `already_connected`, offline, lainnya) → pesan EN/ID | `ConnectModelTests` |
| 3 | `Features/Pairing/{ConnectView,QRScannerView}.swift`: tab Scan QR (VisionKit, izin kamera saat tab dibuka) + Enter code (4 kotak di atas satu field), PR-02 `ProtectedByView`; onboarding memakai ConnectView menggantikan placeholder; sheet Connect dari Shield (tanpa guardian) dan dari link | UI `PairingUITests` |
| 4 | `Features/Pairing/{FamilyCodeModel,FamilyCodeView,QRCode}.swift`: QR `inviteUrl`, kode besar, hitung mundur 60 s + kode baru, "Copy invite link" (P8), daftar x/3 + Remove, keluarga penuh = tanpa kode; dibuka dari Profile dan "Invite your family" | `FamilyCodeModelTests` + UI |
| 5 | `AppEnvironment.open(url)` + `RootView.onOpenURL`: link join → Connect (atau tunda sampai langkah Connect onboarding), lainnya → Shield | `DeepLinkRoutingTests` |
| 6 | String EN/ID baru di `Localizable.xcstrings`, hapus string placeholder | build + test bahasa |
| 7 | Gerbang UI (`qa/img/ui-14`), uji dua simulator melawan `wrangler dev` (kode + link), review security (T11) lalu swift (berurutan), log + PR | `LivePairingUITests` |
