# Fase 01 — Fondasi app: target test, navigasi, repository, String Catalog, avatar

| Field | Nilai |
|---|---|
| Track | app · worktree `../Final-CH7-app` |
| Branch | (1) `chore/APP-test-targets` → (2) `feat/APP-foundation` (stacked di atas 1 sampai merge) |
| Prasyarat | 00 |
| Requirement | Mandat Fase A "Fondasi" |
| Model | Sonnet 5.5 · `apple-design`, `ecc:swiftui-patterns`, `ecc:swift-protocol-di-testing`, `write-swift` |
| Fase berikutnya | 02 |

## Tujuan

Kerangka app yang semua layar Fase A pakai: tab Shield / Activity, satu protocol data `ShooRepository` dengan implementasi `MockRepository` dari fixtures (diganti `ApiRepository` di fase 13 tanpa mengubah view), String Catalog EN + ID, 12 avatar placeholder, dan target test supaya TDD jalan.

## Bacaan wajib

- `ios/project.yml`, `ios/ShooApp/*.swift`, `ios/ShooShared/*.swift` (model, `AppGroup`, `ScoreThreshold`, `JSONDecoder.shoo`)
- `contracts/fixtures/*.json`, `contracts/api.md` (operasi yang perlu ada di protocol)
- `ref/R1` §2, `ref/R5` §1, §4, §6, `log/DECISIONS.md` D-alief-02, D-alief-13

## Output

1. **PR `chore/APP-test-targets`** (pengecualian D-alief-02, satu-satunya edit `ios/project.yml`; diff persis di D-alief-24 — kunci lain, termasuk `info`/`entitlements`, tidak disentuh):
   - target `ShooAppTests` (bundle.unit-test, sources `ShooApp/Tests`, host app Shoo) dan `ShooAppUITests` (bundle.ui-testing, sources `ShooApp/UITests`), keduanya dengan `settings.base.GENERATE_INFOPLIST_FILE: YES` (D-alief-28)
   - target Shoo: tambah `excludes: ["CLAUDE.md", "Tests/**", "UITests/**", "ci/**"]`
   - scheme Shoo: test targets ditambahkan
   - satu test kosong di masing-masing target supaya hijau
   - isi PR: "additive only, tests + excludes", TODO C1
2. **PR `feat/APP-foundation`**:
   - `App/` (AppEnvironment, RootView, Router, AppSettings), `Data/` (ShooRepository, MockRepository, ExtensionStatus, Fixtures/), `Components/` (ScoreRing, StatusChip, AvatarView, SiteIcon, EmptyStateView), `Support/` (formatter waktu relatif + persen, helper lokalisasi), `Resources/Localizable.xcstrings`, `Resources/Assets.xcassets` (avatar_01..12)
   - `ContentView.swift` diganti `RootView` (contoh `extensionLastSeenAt` dipindah ke `ExtensionStatus`)
   - `ios/ShooApp/ci/ios-app.yml` (draf workflow, inert)
   - Test: decoding semua fixture, MockRepository filter/cursor, ExtensionStatus Active/Off, formatter EN/ID, bahasa in-app

## Langkah kerja

1. **Target test** (PR 1). Edit `ios/project.yml` sesuai Output 1, `(cd ios && xcodegen)`, `xcodebuild test` hijau. Kalau build masih gagal karena setting lain, berhenti dan catat (jangan menambah kunci di luar D-alief-24/28). Commit `chore(APP): add ShooAppTests and ShooAppUITests targets`. Buka PR, tulis pesan C1 di log untuk Alief kirim ke Umar.
2. **Protocol** `ShooRepository` (async throws), dibentuk dari `contracts/api.md`:
   `registerDevice(name:mode:)`, `updateMe(name:language:apnsToken:)`, `createFamilyCode()`, `joinFamily(code:)`, `familyMembers()`, `removeMember(_:)`, `leaveGuardian()`, `scans(owner:status:cursor:)`, `scan(id:)`, `setVerdict(scanId:value:)`. Tipe pendukung di `Data/Models.swift` (`FamilyMember`, `FamilyCode`, `GuardianInfo`, `ScanPage`, `ScanOwnerFilter`, `RepositoryError` dengan `code` kontrak).
3. **MockRepository**: baca `Data/Fixtures/*.json` (salinan `contracts/fixtures`, plus `activity-family.json` di-inline), simulasi latensi 300 ms (bisa dimatikan di test), state verdict di memori, mode Guardian/Protected bisa dipilih untuk preview. Error kontrak bisa dipicu lewat kode khusus (mis. join `0000` → `code_invalid`, `9999` → `code_expired`) untuk preview dan test.
4. **Navigasi**: `RootView` → kalau onboarding belum selesai: placeholder Onboarding (diisi fase 02); selain itu `TabView` Shield / Activity, tombol profile kanan atas, `Router` untuk push Detail(scanId).
5. **Lokalisasi**: `Localizable.xcstrings` (source EN, terjemahan ID). Uji (BELUM DIVERIFIKASI) apakah `.environment(\.locale, Locale(identifier: "id"))` mengubah tiga kasus: `Text("literal")`, `Text(variabelString)`, dan `String(localized:)` di view model. Sumber komunitas: hanya kasus pertama yang ikut. Kasus yang tidak ikut → helper `L10n.string(_:locale:)` (`String(localized:bundle:locale:)`) dan catat `D-alief-A…`.
6. **Avatar**: 12 avatar placeholder (SF Symbol hewan/objek di lingkaran warna palet), `AvatarView(id:)` memetakan `avatar_01..12`. Catat "re-skin saat desain final datang".
7. **Komponen**: `ScoreRing` (0–100, warna per ambang `ScoreThreshold`), `StatusChip` (Warning / Blocked / Verified scam / Marked safe), `SiteIcon` (favicon atau huruf awal domain), `EmptyStateView`.
8. **Draf CI iOS**: `ios/ShooApp/ci/ios-app.yml` (`on: pull_request` paths `ios/ShooApp/**`, macOS runner, `brew install xcodegen`, `xcodegen`, `xcodebuild test`). Inert sampai Umar memindahkan (C2).
9. Gerbang UI (PROMPT langkah 7) untuk tab kosong + komponen di preview.

## Verifikasi

```bash
source plan/alief/ref/sim.sh
(cd ios && xcodegen)
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" | tail -20
git diff origin/main -- ios/project.yml   # di PR 1 saja: harus persis diff D-alief-02/D-alief-24
grep -rn "TODO(sync" ios/ShooApp || true
```

## Kriteria selesai (DoD)

- [ ] PR target test dibuka; C1 ditulis di log.
- [ ] Semua fixture terdecode ke model `ShooShared` (test).
- [ ] `MockRepository` memenuhi seluruh protocol, termasuk error kontrak (test).
- [ ] Bahasa in-app EN ↔ ID terbukti (test atau screenshot) dan cara yang dipakai dicatat.
- [ ] Tab Shield / Activity + profile button tampil di simulator (screenshot EN + ID).
- [ ] Draf `ios-app.yml` ada.

## Risiko & fallback

| Risiko | Fallback |
|---|---|
| Umar menolak edit project.yml | Test tetap jalan lokal di branch (project.yml lokal), PR fitur tidak menyertakan test target; catat DECISIONS |
| Environment locale tidak mengubah String Catalog | Helper `L10n` + `id` bundle lookup |
| Fixture `id` bukan UUID valid untuk `ScanResult.id: String` | Tidak masalah (String); test memastikan |

## Catatan handoff

- Fase 02–06 memakai `MockRepository`, `AppSettings`, `Router`, komponen. Fase 13 menambah `ApiRepository` di protocol yang sama.
