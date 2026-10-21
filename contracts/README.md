# Contracts

Single source of truth for data shared between teams. **Owner: lead.** Everyone else: read-only.

| File | What | Producer → Consumer |
|---|---|---|
| [scan-result.schema.json](scan-result.schema.json) | One detection result (score, status, signals) | Extension → Backend → App |
| [detector-interface.md](detector-interface.md) | `PageSnapshot` in, `Signal[]` out, scoring rules | Detector/AI ↔ Extension |
| [api.md](api.md) | HTTP endpoints | Backend/AI ↔ App/Extension |
| [app-group-keys.md](app-group-keys.md) | App Group keys, native messages, deep links | App ↔ Extension |
| [fixtures/](fixtures/) | Example payloads — use as mocks | Everyone |

## Thresholds (PRD §5)
| Score | Status | Extension |
|---|---|---|
| 0–29 | `normal` | Nothing shown, nothing sent |
| 30–49 | `warning` | First popup + highlight |
| 50–79 | `warning` | Second popup + sensitive forms struck through |
| ≥ 80 | `blocked` | Block screen, no bypass |

## Changing a contract
1. Open a PR that edits only `contracts/` + explains why.
2. Lead approves, then each team updates its own code in separate PRs.
3. Additive changes (new optional field) are cheap. Renaming/removing a field breaks other teams — avoid.
