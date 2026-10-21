# Fase 02 — Onboarding: ON-01, ON-02, ON-03, ON-05

| Field | Nilai |
|---|---|
| Track | app |
| Branch | `feat/ON-01-05-onboarding` |
| Prasyarat | 01 |
| Requirement | ON-01, ON-02, ON-03, ON-05 (P0). ON-04 ditahan (fase 17) |
| Model | Sonnet 5.5 · `apple-design`, `ecc:swiftui-patterns`, `emil-design-eng` |
| Fase berikutnya | 03 |

## Tujuan

Pengguna baru bisa menyelesaikan onboarding sampai masuk Home: splash, nama + avatar acak, pilih mode permanen, izin notifikasi. Untuk sekarang data disimpan lewat `MockRepository.registerDevice` (fase 13 memakai API asli).

## Bacaan wajib

- PRD §8.1 (tabel ON-*), §7 wireframe, §3 persona (orang tua 45–65 tahun: teks besar, kalimat pendek)
- `contracts/api.md` Devices, `contracts/app-group-keys.md` (`device.mode` tidak pernah berubah)

## Output

- `Features/Onboarding/`: `OnboardingFlow` (state machine langkah), `SplashView` (3 slide), `NameView`, `ModeView`, `NotificationPermissionView`, `OnboardingModel`
- Pengingat notifikasi kecil di Home (komponen `NotificationReminderBanner`, dipakai Shield di fase 04/05)
- Test: validasi nama, urutan langkah, mode tidak bisa diubah setelah disimpan, alur izin ditolak

## Langkah kerja

1. **ON-01 Splash**: 3 slide (apa itu Shoo, cara kerja, Guardian vs Protected), ilustrasi placeholder + 1 kalimat pendek per slide, `TabView(.page)` dengan indikator titik, tombol Skip → ON-02. Tanpa angka statistik.
2. **ON-02 Nama**: wajib 1–20 karakter (trim spasi; hitung karakter grapheme), tombol Lanjut nonaktif sampai valid, pesan error EN/ID. Layar ini hanya nama (D-alief-22).
3. **ON-03 Mode**: dua kartu "Protect myself and my family" (Guardian) / "Protected by others" (Protected), satu pilihan, teks peringatan bahwa pilihan tidak bisa diganti. Simpan → `registerDevice(name:mode:)` → layar "Hi, [nama]" dengan **avatar acak dari `avatarId`** (bukan inisial; di mock dipilih acak). Setelah tersimpan, tidak ada jalan kembali ke ON-03.
4. **ON-04**: lewati sementara (fase 17). Placeholder `// TODO(sync:umar): ON-04 after spikes #2 #3 — replace after fase 17`.
5. **ON-05 Notifikasi**: setelah (calon) ON-04. Penjelasan singkat → `UNUserNotificationCenter.requestAuthorization`. Guardian: wajib (kalau ditolak, tetap lanjut tapi banner pengingat di Home + tombol buka Settings). Protected: boleh lewati. Register APNs (`registerForRemoteNotifications`) disiapkan, token dikirim di fase 15.
6. Protected setelah ON-03 menuju PR-01 Connect (fase 14). Sementara: placeholder layar "Connect to your guardian" dengan `// TODO(sync:alief): PR-01 — replace after fase 14`.
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
- [ ] ON-05: izin diminta; ditolak → banner pengingat di Home (UI test dengan reset izin simulator).
- [ ] Screenshot EN + ID di `qa/img/ui-02/`.

## Risiko & fallback

| Risiko | Fallback |
|---|---|
| Push capability belum ada (TODO C3) | Izin notifikasi lokal tetap bisa diminta; register APNs gagal → log saja, tidak memblokir |
| Ilustrasi belum ada | SF Symbols besar + warna; catat re-skin |

## Catatan handoff

- Fase 13 mengganti `MockRepository.registerDevice` dengan API dan menulis key App Group.
- Fase 14 mengisi layar Connect Protected.
