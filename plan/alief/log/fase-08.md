# Log fase 08 — Family: kode, join, members, disconnect, halaman undangan

| Field | Nilai |
|---|---|
| Status | `[m]` berhenti di LANGKAH MANUAL (deploy cloud fase 07 + 08). Belum ada PR |
| Track / branch | be · `feat/BE-family` (worktree sesi `happy-mcnulty-9fc732`) |
| Basis | ditumpuk di atas `feat/BE-devices` (PR #9, stacked on #7) → PR nanti menulis "Stacked on #9" |
| Mulai | 21 Okt 2026 21:47 WITA |
| Model | Opus 5.5 |

## Ringkasan rencana

Rencana lengkap: [`fase-08-plan.md`](fase-08-plan.md). Migrasi kecil (`join_attempts.ip_hash`, indeks retensi), `POST /family/code`, `POST /family/join` (urutan R4 §2 dalam satu transaksi berkunci), `GET/DELETE /family/members`, `DELETE /family/guardian`, `GET /join`, `GET /devices/me`, usulan `DELETE /devices/me` (C19). Jam disuntik = `expires_at`/`attempted_at` digeser langsung di DB di test (D-alief-B06).

## Checklist langkah kerja

- [x] 1. `POST /family/code` (R4 §1): 6/menit per guardian, kode lama guardian dihapus, 4 digit acak tanpa bias, kode kedaluwarsa yang bentrok diambil alih, maks 20 percobaan → 503 `code_unavailable`
- [x] 2. `POST /family/join` (R4 §2): `too_many_attempts` (5 gagal/10 menit per device dan per IP, `Retry-After`) → `already_connected` → `code_invalid`/`code_expired` (dicatat gagal) → `family_full` (lock guardian) → link
- [x] 3. `GET /family/members` sesuai fixture (`extensionActive`, `lastScan`)
- [x] 4. `DELETE /family/members/{deviceId}`, `DELETE /family/guardian`
- [x] 5. `GET /join?code=` EN/ID (Accept-Language), XSS test
- [x] 6. `GET /devices/me` + `DELETE /devices/me` (usulan C19)
- [x] 7. Review `ecc:security-reviewer` (T2, T11, T12, T13) + TypeScript/database
- [ ] 8. LANGKAH MANUAL deploy (di bawah) — menunggu Alief
- [ ] Setelah 8: cek hasil uji asap cloud, PR `feat/BE-family` (stacked on #9), status `[r]`

## File dibuat / diubah

- `backend/db/supabase/migrations/20261021160000_family.sql`, `tests/family.test.sql`
- `backend/api/src/db/repo/{codes,joinAttempts,families}.ts`, `src/db/repo/devices.ts` (`findProfile`, `deleteDevice`)
- `backend/api/src/services/{family,screenshots}.ts`, `src/routes/{family,join-page}.ts`, `src/routes/devices.ts` (`GET`/`DELETE /devices/me`)
- `backend/api/src/http/{auth,errors,rateLimit}.ts` (`requireMode`, kode error family, bucket `family_code`), `src/app.ts`, `tsconfig.json` (`resolveJsonModule` untuk fixture)
- `backend/api/test/{family,join-page,devices-me}.test.ts`
- `backend/README.md`, `plan/alief/log/{fase-08,fase-08-plan,DECISIONS}.md`, `PROGRESS.md`

## Hasil verifikasi (lokal)

21 Okt 2026 ±21:58 WITA:

| Perintah | Hasil |
|---|---|
| `(cd backend/db && supabase db reset && supabase test db)` | `Files=3, Tests=67` · `Result: PASS` |
| `pnpm -C backend/api typecheck` | bersih |
| `pnpm -C backend/api test` | `Test Files 8 passed` · `Tests 100 passed (100)` · 0 error tak tertangani |
| `pnpm -C backend/api exec vitest run family join` | termasuk di atas (`family.test.ts`, `join-page.test.ts`) |
| `wrangler dev` + curl | code `8509` + `expiresAt` + `inviteUrl`; join → `{"guardian":{…"name":"Smoke G"…}}`; members → `extensionActive:true, lastScan:null`; `GET /devices/me` guardian terisi; `/join` 200 + CSP + `nosniff` + `no-store`; `DELETE /family/guardian` → ok; `DELETE /devices/me` → ok lalu 401; token di log dev = 0 |

TDD: pgTAP family + 39 test vitest merah dulu, lalu hijau; setelah review 4 test baru merah dulu (batas IP 20, IPv4-mapped, IPv6 rusak) lalu hijau.

## DoD

- [x] Semua test wajib file fase hijau: kode 4 digit + kedaluwarsa 60 s, multi-pakai, Protected ke-4 → `family_full`, 5 gagal → `too_many_attempts` (device dan IP terpisah), Guardian join → 403, Protected code → 403, sudah terhubung → 409, hapus member bukan milik → 404, setelah disconnect Guardian tidak melihat member, dua join paralel ke slot terakhir → satu sukses, `/join?code=<script>` / `12345` / `1234"onclick=` tidak dipantulkan (`test/family.test.ts`, `test/join-page.test.ts`).
- [x] Respons cocok dengan `fixtures/family-members.json` (`family.test.ts` "matches the fixture shape").
- [x] `GET /devices/me` sesuai kontrak (`test/devices-me.test.ts`).
- [x] `DELETE /devices/me` (usulan C19): satu transaksi, cascade link/kode/percobaan/scan/verdict/push_log, path screenshot dihapus setelah commit (placeholder Storage sampai fase 09), token lama → 401 (`devices-me.test.ts`). Masuk "Contract proposals" di PR.
- [x] LANGKAH MANUAL deploy fase 08 tertulis (di bawah).

## Review

| Reviewer | CRITICAL | HIGH | MEDIUM | LOW | Ditangani |
|---|---|---|---|---|---|
| `ecc:security-reviewer` (T2, T11, T12, T13, P3) | 0 | 0 | 3 | 6 | Batas IP join 20/10 menit (CGNAT); FK 23503 → `code_invalid`; IPv4-mapped + IPv6 rusak; `deleteDevice` menghapus scan dulu (`returning`). Ditunda: rem global + pepper HMAC (fase 12), Storage delete (fase 09) |
| `ecc:typescript-reviewer` + database | 0 | 0 | 3 | 5 | Test kode-bentrok dibuat deterministik (503); kode dicek ulang setelah lock guardian; `ip_hash not null`; test baru: `code_expired` dihitung gagal, `family_full`/`already_connected` tidak; unit `clientIp` |

Diperiksa reviewer dan aman: urutan lock device → IP → guardian tanpa deadlock; ruang kunci advisory 1-arg vs 2-arg terpisah; `DELETE /family/members/{id}` dibatasi `guardian_id` (tanpa IDOR); akses dari `family_links` saat request (T12); `/join` hanya memantulkan `^\d{4}$` (T13); cascade FK lengkap (P3). T11 (konfirmasi sebelum join) ada di app, fase 14.

## Deviasi

- D-alief-B06: `join_attempts.ip` → `ip_hash`; jam test = geser `expires_at`/`attempted_at`; halaman `/join` satu bahasa per Accept-Language; CSP lebih ketat (tambahan `base-uri`, `form-action`, `frame-ancestors`); `too_many_attempts` membawa `Retry-After`; `DELETE /devices/me` tanpa flag server.

## Placeholder aktif

- `backend/api/src/services/screenshots.ts` `deleteScreenshots` → hanya log jumlah; diganti Storage API di fase 09 (`TODO(sync:alief)`).
- `backend/api/src/routes/join-page.ts` `APP_STORE_URL = https://apps.apple.com/` → link App Store/TestFlight asli di fase 16 (`TODO(sync:alief)`).
- Dari fase 07: `POST /debug/apns-spike` + `APNS_SPIKE` + secret `SPIKE_KEY` → dihapus di fase 11.

## LANGKAH MANUAL (Alief) — deploy fase 07 + 08

Dijalankan dari root worktree ini, di branch `feat/BE-family` (D-alief-27). Tidak ada secret baru. Centang tiap butir dan tempel hasilnya (tanpa token) di bawah butir itu.

- [ ] 1. **Migrasi cloud** (menerapkan `20261021150000_blocklist_times.sql` dari review fase 07 dan `20261021160000_family.sql`):
  ```bash
  (cd backend/db && supabase migration list --linked)   # dua migrasi baru tampil di kolom Local saja
  (cd backend/db && supabase db push)
  ```
  Tempel output `db push`.
- [ ] 2. **Deploy Worker:**
  ```bash
  pnpm -C backend/api run deploy
  ```
- [ ] 3. **Uji asap cloud** (`U=https://shoo-api.afindo-mi01.workers.dev`):
  ```bash
  U=https://shoo-api.afindo-mi01.workers.dev
  tok() { python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])'; }
  GT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke G","mode":"guardian"}' | tok)
  PT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke P","mode":"protected"}' | tok)
  CODE=$(curl -s -X POST $U/family/code -H "authorization: Bearer $GT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["code"])')
  curl -s -X POST $U/family/join -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "{\"code\":\"$CODE\"}"; echo
  curl -s $U/family/members -H "authorization: Bearer $GT"; echo
  curl -s $U/devices/me -H "authorization: Bearer $PT"; echo
  curl -s -o /dev/null -w "%{http_code} " "$U/join?code=$CODE"; curl -s -o /dev/null -w "%{http_code}\n" "$U/join?code=%3Cscript%3E"
  curl -s $U/blocklist -H "authorization: Bearer $GT"; echo
  curl -s -X DELETE $U/devices/me -H "authorization: Bearer $PT"; curl -s -X DELETE $U/devices/me -H "authorization: Bearer $GT"; echo
  curl -s -o /dev/null -w "%{http_code}\n" $U/devices/me -H "authorization: Bearer $GT"
  ```
  Harapan: `{"guardian":{…"name":"Smoke G"…}}`, `{"members":[{…"name":"Smoke P","extensionActive":true,"lastScan":null}]}`, `GET /devices/me` dengan `guardian` terisi, `200 200`, `{"domains":[],"nextSince":null}`, `{"ok":true}{"ok":true}`, `401`. Tempel hasilnya (jangan tempel `$GT`/`$PT`). Dua device uji itu terhapus oleh `DELETE /devices/me`.
- [ ] 4. Buka `$U/join?code=1234` di Safari iPhone (opsional): halaman tampil, tombol "Open Shoo"/"Buka Shoo" ada (app belum menangani `shoo://` sampai fase 14).
- [ ] 5. Ketik lagi: `Saya Alief, track be. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).` Agent memeriksa hasil, membuka PR `feat/BE-family` (stacked on #9), dan lanjut ke fase 09.

## Catatan handoff

- Fase 09: `requireMode`, `guardianOf`/`family_links` saat request untuk akses `owner=family` / `{deviceId}` (T12); `deleteScreenshots` di `services/screenshots.ts` diganti Storage API + dipanggil juga oleh retensi fase 12; `lastScan` di `GET /family/members` membaca `scans` (indeks `scans_owner_time`).
- Fase 10: `DELETE /devices/me` menghapus verdict (cascade) tanpa menghitung ulang `blocklist_entries.families`; hitung ulang di fase 10 kalau verdict dihapus (atau terima selisih kecil sampai review manual).
- Fase 12: retensi `family_codes` (`family_codes_expires`), `join_attempts` (`join_attempts_time`), `rate_limit_hits`; hardening dari review fase 07 (D-alief-B05).
- Fase 13/14: app memakai `GET /devices/me` (`me()`), `POST /family/code`, `POST /family/join`; error `too_many_attempts` membawa `Retry-After`.
