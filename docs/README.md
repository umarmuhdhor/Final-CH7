# Docs

- PRD (source of truth, living doc): https://docs.google.com/document/d/1n_1vngw5fFizP9YHWg0kT3VnqGhgXlbV/edit — v1.5, PM Richard
- Spikes (week 1, lead): [spikes/](spikes/)

## Decisions (2026-10-21)
1. **Privacy vs. server detection (PRD §10):** page content is sent to `POST /analyze` for layer 3–4 but **never stored**. Only results with score ≥ 30 are stored (`POST /scans`). See contracts/api.md.
2. **Hoax detection (layer 5) is Phase 2**, not MVP. No hoax work in MVP.
3. **Verdict lookup only at score ≥ 30 (EX-02):** the extension asks `GET /verdicts?domain=` only once a page reaches 30 — the same point the domain would be sent with `POST /scans`. Low-score browsing never reaches the backend.

## Open questions for PM
1. PRD §4 Scope table also marks "Validasi item Warning", "AI belajar dari keputusan keluarga", and "Lebih dari 3 orang per guardian" with ✓ in the MVP column. Confirm whether these are MVP or Phase 2.
