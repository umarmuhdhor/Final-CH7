# Rencana fase 09 — Scans + screenshot (feat/BE-scans, stacked on #11)

Sumber: `fase-09-be-scans.md`, `contracts/api.md` Scans, `scan-result.schema.json`, fixture scan, body extension `ios/ShooExtension/Resources/{report,background,capture}.js`, R3 §3–§4, R4 §3, SECURITY T1/T4/T6, ARCHITECTURE §3.

1. **Verifikasi dulu (BELUM DIVERIFIKASI):** ajv di workerd (`new Function`) → kalau ditolak, validator dikompilasi standalone di Node saat config vitest; auth Storage REST lokal (kunci JWT `service_role` vs `sb_secret_…`, header `apikey`/`Authorization`).
2. **`ScreenshotStore`** (`services/screenshots.ts`): `put`, `signedUrl`, `remove` + `SupabaseStorageStore` (REST) ; tanpa `SUPABASE_URL`/kunci → screenshot dibuang (log), scan tetap. `deleteScreenshots` fase 08 memakai `remove`.
3. **`POST /scans`** (120/jam per device, body ≤ 256 KB): zod sesuai skema + R3 §4 (domain = host atau `*.domain`, skor/status konsisten, ≤ 20 sinyal, `detectedAt` ≤ 5 menit ke depan); `ownerDeviceId`/`ownerName` diabaikan; insert → screenshot (base64 ketat tanpa `data:`, ≤ `SCREENSHOT_MAX_BYTES`, magic JPEG/PNG, sisi ≤ 1280 px, dedupe pemilik+domain 24 jam, kuota 50/24 jam) → `201 { id }` → hook `PushSender` (`LogSender`) lewat `waitUntil`.
4. **`GET /scans?owner=&status=&cursor=&limit=`**: owner dari `family_links` saat request (T1/T12), cursor base64url(`detected_at|id`) mikrodetik, `limit` 20/50, `verdict` hanya untuk `blocked`, `pageTitle` null dihilangkan, `screenshotUrl: null`.
5. **`GET /scans/{id}`**: pemilik = saya atau Protected aktif saya, selain itu 404; signed URL 3600 s.
6. Test: validasi, body extension (bentuk `report.js`), dedupe, kuota, > 150 KB dibuang, cursor, IDOR, disconnect, fixture `activity-family.json` + JSON schema.
7. Review berurutan (satu per satu): security (T1, T4, T6) → TypeScript → database. Verifikasi. LANGKAH MANUAL: secret `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (B5), deploy, uji asap → `[m]`.
