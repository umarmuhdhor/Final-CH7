# Log fase 18 — Page replica: EX-07 backend, DT-04 Detail

- **Status:** [r] 18a — PR branch `feat/EX-07-replica-backend`, reviewer @umarmuhdhor (belum merge, belum deploy). 18f/18b belum mulai (menunggu #175, #177, TODO C27).
- **Model:** Claude Opus 5.5. 29 Okt 2026.
- **Rencana:** `log/fase-18-plan.md`, `fase-18-page-replica.md`.

## LANGKAH MANUAL 1 — infra R2 (sebelum merge 18a)

29 Okt 2026, Wrangler 4.151.3, akun Cloudflare Worker yang sama (login OAuth Alief).

| Langkah | Hasil |
|---|---|
| R2 subscription | Aktif, diklik Alief sendiri di dashboard ($0,00, kartu terdaftar) |
| `wrangler r2 bucket create shoo-replicas --location apac` | Dibuat 2026-10-29T04:09:24Z, storage class Standard. Tawaran Wrangler menambah binding ke `wrangler.jsonc` ditolak (binding `REPLICAS` masuk di 18a langkah 2) |
| `wrangler r2 bucket lifecycle add shoo-replicas expire-17d --expire-days 17` | Aktif: `expire-17d`, semua prefix, hapus objek setelah 17 hari. Rule bawaan "Default Multipart Abort Rule" (7 hari) tetap ada |
| `wrangler r2 bucket dev-url get` | "Public access via the r2.dev URL is disabled." |
| `wrangler r2 bucket domain list` | Tidak ada custom domain |
| `wrangler r2 bucket cors list` | Tidak ada konfigurasi CORS (API code 10059) |
| `wrangler r2 bucket info shoo-replicas` | location **APAC**, 0 objek, 0 B |

Belum: notifikasi billing/usage R2, cek izin token CI `CLOUDFLARE_API_TOKEN` untuk binding R2, ukur `storage.objects` Supabase (TODO D10).

## 18a — backend (29 Okt 2026)

Branch `feat/EX-07-replica-backend` dari `origin/main`, tanpa menunggu #177. Berisi juga plan PR #179 (merge `cc04daa`) dan cherry-pick #181 (`f92d8bf`, `screenshotBase64` + `/screenshots` deprecated). Subagent satu per satu.

### Checklist langkah (`fase-18-page-replica.md` 18a)

- [x] 1. `decodeReplica`: base64 ketat ≤ 409 600 char, magic `1f 8b 08`, inflate per 4 KB + `setTimeout(0)`, abort setelah potongan yang lewat 3 145 728 byte, tolak terpotong/sampah/ISIZE palsu.
- [x] 2. Migrasi `20261029100000_page_replicas.sql`, binding `REPLICAS` + `REPLICAS_ENABLED`, `R2ReplicaStore`.
- [x] 3. `pageReplicaBase64` tanpa zod max; 512 KB hanya `POST /scans` (`http/bodyLimit.ts`); push → 201 → replica di `waitUntil` setelah `Promise.allSettled(deliveries)`.
- [x] 4. `attachReplica`, `precheckReplica`, `reserveReplica` (kunci owner `(6, hashtext)` + kunci global `(6, 0)` di sekitar hitungan), `clearReplicaPath`, `replicaPathForViewer`, `dueTombstones` + `replica_path`.
- [x] 5. Kuota global screenshot tetap 300, komentar anggaran.
- [x] 6. `pageReplicaUrl` di `GET /scans/{id}`, `null` di daftar.
- [x] 7. `GET /replicas/:id` (`encodeBody: "manual"`, Sec-Fetch, 10/menit + 500/hari per viewer), link kind `replica`.
- [x] 8. Hapus per store: `deleteDevice`, retensi (anggaran R2 40 batch terpisah), `deleteScreenshots`.
- [x] 9. Favicon baru ke R2 `-icon.<ext>`, `fetchFaviconAll` 1000.
- [x] 10. IDOR, lintas jenis link, kedaluwarsa.
- [x] 11. Privasi EN/ID, `backend/API.md`, `backend/README.md` (runbook kill-switch + takedown), `quota-estimate.sql`, ARCHITECTURE, SECURITY, `ref/R2`, `ref/R3`.
- [x] 12. Benchmark lokal (indikasi, lihat bawah). Angka penentu: LANGKAH MANUAL 3.
- [x] 13. `qa/replica-e2e.sh` + `qa/replica-input.mjs` lulus terhadap `wrangler dev`.
- [x] 14. Review security → typescript → database (berurutan), temuan diperbaiki, PR dibuka. Merge + LANGKAH MANUAL 1 (sisa) – 4: Alief.

### File

- Baru: `backend/api/src/{services/replicas.ts, services/replicaStore.ts, routes/replicas.ts, http/bodyLimit.ts}`, `backend/api/test/{replicas.test.ts, helpers/replica.ts}`, `backend/db/supabase/migrations/20261029100000_page_replicas.sql`, `plan/alief/qa/{replica-e2e.sh, replica-input.mjs}`.
- Diubah: `backend/api/src/{app.ts, env.ts, cron/retention.ts, db/repo/{scans,tombstones,devices}.ts, http/rateLimit.ts, routes/{scans,favicons,privacy}.ts, services/{scans,screenshots,screenshotLinks,favicons}.ts}`, `backend/api/wrangler.jsonc`, `backend/api/test/{env.d.ts, scans,favicons,log-hygiene,privacy}.test.ts`, pgTAP `retention_indexes` + `security_review`, `backend/{API.md, README.md, CLAUDE.md, ci/README.md}`, `backend/db/scripts/quota-estimate.sql`; plan `ARCHITECTURE.md`, `SECURITY.md`, `ref/R2-skema-db.md`, `ref/R3-catatan-api.md`, `TODO.md` (E8), `log/DECISIONS.md` (C28).
- Tidak disentuh: `contracts/`, `ios/` (replica.js/replica-build.js hanya diimpor read-only), `ios/project.yml`, `.github/`.

### Hasil verifikasi (29 Okt 2026, lokal)

| Uji | Hasil |
|---|---|
| `supabase test db` | 158/158 lulus (12 file) |
| `vitest run` penuh | 534 lulus, 1 dilewati (29 file, 37 s). `replicas.test.ts` 68 test |
| `pnpm -C backend/api run typecheck` | bersih |
| `qa/replica-e2e.sh --bench` terhadap `wrangler dev` + Supabase lokal | **ALL PASS**, 31 cek (dijalankan ulang setelah tiap perbaikan review) |

Catatan: `.dev.vars` lokal (dibuat untuk `wrangler dev`) ikut terbaca vitest dan membuat `app-site-association.test.ts` gagal (`APPLINKS_APP_IDS` kosong); file itu dipindah keluar saat vitest jalan. `vitest run` dengan reporter default lewat pipe kadang tidak selesai; `--reporter=verbose` ke file selesai normal.

### Benchmark (langkah 12, indikasi lokal)

Input dibuat dengan `gzipBase64` dari `ios/ShooExtension/Resources/replica-build.js` (`qa/replica-input.mjs`): terburuk = 409 600 char base64 yang meng-inflate tepat 3 145 728 byte; bom = gzip nol 303 733 byte (±298 MB nol).

| Ukuran | Hasil |
|---|---|
| `wrangler dev`, span root `POST /scans` (wall, termasuk `waitUntil` + DB + R2 lokal) | sampel 20 ms, terburuk 131 ms, bom 29 ms. `cpu_time_ms` di workerd lokal selalu 0 (tidak diukur) |
| `POST /scans` sampai 201 (curl) | terburuk 42–52 ms, bom 39–41 ms; replica terburuk terlihat ±340 ms setelah 201 |
| Bom di `wrangler dev` | 201, replica dibuang `too_large`, `replica_path` null, tanpa error CPU/memori di log |
| CPU loop inflate yang sama di Node 24 (`process.cpuUsage`, termasuk decode base64) | terburuk **9–15 ms**, bom 3–7 ms (abort setelah 12–20 KB input di Node; di workerd test 4096 byte) |

**Risiko:** angka Node untuk inflate saja sudah di atas batas 8 ms rencana A (K2). Node bukan workerd, jadi ini hanya indikasi; angka penentu dari cloud (LANGKAH MANUAL 3, CPU dari dashboard / `wrangler tail`). Kalau di cloud > 8 ms atau ada 1102: rencana B K2 (backend hanya cek magic + ukuran + inflate 64 KB pertama, batas 3 MB di `ReplicaLoader` app), usulan ke Umar di #176, catat di DECISIONS. Push tetap aman: replica jalan setelah push terkirim.

### DoD 18a + bukti

- [x] Replica sah → 201 + `pageReplicaUrl`; `GET /scans` key `pageReplicaUrl` = `null` (cek eksplisit, juga di e2e); rusak / bom / terlalu besar → dibuang, scan 201 — `replicas.test.ts` "POST /scans stores…", e2e.
- [x] Batas 409 600 / 3 145 728 lolos; 409 604 `too_large`, 409 601 `invalid`, 3 145 729 dibuang, semua 201; body > 524 288 → 413; `/scans/`, `/scans/:id` 256 KB — `replicas.test.ts`, `scans.test.ts`.
- [~] Bom 307 200 byte di-abort setelah potongan 4 KB (test, `consumed === 4096`); cloud tanpa 1102/OOM → LANGKAH MANUAL 3.
- [x] Push + favicon tetap jalan walau replica gagal/lambat — test urutan (`DecompressionStream` dipanggil setelah push), replica melempar → push tetap.
- [~] `GET /replicas/:id` header persis + `Content-Disposition`, byte gzip apa adanya (e2e `curl` tanpa `--compressed`: magic `1f8b`, byte = input), navigasi browser 404, 404 setelah `DELETE /devices/me`, `POST /devices/me/protected`, retensi, disconnect, link kedaluwarsa, link jenis lain (test + e2e). Uji asap cloud → LANGKAH MANUAL 3.
- [x] Replica scan hidup tidak dihapus cron tombstone; scan yang hanya punya replica dihapus pada hari 14 bersama objeknya (test retensi).
- [~] Kuota 50/24 jam, reuse 24 jam, global 3000 + 500 MB (juga paralel lintas owner), `replicaIp` 300, tanpa keluarga → tidak disimpan, tampilan 10/menit + 500/hari → 429 (test); retensi > 1000 objek R2 per run (4000 R2 + 1000 Supabase, test); kuota screenshot 300 tetap; objek > 307 200 byte atau bukan gzip tidak sampai R2 (test); anggaran di ARCHITECTURE §3. CPU cron 40 batch R2 dari cloud → LANGKAH MANUAL 3.
- [x] Bucket R2 privat + lifecycle 17 hari (LANGKAH MANUAL 1 di atas).
- [ ] CPU `POST /scans` terburuk ≤ 8 ms di cloud → LANGKAH MANUAL 3 (indikasi lokal di atas: berisiko).
- [x] Wire lokal `qa/replica-e2e.sh` lulus: HTML yang dibaca app = HTML yang dikirim extension (byte gzip identik).
- [x] Favicon baru di R2 (`-icon.`), favicon lama `-favicon.` tetap tampil dan terhapus dari Supabase; `fetchFaviconAll` 1000 — `favicons.test.ts`.
- [x] Kill-switch mati → tanpa `put`, `/replicas` 404, `pageReplicaUrl` null, hapus tetap jalan (test); runbook takedown di `backend/README.md`.
- [x] DB: `scans_original_replica` dipakai kuota, `replica_bytes` hanya di baris asli, predikat retensi utuh lewat `pg_indexes.indexdef`, index valid, 23514 untuk bytes tanpa path (pgTAP); migrasi `set local` timeout, index baru sebelum drop.
- [x] Halaman privasi EN/ID dengan kata-kata K17 + Cloudflare R2; review security tanpa HIGH terbuka. (Baris onboarding: 18b. `docs/README.md:7` + PRD §10: Umar, C26.)
- [x] Regresi backend: pgTAP penuh, `vitest run` penuh (termasuk `favicons`, `push-*`, `family`, `verdicts`, `profile`, `settings`). Regresi iOS (`xcodebuild`, `push-e2e.sh`): tidak relevan untuk 18a (tanpa perubahan `ios/`), dijalankan di 18b.
- Butir DoD 18f/18b (#175/#177, gerbang TestFlight #176, Detail, `ReplicaViewTests`, ambil ulang) belum, di luar 18a.

### Review (berurutan)

| Review | CRITICAL/HIGH | Diperbaiki | Dicatat, tidak diubah |
|---|---|---|---|
| `ecc:security-reviewer` | 0 | M2: teks privasi menjanjikan salinan dihapus saat disconnect → teks jujur (akses hilang seketika, objek ikut scan; D-alief-C28). L4: test memaku aturan akhiran path SQL = `storeKind` | M1: penyerang dengan beberapa device + Guardian sendiri bisa menghabiskan kuota global → TODO E8 (kuota per keluarga + notifikasi). L1 Safari < 16.4 tanpa `Sec-Fetch-*` (lapisan lain tetap: attachment, CSP sandbox, nosniff). L2 CPU `waitUntil` (lihat benchmark). L3 IP `unknown` di luar Cloudflare |
| `ecc:typescript-reviewer` | 0 | M1: gagal `clearReplicaPath` kini di-log `replica_clear_failed`. M2: `GET /replicas` membaca objek utuh (≤ 300 KB) sebelum cek magic. L7: `replica_dropped` satu level (`console.error`) | M3 `encodeBody` dibuktikan e2e (`curl` dapat gzip mentah). L1/L2 waktu test, L3/L4 bentuk union, L5 nilai falsy yang dilempar, L6 `yieldToReader` (dipertahankan: test `consumed === 4096` bergantung padanya) |
| `ecc:database-reviewer` | 0 | M2: kunci global `(6, 0)` di sekitar hitungan kuota (test paralel lintas owner gagal 3/3 tanpa kunci). L4: `clearReplicaPath` di bawah kunci owner. M1/L1: komentar migrasi (satu ACCESS EXCLUSIVE, wajib satu transaksi). pgTAP: predikat utuh, `indisvalid`, batas bawah path | L2 check constraint scan penuh (tabel kecil), L3 rollback = forward fix, L5 visibility map (dibatasi kuota). Celah: hapus device membebaskan kuota sebelum cron menghapus objek (dibatasi POST /devices 10/jam/IP, `replicaIp`, lifecycle 17 hari; dicatat di komentar) |

## LANGKAH MANUAL tersisa (Alief, setelah review Umar; deploy hanya lewat CI)

- [ ] 1 (sisa). Cek token CI `CLOUDFLARE_API_TOKEN` boleh deploy Worker dengan binding R2; ukur `storage.objects` Supabase per bucket + jumlah baris `scans` (`supabase db query --linked`), catat di sini + ARCHITECTURE §3; notifikasi billing/usage R2.
- [ ] 2. Merge PR 18a di menit :10–:40, tidak di 18:30–19:30 UTC; tunggu CI `backend.yml` (`supabase db push` + `wrangler deploy`) hijau; catat jam deploy.
- [ ] 3. `SHOO_API=https://shoo-api.afindo-mi01.workers.dev bash plan/alief/qa/replica-e2e.sh --cloud --bench` dengan `wrangler tail` terbuka: header + byte, Sec-Fetch 404, CPU `POST /scans` terburuk + bom (tanpa 1102/OOM), `wrangler r2 object get … --remote` ada sebelum dan hilang setelah `DELETE /devices/me` (skrip berhenti dan menampilkan perintahnya).
- [ ] 4. Kabari Umar di #176: backend hidup sejak jam deploy; gerbang TestFlight tetap sampai 18b merge.

