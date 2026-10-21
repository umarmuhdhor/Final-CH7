# Fase 17 — Ditahan: Live Activity lewat push

| Field | Nilai |
|---|---|
| Track | be (Live Activity push) |
| Branch | `feat/BE-live-activity-push` |
| Prasyarat | Spike Umar `docs/spikes/dynamic-island.md` memilih jalur push-to-start + perubahan kontrak dari Umar |
| Requirement | EX-03 jalur push-to-start (kalau dipilih Umar) |
| Model | Opus 5.5 |

## Status

**Jangan dikerjakan** sampai Umar memberi kabar (mandat "Ditahan dulu") dan TODO §D mencatatnya. Agent mode auto melewati fase ini. ON-04 tidak lagi ditahan: dikerjakan di fase 02 + spike 01S (D-alief-29).

## Live Activity push (kalau Umar memilih push-to-start)

- Endpoint tambahan dari Umar (perubahan kontrak), token push-to-start disimpan per device, Worker mengirim APNs `apns-push-type: liveactivity`. Rencana rinci ditulis setelah kontrak ada.
