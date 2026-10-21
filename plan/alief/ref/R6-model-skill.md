# R6 — Model AI dan skill per fase

## 0. Harness

Claude Code + plugin **ECC** (Everything Claude Code) + plugin **Superpowers**. Siklus wajib per fase ada di `PROMPT.md` langkah 4–12. Ringkasnya:

| Langkah | ECC | Superpowers |
|---|---|---|
| Rencana | agent `ecc:planner` | `superpowers:writing-plans` → `log/fase-XX-plan.md` |
| UX belum jelas | – | `superpowers:brainstorming` (singkat) |
| Test dulu | agent `ecc:tdd-guide`, skill `ecc:tdd-workflow` | `superpowers:test-driven-development` |
| Eksekusi | – | `superpowers:executing-plans` / `superpowers:subagent-driven-development` |
| Debug | – | `superpowers:systematic-debugging` |
| Build merah | `ecc:swift-build-resolver`, `ecc:build-error-resolver` | – |
| Review | `ecc:swift-reviewer`, `ecc:typescript-reviewer`, `ecc:database-reviewer`, `ecc:security-reviewer`, `ecc:a11y-architect` | `superpowers:requesting-code-review` |
| Verifikasi | skill `ecc:verification-loop` | `superpowers:verification-before-completion` |
| Selesai | `/ecc:save-session` | `superpowers:finishing-a-development-branch` |
| Worktree | – | `superpowers:using-git-worktrees` |

## 1. Pilihan model

| Model | Dipakai untuk |
|---|---|
| Opus 5.5 | Backend (auth, family, akses data, push, retensi), track c (sambung app ↔ backend, sesi App Group), perbaikan bug keamanan |
| Sonnet 5.5 | Layar SwiftUI melawan fixture, QA run, dokumen |

Eskalasi: kalau Sonnet gagal dua kali di build/test yang sama, pindah ke Opus untuk langkah itu, catat di log.

## 2. Rekomendasi per fase

| Fase | Model | Skill domain (dimuat otomatis) | Review wajib |
|---|---|---|---|
| 01 | Sonnet 5.5 | `apple-design`, `ecc:swiftui-patterns`, `ecc:swift-protocol-di-testing`, `write-swift` | swift-reviewer |
| 02 | Sonnet 5.5 | `apple-design`, `ecc:swiftui-patterns`, `emil-design-eng` (splash) | swift-reviewer, a11y |
| 03 | Sonnet 5.5 | `apple-design`, `ecc:swiftui-patterns` | swift-reviewer, a11y |
| 04 | Sonnet 5.5 | `apple-design`, `ecc:swiftui-patterns` | swift-reviewer, a11y |
| 05 | Sonnet 5.5 | `apple-design`, `ecc:swiftui-patterns` | swift-reviewer, a11y |
| 06 | Sonnet 5.5 | `apple-design`, `ecc:swiftui-patterns` | swift-reviewer, a11y |
| 06Q | Sonnet 5.5 | R7, iOS Simulator tool | – |
| 07 | Opus 5.5 | `ecc:api-design`, `ecc:postgres-patterns`, `ecc:database-migrations`, `ecc:backend-patterns`, `ecc:documentation-lookup` (Cloudflare, Supabase) | typescript, database, security |
| 08 | Opus 5.5 | sama dengan 07 | typescript, database, security |
| 09 | Opus 5.5 | sama dengan 07 | typescript, database, security |
| 10 | Opus 5.5 | sama dengan 07 | typescript, database, security |
| 11 | Opus 5.5 | sama dengan 07 + docs APNs | typescript, security |
| 12 | Opus 5.5 | sama dengan 07 + `ecc:deployment-patterns` | typescript, database, security |
| 13 | Opus 5.5 | `ecc:swift-concurrency-6-2`, `ecc:swift-protocol-di-testing`, `ecc:api-design` | swift, security |
| 14 | Opus 5.5 | `apple-design`, `ecc:swiftui-patterns`, `ecc:swift-concurrency-6-2` | swift, security, a11y |
| 15 | Opus 5.5 | `ecc:swift-concurrency-6-2` | swift, security |
| 16 | Sonnet 5.5 (fix keamanan: Opus 5.5) | R7, iOS Simulator tool, `ecc:e2e-testing` | sesuai fix |

## 3. Efisiensi

- Satu fase per sesi. Konteks > 60%: simpan log + `/ecc:save-session`, mulai sesi baru dengan kalimat yang sama.
- Pencarian luas di repo pakai agent `Explore`/`ecc:code-explorer`, bukan membaca semua file di thread utama.
- Fakta library (Hono, postgres.js, wrangler, Supabase CLI, APNs) dari dokumentasi resmi lewat `ecc:documentation-lookup`, bukan ingatan.
