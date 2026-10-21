# ai/ — owner: Team AI

Server-side detection: layer 3 (content & forms) + layer 4 (reality check, LLM). Layer 5 (hoax) is Phase 2 — do not build it in MVP.
Exposes `POST /analyze` exactly as in contracts/api.md.

- Input `{ snapshot, localSignals }`, output `{ signals: Signal[] }`. Shapes from contracts/ only.
- `/analyze` is stateless: never store or log the snapshot text.
- Respond within 8 s; the extension gives up after that. Layer 3 (rules) should answer even if the LLM is slow/down.
- LLM keys only in `.env` (gitignored). Commit `.env.example`.
- Keep a labelled eval set (scam + legit pages) in `ai/eval/` and report precision/recall when changing prompts or weights.
- Don't touch anything outside `ai/`.
