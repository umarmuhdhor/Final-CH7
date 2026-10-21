# Fase 00 — Plan + tooling

| Field | Nilai |
|---|---|
| Track | – (sekali, sebelum app dan be) |
| Branch | `docs/alief-plan` |
| Prasyarat | – |
| Requirement | Mandat Alief (seluruhnya), aturan repo |
| Model | Opus 5.5 |
| Fase berikutnya | 01 (track app) dan 07 (track be), paralel |

## Tujuan

Folder `plan/alief/` lengkap dari hasil grilling 21 Okt 2026, mesin dan plugin siap, worktree per track siap dipakai.

## Bacaan wajib

- `CLAUDE.md` root, `backend/CLAUDE.md`, `ios/ShooApp/CLAUDE.md`, `ios/CLAUDE.md`, `.github/CODEOWNERS`
- `docs/mandates/alief.md`, `contracts/*`, PRD v1.5

## Output

- `plan/alief/**` (README, PROMPT, VERIFY_PROMPT, PROGRESS, TODO, ARCHITECTURE, SECURITY, fixbug, fase-00..17, ref/R1–R7, log/DECISIONS, qa/README)
- PR `docs/alief-plan` → `main` (reviewer Umar)

## Langkah kerja

1. Tulis semua file plan (selesai di sesi grilling).
2. Jalankan `VERIFY_PROMPT.md` di sesi baru (read-only). Perbaiki temuan KRITIS/TINGGI di plan.
3. Cek tool lokal (TODO D1, D2): `xcodebuild -version`, `xcodegen --version`, `supabase --version`, `docker info`, `node -v` (24), `pnpm -v`, `npx wrangler --version`.
4. Buat worktree: `git worktree add ../Final-CH7-app origin/main` dan `git worktree add ../Final-CH7-be origin/main` (setelah PR plan di-merge, supaya plan ada di kedua worktree).
5. Commit `docs(plan): add Alief plan for Team App + Backend`, push, buka PR (hanya setelah Alief bilang "buka PR").

## Verifikasi

```bash
ls plan/alief plan/alief/ref plan/alief/log plan/alief/qa
grep -rn "TODO(sync" plan/alief || true      # harus kosong
git diff --stat origin/main -- . ':!plan/alief'  # harus kosong: fase ini hanya menyentuh plan/alief
```

## Kriteria selesai (DoD)

- [ ] Semua file di README §2 ada.
- [ ] Setiap checkbox mandat Alief dipetakan ke satu fase (PROGRESS tabel P0).
- [ ] VERIFY_PROMPT dijalankan, temuan KRITIS/TINGGI ditutup.
- [ ] PR di-merge (G1).

## Catatan handoff

- Fase 01 dan 07 boleh mulai bersamaan di worktree masing-masing.
