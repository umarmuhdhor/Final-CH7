# Log fase 20 — Pensiun screenshot (EX-07)

- **Status:** [ ] 20a **ditunda: gerbang G2 belum lulus** (LANGKAH MANUAL 1 belum dicentang di mana pun, 1 Nov 2026) · 20b/20c tidak dikerjakan sesi ini (brief track be: skip) · 20d milik track app.
- **Model:** Claude Opus 5.5, sesi track be. 1 Nov 2026.
- **Rencana:** `fase-20-screenshot-sunset.md` (PR #207).
- **Keputusan:** brief koordinator: 20a hanya kalau G2 dicentang; kalau tidak, tulis LANGKAH MANUAL dan lewati. Tidak ada kode di PR ini.

## Cek gerbang (1 Nov 2026)

- `log/fase-20.md` belum ada di `origin/main` maupun `docs/alief-plan-19-26` → LANGKAH MANUAL 1 (G2) belum dicentang.
- G2 butuh SQL produksi (read-only) dan pengecekan HP demo: aksi cloud/device, tidak dijalankan sesi ini.

## LANGKAH MANUAL

- [ ] **1. G2 — sebelum 20a (Alief): semua device demo di build ≥ #201.**
  - Checklist per HP demo (Alief, Umar, tester lain): app + extension dipasang ulang dari `main` ≥ 2720b13 (Xcode) atau build TestFlight dari commit itu. Versi di Profile selalu `0.1.0 (1)`, jadi catat tanggal pasang, bukan versi.
  - SQL read-only di Supabase SQL editor (harus 0):
    ```sql
    -- Devices whose latest scan in the last 7 days still carried a screenshot (old build).
    select count(*) as devices_on_old_build from (
      select distinct on (owner_id) owner_id, screenshot_path
      from scans where created_at > now() - interval '7 days'
      order by owner_id, created_at desc) last
    where screenshot_path is not null;
    ```
  - Kalau > 0: lihat nama device di SQL editor (jangan disalin ke log/chat), minta pemiliknya update, ulangi.
  - Catat di sini: tanggal, angka (0), tanpa id/nama.
- [ ] **2. Pertanyaan K7 ke Umar** (R8 §b #1, wajib sebelum merge 20a): diajukan di PR ini (`## Questions for Umar`, D-alief-C29), bukan issue.
- [ ] **3. Setelah 1 + 2:** sesi berikut menjalankan 20a (`fix/EX-07-ignore-screenshot-upload`) sesuai Langkah kerja 20a di file fase (TDD, review security → TypeScript, merge di menit :10–:40, tidak di 18:30–19:30 UTC; jam deploy CI = awal jam G1).

## Catatan handoff

- 20a tidak menunggu jawaban K7 untuk mulai coding (field opsional + deprecated), tetapi pertanyaan harus sudah diajukan sebelum merge.
