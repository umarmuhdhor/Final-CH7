# Fase 04 — Protected: Shield (PR-04) + Activity (PR-05)

| Field | Nilai |
|---|---|
| Track | app |
| Branch | `feat/PR-04-05-shield-activity` |
| Prasyarat | 03 |
| Requirement | PR-04, PR-05 (P0) |
| Model | Sonnet 5.5 · `apple-design`, `ecc:swiftui-patterns` |
| Fase berikutnya | 05 |

## Tujuan

Home dan riwayat untuk orang tua (mode Protected): status perlindungan, guardian-nya, blokir terakhir, dan riwayat Warning/Blocked.

## Bacaan wajib

- PRD §8.2 (PR-04, PR-05), §3 persona orang tua, §9 notifikasi
- `ContentView.swift` lama / `Data/ExtensionStatus.swift` (Active/Off dari `AppGroup.Key.extensionLastSeenAt`)

## Output

- `Features/Shield/ProtectedShieldView`, `ShieldModel`
- `Features/Activity/ActivityView`, `ActivityModel` (dipakai ulang Guardian di fase 05), `ActivityRow`, `FilterChips`
- Test: Active/Off berdasarkan umur heartbeat, card blokir terakhir = scan blocked terbaru, filter All/Warning/Blocked, urutan terbaru di atas, paginasi cursor, empty state

## Langkah kerja

1. **PR-04**: ikon profile kanan atas; lingkaran status extension (Active/Off) + avatar guardian (nama guardian dari sesi; mock: "Adhella"); card "Blocked!" terakhir (skor, link, alasan 1–2 kalimat dari sinyal teratas `labelSimple`); tap → Detail; kosong → ilustrasi + "Nothing blocked yet". Banner pengingat notifikasi (fase 02) kalau izin ditolak.
2. Ambang "Active": `extensionLastSeenAt` lebih baru dari `AppGroup.extensionActiveWindow` (24 jam, `ShooShared`) — jangan membuat konstanta sendiri (D-alief-23). Refresh saat app kembali ke foreground.
3. **PR-05**: chip filter All / Warning / Blocked; item: ikon situs, link (domain tebal), waktu relatif, chip status; terbaru di atas; tap → Detail; scroll tak berujung dengan `nextCursor`; pull to refresh; empty state per filter.
4. Gerbang UI dengan teks besar (persona 45–65 tahun): Dynamic Type XL tanpa terpotong.

## Verifikasi

```bash
source plan/alief/ref/sim.sh
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppTests/ShieldModelTests -only-testing:ShooAppTests/ActivityModelTests
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppUITests/ProtectedUITests
```

## Kriteria selesai (DoD)

- [ ] PR-04 sesuai "Selesai kalau" (screenshot Active, Off, kosong, ada blokir).
- [ ] PR-05 filter dan urutan benar (test), tap → Detail (UI test).
- [ ] Tidak ada tombol It's safe/Not safe di mana pun untuk Protected (UI test).

## Catatan handoff

- `ActivityModel` dipakai GD-05 dengan filter orang (fase 05).
