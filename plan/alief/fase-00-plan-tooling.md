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
3. Cek tool lokal (TODO D1, D2): `xcodebuild -version`, `xcodegen --version`, `supabase --version`, `docker info`, `node -v` (24), `pnpm -v`, `npx wrangler --version`, `gitleaks version`, `jq --version`, `source plan/alief/ref/sim.sh`.
4. Alief mengirim C1, C3, C11, C13 ke Umar sekarang (TODO §C), supaya jawaban ada sebelum fase 01S/05/08/14. C14 dikirim setelah spike 01S.
5. Buat worktree: `git worktree add ../Final-CH7-app origin/main` dan `git worktree add ../Final-CH7-be origin/main` (+ `git worktree add ../Final-CH7-spike origin/main` saat fase 01S dimulai) (setelah PR plan di-merge, supaya plan ada di kedua worktree).
6. Commit `docs(plan): add Alief plan for Team App + Backend`, push, buka PR (hanya setelah Alief bilang "buka PR").

## Verifikasi

```bash
ls plan/alief plan/alief/ref plan/alief/log plan/alief/qa
grep -rln "TODO(sync" plan/alief | grep -v -e PROMPT.md -e R5-konvensi.md -e "fase-" -e "log/" || true   # harus kosong (PROMPT, R5, file fase, dan log memang menyebut formatnya)
git diff --stat origin/main...HEAD -- . ':!plan/alief'  # harus kosong: fase ini hanya menyentuh plan/alief (tiga titik = sejak merge-base)
```

## Kriteria selesai (DoD)

- [ ] Semua file di README §2 ada.
- [ ] Setiap checkbox mandat Alief dipetakan ke satu fase (PROGRESS tabel P0).
- [ ] VERIFY_PROMPT dijalankan di sesi baru berulang sampai tidak ada temuan KRITIS/TINGGI (laporan di `log/verify/run-NN.md`).
- [ ] PR di-merge (G1).

## Catatan handoff

- Fase 01 dan 07 boleh mulai bersamaan di worktree masing-masing.
