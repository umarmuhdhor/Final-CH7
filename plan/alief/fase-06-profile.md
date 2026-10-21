# Fase 06 — Profile: PF-01

| Field | Nilai |
|---|---|
| Track | app |
| Branch | `feat/PF-01-profile` |
| Prasyarat | 05 |
| Requirement | PF-01 (P0) |
| Model | Sonnet 5.5 · `apple-design`, `ecc:swiftui-patterns` |
| Fase berikutnya | 06Q |

## Tujuan

Layar Profile untuk semua mode: identitas, bahasa, status extension, dan kontrol keluarga.

## Bacaan wajib

- PRD §8.6 PF-01, §10 (Guardian dan Protected sama-sama bisa memutus koneksi)
- `contracts/api.md` `PATCH /devices/me`, `DELETE /family/guardian`, `DELETE /family/members/{id}`

## Output

- `Features/Profile/ProfileView`, `ProfileModel`
- Test: ganti nama (validasi 1–20, `updateMe`), ganti bahasa EN ↔ ID berlaku langsung di seluruh app, Disconnect Protected, menu Family code hanya untuk Guardian

## Langkah kerja

1. Dibuka dari ikon kanan atas di Shield (semua mode).
2. Nama + avatar (nama bisa diubah, validasi sama ON-02).
3. Bahasa: English (default) / Bahasa Indonesia → `AppSettings.language` + `updateMe(language:)` (push dilokalkan sesuai bahasa ini, D-alief-05).
4. Status extension Active/Off (`ExtensionStatus`).
5. Protected: guardian terhubung (avatar + nama) + tombol Disconnect (dialog konfirmasi standar iOS boleh di sini karena bukan validasi GD-07) → `leaveGuardian()` → kembali ke layar Connect.
6. Guardian: menu "Family code" (GD-04, layar di fase 14; sementara placeholder) dan daftar terhubung x/3 ringkas.
7. **Refine ON-04** (hanya kalau log fase 01S punya handoff "Refine ON-04" yang belum diterapkan fase 02): ubah langkah ilustrasi, tombol, petunjuk, dan window di `TurnOnExtensionView` sesuai hasil spike; test + gerbang UI. Tandai handoff itu "diterapkan di fase 06" di log 01S.
8. Gerbang UI.

## Verifikasi

```bash
source plan/alief/ref/sim.sh
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppTests/ProfileModelTests -only-testing:ShooAppUITests/ProfileUITests
```

## Kriteria selesai (DoD)

- [ ] PF-01 sesuai "Selesai kalau" untuk Guardian dan Protected.
- [ ] Ganti bahasa mengubah semua layar Fase A tanpa restart (UI test + screenshot).

## Catatan handoff

- Setelah fase ini: jalankan fase 06Q (QA-A).
