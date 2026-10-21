---
description: Load your Shoo mandate and start the next unchecked task
argument-hint: "[imelda|alief] [task, e.g. M3 or ON-02]"
---

You are helping a member of the Shoo team work on their mandate.

## 1. Identify the member
- If `$ARGUMENTS` starts with `imelda` or `alief`, use that.
- Otherwise run `gh api user --jq .login` (fallback: `git config user.name`) and map:
  - `imeldamayanti` → `docs/mandates/imelda.md` (Team AI)
  - `aliefauzan` → `docs/mandates/alief.md` (Team App + Backend)
  - `umarmuhdhor` → the lead; ask which mandate to review instead of starting work.
- If you can't tell, ask.

## 2. Load context
Read, in order: the mandate file, the root `CLAUDE.md`, the `CLAUDE.md` of every folder the mandate lets them edit, and every `contracts/` file the mandate lists as required reading.

## 3. Pick the task
- If `$ARGUMENTS` names a task (e.g. `M3`, `ON-02`), use it. Otherwise pick the **first unchecked** `- [ ]` item in order.
- Check its "Bergantung pada" / "Ditahan dulu" notes. If it's blocked, say so and suggest the next unblocked task (use mocks/fixtures where the mandate allows).

## 4. Confirm before coding
Reply in Bahasa Indonesia with:
- Task + PRD ID, and its "Selesai kalau" criteria
- Files you'll create/edit (must be inside their folders)
- Short plan (3–6 steps) and the branch name from the mandate
Wait for "ok" before writing code.

## 5. Work
- `git switch main && git pull`, then create the branch from the mandate.
- Stay inside the member's folders. If the task needs a change to `contracts/`, `ios/project.yml`, `ios/ShooShared/`, or another team's folder: STOP and draft a message for Umar instead.
- iOS: run `cd ios && xcodegen` after adding files; build before saying it works.
- Test against the "Selesai kalau" criteria.

## 6. Finish
- Tick the task's checkbox in the mandate file (only that task).
- Commit, push, and open a PR with `gh pr create` — title `[<ID>] <summary>`, body from `.github/pull_request_template.md`, reviewer `umarmuhdhor`.
- Tell the member what was done, what was tested, and the next task.
