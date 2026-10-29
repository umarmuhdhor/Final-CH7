# Rencana fase 18 — Page replica (EX-07 backend, DT-04 Detail)

> Ditulis 29 Okt 2026 dari issue #176 (Umar). 18a `feat/EX-07-replica-backend` dari `origin/main`; 18b `feat/DT-04-page-replica` setelah 18a (stacked) dan TODO C27.
> Sumber: `fase-18-page-replica.md` (tabel cek kelayakan K1–K17), PR #177 (kontrak), PR #178 (extension), fase 09/12 + favicon PR-05, SECURITY §3 P1–P13.

## 18a — backend

| # | Langkah | Test dulu |
|---|---|---|
| 1 | `services/replicas.ts` `decodeReplica`: base64 ketat ≤ 400 KB, magic gzip, inflate streaming berhenti di 3 MB, tolak sampah setelah member | `replicas.test.ts` (rusak, bukan gzip, bom ISIZE palsu, terpotong, 3 MB + 1) |
| 2 | Migrasi `20261029100000_page_replicas.sql`: bucket `replicas`, `replica_path`, `replica_bytes`, index reuse/kuota, predikat index retensi diperluas | pgTAP `storage.test.sql`, `grants.test.sql` |
| 3 | `db/repo/scans.ts`: `reserveReplica` (lock per owner, reuse 24 jam, kuota 50 + global 300 upload / 20 MB, tombstone), `clearReplicaPath`, `replicaPathForViewer`, `replica_path` di `selectScans`; `tombstones.ts` `dueTombstones` + `replica_path` | `replicas.test.ts` (kuota, reuse, paralel), `retention.test.ts` (replica hidup tidak dihapus cron) |
| 4 | `services/screenshots.ts`: store per bucket; path dikelompokkan per bucket sebelum batch (`retention.ts:85`, `:161`, `removeTombstoned`) | `retention.test.ts` (store palsu per bucket, batch campur ≤ anggaran) |
| 5 | `routes/scans.ts` + `app.ts`: `pageReplicaBase64`, 512 KB khusus `POST /scans`; `toScanResult(…, pageReplicaUrl)`; kuota global screenshot 60 | `scans.test.ts` (512 KB lolos, 512 KB + 1 → 413, daftar `null`, ajv) |
| 6 | `routes/replicas.ts` (`Response` mentah, guard magic `1f 8b`) + `screenshotLinks.ts` kind `replica` + `viewReplica`/`viewReplicaDay`/`viewReplicaAll` | `replicas.test.ts` (header + byte mentah lewat `app.fetch`, IDOR, lintas jenis, kedaluwarsa, rate limit) |
| 7 | `deleteDevice`, retensi (tiga predikat + `union` path) dengan `replica_path` | `devices-me.test.ts`, `retention.test.ts` (scan hanya-replica di jalur stored-files) |
| 8 | `privacy.ts` EN/ID (salinan seluruh halaman, tanpa isian ketik), `backend/API.md`, `quota-estimate.sql`, ARCHITECTURE §3/§4, SECURITY P2/P9, R2, R3 | `privacy.test.ts`, `log-hygiene.test.ts` |
| 9 | Benchmark CPU kasus terburuk (fixture dari `replica-build.js` PR #178); angka penentu dari cloud, > 8 ms → rencana B K2 | angka di log |
| 10 | `qa/replica-e2e.sh` (lokal, `--cloud` untuk uji asap) | jalan hijau |
| 11 | Review security → typescript → database (berurutan), log, LANGKAH MANUAL, PR | — |

## 18b — app

| # | Langkah | Test dulu |
|---|---|---|
| 1 | `ReplicaMeta.swift`: baca meta `shoo-replica` di 16 KB pertama | `ReplicaMetaTests` |
| 2 | `ReplicaLoader.swift` (pola `URLSessionScreenshotLoader` + `RedirectRefuser`, ≤ 3 MB) | `ReplicaLoaderTests` |
| 3 | `DetailModel`: pilihan bukti replica → screenshot → placeholder, `refreshEvidenceLink()` | `DetailModelTests` |
| 4 | `ReplicaHTML.swift` (sisip CSP + DNS prefetch off + style anti-seleksi setelah doctype) + `ReplicaView.swift`: WKWebView terkunci (JS mati, nonPersistent, rule list ditunggu, context menu `nil`, navigasi dibatalkan, privacy cover), scroll `focusY` (KVO + clamp), label + "Copied from" + "Page cut short" | `ReplicaHTMLTests`; `ReplicaViewTests` dengan `NWListener` 127.0.0.1 (`img`/`link`/`dns-prefetch`/`meta refresh`/form → nol koneksi, nol navigasi) |
| 5 | `DetailView` + String Catalog EN/ID + fixture app `pageReplicaUrl: null` + `MockRepository` | `DetailUITests` |
| 6 | Gerbang UI (Guardian/Protected × EN/ID × SE/XL), UI test live opt-in | screenshot |
| 7 | Review security → swift (berurutan), log, PR | — |
