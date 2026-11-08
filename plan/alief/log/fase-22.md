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

- [ ] 1. **(Alief, lokal)** S1 + S3: `supabase start`, `pnpm -C backend/api dev`, `d` → DevTools → Profiler, jalankan `replica-e2e.sh --bench` + `cpu-bench.sh` (dibuat di PR plan, bukan sesi ini), di `main` lalu di cabang 22a-1. Catat 10 fungsi teratas per rute + porsi `postgres` di `POST /devices` di sini. Kalau porsi postgres ≥ 20 %: buka 22a-3 (K5 a).
- [~] 2. **(Alief, cloud)** S2 sebelum dan sesudah deploy 22a-1: diam ≥ 10 menit, `npx wrangler tail shoo-api --format json` + 10× `curl -s https://shoo-api.afindo-mi01.workers.dev/healthz`. Salin hanya `cpuTime`, `wallTime`, `outcome`.
  - **Sesudah 22a-1, 7 Nov 2026, 17:12 UTC:** 10× `/healthz` → semua 200, `ok`. cpuTime (ms): 1, 10, 1, 6, 5, 1, 6, 6, 12, 1 (median 5,5, maks 12). wallTime (ms): 2, 11, 1, 7, 5, 1, 6, 7, 12, 2. Syarat diam ≥ 10 menit tidak dicek. **Sebelum** tidak bisa diukur lagi: 22a-1 (#212) sudah ter-deploy sejak 1 Nov 07:47 UTC.
- [ ] 3. **(Alief, dashboard)** Flamegraph CPU produksi 10 s (Workers & Pages → `shoo-api` → Observability → Flamegraph) sebelum dan sesudah 22a-1. Setelah 22a-1 nama fungsi harus terbaca (source map).
- [~] 4. **(Alief, cloud)** GraphQL `workersInvocationsAdaptive` 24 jam sebelum dan sesudah deploy: `cpuTimeP50`, `cpuTimeP99`, status. Plus `SHOO_API=https://shoo-api.afindo-mi01.workers.dev bash plan/alief/qa/replica-e2e.sh --cloud --bench` dengan `wrangler tail` terbuka → tanpa 1102/`exceededCpu`.
  - **7 Nov 2026, 17:13 UTC**, GraphQL `workersInvocationsAdaptive`, `shoo-api`, per status (ms):

    | Jendela (UTC) | status | request | error | cpu p50 | cpu p99 |
    |---|---|---|---|---|---|
    | Sebelum 22a-1: 31 Okt 07:47 → 1 Nov 07:47 | success | 267 | 0 | 7,68 | 62,73 |
    | Sesudah 22a-1: 1 Nov 07:48 → 2 Nov 07:48 | success | 1 236 | 0 | 5,90 | 41,90 |
    | Sesudah 22a-1 | clientDisconnected | 3 | 0 | 3,91 | 5,14 |
    | 24 jam terakhir: 6 Nov 17:00 → 7 Nov 17:00 | success | 148 | 0 | 12,89 | 52,02 |
    | 24 jam terakhir | clientDisconnected | 271 | 0 | 6,30 | 18,91 |

  - 22a-1: p50 −23 %, p99 −33 %. Tidak ada status `exceededCpu`/`exceededResources` di jendela mana pun. p50 24 jam terakhir 12,89 ms > target K1 10 ms, tapi angka ini gabungan semua rute dengan volume kecil (148), bukan per rute DB.
  - **Belum:** `replica-e2e.sh --cloud --bench` (fase 19 butir 4 jalan tanpa `--bench`).
- [ ] 5. **(Umar)** K11 gerbang ukuran bundle di CI: ditanyakan di PR 22a-1 (`## Questions for Umar`), bukan issue (D-alief-C29). Merge di menit :10–:40, deploy lewat CI.

## Catatan handoff

- `bundle-size.mjs` belum dipanggil CI (`.github/` milik Umar, K11). Sampai dijawab: angka ditulis di deskripsi PR backend.
- 22a-2 (`fix/EX-07-replica-inflate`) stacked di 19a (#211): `INFLATE_SLICE` 16 384 + pre-check kuota K12.

## Fix — replica link after upload (8 Nov 2026)

- **Bug:** di cloud (`replica-e2e.sh --cloud --bench`, replica terbesar 409 600 karakter base64 → 307 KB gzip) `GET /scans/{id}` sudah memberi `pageReplicaUrl` 379 ms setelah 201, tapi `GET /replicas/{id}` lewat link itu 404.
- **Sebab:** `attachReplica` memanggil `reserveReplica`, yang menulis `scans.replica_path` (+ `replica_bytes`, tombstone) lalu commit; `store.put` ke R2 baru jalan sesudahnya. Di sela commit dan selesainya put, link dibuat dari `replica_path` (`toScanResult` → `replicaUrl`) dan `replicaPathForViewer` → `store.get` → kosong → 404. Reuse 24 jam (`recentReplicaQuery`) juga bisa memberi scan lain path yang masih diunggah.
- **Perbaikan:** kolom baru `scans.replica_ready_at timestamptz` (migrasi `20261108100000_replica_ready.sql`, check `replica_ready_at is null or replica_path is not null`, backfill `now()` untuk baris yang sudah punya path). `markReplicaReady` mengisinya setelah put berhasil (`where id = … and replica_path = …`; 0 baris = scan dihapus/path dibersihkan → `abandonUpload`, menggantikan `scanExists`). Baris reuse langsung ready (sumbernya pasti ready). `selectScans` (link Detail), `replicaPathForViewer` dan `recentReplicaQuery` mensyaratkan ready. `clearReplicaPath` ikut mengosongkan ready. Kuota (`replica_bytes`, lock (6, 0)), retensi, tombstone dan `DELETE /devices/me` tetap membaca `replica_path`, jadi unggahan yang sedang jalan tetap dihitung dan tetap terhapus seketika (P13). Kontrak tidak berubah: `pageReplicaUrl` memang boleh `null` ("saving a copy").
- **File:** `backend/db/supabase/migrations/20261108100000_replica_ready.sql`, `backend/api/src/db/repo/scans.ts`, `backend/api/src/services/replicas.ts`, `backend/api/test/replicas.test.ts`, `backend/api/test/log-hygiene.test.ts`, `backend/db/supabase/tests/security_review.test.sql`, `backend/API.md`.
- **Tes:** 3 tes baru di `replicas.test.ts` ("replica link only after the upload"; put ditahan dengan spy `R2ReplicaStore.prototype.put`). Merah di kode lama: 2 gagal (`pageReplicaUrl` berisi link saat put tertunda; `reserveReplica` mengembalikan `{ reuse }` untuk path yang belum terunggah), 1 lulus (put gagal → tanpa path/link/objek). Hijau: `replicas.test.ts` 88/88; suite penuh tanpa `.dev.vars`: 40 file, 689 lulus, 1 skip; `typecheck` bersih. pgTAP `security_review` +4 assert, lulus (`supabase test db` lokal: file admin_* gagal karena data DB lokal bersama dari sesi lain, bukan karena migrasi ini; tidak di-reset).
- **Cek ulang cloud:** setelah deploy (migrasi lewat CI), jalankan `SHOO_API=https://shoo-api.afindo-mi01.workers.dev bash plan/alief/qa/replica-e2e.sh --cloud --bench`: link harus muncul hanya setelah objek ada, dan link pertama yang muncul harus 200.
- **Tindak lanjut review (8 Nov 2026):** `attachReplica` kini memakai satu helper `dropUpload` untuk put gagal dan mark ready gagal (log `{"event":"replica_dropped","reason":"ready_failed","error":…}`, bentuk sama dengan `upload_failed`, hanya `errorInfo`, tanpa id; event lama `replica_ready_failed` dihapus, tidak ada tes/log-hygiene yang merujuknya). Tes baru "a failed ready mark (after the put)…": trigger sementara (role postgres) `before update of replica_ready_at` yang raise hanya untuk owner tes, di-drop di `finally`; cek log drop, `replica_path` + `replica_ready_at` null, tidak ada objek R2, tombstone ada, `pageReplicaUrl` null, baris log tanpa id. Merah dulu (catch dikembalikan ke `return` sementara, tidak di-commit): gagal di `droppedFor("ready_failed")` (timeout); hijau setelah dikembalikan. `holdPuts` kini selalu dilepas di `afterEach`, jadi put yang ditahan tidak menggantung ke tes berikutnya walau assert gagal. Migrasi: komentar bahwa fungsi/view `admin.*` milik lead (mis. `admin.replica_for`, `has_replica`) masih membaca `replica_path` saja dan sengaja tidak diubah di sini (pertanyaan ke lead di PR).
- **Hasil:** `typecheck` bersih; `replicas.test.ts` + `log-hygiene.test.ts` 92/92; suite penuh tanpa `.dev.vars`: 40 file, 690 lulus, 1 skip.

### Review

| Reviewer | Temuan | Tindakan |
|---|---|---|
| security | tidak ada di atas LOW; LOW: mark ready gagal meninggalkan path + objek | diperbaiki di `4e88168` (mark gagal → `clearReplicaPath` + `abandonUpload`) |
| typescript | Tidak ada CRITICAL/HIGH. MEDIUM: (1) cabang mark gagal tanpa test; (2) `holdPuts` bisa menggantung kalau assertion gagal sebelum `release`; (3) fungsi/view `admin.*` (`admin.replica_for`, `has_replica`, review L5) masih membaca `replica_path` saja. LOW: cleanup ganda; event log mark gagal beda dari `replica_dropped`; backfill migrasi tanpa batch | (1) test trigger, merah → hijau; (2) `afterEach` selalu melepas; (3) milik lead: komentar di migrasi + pertanyaan di PR. LOW: `dropUpload` + `reason: "ready_failed"`; backfill dibiarkan (tabel kecil, retensi 14 hari) |
