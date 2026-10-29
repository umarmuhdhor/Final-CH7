# Rencana fase 18 — Page replica (EX-07 backend, DT-04 Detail)

> Ditulis 29 Okt 2026 dari issue #176 (Umar), direvisi setelah verify ronde 6 (PR #178 sudah merge ke `main` 29 Okt 04:05 UTC, a57c531). Urutan: komentar #176 (C26/C27) → 18a `feat/EX-07-replica-backend` dari `origin/main` sekarang (tidak menunggu #177) → merge + deploy CI + uji asap → #175 → 18f `fix/EX-07-app-fixtures` ke branch #177 → #177 → 18b `feat/DT-04-page-replica` → TestFlight (D-alief-C24) → 18c.
> Sumber: `fase-18-page-replica.md` (tabel cek kelayakan K1–K22, peta dampak, **satu-satunya sumber urutan langkah**; nomor di bawah sama), PR #177 (kontrak), kode #178 di `ios/ShooExtension/Resources/`, fase 09/12 + favicon PR-05, SECURITY §3 P1–P13.

## 18a — backend

| # | Langkah | Test dulu |
|---|---|---|
| 1 | `services/replicas.ts` `decodeReplica`: base64 ketat ≤ 400 KB, magic gzip, inflate streaming dengan input 4 KB per `write` + abort di 3 MB, tolak sampah setelah member | `replicas.test.ts` (rusak, bukan gzip, bom ISIZE palsu, bom nol 307 200 byte di-abort per potongan, terpotong, 3 MB + 1) |
| 2 | Migrasi `20261029100000_page_replicas.sql`: `replica_path`, `replica_bytes`, index reuse/kuota + `scans_replica_path`, predikat index retensi diperluas; binding R2 `REPLICAS` + var `REPLICAS_ENABLED` di `wrangler.jsonc` + `env.ts` + `test/env.d.ts`; `services/replicaStore.ts` | pgTAP `security_review.test.sql` (23514 untuk path/bytes), `retention_indexes.test.sql` (predikat + `scans_original_replica` lewat `pg_indexes.indexdef`); vitest R2 lokal miniflare; `typecheck` |
| 3 | `routes/scans.ts` + `app.ts`: `pageReplicaBase64` (tanpa zod max), 512 KB khusus `POST` + path persis `/scans`, urutan push → 201 → replica di `waitUntil` | `scans.test.ts` (`:142-146` jadi 512 KB, `/scans/` + `/scans/:id` tetap 256 KB, 409 600 char / 3 145 728 byte lolos, 409 604 char `too_large`, 409 601 char `invalid`, push tetap terkirim saat replica gagal) |
| 4 | `attachReplica` + `db/repo/scans.ts` `precheckReplica` (reuse + relasi keluarga, sebelum `replicaIp` dan decode) + `reserveReplica` (kill-switch, `replicaIp` 100/24 jam, kunci advisory kelas 6, reuse 24 jam, kuota 50 + global 1000 upload, tombstone), `clearReplicaPath`, `replicaPathForViewer`; `tombstones.ts` `dueTombstones` + `replica_path` | `replicas.test.ts` (kuota, IP, tanpa keluarga, var mati, reuse, paralel), `retention.test.ts` (replica hidup tidak dihapus cron) |
| 5 | Kuota global screenshot **tetap 300**, komentar anggaran `services/scans.ts:13-16` | `scans.test.ts` (kuota lama tetap) |
| 6 | `GET /scans/{id}` `pageReplicaUrl` (link `replica` 1 jam), daftar `null` | ajv kontrak checkout + cek eksplisit string/null; ulang setelah #177 |
| 7 | `routes/replicas.ts` (`Response` mentah, guard magic `1f 8b`, `Content-Disposition: attachment`, tolak `Sec-Fetch-Mode: navigate` / `Sec-Fetch-Dest` selain `empty`, var mati → 404) + `screenshotLinks.ts` kind `replica` + `viewReplica`/`viewReplicaDay`/`viewReplicaAll` (per viewer → global, global habis → 429) | `replicas.test.ts` (header, rate limit: 429 per viewer tidak memakai slot global; `Sec-Fetch-Dest: iframe`/`document` → 404, tanpa `Sec-Fetch-*` → 200) |
| 8 | `deleteDevice` (`DELETE /devices/me` + `POST /devices/me/protected`), retensi (tiga predikat + `union` path), store per path di `removeTombstoned` + `deleteScreenshots` + retensi (`abandonUpload` tetap) | `devices-me.test.ts`, `retention.test.ts`, `security-review.test.ts` (store palsu per store, bagian Supabase ≤ `storageCalls`, batch R2 ≤ 100, kill-switch tidak menghentikan hapus) |
| 9 | IDOR + lintas jenis + kedaluwarsa | `replicas.test.ts` |
| 10 | `privacy.ts` EN/ID (kata-kata K17), `backend/API.md`, `backend/README.md` (runbook kill-switch/takedown), `quota-estimate.sql`, ARCHITECTURE §2/§3/§4, SECURITY P2/P9/P13, R2, R3 | `privacy.test.ts`, `log-hygiene.test.ts` |
| 11 | Benchmark CPU kasus terburuk + bom nol 307 200 byte (fixture dari `ios/ShooExtension/Resources/replica-build.js`); angka penentu dari cloud, > 8 ms atau bom tidak andal → rencana B K2 | angka di log |
| 12 | `qa/replica-e2e.sh` (impor read-only dari `ios/ShooExtension/Resources/`, DOM stand-in; `curl --raw`; `--cloud` untuk uji asap) | jalan hijau |
| 13 | Review security → typescript → database (berurutan), log, PR, merge, LANGKAH MANUAL (CI deploy + uji asap + kabari #176) | — |

## 18f — fixture app (setelah #175 merge, ke branch #177)

| # | Langkah | Test dulu |
|---|---|---|
| 1 | Tunggu #175 + #177 di-update dari `main`; salin 5 fixture kontrak #177 ke `ios/ShooApp/Data/Fixtures/` per byte | — |
| 2 | PR base `feat/EX-07-page-replica-contract` | `FixtureTests.appFixtureMatchesContract` |

## 18b — app

| # | Langkah | Test dulu |
|---|---|---|
| 1 | Tunggu #175, #177, C27 (`ScanResult.pageReplicaUrl` atau DTO `scanDetail(id:)` dengan default, K10) | — |
| 2 | `ReplicaMeta.swift` (JSON ketat, key tak dikenal → rusak, clamp `capturedAt`/`focusY`, `meta.url` host sama) + `ReplicaHTML.swift` (gerbang leksikal, sisip CSP + DNS prefetch off + style) + `ReplicaLoader.swift` (≤ 3 145 728 byte, 429 → `.rateLimited`) + `DetailModel` (replica → screenshot → placeholder, `refreshEvidenceLink()`) | `ReplicaMetaTests` (`$'`), `ReplicaHTMLTests` (satu kasus per tag), `ReplicaLoaderTests`, `DetailModelTests` |
| 3 | `ReplicaView.swift`: `LockedWebView` (menu mati, tidak bisa first responder), JS mati, nonPersistent, rule list ditunggu, context menu `nil`, navigasi dibatalkan, CSS form control mati di layar penuh | — |
| 4 | Uji jaringan + input | `ReplicaViewTests` dengan `NWListener` 127.0.0.1 (nol koneksi, nol navigasi), tanpa keyboard di layar penuh |
| 5 | "Saving a copy…" + ambil ulang 3 s / 15 s (hanya `pageReplicaUrl`), 429, scroll `focusY`, label, "Copied from" (host sama), "Page cut short", privacy cover, aksesibilitas | `DetailModelTests` |
| 6 | `DetailView` + String Catalog EN/ID + Mock replica contoh + baris info onboarding Protected; rename di `DetailScreenshotLinkTests`, `MockRepositoryTests`, `DetailPrivacyTests`, `AccessibilityAuditUITests` | `DetailUITests` |
| 7 | Gerbang UI (Guardian/Protected × EN/ID × SE/XL), UI test live opt-in | screenshot |
| 8 | Review security → swift (berurutan), log, PR | — |
