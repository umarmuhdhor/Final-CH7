# Rencana fase 12 — Retensi + hardening + deploy (dari `ecc:planner`, 22 Okt 2026)

## Keputusan awal (D-alief-B12)
- Batch retensi 100 scan × maks 10 batch/run (bukan 500 di R4 §5): satu `DELETE` Storage per batch (= `REMOVE_BATCH`), aman di bawah 50 subrequest/cron Workers Free. Batch ke-10 penuh → log `backlog: true`.
- Urutan per batch: pilih batch (tanpa transaksi) → path yang bisa dihapus (tidak dipakai scan di luar batch; dedupe) → **hapus objek Storage dulu** (gagal → baris tetap, dicoba besok; objek tidak pernah yatim, P13) → satu transaksi `set local lock_timeout`/`statement_timeout`: `update verdicts set scan_id = null` lalu `delete from scans` (urutan verdict → scan). `55P03`/`40P01` → rollback batch, berhenti, tabel lain tetap dipangkas.
- Heartbeat `ops_heartbeat('cron')` paling awal; tiap langkah try/catch; error dilempar ulang di akhir (Cron Events).
- `family_codes` kedaluwarsa > 1 jam, `join_attempts` > 1 hari, `push_log` > 14 hari, `rate_limit_hits` > 1 hari (chunk berbasis id). Verdict tetap (D-alief-14).
- Ras dedupe tertutup: `recentScreenshot` hanya memakai ulang path dari scan < 24 jam.

## Langkah TDD
A. `src/cron/retention.ts` + `scheduled()` + `triggers.crons ["0 19 * * *"]`; test umur 15/13 hari, path bersama, backlog 1001, Storage gagal, lock verdict (55P03), batas tiap tabel, heartbeat, log hanya jumlah.
B. Migrasi hardening: `statement_timeout 10s`, `idle_in_transaction_session_timeout 15s`, `lock_timeout 5s` untuk `shoo_api`; `blocklist_entries` UPDATE hanya kolom `families` (Worker tidak bisa menyetujui domain, T5). pgTAP.
C. Header keamanan semua respons (nosniff, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`, HSTS, CSP default untuk JSON; CSP `/join` & `/screenshots` tetap), CORS tertutup (OPTIONS 404, tanpa ACAO), `content-length` > 256 KB → 413 sebelum DB.
D. Batas 401 per IP (token tidak dikenal saja): bucket `auth_fail`.
E. Pepper hash IP: secret `RATE_KEY_SECRET` → HMAC untuk kunci rate limit + `join_attempts.ip_hash`; kosong → sha256 + peringatan.
F. Test kebersihan log (alur penuh, spy console) + cakupan semua bucket `limits`.
G. `GET /privacy` EN/ID (P12): data, retensi 14 hari, verdict/blocklist lebih lama, hapus data di app, tanpa tracking, prosesor (Cloudflare, Supabase, Apple).
H. Estimasi kuota (1000 scan) → angka di log; pemicu R2.
I. Review berurutan: security → database (seluruh `backend/`).
J. CI (`backend.yml`: dry-run deploy, gitleaks CLI), `ci/README.md` (C2), `backend/README.md` final (cron, privacy, rollback, kuota).
K. `gitleaks` 0 temuan.
Latensi (D-alief-B10 g): `placement: { mode: "smart" }` (satu baris, bisa dibalik), ukur ulang di LANGKAH MANUAL; gabung query tetap ditunda.

## LANGKAH MANUAL
db push + cek `pg_db_role_setting`; secret `RATE_KEY_SECRET`; deploy (cron terdaftar, screenshot Triggers); bukti run cron di `ops_heartbeat`; uji asap semua endpoint dua device; p95 `/verdicts` ulang; `pg_stat_user_indexes` `verdicts_not_safe`.
