# Log fase 25 — Verdict realtime (EX-06)

- **Status:** [ ] 25-0 baseline (cloud/device, LANGKAH MANUAL 1–3) · [r] 25a-be PR `feat/EX-06-verdict-latency-log`, reviewer @umarmuhdhor, **pending LANGKAH MANUAL 7** (setelah merge) · 25a-ext milik Umar (Q1) · 25b/25c tidak dikerjakan sesi ini (brief: skip; menunggu Q2–Q5).
- **Model:** Claude Opus 5.5, sesi track be. 1 Nov 2026.
- **Rencana:** `fase-25-realtime-verdict.md`.
- **Keputusan K:** R8 §c (D-alief-C29): K7 ya (log `verdict_seen`, 25a-be). K1–K6, K8 menunggu jawaban Umar Q1–Q5 (ditanyakan di PR 25a-be, bukan issue). Tidak ada D-alief baru: K7 sudah rekomendasi file fase.

## 25-0 — baseline

Semua langkah 25-0 butuh produksi atau device (M5 SQL editor produksi, M1 rekaman 2 iPhone, M2/M4 Safari Develop + Xcode). Sesi ini tidak menjalankan aksi cloud → LANGKAH MANUAL 1–3. Angka teoritis dari file fase (belum diukur): p50 ±2,5 s + RTT, p95 ±4,75 s + RTT.

## 25a-be — `feat/EX-06-verdict-latency-log` (dari `origin/main` aa976af)

### Checklist langkah

- [x] 1. Merah: `test/verdicts.test.ts` — verdict ≤ 120 s → satu baris `verdict_seen` dengan kunci persis `event`, `ageMs` (angka, 0 ≤ ageMs ≤ 120 000), `value`, tanpa domain/id/nama/token; verdict 121 s lalu atau tidak ada verdict → tidak ada baris. `test/log-hygiene.test.ts`: baris `verdict_seen` ada dalam alur penuh dan daftar bocoran (token, id, nama, domain) tetap bersih. Tanpa kode: 2 merah.
- [x] 2. Kode: `routes/verdicts.ts` `GET /verdicts` → `logFreshVerdict` setelah `findVerdict` (`ageMs = max(0, Date.now() − decidedAt)`, NaN dilewati; `Date.now()` sudah maju setelah query DB).
- [x] 3. Hijau: typecheck + suite. `API.md` `GET /verdicts`: paragraf "Log (fase 25 K7)".

Cherry-pick `b9987db` dari #210 supaya CI hijau.

### Verifikasi

| Perintah | Hasil |
|---|---|
| `npx tsc --noEmit` (`backend/api`) | bersih |
| `vitest run test/verdicts.test.ts test/log-hygiene.test.ts` | 53/53 (tanpa log: 2 merah) |
| `vitest run` (suite penuh) | 537 lulus, 1 skip |

### Review

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:typescript-reviewer` | HIGH: symlink `backend/api/node_modules` (alat lokal sesi, worktree terpisah) ikut ter-commit. Format `decidedAt` (`ISO_MS` diakhiri `Z`), `Date.now()` setelah I/O, batas 121 s, volume log: semua aman. LOW: tipe kembali `void`, konstanta di atas route | HIGH: dihapus dari commit sebelum push (`git rm --cached`, amend), cabang lain dicek bersih. LOW diperbaiki |

### Privasi Apple (SECURITY §3)

- P6: `verdict_seen` hanya `ageMs` + `value` (test kunci persis + log-hygiene). Tanpa domain, id device, nama Guardian.
- Tidak ada data atau kolom baru.

## LANGKAH MANUAL

- [x] 1. **(Alief, Supabase SQL editor, baca saja)** M5 sebaran waktu reaksi Guardian (query di `fase-25-realtime-verdict.md` LANGKAH MANUAL 1), hasil agregat saja ke log ini.
  - **7 Nov 2026, 17:11 UTC** (`supabase db query --linked`, query M5 persis): n = 1, p50 = p90 = p95 = 80,3 s. Sampel terlalu kecil untuk sebaran (retensi 14 hari); ulangi setelah M1.
  - **8 Nov 2026, 17:48 UTC** (query M5 persis, ulang): n = 1, p50 = p95 = 80,3 s. Belum ada verdict baru untuk scan blocked; tunggu M1 (2 iPhone).
- [ ] 2. **(Alief + 1 penguji, 2 iPhone)** M1: tap Aman → halaman terbuka, rekam 60 fps, 20×; p50/p95 ke log.
- [ ] 3. **(Alief, Mac + iPhone)** M2/M4: hitung `GET /verdicts` per 10 menit layar blokir (Safari Develop), Energy Impact indikatif.
- [ ] 4. ~~Issue Umar~~ — ditanyakan di PR 25a-be (`## Questions for Umar`, D-alief-C29).
- [ ] 7. **(Alief, cloud, setelah 25a-be merge + CI deploy)** `npx wrangler tail shoo-api --format json` saat M1: salin hanya baris `verdict_seen` (`ageMs`, `value`).

## Catatan handoff

- 25b (spike WebSocket) baru boleh mulai setelah Q2 dijawab; 25a-ext (jadwal polling adaptif) dikerjakan Umar setelah Q1.
- `verdict_seen` dipakai untuk mengukur semua varian (sekarang, 25a-ext, 25c).
