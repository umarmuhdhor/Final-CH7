# Fase 09 — Scans + screenshot

| Field | Nilai |
|---|---|
| Track | be |
| Branch | `feat/BE-scans` |
| Prasyarat | 08 |
| Requirement | Mandat Fase B Scans (`POST /scans` + upload screenshot, `GET /scans` filter + cursor, `GET /scans/{id}`); keamanan "Guardian hanya bisa melihat data perangkat yang terhubung" |
| Model | Opus 5.5 |
| Fase berikutnya | 10 |

## Tujuan

Extension bisa mengirim hasil scan (skor ≥ 30) beserta screenshot bukti, app bisa membaca Activity milik sendiri/keluarga dengan filter dan paginasi, dan Detail mendapat screenshot lewat signed URL. Kuota Storage Free (1 GB, 5 GB egress) dijaga.

## Bacaan wajib

- `contracts/api.md` Scans, `contracts/scan-result.schema.json`, semua fixture scan
- `ref/R2` scans, `ref/R3` §3, §4 (POST/GET scans, screenshot), `ref/R4` §3, `SECURITY.md` T1, T4, T6, `ARCHITECTURE.md` §3

## Output

- `services/screenshots.ts`: `interface ScreenshotStore { put(path, bytes, contentType); signedUrl(path, ttl); remove(paths[]) }` + `SupabaseStorageStore` (REST: `POST /storage/v1/object/screenshots/<path>`, `POST /storage/v1/object/sign/screenshots/<path>`, `DELETE /storage/v1/object/screenshots` dengan `prefixes`)
- Repo `scans.ts`, service `scans.ts` (`toScanResult`), route `scans.ts`
- Test: validasi, kuota, dedupe, cursor, IDOR

## Langkah kerja

1. `POST /scans`: validasi zod sesuai skema (R3 §4), `ownerDeviceId`/`ownerName` di body diterima tapi diabaikan, `owner = principal`, simpan, screenshot (ukuran ≤ `SCREENSHOT_MAX_BYTES`, magic bytes JPEG/PNG, dedupe pemilik+domain 24 jam, kuota 50/24 jam) → `201 { id }`. Hook push (fase 11) dipanggil lewat interface `PushSender` yang di fase ini adalah `LogSender`.
2. `GET /scans?owner=me|family|{deviceId}&status=&cursor=&limit=`: R3 §3–§4 (`family` = saya + Protected aktif, D-alief-19), `screenshotUrl: null` di daftar (D-alief-04), `verdict` dari join hanya untuk scan `blocked`, `pageTitle` null dihilangkan, `nextCursor`. Setiap respons divalidasi `test/helpers/schema.ts` (ajv + `contracts/scan-result.schema.json`).
3. `GET /scans/{id}`: otorisasi R3 §3, signed URL 1 jam.
4. Usulan kontrak D-alief-07 (batas screenshot) + D-alief-04 (`screenshotUrl` daftar null) + catatan C10 → PR "Contract proposals" + TODO C4, C10.
5. Test IDOR: Guardian A tidak bisa membaca scan Protected milik Guardian B (`GET /scans/{id}` → 404, `?owner=<id>` → 404); Protected tidak bisa `owner=family` (403); setelah disconnect → 404.
6. `ecc:security-reviewer` fokus T1, T4, T6.

## Verifikasi

```bash
(cd backend/db && supabase start && supabase test db)
pnpm -C backend/api exec vitest run scans screenshots
```

## Kriteria selesai (DoD)

- [ ] Respons `GET /scans?owner=family` cocok dengan bentuk dan isi `activity-family.json` (seed dari fixture; termasuk scan Guardian sendiri) dan lolos validasi JSON schema.
- [ ] Body berisi `ownerDeviceId` device lain → tersimpan sebagai milik principal (test).
- [ ] Screenshot > 150 KB dibuang, scan tetap 201 (test). Dedupe dan kuota terbukti (test).
- [ ] Semua test IDOR hijau.
- [ ] LANGKAH MANUAL deploy fase 09 + secret `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (B5).
