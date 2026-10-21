# Fase 05 — Guardian & Family mode: GD-01, GD-02, GD-03, GD-05

| Field | Nilai |
|---|---|
| Track | app |
| Branch | `feat/GD-family-mode` |
| Prasyarat | 04 |
| Requirement | GD-01, GD-02, GD-03, GD-05 (P0) |
| Model | Sonnet 5.5 · `apple-design`, `ecc:swiftui-patterns` |
| Fase berikutnya | 06 |

## Tujuan

Tampilan Guardian untuk dirinya sendiri dan Family mode untuk memantau sampai 3 anggota keluarga.

## Bacaan wajib

- PRD §8.3 (GD-01, 02, 03, 05), §9
- Fixture `family-members.json`, `activity-family.json`

## Output

- `Features/Shield/GuardianShieldView`, `FamilyShieldView`, `FamilyMemberCard`, toggle Family mode di kiri atas
- `AppSettings.familyModeEnabled` (diingat, GD-02)
- `ActivityModel` + filter orang (Everyone / per nama) + nama pemilik di item
- Test: toggle diingat lintas peluncuran, "Not connected" saat `extensionActive == false`, filter orang, empty state "Invite your family"

## Langkah kerja

1. **GD-01**: toggle Family mode kiri atas, profile kanan atas; lingkaran "You're protected" (Off → "You're not protected · Turn on", tombol Turn on menuju placeholder ON-04 / Settings); card Blocked terakhir milik sendiri; navbar Shield / Activity.
2. **GD-02**: toggle mengganti tampilan ke sudut pandang keluarga; Safari Guardian tetap dilindungi (hanya tampilan); pilihan terakhir disimpan di `AppSettings`.
3. **GD-03**: lingkaran + avatar orang yang dilindungi (maks 3); card ramping per orang: nama, status terakhir, link, waktu; "Not connected" kalau extension orang itu mati (`extensionActive == false`, lihat D-alief-15); tap card → Detail scan terakhir; kosong → tombol "Invite your family" (membuka Family code, fase 14; sementara placeholder).
4. **GD-05**: Activity Family: filter orang (Everyone / per nama) + status; item menampilkan nama pemilik; catatan "Riwayat sendiri: matikan Family mode".
5. Gerbang UI: 0, 1, 2, 3 anggota; anggota Not connected; EN + ID.

## Verifikasi

```bash
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppTests -only-testing:ShooAppUITests/GuardianUITests
```

## Kriteria selesai (DoD)

- [ ] GD-01, 02, 03, 05 sesuai "Selesai kalau" (screenshot + test).
- [ ] Toggle diingat setelah app ditutup (UI test relaunch).
- [ ] Tombol validasi tampil di Detail untuk item keluarga dan milik sendiri (sudah dari fase 03; regresi test).

## Catatan handoff

- "Invite your family" dan menu Family code disambung di fase 14.
