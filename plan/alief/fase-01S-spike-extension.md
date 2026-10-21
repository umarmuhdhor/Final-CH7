# Fase 01S — Spike S1/S2 di iPhone sendiri: status extension + buka pengaturan

| Field | Nilai |
|---|---|
| Track | spike (manual, iPhone Alief; tidak dipilih mode auto track app/be/c) |
| Branch | `spike/S1-S2-extension` |
| Prasyarat | PR fase 01 (`chore/APP-test-targets` + `feat/APP-foundation`) MERGED, atau branch spike ditumpuk di atas `feat/APP-foundation` ("Stacked on #N") · signing ke iPhone Alief lewat L0 (`ios/Config/Local.xcconfig`, sudah ada di `main` `495c792`) |
| Requirement | Mandat "Spike · di iPhone sendiri" S1 + S2; masukan untuk ON-04, PR-04, GD-01, EX-01 (U7 Umar) |
| Model | Sonnet 5.5 · `apple-design`, `write-swift` |
| Fase berikutnya | Hasil dipakai track app: fase 02 (ON-04) atau, kalau 02 sudah lewat, fase 06 (handoff "Refine ON-04") |

## Tujuan

Mengisi `docs/spikes/extension-status.md` (S1) dan `docs/spikes/open-extension-settings.md` (S2) dengan hasil uji di iPhone nyata, mengusulkan nilai `AppGroup.extensionActiveWindow` ke Umar, dan menyerahkan rekomendasi ON-04 ke track app (D-alief-29, D-alief-34).

## Bacaan wajib

- `docs/mandates/alief.md` bagian "Spike", `docs/spikes/README.md`, kedua file spike (template + checklist "To test on device")
- `ios/ShooShared/AppGroup.swift` (`Key.extensionLastSeenAt`, `extensionActiveWindow`), `ios/ShooApp/ContentView.swift` (contoh Active/Off), `ios/ShooExtension/` (heartbeat `content.js` → `background.js` → `SafariWebExtensionHandler`) — read-only
- PRD §8.1 ON-04, §8.5 EX-01, §10 risiko "Buka pengaturan extension" + "Deteksi extension On"
- `README.md` root bagian "Running on your own iPhone", `ios/Config/Local.xcconfig.example`, `ios/CLAUDE.md` (App Group selalu lewat `AppGroup.id`)
- Docs Apple SafariServices: `SFSafariExtensionManager` (`getStateOfSafariExtension(withIdentifier:)`) dan `SFSafariSettings.openExtensionsSettings(forIdentifiers:)` — menurut verify run 04 tersedia di iOS 26.2+ (BELUM DIVERIFIKASI di perangkat, diuji di fase ini)

## Output

- `ios/ShooApp/Debug/ExtensionSpikeView.swift` (seluruh file di dalam `#if DEBUG`, dibuka lewat launch argument `-ShooSpike`): `extension.lastSeenAt` live + umurnya, status menurut `ExtensionStatus` dengan window saat ini, status dari `SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier:)` (`if #available(iOS 26.2, *)`), tombol "Open extension settings" (`SFSafariSettings.openExtensionsSettings(forIdentifiers:)` di iOS 26.2+) dan "Open Settings" (`UIApplication.openSettingsURLString`), daftar cap waktu perubahan `scenePhase` dan heartbeat. Identifier extension = `Bundle.main.bundleIdentifier! + ".extension"` (L0: `$(SHOO_BUNDLE_ID).extension`)
- `docs/spikes/extension-status.md` dan `docs/spikes/open-extension-settings.md`: bagian `## Result` terisi (pengecualian folder D-alief-29)
- Screenshot per langkah Settings di `plan/alief/qa/img/spike-01S/` (bahan ilustrasi ON-04)
- Pesan TODO C14 (usulan window Active + ringkasan S2) siap dikirim Alief

## Langkah kerja

1. **Signing (Alief, sekali).** `cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig` (gitignored), isi `DEVELOPMENT_TEAM`, `SHOO_BUNDLE_ID`, `SHOO_APP_GROUP` milik Alief, lalu `(cd ios && xcodegen)`. `ios/project.yml` dan `ios/ShooShared/` tidak diubah sama sekali; App Group selalu dibaca lewat `AppGroup.id`. Kalau Xcode menolak capability App Groups (biasanya akun gratis / Personal Team): lapor ke Umar (mandat), catat di log.
2. **Debug view.** TDD untuk logika murni: `ExtensionStatus` (Active/Off dari umur heartbeat) sudah ada dari fase 01; tambah test batas window kalau perlu. Tampilan spike cukup sederhana, tanpa gerbang UI penuh (layar debug, tidak dirilis).
3. **LANGKAH MANUAL (Alief, iPhone; tulis checklist di log, set `[m]`, berhenti):**
   - [ ] S1: extension On + "Allow on every website" → buka satu situs → kembali ke app → Active? Catat jeda heartbeat pertama setelah toggle, dan apakah harus membuka halaman dulu.
   - [ ] S1: extension Off → berapa lama sampai Off (heartbeat basi)? Usulan window Active.
   - [ ] S1: cabut "Allow on every website" → sama dengan Off? (EX-01)
   - [ ] S1: di iPhone iOS 26.2+ (catat versi iOS): `getStateOfSafariExtension(withIdentifier:)` cocok dengan toggle On/Off? Bandingkan dengan heartbeat. Catat juga perilakunya kalau extension On tapi "Allow on every website" dicabut.
   - [ ] S2: di iOS 26.2+: `openExtensionsSettings(forIdentifiers: [<id extension>])` langsung membuka halaman detail Shoo? (harus dipanggil saat app foreground)
   - [ ] S2: untuk iOS < 26.2 (kalau ada perangkat/simulator): `openSettingsURLString` mendarat di mana; jumlah tap sampai switch Shoo; jalur Settings › Safari › Extensions (iOS 17) vs Settings › Apps › Safari › Extensions (iOS 18+); screenshot tiap langkah ke `qa/img/spike-01S/`.
   - [ ] S2: `App-prefs:` hanya dicatat, tidak dipakai (mandat).
   - [ ] Tempel hasil (angka + catatan) di log fase ini.
4. **Isi hasil (agent, setelah butir 3 dicentang).** Tulis `## Result` di kedua file spike dari log (Decision, Active window, instruksi untuk user setelah toggle; direct link possible per versi iOS, taps, langkah ilustrasi). Template Umar di `extension-status.md` masih menulis `SFSafariExtensionManager` macOS-only: koreksi di Result dan sebutkan di PR. Keputusan → `D-alief-S01, S02, …`. Siapkan TODO C14 + C17.
5. **Handoff ON-04.** Tulis bagian "Refine ON-04" di Catatan handoff log fase ini (langkah ilustrasi per versi iOS, API yang terbukti, petunjuk setelah toggle, window). Fase ini TIDAK mengubah `TurnOnExtensionView` (milik track app, supaya worktree paralel tidak bentrok). Fase 02 membacanya kalau belum lewat; kalau sudah, fase 06 mengerjakannya (langkah "Refine ON-04" di fase 06).
6. PR dibuka di PROMPT langkah 11 seperti fase lain: judul `S1/S2: extension status and settings spike results`, centang S1 + S2 di `docs/mandates/alief.md`.

## Verifikasi

```bash
source plan/alief/ref/sim.sh
(cd ios && xcodegen)
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppTests/ExtensionStatusTests
git diff --name-only origin/main...HEAD -- ios/project.yml ios/ShooShared ios/ShooExtension   # harus kosong
grep -A4 "^## Result" docs/spikes/extension-status.md docs/spikes/open-extension-settings.md   # semua field terisi
grep -L "#if DEBUG" ios/ShooApp/Debug/*.swift || true   # harus kosong: semua file debug di dalam #if DEBUG
```

## Kriteria selesai (DoD)

- [ ] Checklist LANGKAH MANUAL tercentang dengan angka (jeda heartbeat, waktu sampai Off, jumlah tap).
- [ ] `## Result` di kedua file spike terisi dan dirujuk dari log.
- [ ] TODO C14 siap (usulan window Active untuk `AppGroup.extensionActiveWindow`) dan C17 (pakai API status iOS 26.2 sebagai sumber tambahan) kalau API terbukti.
- [ ] Tidak ada commit ke `ios/project.yml`, `ios/ShooShared/`, `ios/ShooExtension/` (perintah Verifikasi kosong).
- [ ] Handoff "Refine ON-04" tertulis di log (dibaca fase 02 atau 06).

## Risiko & fallback

| Risiko | Fallback |
|---|---|
| Xcode menolak App Groups di akun Alief (Personal Team) | S2 tetap diuji (tidak butuh App Group). S1 dijalankan di iPhone dengan tim berbayar (TODO C3), lapor ke Umar |
| iPhone Alief < iOS 26.2 | API iOS 26.2 ditandai BELUM DIVERIFIKASI; S1 pakai heartbeat, S2 pakai `openSettingsURLString` + ilustrasi (fallback PRD §10) |
| API status iOS 26.2 tidak cocok dengan toggle | Tetap heartbeat App Group (aturan `ios/ShooApp/CLAUDE.md`) |

## Catatan handoff

- Fase 02 (ON-04), 04 (PR-04), 05 (GD-01), 06 (PF-01) membaca status lewat `ExtensionStatus`; window final ditentukan Umar dari C14. API status iOS 26.2 hanya dipakai kalau Umar menyetujui C17.
- Umar: U7/EX-01 memakai hasil butir "cabut Allow on every website".
