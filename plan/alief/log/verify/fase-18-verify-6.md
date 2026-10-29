# Fase 18 — verify ronde 6 (29 Okt 2026), BELUM DIPERBAIKI di rencana

Konteks baru: PR #178 (extension) **sudah merge ke `main`** 29 Okt 04:05 UTC (a57c531), sebelum 18a. #177 belum merge. Backend `main` membuang `pageReplicaBase64` (`z.object` strip, `routes/scans.ts:46`) atau 413 > 256 KB lalu extension kirim ulang tanpa replica (`background.js:153`). Scan baru tanpa bukti; `DetailView.swift:70` menyembunyikan bukti saat `screenshotUrl` nil.

Review berurutan: security (ecc:security-reviewer) → wiring (general-purpose). Review database belum jalan.

## Security

1. **TINGGI** Replica menyalin seluruh teks halaman skor 30–79 (bisa false positive di webmail/bank). `docs/README.md:7` "page content never stored", `privacy.ts:28`, SECURITY P2 belum mencakup. Fix: K17 + Output ubah README §10 + privacy ("isian yang diketik dihapus; teks yang tampil disalin"); TODO tanya Umar di #176 batasi replica ke `blocked` atau `warning` dengan `focus != null`; baris persetujuan di onboarding Protected.
2. **SEDANG** Kuota global (1000 upload, 20 000 view) habis murah: 10 device/jam/IP (`rateLimit.ts:12-15`). Fix: limit per IP ~100/24 jam (`limits.replicaIp`), simpan replica hanya kalau owner punya relasi keluarga; ganti "risiko diterima" K5.
3. **SEDANG** Guard gzip bomb (belum terverifikasi): satu `write` besar ke `DecompressionStream` bisa meng-inflate penuh sebelum counter. Fix: input dipotong 4 KB per `write` (await), cek output tiap potong; bom 307 200 byte nol di benchmark langkah 10 + LANGKAH MANUAL 3 (kriteria: tanpa 1102/OOM).
4. **SEDANG (terverifikasi)** Bug `replica.js:279` `html.replace(metaToken, escapeAttr(meta))`: `$'`/`$&` di path URL (tidak di-escape `escapeAttr:56`, tidak di-percent-encode) merusak meta. Fix: minta Umar `() => escapeAttr(meta)` (C26); 18b `ReplicaMeta` meta tidak valid → mulai dari atas; test `$'`.
5. **SEDANG** `<link rel=preconnect>` lolos CSP. Fix: gerbang leksikal fail-closed di `ReplicaHTML` (`<link`, `<base`, `<script`, `<iframe`, `<frame`, `<object`, `<embed`, `<noscript`, `<meta http-equiv` > 1 → placeholder) + test per kasus.
6. **SEDANG** Rencana usang setelah #178 merge (K16, K18, LANGKAH MANUAL 4, Bacaan wajib, langkah 11, C26). Fix: tulis ulang "#178 sudah merge; jendela tanpa bukti"; gerbang = tidak ada TestFlight dari `main` sampai 18a deploy + 18b merge; langkah 11 dari `main`.
7. **RENDAH-SEDANG** `replica.js` menyimpan atribut lain di form control (`data-*`, `aria-*`, `title`, `placeholder`); `searchbox`/`combobox`/`designMode` tidak dianggap editable. Fix: minta Umar allow-list atribut + perluas `EDITABLE`.
8. **RENDAH** Meta dikendalikan penyerang. Fix: `meta.url` hanya kalau host = `scan.domain`/subdomain, teks polos; clamp `capturedAt` ke `[detectedAt − 24 jam, detectedAt + 5 menit]`, clamp `focusY`.
9. **RENDAH** Fullscreen bisa fokus form. Fix: CSS `pointer-events:none` di control, `-webkit-user-modify:read-only`, `canBecomeFirstResponder` false; test tanpa keyboard.
10. **RENDAH** Pengecualian 512 KB: cocokkan method `POST` + path ternormalisasi `/scans`; test `/scans/`, `/scans/:id`, `/replicas/*` tetap 256/16 KB.
11. **RENDAH** Tanpa kill-switch: var `REPLICAS_ENABLED` + runbook takedown (`replica_path = null` + `wrangler r2 object delete --remote`).

## Wiring

1. **TINGGI** 18a tidak perlu menunggu #177: `scan-result.schema.json` tanpa `additionalProperties: false`, ajv `test/helpers/schema.ts:4-9` memakai `contracts/` checkout. Fix: 18a dari `origin/main` sekarang; langkah 6 cek eksplisit `pageReplicaUrl` string|null, ulang setelah #177. Urutan: komentar #176 → 18a merge+deploy → #175 → 18f ke #177 → #177 + ScanResult → 18b → TestFlight → 18c.
2. **TINGGI (terverifikasi)** CI iOS merah karena `TestDoubles.swift:88` `CountingScansRepository` belum punya `setMemberNotify`/`remindMember`/`becomeProtected` di `main`; perbaikan di PR #175 (open). Fix: prasyarat #175 merge lalu #177 update dari main, sebelum 18f/18b; K19 + DoD :188.
3. **TINGGI** Mitigasi regresi bukti tidak ada (lihat Security 6). Fix: K16, langkah 4, D10, C26(4)/(d) + DECISIONS baru menggantikan C22(b). Ada draft PR #174 (TestFlight workflow): pastikan gerbangnya ditulis.
4. **SEDANG** C26/C27 belum dikirim (#176 0 komentar). Fix: revisi lalu kirim hari ini (setelah izin Alief); C27 sebut #175.
5. **SEDANG** Kuota screenshot 300 → 60 terlalu dini (alasan dari C19 Supabase, sudah diganti C23). Fix: tetap 300 di 18a.
6. **SEDANG** 18c: ≥ 15 hari setelah `max(created_at) where screenshot_path is not null` dan semua device demo memakai build #178 + 18b.
7. **SEDANG** DTO sementara C27: requirement protokol `scanDetail(id:)` dengan default extension (10 conformer `ShooRepository`), `ScanDetail: Decodable` (`ScanResult(from:)` + `pageReplicaUrl`), hanya ApiRepository + Mock override; DetailModel simpan `pageReplicaUrl` sendiri; tanggal hapus DTO.
8. **SEDANG** Titik sentuh hilang di Peta dampak: (a) `test/env.d.ts` tanpa `REPLICAS` (typecheck CI); (b) `scans.test.ts:142-146` 413 > 256 KB → 512 KB; (c) `routes/devices.ts:153-175` `POST /devices/me/protected` juga `deleteDevice` + `deleteScreenshots`; (d) `security-review.test.ts`, `retention.test.ts` satu store; (e) `retention_indexes.test.sql` `has_index` tidak cek predikat → `pg_indexes.indexdef`.
9. **RENDAH** `abandonUpload` tidak perlu routing per path (pemanggil sudah memberi store).
10. **RENDAH** Test batas: 409 601 char gagal `% 4` (`invalid`); uji ukuran dengan 409 604 char.
11. **RENDAH** Sumber usang: langkah 10/11 + `log/fase-18-plan.md:25` → import dari `ios/ShooExtension/Resources/`; header main af0d07b → a57c531.
12. **RENDAH** Jumlah langkah beda (18a 12 vs 11, 18b 8 vs 7); privacy/docs tanpa langkah di rencana utama; C22 (c)/(e) dobel.
13. **RENDAH** Verifikasi :176 tambah test `favicons` + `security-review`.

## Sisa

- Review database/retensi (ecc:database-reviewer) belum jalan.
- Semua temuan di atas belum diterapkan ke `fase-18-page-replica.md`, `log/fase-18-plan.md`, TODO, DECISIONS.
