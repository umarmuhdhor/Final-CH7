# Log fase 19 — Kuota salinan halaman per keluarga + sinyal alert

- **Status:** [r] 19a — PR `feat/EX-07-replica-family-quota`, reviewer @umarmuhdhor, **pending LANGKAH MANUAL 1, 3–5** (data cloud untuk meninjau angka, merge di jam aman, uji asap cloud).
- **Model:** Claude Opus 5.5, sesi track be. 1 Nov 2026.
- **Rencana:** `fase-19-replica-quota.md` (Langkah kerja 19a dipakai langsung).
- **Keputusan K:** R8 §c (D-alief-C29): K2 per keluarga 60 upload + 10 MB / 24 jam, device 50, IP 300, global tetap, tanpa batas churn join; K3 (b) cadangan 20 % terakhir global untuk keluarga < 10 upload. K1 (a), K4–K8 rekomendasi file fase. Lihat D-alief-B14.

## 19a — backend (`feat/EX-07-replica-family-quota`, dari `origin/main` aa976af)

### Checklist langkah

- [x] 1. Test merah (`test/replicas.test.ts`): kuota keluarga (Guardian + 3 Protected, 60 upload tersebar → `family_quota`, keluarga lain tetap menyimpan), Guardian sendiri ikut dihitung, byte keluarga (34 × 307 200 → halaman kecil lolos, ukuran penuh berikutnya `family_bytes`), cadangan per upload (2400 global: keluarga 10 upload → `reserve`, keluarga 9 → tersimpan; 3000 → `global_quota`) dan per byte (> 400 MiB), urutan alasan (device + keluarga penuh → `quota`), paralel 4 anggota dengan 59 upload → tepat satu tersimpan, churn (anggota lepas membawa uploadnya), reuse tidak dihitung, `expect(REPLICA_QUOTA)`. `test/replica-usage.test.ts` baru (field K5.2 persis + urutannya, level `ok`/`reserve`/`full` → `log`/`warn`/`error`, tanpa id/domain/path, gauge gagal → `replica_usage_failed` dan notifikasi tetap jalan). `log-hygiene.test.ts`: drop `family_quota` + gauge tanpa id/domain.
- [x] 2. `reserveReplica`: semua hitungan (owner, keluarga, global) satu statement setelah `pg_advisory_xact_lock(6, 0)`; `REPLICA_QUOTA` + `QUOTA_DROP` baru.
- [x] 3. `replicaUsage` + `logReplicaUsage` + cabang cron per jam `index.ts` (`try/finally`: gauge jalan walau notifikasi gagal, gagal gauge tidak menggagalkan run).
- [x] 4. `EXPLAIN` lokal (lihat bawah). File `plan/alief/qa/replica-quota-explain.sql` **tidak** dibuat: sesi ini hanya boleh `backend/**` + `plan/alief/log/**`; SQL-nya tercatat di bawah.
- [x] 5. Docs: `backend/API.md` (aturan replica), `backend/README.md` (Quota, Notifications: gauge). `ARCHITECTURE.md` §3, `SECURITY.md` T10, `ref/R3` §5, `TODO.md` E8, `DECISIONS.md`: **tidak** diubah di sini (di luar folder sesi; koordinator, PR #207).
- [x] 6. Review berurutan: security → database → TypeScript.

### Bukti C3 (kunci global)

Test "parallel scans of different members cannot overrun the family quota" dijalankan 3× dengan baris `pg_advisory_xact_lock(6, 0)` dihapus sementara: **3/3 merah**. Dengan kunci: hijau.

### EXPLAIN (langkah 4, Supabase lokal, 1 Nov 2026)

Data: Guardian `xg` + 3 Protected, 50 owner lain, 3000 baris `scans` dengan `replica_bytes` (200 milik keluarga) + 1000 tanpa, `vacuum analyze scans`. Statement hitungan persis dari `replicaCounts` (`db/repo/scans.ts`) dengan id literal.

| Setelan | Rencana untuk `scans` | Waktu |
|---|---|---|
| bawaan | `Seq Scan on scans` (3000 dari 4000 baris lolos filter, 105 buffer) | 0,51 ms |
| `enable_seqscan = off` | `Index Scan using scans_created` | 0,57 ms |

`family_links`: `Index Scan using family_links_pkey` (seq scan di tabel 3 baris). **Deviasi DoD:** planner tidak memilih `Index Only Scan using scans_original_replica` di data uji ini karena 75 % baris adalah upload 24 jam (selektivitas rendah); di produksi sebagian besar baris `scans` tidak punya `replica_bytes` dan berumur > 24 jam, jadi index parsial lebih menarik. Waktu < 1 ms di bawah kunci `(6, 0)` dalam kedua rencana. Hitungan global lama (sebelum fase 19) memindai baris yang sama. Diperiksa ulang di cloud setelah ada data (LANGKAH MANUAL 1).

### File

Diubah: `backend/api/src/db/repo/scans.ts` (`ReplicaQuota`, `ReplicaQuotaReason`, `reserveReplica`, `replicaCounts`, `quotaFull`, `replicaUsage`), `src/services/replicas.ts` (`REPLICA_QUOTA`, `Drop`, `QUOTA_DROP`, `logReplicaUsage`), `src/index.ts`, `test/replicas.test.ts`, `test/log-hygiene.test.ts`, `backend/API.md`, `backend/README.md`. Baru: `test/replica-usage.test.ts`. Tanpa migrasi.

### Verifikasi

| Perintah | Hasil |
|---|---|
| `pnpm -C backend/api typecheck` | bersih |
| `vitest run test/replica-usage.test.ts test/replicas.test.ts test/log-hygiene.test.ts` (setelah review TS) | 86/86 |
| `supabase db reset && supabase test db` | PASS (tanpa migrasi baru) |
| `vitest run` (suite penuh) | 549 lulus, 1 skip, 1 gagal di luar fase ini (`allowlist.test.ts`, diperbaiki PR #210) |

`bash plan/alief/qa/replica-e2e.sh` (wire lokal) tidak dijalankan: perilaku wire sama dipaku `replicas.test.ts` lewat `POST /scans`.

### Review (berurutan)

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:security-reviewer` | Tidak ada CRITICAL/HIGH. MEDIUM 1: keluarga dihitung ulang dari `family_links`, jadi banyak keluarga palsu 1-Guardian (masing-masing < 10 upload) tetap bisa memakai cadangan. LOW 2: owner yang sudah 50 tetap mengambil `(6, 0)`. LOW 3: komentar "tidak bisa terlampaui" terlalu kuat (pairing tidak mengambil `(6, 0)`). LOW 4: gauge vs kuota bisa beda akar untuk device yang Guardian sekaligus Protected (tidak mungkin: mode tetap, I1) | MEDIUM 1: diterima = kelemahan churn C4/K2 (syarat `mine < 10` sudah tercakup karena `mine ⊆ family`); dibatasi device 50, IP 300, `POST /devices` 10/jam/IP; terlihat lewat `level = reserve` (21c). LOW 2: pre-check tanpa kunci di 22a-2 (K12). LOW 3: komentar diperbaiki (`0dd5813`). LOW 4: tidak berlaku (mode device tidak berubah) |
| `ecc:database-reviewer` | Tidak ada CRITICAL/HIGH; tidak ada deadlock (urutan selalu owner → global; kelas lain beda). MEDIUM: kunci global menyerialkan semua upload baru; kalau `update` tertahan kunci baris, yang lain kena `lock_timeout` 5 s. MEDIUM: rencana query di data besar belum terverifikasi; predikat sudah cocok dengan index parsial, jangan di-hint di kode | MEDIUM 1: `lock_timeout` → `attachReplica` melempar → `replica_dropped reason=error` (perilaku sama dengan sebelum fase 19, scan dan push tidak terpengaruh). MEDIUM 2: dicek di cloud (LANGKAH MANUAL 1, `explain` read-only setelah data 14 hari) |
| `ecc:typescript-reviewer` | Tidak ada CRITICAL/HIGH. MEDIUM 1: jalur `finally` saat `runNotifications` gagal tidak dites. MEDIUM 2: `r?.path !== null` meloloskan baris yang hilang. LOW 3: komentar urutan alasan tanpa `family_bytes`/`global_bytes`. LOW 4: `reserve` di gauge vs `quotaFull` beda ambang byte (gauge tanpa ukuran upload). LOW 5: test gauge gagal bergantung pada `console.log`. LOW 6: angka keras di test | MEDIUM 1: test baru (notifikasi gagal di baris log → gauge tetap tercatat, cron gagal dengan error asli). MEDIUM 2: `rows.every(Boolean)` + `!= null`. LOW 3: komentar diperbaiki. LOW 4: disengaja (gauge melaporkan pemakaian, bukan satu upload; selisih ≤ 300 KB), dicatat di komentar. LOW 5: dibiarkan (pool workers tidak mendukung mock modul ESM). LOW 6: pakai `REPLICA_QUOTA.*` |

### Privasi Apple (SECURITY §3)

- P3/P13: tanpa kolom baru; keluarga dihitung dari `family_links` saat ini, tidak disimpan siapa Guardian sebuah scan setelah putus (K1).
- P6: `replica_dropped` hanya `reason`; `replica_quota_usage` hanya angka agregat (test + `log-hygiene`).
- Tidak ada data baru di DB, R2, atau respons. Halaman privasi tidak berubah (kuota bukan data).

## D-alief-B14 · 1 Nov 2026 · fase 19a · Kuota replica per keluarga + cadangan + gauge

- Keputusan: fase 19 K1 (a) keluarga dari `family_links` saat ini; K2 60 upload + 10 MiB per keluarga per 24 jam, device 50, IP 300, global 3000 + 500 MiB tetap, tanpa batas churn join; K3 (b) 600 upload + 100 MiB terakhir global hanya untuk keluarga < 10 upload; K4 satu statement di bawah `(6, 0)`, urutan owner → keluarga → global → cadangan; K5 event `replica_dropped` (alasan baru `family_quota`, `family_bytes`, `reserve`) + gauge per jam `replica_quota_usage`; K6–K8 tanpa perubahan app/kontrak/atestasi. Sumber: R8 §c (D-alief-C29).
- Biaya penyerang naik ±2,3× (dengan churn) sampai ±4× (fase 19 K2). Batas churn join (`familyJoinGuardian`) masuk TODO kalau gauge fase 21 menunjukkan `global_*`.
- Angka ditinjau ulang setelah 2 minggu data gauge (LANGKAH MANUAL 1 belum: K2 diputuskan dari rekomendasi, bukan dari data cloud).
- Catatan untuk koordinator: entri ini dipindah ke `log/DECISIONS.md` di PR #207.

## LANGKAH MANUAL

- [ ] 1. **(Alief, read-only, kapan saja)** Data nyata untuk meninjau K2 (sebelumnya syarat sebelum K2; sekarang pemeriksaan setelah, karena K2 dari rekomendasi R8): dari `backend/db`, `supabase db query --linked "select count(*), avg(replica_bytes), percentile_cont(0.95) within group (order by replica_bytes) from scans where replica_bytes is not null"` dan query per akar keluarga per hari di `fase-19-replica-quota.md` LANGKAH MANUAL 1 (agregat saja). Catat di sini tanpa id. Kalau p95 upload per keluarga per hari > 30 atau p95 byte > 100 KB: tinjau angka.
- [ ] 2. ~~Jawab K2/K3~~ — dijawab lewat D-alief-C29 (rekomendasi R8).
- [ ] 3. **(Umar merge)** Merge di menit :10–:40, tidak di 18:30–19:30 UTC. Deploy hanya lewat CI.
- [ ] 4. **(Alief)** Uji asap cloud dengan `wrangler tail` terbuka: `SHOO_API=https://shoo-api.afindo-mi01.workers.dev bash plan/alief/qa/replica-e2e.sh --cloud` → replica tersimpan, `POST /scans` tanpa `exceededCpu`; tunggu cron `:05` → satu baris `replica_quota_usage`.
- [ ] 5. Fase 21c memakai `replicaUsage` (sudah dikerjakan stacked, lihat `log/fase-21.md`).

## Catatan handoff

- Fase 21c: `replicaUsage(sql, REPLICA_QUOTA, MAX_REPLICA_BYTES)` (argumen ketiga = ukuran replica maksimal, supaya `level`/`familiesAtCap` mengikuti rumus K5.2 tanpa impor silang repo → service).
- Fase 22a-2 (K12): pre-check kuota sebelum `hit(replicaIp)` memakai `replicaCounts`/`quotaFull` yang sama (tanpa kunci).
- Fase 20b: tidak menyentuh kuota replica.
- K8 (App Attest/DeviceCheck) tetap usulan ke Umar hanya kalau gauge menunjukkan drop `global_*` nyata.
