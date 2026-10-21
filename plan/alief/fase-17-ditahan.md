# Fase 17 — Ditahan: ON-04 (Turn on extension) dan Live Activity lewat push

| Field | Nilai |
|---|---|
| Track | app (ON-04), be (Live Activity push) |
| Branch | `feat/ON-04-turn-on-extension`, `feat/BE-live-activity-push` |
| Prasyarat | Spike Umar `docs/spikes/extension-status.md`, `open-extension-settings.md`, `dynamic-island.md` berisi keputusan |
| Requirement | ON-04 (P0, ditahan), EX-03 jalur push-to-start (kalau dipilih Umar) |
| Model | Sonnet 5.5 (ON-04), Opus 5.5 (push Live Activity) |

## Status

**Jangan dikerjakan** sampai TODO D5 `[x]` dan file spike punya bagian "Result → Decision" terisi. Agent mode auto melewati fase ini.

## ON-04 (rencana kalau spike selesai)

1. Ilustrasi letak switch, tombol Turn on membuka Settings sesuai hasil spike #3 (atau Settings umum + langkah bergambar).
2. Status dicek otomatis saat app kembali ke foreground (`ExtensionStatus`, hasil spike #2). On → lanjut; Off → tetap.
3. Link "Still can't? Watch video" → video ≤ 60 s dari PM, PiP (`AVPictureInPictureController`) tetap tampil saat di Settings.
4. Menggantikan placeholder `TODO(sync:umar): ON-04` dari fase 02 dan tombol "Turn on" di GD-01.

## Live Activity push (kalau Umar memilih push-to-start)

- Endpoint tambahan dari Umar (perubahan kontrak), token push-to-start disimpan per device, Worker mengirim APNs `apns-push-type: liveactivity`. Rencana rinci ditulis setelah kontrak ada.
