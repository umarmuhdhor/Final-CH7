# Fase 01S — Spike S1/S2 di iPhone sendiri: status extension + buka pengaturan

| Field | Nilai |
|---|---|
| Track | spike (manual, iPhone Alief; tidak dipilih mode auto track app/be/c) |
| Branch | `spike/S1-S2-extension` (+ `feat/ON-04-refine` kalau ON-04 sudah ada, langkah 6) |
| Prasyarat | 01 (struktur app + `ExtensionStatus`) · signing ke iPhone Alief: L0 Umar (`ios/Local.xcconfig`) atau ubahan lokal yang TIDAK di-commit |
| Requirement | Mandat "Spike · di iPhone sendiri" S1 + S2; masukan untuk ON-04, PR-04, GD-01, EX-01 (U7 Umar) |
| Model | Sonnet 5.5 · `apple-design`, `write-swift` |
| Fase berikutnya | Hasil dipakai fase 02 (ON-04) atau PR `feat/ON-04-refine` |

## Tujuan

Mengisi `docs/spikes/extension-status.md` (S1) dan `docs/spikes/open-extension-settings.md` (S2) dengan hasil uji di iPhone nyata, mengusulkan nilai `AppGroup.extensionActiveWindow` ke Umar, dan menyempurnakan ON-04 dari hasil itu (D-alief-29).

## Bacaan wajib

- `docs/mandates/alief.md` bagian "Spike", `docs/spikes/README.md`, kedua file spike (template + checklist "To test on device")
- `ios/ShooShared/AppGroup.swift` (`Key.extensionLastSeenAt`, `extensionActiveWindow`), `ios/ShooApp/ContentView.swift` (contoh Active/Off), `ios/ShooExtension/` (heartbeat `content.js` → `background.js` → `SafariWebExtensionHandler`) — read-only
- PRD §8.1 ON-04, §8.5 EX-01, §10 risiko "Buka pengaturan extension" + "Deteksi extension On"
- `docs/mandates/umar.md` L0 (override signing per developer)

## Output

- `ios/ShooApp/Debug/ExtensionSpikeView.swift` (seluruh file di dalam `#if DEBUG`, dibuka lewat launch argument `-ShooSpike`): `extension.lastSeenAt` live + umurnya, status menurut `ExtensionStatus` dengan window saat ini, tombol "Open Settings" (`UIApplication.openSettingsURLString`), daftar cap waktu perubahan `scenePhase` dan heartbeat (untuk mengukur jeda)
- `docs/spikes/extension-status.md` dan `docs/spikes/open-extension-settings.md`: bagian `## Result` terisi (pengecualian folder D-alief-29)
- Screenshot per langkah Settings di `plan/alief/qa/img/spike-01S/` (bahan ilustrasi ON-04)
- Pesan TODO C14 (usulan window Active + ringkasan S2) siap dikirim Alief

## Langkah kerja

1. **Signing (Alief, sekali).** Kalau L0 sudah ada di `main`: salin `ios/Local.xcconfig.example` → `ios/Local.xcconfig` (gitignored) dan isi Team ID + prefix bundle ID + App Group milik Alief. Kalau belum: ubah bundle ID / App Group / Team **lokal** di `ios/project.yml` (dan `AppGroup.id` di `ios/ShooShared/AppGroup.swift` kalau App Group harus diganti), `(cd ios && xcodegen)`. File itu **tidak pernah di-commit**: commit selalu dengan path eksplisit (`git add docs/spikes ios/ShooApp/Debug plan/alief`), dan Verifikasi memeriksanya. Apakah App Group butuh akun berbayar: BELUM DIVERIFIKASI, catat hasilnya (risiko di bawah).
2. **Debug view.** TDD untuk logika murni: `ExtensionStatus` (Active/Off dari umur heartbeat) sudah ada dari fase 01; tambah test batas window kalau perlu. Tampilan spike cukup sederhana, tanpa gerbang UI penuh (layar debug, tidak dirilis).
3. **LANGKAH MANUAL (Alief, iPhone; tulis checklist di log, set `[m]`, berhenti):**
   - [ ] S1: extension On + "Allow on every website" → buka satu situs → kembali ke app → Active? Catat jeda heartbeat pertama setelah toggle, dan apakah harus membuka halaman dulu.
   - [ ] S1: extension Off → berapa lama sampai Off (heartbeat basi)? Usulan window Active.
   - [ ] S1: cabut "Allow on every website" → sama dengan Off? (EX-01)
   - [ ] S1: cari API publik iOS untuk status extension (`SFSafariExtensionManager` hanya macOS); catat sumbernya.
   - [ ] S2: `openSettingsURLString` mendarat di mana; jumlah tap sampai switch Shoo; screenshot tiap langkah ke `qa/img/spike-01S/`.
   - [ ] S2: ada API/URL publik yang langsung ke Safari › Extensions? (`App-prefs:` hanya dicatat, tidak dipakai.)
   - [ ] Tempel hasil (angka + catatan) di log fase ini.
4. **Isi hasil (agent, setelah butir 3 dicentang).** Tulis `## Result` di kedua file spike dari log (Decision, Active window, instruksi untuk user setelah toggle; direct link possible, taps, langkah ilustrasi). Keputusan copy/langkah ON-04 → `D-alief-A…`. Siapkan TODO C14.
5. **PR spike.** `spike/S1-S2-extension` dari `origin/main`: file spike + debug view + log. Judul `S1/S2: extension status and settings spike results`. Centang S1 + S2 di `docs/mandates/alief.md`.
6. **Sempurnakan ON-04.** Kalau fase 02 belum dimulai: cukup "Catatan handoff" (fase 02 memakai hasil ini). Kalau fase 02 sudah `[r]`/`[x]`: PR kedua `feat/ON-04-refine` (dari `origin/main`, atau ditumpuk di atas branch fase 02 kalau masih `[r]`) yang mengubah langkah ilustrasi, petunjuk, dan window di `TurnOnExtensionView` sesuai hasil; test + gerbang UI (PROMPT langkah 7).

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
- [ ] TODO C14 siap (usulan window Active untuk `AppGroup.extensionActiveWindow`).
- [ ] Tidak ada commit ke `ios/project.yml`, `ios/ShooShared/`, `ios/ShooExtension/` (perintah Verifikasi kosong).
- [ ] ON-04 memakai hasil spike (handoff fase 02, atau PR `feat/ON-04-refine`).

## Risiko & fallback

| Risiko | Fallback |
|---|---|
| L0 belum ada, App Group tidak bisa didaftarkan di akun Alief (mungkin butuh akun berbayar, BELUM DIVERIFIKASI) | S2 tetap diuji (tidak butuh App Group). S1 dijalankan di iPhone dengan akun tim Umar, atau tunggu L0; catat di log dan TODO C3 |
| Tidak ada API status extension | Pakai fallback PRD §10 (heartbeat App Group), sudah dipakai ON-04 sejak fase 02 |
| Tidak ada link langsung ke Safari › Extensions | Settings umum + ilustrasi langkah + video (fallback PRD §10) |

## Catatan handoff

- Fase 02 (ON-04), 04 (PR-04), 05 (GD-01), 06 (PF-01) membaca status lewat `ExtensionStatus`; window final ditentukan Umar dari C14.
- Umar: U7/EX-01 memakai hasil butir "cabut Allow on every website".
