# Fase 02 — Onboarding: ON-01 … ON-05

| Field | Nilai |
|---|---|
| Track | app |
| Branch | `feat/ON-01-05-onboarding` |
| Prasyarat | 01 |
| Requirement | ON-01, ON-02, ON-03, ON-04, ON-05 (P0). ON-04 dari fallback PRD §10, disempurnakan dari spike 01S (D-alief-29) |
| Model | Sonnet 5.5 · `apple-design`, `ecc:swiftui-patterns`, `emil-design-eng` |
| Fase berikutnya | 03 |

## Tujuan

Pengguna baru bisa menyelesaikan onboarding sampai masuk Home: splash, nama + avatar acak, pilih mode permanen, menyalakan extension, izin notifikasi. Untuk sekarang data disimpan lewat `MockRepository.registerDevice` (fase 13 memakai API asli).

## Bacaan wajib

- PRD §8.1 (tabel ON-*), §7 wireframe, §3 persona (orang tua 45–65 tahun: teks besar, kalimat pendek), §10 risiko ON-04 (fallback)
- `docs/spikes/extension-status.md`, `docs/spikes/open-extension-settings.md` (bagian Result kalau 01S sudah selesai), `ios/ShooShared/AppGroup.swift` (`extensionActiveWindow`)
- `contracts/api.md` Devices, `contracts/app-group-keys.md` (`device.mode` tidak pernah berubah)

## Output

- `Features/Onboarding/`: `OnboardingFlow` (state machine langkah), `SplashView` (3 slide), `NameView`, `ModeView`, `TurnOnExtensionView` (ON-04, dipakai ulang sebagai sheet dari tombol "Turn on" PR-04/GD-01), `TutorialVideoPlayer` (AVPlayerViewController + PiP), `NotificationPermissionView`, `OnboardingModel`
- Pengingat notifikasi kecil di Home (komponen `NotificationReminderBanner`, dipakai Shield di fase 04/05)
- Test: validasi nama, urutan langkah (Guardian ON-03 → ON-04 → ON-05; Protected ON-03 → Connect → ON-04 → ON-05), mode tidak bisa diubah setelah disimpan, ON-04 tetap di layar saat Off dan lanjut saat Active (App Group suite uji menulis `extension.lastSeenAt`), alur izin ditolak

## Langkah kerja

1. **ON-01 Splash**: 3 slide (apa itu Shoo, cara kerja, Guardian vs Protected), ilustrasi placeholder + 1 kalimat pendek per slide, `TabView(.page)` dengan indikator titik, tombol Skip → ON-02. Tanpa angka statistik.
2. **ON-02 Nama**: wajib 1–20 karakter (trim spasi; hitung karakter grapheme), tombol Lanjut nonaktif sampai valid, pesan error EN/ID. Layar ini hanya nama (D-alief-22).
3. **ON-03 Mode**: dua kartu "Protect myself and my family" (Guardian) / "Protected by others" (Protected), satu pilihan, teks peringatan bahwa pilihan tidak bisa diganti. Simpan → `registerDevice(name:mode:)` → layar "Hi, [nama]" dengan **avatar acak dari `avatarId`** (bukan inisial; di mock dipilih acak). Setelah tersimpan, tidak ada jalan kembali ke ON-03.
4. **ON-04 Turn on extension** (fallback PRD §10; kalau Result 01S sudah ada, pakai langkah + petunjuknya):
   - Ilustrasi letak switch: langkah bergambar Settings › Apps › Safari › Extensions › Shoo › On + "Allow on every website" (SF Symbols besar sampai aset ilustrasi ON-04 dari designer; screenshot 01S kalau ada). Catat re-skin.
   - Tombol Turn on → `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`. JANGAN pakai `App-prefs:` (mandat).
   - Saat `scenePhase == .active`: cek `ExtensionStatus` (`AppGroup.Key.extensionLastSeenAt` dalam `AppGroup.extensionActiveWindow`). Active → lanjut ON-05. Off → tetap di layar + petunjuk "Open any website in Safari, then come back" (heartbeat butuh halaman dimuat: BELUM DIVERIFIKASI sampai S1).
   - Link "Still can't? Watch video" → `TutorialVideoPlayer` (`allowsPictureInPicturePlayback = true`, `canStartPictureInPictureAutomaticallyFromInline = true`). Video ≤ 60 s dibuat PM: placeholder `// TODO(sync:umar): ON-04 tutorial video from PM — replace after C15`. PiP yang tetap tampil di Settings butuh Background Modes audio (`UIBackgroundModes: [audio]`) = permintaan C3 butir 4; tanpa itu video tetap diputar di dalam app (catat di log).
   - UI test: launch argument `-UITestExtensionActive` menulis heartbeat ke suite uji supaya alur bisa lewat ON-04 di simulator.
5. **ON-05 Notifikasi**: setelah ON-04. Penjelasan singkat → `UNUserNotificationCenter.requestAuthorization`. Guardian: wajib (kalau ditolak, tetap lanjut tapi banner pengingat di Home + tombol buka Settings). Protected: boleh lewati. Register APNs (`registerForRemoteNotifications`) disiapkan, token dikirim di fase 15.
6. Protected setelah ON-03 menuju PR-01 Connect (fase 14), lalu PR-02 → ON-04 → ON-05 (PRD PR-02 "Lanjut ke ON-04"). Sementara: placeholder layar "Connect to your guardian" dengan tombol Continue ke ON-04 dan `// TODO(sync:alief): PR-01 — replace after fase 14`.
7. Gerbang UI: semua langkah EN + ID, light/dark, Dynamic Type XL, VoiceOver membaca slide dan tombol. Log: "re-skin saat desain final datang".

## Verifikasi

```bash
source plan/alief/ref/sim.sh
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppTests
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppUITests/OnboardingUITests
```

## Kriteria selesai (DoD)

- [ ] ON-01: 3 slide, bisa digeser, indikator titik, Skip ke ON-02 (UI test).
- [ ] ON-02: 0 dan 21 karakter ditolak, 1 dan 20 diterima (unit test).
- [ ] Avatar acak tampil setelah registrasi (bukan inisial).
- [ ] ON-03: mode tersimpan dan tidak bisa diganti (unit test + UI test tidak ada jalan kembali).
- [ ] ON-04: Off → tetap di layar, Active (heartbeat) → lanjut; tombol Turn on membuka Settings; link video membuka player (UI test + screenshot). Uji di iPhone nyata ikut 01S / QA-E2E #17.
- [ ] ON-05: izin diminta; ditolak → banner pengingat di Home (UI test dengan reset izin simulator).
- [ ] Screenshot EN + ID di `qa/img/ui-02/`.

## Risiko & fallback

| Risiko | Fallback |
|---|---|
| Push capability belum ada (TODO C3) | Izin notifikasi lokal tetap bisa diminta; register APNs gagal → log saja, tidak memblokir |
| Ilustrasi belum ada | SF Symbols besar + warna; catat re-skin |
| Video PM belum ada | Tautan tetap tampil, player memutar placeholder lokal pendek; C15 |
| `UIBackgroundModes` audio belum ada (C3 butir 4) | Video diputar di app tanpa PiP di Settings; dicatat sebagai deviasi sampai Umar menambah key |

## Catatan handoff

- Fase 13 mengganti `MockRepository.registerDevice` dengan API dan menulis key App Group.
- Fase 14 mengisi layar Connect Protected (PR-02 lanjut ke ON-04).
- Fase 01S / `feat/ON-04-refine` menyempurnakan langkah dan window dari hasil spike.
