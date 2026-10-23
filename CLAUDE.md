# Shoo — rules for every AI agent in this repo

Shoo = iPhone Safari Web Extension + app that blocks scam sites (see docs/README.md for the PRD).

## Mandates (task lists)
- Umar (Lead · Extension): [docs/mandates/umar.md](docs/mandates/umar.md)
- Imelda (Team AI): [docs/mandates/imelda.md](docs/mandates/imelda.md) — sekarang dikerjakan Umar (diambil alih 23 Okt 2026)
- Alief (Team App + Backend): [docs/mandates/alief.md](docs/mandates/alief.md)

Before starting any task, read the mandate of the person you're working for. `/mandate` loads it and picks the next task.

## Who owns what
Lead: @umarmuhdhor (Umar) · Team AI: @imeldamayanti (Imelda) · Team App: @aliefauzan (Alief)

| Folder | Owner | Notes |
|---|---|---|
| `contracts/` | Lead | Shared data shapes. Read-only for everyone else |
| `ios/project.yml` | Lead | Targets, capabilities, build settings |
| `ios/ShooShared/` | Lead | Swift models used by app + extension |
| `ios/ShooExtension/` | Lead | Safari extension (except `Resources/detector.js`) |
| `ios/ShooLiveActivity/` | Lead | Dynamic Island (EX-03) |
| `ios/ShooApp/` | Team App | All app screens (ON, PR, GD, DT, PF) |
| `backend/` | Team App | Pairing, Activity, verdicts, push, 14-day retention |
| `detector/` | Lead (diambil alih dari Team AI, 23 Okt 2026) | On-device detection (layer 1–2) |
| `ai/` | Lead (diambil alih dari Team AI, 23 Okt 2026) | Server-side detection (layer 3–4, LLM) |
| `plan/<name>/` | That person | Their own work plan (docs only), e.g. `plan/alief/`. Reviewed by the lead |

## Hard rules
1. Only edit files inside your team's folder. If the task needs a change elsewhere, stop and tell the user.
2. NEVER edit `contracts/`, `ios/project.yml`, or `ios/ShooShared/`. If you need a change, open a GitHub issue (rule 7) and wait for the lead's answer there.
3. Every JSON you send or receive must match `contracts/`. Use `contracts/fixtures/` as mock data instead of waiting for another team.
4. One branch = one PRD ID: `feat/EX-04-popup-warning`, `fix/GD-04-code-expiry`. Keep PRs small, merge at least daily.
5. Never commit secrets (API keys, APNs keys, LLM keys). Use `.env` (gitignored) and `.env.example`.
6. Read the `CLAUDE.md` inside the folder you work in — it has more rules.
7. Every question or proposal for another person (lead, other team, PM) goes into a GitHub issue, not chat, a PR description, or a plan file only. Use the **Question / proposal** template (`.github/ISSUE_TEMPLATE/question.yml`): label `question`, assign the person who must answer, title `<PRD ID or area>: <short question>`, numbered questions, and what you do until answered. One issue = one topic. Link the issue number wherever the question is tracked (plan TODO, PR). The answer and decision stay in the issue; close it once decided.
