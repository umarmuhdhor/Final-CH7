# Rencana fase 05 — Guardian & Family mode: GD-01, GD-02, GD-03, GD-05

> Ditulis agent track app (22 Okt 2026). Branch `feat/GD-family-mode`, stacked on #19 (fase 04) → #18 → #14.
> Fase 02 (#16) belum di rantai: tombol Turn on tetap membuka Settings (`TODO(sync:alief)`, D-alief-A14) sampai 02 digabung sebelum 06Q.

| # | Langkah | Test dulu |
|---|---|---|
| 1 | `GuardianShieldView`: toggle Family mode kiri atas (`AppSettings.familyModeOn`, sudah ada sejak fase 01), profile kanan atas; mode off → layar Shield diri sendiri (lingkaran "You're protected" / "You're not protected" + Turn on, kartu blokir terakhir milik sendiri, tanpa baris guardian) — `ProtectedShieldView` diberi parameter perspektif | UI test toggle diingat setelah relaunch |
| 2 | `FamilyShieldModel`: `familyMembers()` (maks 3 ditampilkan) + id scan terbaru per anggota (`scans(owner: .device(id))`) untuk tap → Detail | `FamilyShieldModelTests`: anggota, Not connected hanya bila `extensionActive == false`, id scan terbaru, kosong, gagal |
| 3 | `FamilyShieldView` + `FamilyMemberCard` (avatar, nama, status terakhir, host+path, waktu; "Not connected"); kosong → "Invite your family" (placeholder sampai fase 14) | UI test card → Detail dengan tombol verdict |
| 4 | GD-05: `ActivityModel` filter orang (Everyone / You / per nama) → `owner` `.family` / `.me` / `.device(id)`; nama pemilik di baris; catatan "matikan Family mode untuk riwayat sendiri"; Family mode off → Activity milik sendiri | `ActivityModelTests` filter orang + kombinasi status |
| 5 | Mock: skenario `oneMember`, `threeMembers` (DEBUG `-mock.scenario`) untuk gerbang 0/1/2/3 anggota | test skenario |
| 6 | Gerbang UI `qa/img/ui-05/` (0, 1, 2, 3 anggota; Not connected; Family off; Activity orang; EN/ID, light/dark, AX-XL), review, log, PR | – |
