# Rencana fase 01 — Fondasi app

> Ditulis agent track app (21 Okt 2026). Ringkasan di `log/fase-01.md`.

## PR 1 · `chore/APP-test-targets`
1. `ios/project.yml`: diff persis D-alief-24 + D-alief-28 (dua target test, `GENERATE_INFOPLIST_FILE`, `excludes`, scheme test).
2. Satu smoke test per target. `(cd ios && xcodegen)` + `xcodebuild test` hijau.
3. PR ke `main`, reviewer Umar, "Stacked on #7".

## PR 2 · `feat/APP-foundation` (stacked di atas PR 1)
| # | Langkah | Test dulu (Swift Testing) |
|---|---|---|
| 1 | `Data/Models.swift`: tipe app sesuai JSON kontrak (`DeviceRegistration`, `DeviceProfile`, `DeviceUpdate`, `GuardianInfo`, `FamilyCode`, `FamilyMember`, `ScanPage`, `ScanOwnerFilter`, `APIErrorCode`, `RepositoryError`) | `FixtureTests`: semua fixture terdecode ke model ShooShared; error body; `DeviceProfile` guardian null |
| 2 | `Data/Fixtures/`: salinan `contracts/fixtures` + `activity-family.json` di-inline | `FixtureTests`: salinan == kontrak (byte), inline == daftar `$ref` |
| 3 | `Data/ShooRepository.swift` + `Data/MockRepository.swift` (actor, latensi 300 ms, mode Guardian/Protected, skenario `empty`, kode join ajaib untuk error kontrak) | `MockRepositoryTests`: filter owner/status, cursor, verdict (blocked saja, per domain+pemilik), join error, kode 60 s, members, validasi nama/bahasa |
| 4 | `Data/ExtensionStatus.swift` (heartbeat App Group, `AppGroup.extensionActiveWindow`) | `ExtensionStatusTests` |
| 5 | `Support/`: `AppLanguage`, `L10n`, `Formatters`, `ScoreLevel`, `Log` (os.Logger `.private`) | `LocalizationTests`, `FormatterTests`, `ComponentLogicTests` |
| 6 | `App/`: `AppSettings`, `Router`, `AppEnvironment`, `AppConfig`, `RootView`; `ContentView.swift` dihapus | `AppSettingsTests` (persist, default bahasa, router) |
| 7 | `Components/`: `ScoreRing`, `StatusChip` (`ScanBadge`), `AvatarView` (`AvatarCatalog`), `SiteIcon`, `EmptyStateView` | logika di `ComponentLogicTests`; visual lewat preview + screenshot |
| 8 | `Features/*` placeholder: Onboarding (pilih mode), Main (TabView + tombol profile), Shield, Activity, Profile (pilih bahasa) | XCUITest `SmokeUITests`: tab EN, tab ID, ganti bahasa live dari Profile |
| 9 | `Resources/Localizable.xcstrings` EN + ID | test semua key punya ID |
| 10 | `PrivacyInfo.xcprivacy` (P1) | `plutil -lint` + cek ada di bundle |
| 11 | `ci/ios-app.yml` draf inert | – |
| 12 | Gerbang UI: screenshot EN/ID, light/dark, Dynamic Type XL → `qa/img/ui-01/` | – |
| 13 | Review `ecc:swift-reviewer`, verifikasi, log, PROGRESS, PR | – |
