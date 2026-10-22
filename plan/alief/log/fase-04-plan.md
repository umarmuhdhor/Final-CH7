# Rencana fase 04 — Protected: Shield (PR-04) + Activity (PR-05)

> Ditulis agent track app (22 Okt 2026). Branch `feat/PR-04-05-shield-activity`, stacked on #18 (`feat/DT-detail`, fase 03) → #14.
> Fase 02 (#16) ada di cabang samping; digabung ke rantai sebelum 06Q (instruksi koordinator).

| # | Langkah | Test dulu |
|---|---|---|
| 1 | `ShieldModel`: status extension (closure, default heartbeat App Group + `-UITestExtensionActive` DEBUG), guardian dari `me()`, blokir terakhir = `scans(owner: .me, status: .blocked)` item pertama, alasan = 1–2 `labelSimple` dengan bobot tertinggi | `ShieldModelTests`: Active/Off dari umur heartbeat (`AppGroup.extensionActiveWindow`), card = blocked terbaru, kosong, guardian ada/tidak, gagal muat |
| 2 | `ProtectedShieldView`: lingkaran status + avatar/nama guardian + card "Blocked!" (skor, domain, alasan, waktu) → Detail; kosong → "Nothing blocked yet"; refresh saat foreground | UI test |
| 3 | `ActivityModel` (dipakai GD-05): filter All/Warning/Blocked, terbaru di atas, `nextCursor` load more, refresh, abaikan respons basi saat filter berganti | `ActivityModelTests` |
| 4 | `ActivityView` + `ActivityRow` + `FilterChips`; `.refreshable`; empty state per filter; tap → Detail | `ProtectedUITests` |
| 5 | `MainTabView`: Protected → Shield/Activity baru; Guardian tetap placeholder (fase 05) | UI test |
| 6 | Gerbang UI `qa/img/ui-04/` (Active, Off, kosong, ada blokir, Activity per filter; EN/ID, light/dark, AX-XL), review, log, PR | – |

Banner pengingat notifikasi: hanya Guardian (D-alief-A08) → tidak ada di PR-04. Tombol "Turn on" saat Off: buka Settings sekarang; sheet `TurnOnExtensionView` (fase 02) dipasang saat 02 digabung ke rantai (`TODO(sync:alief)`).
