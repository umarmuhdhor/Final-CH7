# Log fase 22 — CPU Worker (backend)

- **Status:** [r] 22a-0 sebagian (ukuran bundle lokal; S1 profiler, S2, S3, S4 = LANGKAH MANUAL) · [r] 22a-1 PR `fix/BE-worker-cpu`, reviewer @umarmuhdhor, **pending LANGKAH MANUAL 2–5**. 22a-2 di PR terpisah (stacked di 19a, lihat bagian 22a-2). 22a-3, 22b, 22c tidak dikerjakan sesi ini (bukan bagian brief track be; 22a-3 menunggu S3).
- **Model:** Claude Opus 5.5, sesi track be. 1 Nov 2026.
- **Rencana:** `fase-22-performance.md`.
- **Keputusan K:** R8 §c (D-alief-C29): K1 (a), K2 (a), K3 (a), K4 (a), K5 (b) sampai S3 diukur, K6 (a), K11 (c) manual di PR sambil menunggu Umar, K12 (a). K7–K10 milik 22b/22c (app), tidak disentuh. Lihat D-alief-B15.

## 22a-0 — baseline (`origin/main` aa976af)

### Ukuran bundle (lokal, `npx wrangler deploy --dry-run --outdir`, wrangler 4.151.3)

| | `index.js` | gzip -9 `index.js` | Total upload wrangler (termasuk `og-invite.jpg` 229 KB) | zod (sumber di bundle) |
|---|---|---|---|---|
| Sebelum (`main` aa976af) | 1 091 927 B | 200 780 B | 1295,16 KiB / gzip 427,84 KiB | 825 924 B |
| Sesudah O2 + O3 (22a-1) | 267 988 B | 88 842 B | 490,53 KiB / gzip 316,55 KiB | 370 313 B |
| Selisih | −75 % | −56 % | −62 % / −26 % | −55 % |

Paket terbesar sesudah (sumber sebelum minify, `backend/ci/bundle-size.mjs`): zod 370 313, kode app 230 755, postgres 77 717, hono 64 706.

### S1–S4

| Langkah | Status | Alasan |
|---|---|---|
| S1 profil lokal (DevTools Profiler) | **BELUM DIVERIFIKASI** | Butuh DevTools interaktif (`d` di terminal `wrangler dev`) dan `plan/alief/qa/cpu-bench.sh`; sesi ini hanya boleh menulis `backend/**` + `plan/alief/log/**`, jadi skrip bench tidak dibuat. Lihat LANGKAH MANUAL 1. |
| S2 cold vs warm (cloud) | LANGKAH MANUAL 2 | Aksi cloud. |
| S3 porsi postgres.js | Menunggu S1 | Tanpa angka S3, K5 = (b) (rate limit tetap transaksi; 22a-3 tidak dibuat). |
| S4 GraphQL p50/p99 + flamegraph | LANGKAH MANUAL 3–4 | Aksi cloud/dashboard. |

## 22a-1 — `fix/BE-worker-cpu` (dari `origin/main` aa976af)

### Checklist langkah

- [x] 6. Vektor emas link dihitung di luar Worker (HMAC-SHA256 Node, sama dengan implementasi `main`), ditempel ke `test/links-cache.test.ts`. Test vektor emas hijau di kode lama; test spy `importKey` **merah** (50 panggilan, harus 1).
- [x] 7. O1 cache kunci (`services/screenshotLinks.ts`, `Map` per `usage|secret`, ≤ 8 entri, import gagal dibuang) → hijau. O4 `decodeBase64` memakai `Uint8Array.fromBase64` kalau ada (workerd lokal: ada) dengan fallback `atob`; test baru: 12 vektor identik di jalur native dan fallback (fallback dipaksa dengan menyembunyikan `fromBase64`).
- [x] 8. O2 `import * as z from "zod"` di 6 file. Typecheck + suite hijau tanpa mengubah test lama.
- [x] 9. O3 `wrangler.jsonc` `minify: true` + `upload_source_maps: true`. Ukuran sebelum/sesudah di atas. `backend/ci/bundle-size.mjs` (ambang = sesudah + 10 %: 295 000 B raw, 97 500 B gzip; exit 1 kalau lewat).
- [x] 10. Review berurutan (lihat tabel). Profil lokal ulang: BELUM DIVERIFIKASI (sama dengan S1, LANGKAH MANUAL 1).
- [ ] 11–12. LANGKAH MANUAL 2, 4, 5.

### File

Diubah (juga cherry-pick `b9987db` dari #210 supaya CI hijau): `backend/api/src/services/screenshotLinks.ts`, `src/services/images.ts`, `src/http/validate.ts`, `src/routes/{devices,family,scans,verdicts,blocklist}.ts` (import zod), `wrangler.jsonc`, `test/images.test.ts`. Baru: `test/links-cache.test.ts`, `backend/ci/bundle-size.mjs`. File `plan/alief/qa/cpu-bench.sh` **tidak** dibuat (di luar folder sesi).

### Verifikasi

| Perintah | Hasil |
|---|---|
| `pnpm -C backend/api typecheck` | bersih |
| `vitest run test/links-cache.test.ts test/images.test.ts` | 37/37 setelah review (sebelum O1: 1 merah, spy `importKey`) |
| `vitest run` (suite penuh, termasuk cherry-pick #210) | 562 lulus, 1 skip |
| `node backend/ci/bundle-size.mjs` | OK, 267 988 B / gzip 88 842 B |
| `log-hygiene.test.ts` | hijau. Catatan: vitest tidak memakai bundle minify; `errorInfo` hanya membaca `err.name` (properti runtime atau literal), jadi minify tidak mengubahnya; `keepNames` esbuild bawaan wrangler aktif. Bukti di cloud: LANGKAH MANUAL 4 (`wrangler tail`) |

### Review (berurutan)

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:performance-optimizer` | Tidak ada CRITICAL/HIGH. MEDIUM: regex masih memindai 400 KB sebelum `fromBase64`. LOW: `catch` cache bisa menghapus entri baru. LOW: komentar "keep_names" bukan kunci config. Info: cache Promise lintas request aman (CryptoKey bukan objek I/O); `AB==` diterima sama oleh `atob` dan `fromBase64` | MEDIUM: jalur native tanpa regex, diganti cek panjang persis (`len/4×3 − pad`); regex hanya di fallback. LOW: hapus hanya kalau `keys.get(id) === key`. LOW: komentar diperbaiki (`1059851`) |
| `ecc:typescript-reviewer` | Tidak ada CRITICAL/HIGH. MEDIUM: test "records" selalu lulus (kalau workerd kehilangan `fromBase64`, perbandingan native vs fallback diam-diam membandingkan fallback dengan dirinya). MEDIUM: cast ad-hoc ke tipe konstruktor. MEDIUM: whitespace + padding belum dites. LOW: asumsi sinkron di test spy; `npx` bisa mengunduh wrangler; ENOENT samar kalau map hilang | Semua diperbaiki (`09e293b`): `toBe("function")`, `interface Uint8ArrayWithBase64`, vektor `"AA\n="`, `"A A="`, `"AAA "`, komentar asumsi, `pnpm exec wrangler`, pesan jelas kalau `index.js`/map tidak ada |
| `ecc:security-reviewer` | Tidak ada CRITICAL/HIGH. Kontrak base64 ketat tetap (whitespace, `-`/`_`, `=` di tengah, padding hilang semua ditolak). MEDIUM: pastikan test native = fallback mencakup `-`, `_`, `=` di tengah, `====`. LOW: ≤ 8 secret lama di RAM isolate (opsional: kunci cache = hash secret). LOW: source map memuat kode sumber (tanpa secret; grep `src/` bersih). LOW: test `keepNames` | MEDIUM: sudah tercakup + `====` ditambah. LOW secret di RAM: diterima (sama dengan `env`; hash per panggilan menghapus manfaat cache). LOW source map: diterima (privat di akun Cloudflare). LOW `keepNames`: bukti di cloud (LANGKAH MANUAL 4) |

### Privasi Apple (SECURITY §3)

- Tidak ada data baru, log baru, atau kolom baru. Cache kunci HMAC hanya di memori isolate (secret sudah ada di `env`), tidak pernah dilog.
- Link bertanda tangan tetap sama persis (vektor emas), jadi hapus/putus tetap berlaku seketika (cek DB di route tidak berubah).
- Source map diunggah ke Cloudflare (akun yang sama dengan Worker), berisi kode sumber saja, tanpa data pengguna.

## 22a-2 — `fix/EX-07-replica-inflate` (stacked di 19a `feat/EX-07-replica-family-quota`, #211)

### Checklist langkah

- [x] 13a. K4 (a): test batas diperketat dulu (`INFLATE_SLICE` dipaku, bom zero-gzip `consumed` = satu slice) → `INFLATE_SLICE` naik, yield `setTimeout(0)` tetap. **Deviasi:** 8 192, bukan 16 384 (lihat review security). Putaran write + yield untuk replica 300 KB: ±75 → ±38. Test bom ISIZE palsu memakai bom 32 MB (±32 KB gzip, beberapa slice); bom yang muat satu slice gagal di cek trailer (`invalid`), tetap dibuang.
- [x] 13b. K12 (a): test merah dulu (4/4 merah tanpa drop awal: device penuh → `quota`, keluarga → `family_quota`, global → `global_quota`, byte keluarga dari panjang base64 → `family_bytes`; semua tanpa `DecompressionStream` dan tanpa baris `replicas_ip`). Lalu `precheckReplica(sql, scan, bytes, quota)` menghitung kuota di statement yang sama (fragmen `replicaCountsQuery`, juga dipakai `reserveReplica` di bawah `(6, 0)`), `attachReplica` drop dengan alasan yang sama sebelum `hit(replicaIp)`. `estimatedBytes` dari panjang + padding (tanpa regex; 0 untuk bentuk yang pasti ditolak decoder). Reuse tidak pernah diblokir kuota penuh (test).
- [x] 13c. `API.md` aturan replica: kuota penuh dicek sebelum dekompresi dan sebelum slot IP.
- [ ] 14. LANGKAH MANUAL 4 setelah merge (`replica-e2e.sh --cloud --bench`).

**Deviasi lain:** rencana K12 menyebut cek byte "hanya kalau string lolos regex + panjang"; di sini hanya panjang (tanpa pass regex 400 KB, sejalan dengan O4). String dengan panjang benar tapi karakter salah bisa terdrop sebagai `family_bytes` alih-alih `invalid`; keduanya drop, reason hanya di log.

### Verifikasi

| Perintah | Hasil |
|---|---|
| `pnpm -C backend/api typecheck` | bersih |
| `vitest run test/replicas.test.ts` | 84/84 (K12 tanpa drop awal: 4 merah) |
| `vitest run` (suite penuh) | 558 lulus, 1 skip |

### Review (berurutan)

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:security-reviewer` | Tidak ada CRITICAL/HIGH. Rasio deflate maks ±1032:1, multi-member/stored block tidak lebih buruk. MEDIUM: puncak ±17 MB per request dengan slice 16 KB; beberapa bom bersamaan di satu isolate (128 MB) bisa > 100 MB. LOW: hitungan kuota juga jalan untuk reuse/tanpa keluarga. Tidak ada jalur penyalahgunaan pre-check (estimasi hanya untuk upload sendiri), TOCTOU aman (`reserveReplica` tetap penentu), fragmen SQL ter-bind | MEDIUM: slice 8 KB (puncak ±8,5 MB) (`ef8bd23`). LOW: diterima, satu pass index-only lebih murah daripada round trip kedua (komentar) |
| `ecc:typescript-reviewer` | Tidak ada CRITICAL/HIGH. Tipe baris benar (`family` vs `hasFamily`, `"all"` dikutip), spy tidak lulus karena alasan salah (kasus kecil membuktikan spy aktif). MEDIUM: hitungan untuk reuse dibuang. LOW: komentar `row!`; tidak ada test reuse + kuota penuh | MEDIUM/LOW komentar ditambah. Test reuse + kuota penuh ditambah (reuse tetap, tanpa inflate, tanpa drop) |

### Privasi Apple (SECURITY §3)

- Tidak ada data, kolom, atau log baru; `replica_dropped` tetap `reason` saja.

## D-alief-B15 · 1 Nov 2026 · fase 22a · CPU Worker

- Keputusan: K1 (a) target p50 ≤ 10 ms per rute DB, p99 tanpa `exceededCpu`; K2 (a) `import * as z`; K3 (a) minify + source map; K4 (a) inflate penuh lebih murah (slice 16 KB, yield `setTimeout` tetap); K5 (b) sampai S3 diukur; K6 (a) tetap Free, pemicu pindah = `exceededResources` > 0 atau 1102; K11 (c) angka bundle di deskripsi PR sambil menunggu Umar; K12 (a) pre-check kuota sebelum slot IP + inflate. Sumber: R8 §c (D-alief-C29).
- Catatan untuk koordinator: entri ini dipindah ke `log/DECISIONS.md` di PR #207.

## LANGKAH MANUAL

- [~] 1. **(Alief, lokal)** S1 + S3: `supabase start`, `pnpm -C backend/api dev`, `d` → DevTools → Profiler, jalankan `replica-e2e.sh --bench` + `cpu-bench.sh` (dibuat di PR plan, bukan sesi ini), di `main` lalu di cabang 22a-1. Catat 10 fungsi teratas per rute + porsi `postgres` di `POST /devices` di sini. Kalau porsi postgres ≥ 20 %: buka 22a-3 (K5 a).
  - **8 Nov 2026:** profiler lokal (DevTools) belum dijalankan. Pengganti untuk keputusan K5: flamegraph produksi di butir 3 menunjukkan konstruksi klien postgres (`createSql`) 21 % dari profil, juga di rute tanpa DB → di atas ambang 20 % → **22a-3 dibuka** (klien postgres dibuat malas, hanya saat rute butuh DB).
- [~] 2. **(Alief, cloud)** S2 sebelum dan sesudah deploy 22a-1: diam ≥ 10 menit, `npx wrangler tail shoo-api --format json` + 10× `curl -s https://shoo-api.afindo-mi01.workers.dev/healthz`. Salin hanya `cpuTime`, `wallTime`, `outcome`.
  - **Sesudah 22a-1, 7 Nov 2026, 17:12 UTC:** 10× `/healthz` → semua 200, `ok`. cpuTime (ms): 1, 10, 1, 6, 5, 1, 6, 6, 12, 1 (median 5,5, maks 12). wallTime (ms): 2, 11, 1, 7, 5, 1, 6, 7, 12, 2. Syarat diam ≥ 10 menit tidak dicek. **Sebelum** tidak bisa diukur lagi: 22a-1 (#212) sudah ter-deploy sejak 1 Nov 07:47 UTC.
- [x] 3. **(Alief, dashboard)** Flamegraph CPU produksi 10 s (Workers & Pages → `shoo-api` → Observability → Flamegraph) sebelum dan sesudah 22a-1. Setelah 22a-1 nama fungsi harus terbaca (source map).
  - **Sesudah 22a-1, 8 Nov 2026 ±07:45 UTC** (Observability → Flamegraph, CPU 10 s, traffic `/privacy` + `/support`): nama fungsi terbaca dengan path sumber (`src/db/client.ts:9`, `src/routes/privacy.ts:192`, `hono/dist/compose.js:24`) → source map jalan. **Sebelum** tidak bisa diukur lagi (22a-1 sudah ter-deploy).
  - Isi profil (33 sampel): GC 54,5 %, `dispatch` hono 36,4 %, di dalamnya **`createSql` 21,2 %** (`Postgres` + `parseOptions` + `Subscribe`), padahal `/privacy` dan `/support` tidak memakai DB. Render halaman sendiri 3 %.
- [x] 4. **(Alief, cloud)** GraphQL `workersInvocationsAdaptive` 24 jam sebelum dan sesudah deploy: `cpuTimeP50`, `cpuTimeP99`, status. Plus `SHOO_API=https://shoo-api.afindo-mi01.workers.dev bash plan/alief/qa/replica-e2e.sh --cloud --bench` dengan `wrangler tail` terbuka → tanpa 1102/`exceededCpu`.
  - **7 Nov 2026, 17:13 UTC**, GraphQL `workersInvocationsAdaptive`, `shoo-api`, per status (ms):

    | Jendela (UTC) | status | request | error | cpu p50 | cpu p99 |
    |---|---|---|---|---|---|
    | Sebelum 22a-1: 31 Okt 07:47 → 1 Nov 07:47 | success | 267 | 0 | 7,68 | 62,73 |
    | Sesudah 22a-1: 1 Nov 07:48 → 2 Nov 07:48 | success | 1 236 | 0 | 5,90 | 41,90 |
    | Sesudah 22a-1 | clientDisconnected | 3 | 0 | 3,91 | 5,14 |
    | 24 jam terakhir: 6 Nov 17:00 → 7 Nov 17:00 | success | 148 | 0 | 12,89 | 52,02 |
    | 24 jam terakhir | clientDisconnected | 271 | 0 | 6,30 | 18,91 |

  - 22a-1: p50 −23 %, p99 −33 %. Tidak ada status `exceededCpu`/`exceededResources` di jendela mana pun. p50 24 jam terakhir 12,89 ms > target K1 10 ms, tapi angka ini gabungan semua rute dengan volume kecil (148), bukan per rute DB.
  - **`--bench`, 8 Nov 2026 07:38 UTC** (`replica-e2e.sh --cloud --bench`, tail terbuka): worst case (409 600 karakter, 3 145 728 byte inflate) → `POST /scans` 201 dalam 959 ms, cpu 80 ms; bom gzip nol → 201, cpu 90 ms, replica ditolak (`replica_dropped` `too_large`), tanpa `exceededCpu`/1102. Semua rute lain 1–64 ms cpu.
  - **Temuan (bug, belum diperbaiki):** `GET pageReplicaUrl` worst case → **404**, padahal link sudah muncul 379 ms setelah 201. Sebab: `attachReplica` (`services/replicas.ts`) mengisi `replica_path` lewat `reserveReplica` **sebelum** `store.put` ke R2 selesai, jadi selama upload Guardian sudah dapat link ke objek yang belum ada. Replica kecil (sampel) tidak kena karena upload-nya cepat. Perbaikan diusulkan di PR terpisah (link hanya dikirim setelah upload selesai).
  - `replica-input.mjs worst` sesekali gagal ("no worst-case replica found", pencarian ukuran acak); ulangi sekali cukup.
- [ ] 5. **(Umar)** K11 gerbang ukuran bundle di CI: ditanyakan di PR 22a-1 (`## Questions for Umar`), bukan issue (D-alief-C29). Merge di menit :10–:40, deploy lewat CI.

## Catatan handoff

- `bundle-size.mjs` belum dipanggil CI (`.github/` milik Umar, K11). Sampai dijawab: angka ditulis di deskripsi PR backend.
- 22a-2 (`fix/EX-07-replica-inflate`) stacked di 19a (#211): `INFLATE_SLICE` 16 384 + pre-check kuota K12.
