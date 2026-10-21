# Log fase 11 — Push APNs

| Field | Nilai |
|---|---|
| Status | `[r]` LANGKAH MANUAL 1–4 selesai di cloud (22 Okt, Worker `ac2025ec`); PR stacked on #15, **pending B6/B7/C3** (butir 5–6: kunci APNs + uji iPhone, diulang di fase 15 / G7) |
| Track / branch | be · `feat/BE-push` (worktree sesi `happy-mcnulty-9fc732`) |
| Basis | ditumpuk di atas `feat/BE-verdicts` (PR #15, stacked on #13) → PR nanti menulis "Stacked on #15" |
| Mulai | 22 Okt 2026 ±00:35 WITA |
| Model | Opus 5.5 |

## Ringkasan rencana

Rencana lengkap: [`fase-11-plan.md`](fase-11-plan.md) (`ecc:planner`). Push dikirim **langsung dari Worker ke APNs** (D-alief-B01 menang atas teks relay di file fase; keputusan lengkap D-alief-B11): `ApnsSender` dengan JWT ES256 yang di-cache, `deliverPush` di `waitUntil` (kirim → kosongkan token 410 → `push_log`), `push_log` tanpa teks, route spike fase 07 dihapus. Edge Function `push` / `RelaySender` / test Deno **tidak dibuat** (hanya kalau D7 gagal di jalur langsung).

## Checklist langkah kerja

- [x] 1. `messages.ts` EN/ID (sudah dari fase 09, test `push-messages.test.ts`)
- [x] 2. ~~Edge Function `push`~~ → tidak dibuat (D-alief-B01/B11). `ApnsSender` langsung: `services/push/apns.ts`
- [x] 3. Token 410 → dikosongkan (compare-and-clear), 400 `BadDeviceToken` → tetap
- [x] 4. `POST /scans` → `waitUntil(deliverPush)`, `push_log` `sent`/`logged`/`failed:…` tanpa token/secret/teks
- [x] 5. `debug-apns.ts`, `APNS_SPIKE`, `SPIKE_KEY` dihapus dari kode/config/README (`grep -rn "apns-spike\|APNS_SPIKE\|SPIKE_KEY" backend/` kosong); `wrangler secret delete SPIKE_KEY` = LANGKAH MANUAL 3
- [x] 6. C9: sudah `[x]` (diterima kontrak PR #1/#3/#4); payload = kontrak + `sound`
- [x] 7. Uji lokal (hasil di bawah)
- [x] 8. Review berurutan: security → TypeScript → database → cek P1–P13
- [x] 9. LANGKAH MANUAL 1–4 (cloud, coordinator); 5–6 pending B6/B7/C3 (PROMPT 6h: bukan blocker kode)

## File dibuat / diubah

- Baru: `backend/api/src/services/push/{apns,deliver}.ts`, `src/db/repo/push.ts`, `src/http/logError.ts`, `backend/db/supabase/migrations/20261022100000_push_log_privacy.sql`, `tests/push_log.test.sql`, test `push-apns.test.ts`, `push-deliver.test.ts`, `logError.test.ts`
- Diubah: `src/services/push/{sender,notify}.ts`, `src/routes/scans.ts`, `src/app.ts`, `src/env.ts`, `src/routes/screenshots.ts`, `src/services/{scans,screenshots}.ts` (log `errorInfo`), `wrangler.jsonc`, `vitest.config.ts`, `.dev.vars.example`, `test/{apns,push-notify,env.d}.ts`, `backend/README.md`
- Dihapus: `src/routes/debug-apns.ts`
- Plan: `log/{fase-11,fase-11-plan,DECISIONS}.md` (D-alief-B11), `ref/R1`, `R2`, `R3` §6–§7, `R4`, `TODO.md` (B5, B7), `PROGRESS.md`

## Hasil verifikasi (lokal)

- `(cd backend/db && supabase db reset && supabase test db)` → **PASS, 92 test** (6 file; baru `push_log.test.sql` 15: tanpa `body`, CHECK menolak string mirip token / spasi bebas / newline / status 4 digit / kata kedua, index `push_log_device_created`, cascade hapus scan).
- `pnpm -C backend/api exec tsc --noEmit --noUnusedLocals` → bersih. `pnpm -C backend/api test` → **19 file, 274 test lulus** (baru: `push-apns.test.ts` 21, `push-deliver.test.ts` 7, `push-notify.test.ts` +3, `logError.test.ts` 1).
- Test wajib file fase: teks EN/ID ✓; payload kontrak + `sound` ✓ (header persis, JWT terverifikasi kunci publik); tanpa push untuk scan Guardian sendiri / Protected tanpa Guardian / Guardian tanpa `apns_token` ✓; 410 `Unregistered` & `ExpiredToken` → token kosong ✓; 400 `BadDeviceToken` → token tetap + `push_log` ✓; error APNs/fetch tidak menggagalkan `POST /scans` ✓; secret/token/JWT/nama tidak muncul di log ✓ (test log memakai `ApnsSender` + `deliverPush` asli). "Relay 401" dan test Deno tidak berlaku (tanpa relay).
- `grep -rn "x-push-secret\|APNS_KEY_P8_B64" backend/api/src | grep -v "env\.\|c\.env"` → hanya daftar nama env di `apns.ts:15` (tanpa nilai).
- **Uji lokal langkah 7** (pengganti relay lokal): `wrangler dev` + `.dev.vars` sementara berisi kunci P-256 sekali pakai (dibuat `openssl`, dihapus setelah uji), Guardian dengan token dummy 64 hex, Protected join, `POST /scans` → `201`; `push_log` = `failed:network`, log `{"event":"push","result":"failed:network"}`. Sebab: workerd lokal memakai HTTP/1.1, APNs hanya HTTP/2 — `curl --http2 … api.sandbox.push.apple.com` → `403 http_version=2`, `curl --http1.1` → koneksi ditolak (`000`). Terbukti lokal: baris `push_log` ditulis dari `waitUntil` setelah respons, jalur error tidak menggagalkan scan. Respons APNs asli dari Worker cloud sudah terbukti di D-alief-B01 dan diulang di LANGKAH MANUAL 5.

## DoD

- [x] Semua test vitest hijau (Deno tidak berlaku, D-alief-B11); payload = kontrak + `sound` (`push-apns.test.ts` "POSTs the contract payload…").
- [~] Uji lokal: `push_log` mencatat hasil dari jalur lengkap lokal (`failed:network`, HTTP/1.1 lokal). Cloud: `push_log` `logged` lewat `waitUntil` + Hyperdrive (butir 4). Respons APNs asli dengan kunci nyata = butir 5 (pending B7).
- [x] Endpoint spike dihapus (`grep -rn apns-spike backend/` kosong).
- [x] PR `[r]` + "pending B6/B7/C3" (PROMPT 6h); push nyata di iPhone (D7) diulang di fase 15 / G7.

## Review

Berurutan, satu per satu (aturan Alief).

| Reviewer | CRITICAL | HIGH | MEDIUM | Diperbaiki | Commit |
|---|---|---|---|---|---|
| `ecc:security-reviewer` | 0 | 0 | 1 | M: Guardian bisa dibanjiri push → maks 10 / 10 menit per Guardian + `apns-expiration` 1 jam. L: `String(err)` di log → `errorInfo` (nama + SQLSTATE) di semua file; migrasi aman untuk baris lama; hapus cache kunci hanya entri yang sama; reset JWT hanya token yang dipakai. Diterima: nama pilihan Protected di teks push (sudah tanpa kontrol/bidi), race disconnect < 1 s (satu push ke Guardian lama, isi hanya nama + skor) | `6b682aa` |
| `ecc:typescript-reviewer` | 0 | 0 | 4 | M: referensi JWT per send (`tokenRef`), test log yang kosong diganti test `ApnsSender` + `deliverPush` asli, komentar DB di `waitUntil` + cek cloud (LANGKAH MANUAL 5). L: body 200 di-cancel, `push_log` tetap ditulis kalau kosongkan token gagal, `push_key_failed` dicatat (nama saja), `errorInfo` memotong nama, test timeout `AbortSignal` asli / rotasi kunci / refresh paralel / 403 token lama. Diterima: batas lunak (M2) | `fe10276` |
| `ecc:database-reviewer` | 0 | 0 | 2 | M: insert `push_log` `FOR KEY SHARE` + telan 23503; CHECK `not valid` + `validate`. L: index `(to_device_id, created_at)` ganti `push_log_device`; pgTAP kasus tolak tambahan + cascade scan | `d8e1121` |

### Cek privasi Apple P1–P13 (D-alief-40)

| # | Hasil | Bukti |
|---|---|---|
| P1 Privacy manifest | Tidak berlaku (app, fase 01) | – |
| P2 Label privasi | Data baru: tidak ada. `push_log` menyimpan id Guardian + id scan + kode hasil (Device ID, sudah di P2) | migrasi `20261022100000` |
| P3 Hapus data | `push_log` ikut terhapus lewat cascade saat device/scan dihapus; insert terlambat tidak menghidupkan referensi (`FOR KEY SHARE`) | `push-deliver.test.ts` "scan or guardian deleted…", pgTAP cascade |
| P4 Keychain | Tidak berlaku (app) | – |
| P5 ATS | Hanya HTTPS ke `api{.sandbox}.push.apple.com` (host tetap, bukan dari input) | `apns.ts` `HOST` |
| P6 Log | Tidak ada token, JWT, kunci, nama, teks, id; error dicatat `errorInfo` (nama + SQLSTATE); `push_config_incomplete` hanya nama env | `push-deliver.test.ts` test log, `logError.test.ts` |
| P7 Izin | Tidak berlaku (app, ON-05) | – |
| P8 Pasteboard | Tidak berlaku | – |
| P9 Screenshot | Tidak berubah | – |
| P10 Push | Teks hanya nama + kata kerja + skor; payload `scanId` acak; tanpa URL/domain | `push-messages.test.ts`, `push-apns.test.ts` body |
| P11 Export compliance | Tidak berlaku | – |
| P12 Kebijakan privasi | Fase 12 | – |
| P13 Hapus = langsung hilang | Tidak ada salinan teks push di DB (`body` dihapus); `push_log` cascade; push yang sudah di perangkat Guardian tidak bisa ditarik (APNs), `apns-expiration` 1 jam membatasi push yang belum terkirim | migrasi, `apns.ts` |

## Placeholder aktif

- `TODO(sync:alief): ApnsSender — replace in fase 11` di `sender.ts` → **diganti** (tidak ada lagi).

## LANGKAH MANUAL (Alief) — migrasi + deploy + uji cloud fase 11

Dari root worktree, branch `feat/BE-push`. Butir 1–5 tidak butuh kunci Apple; butir 6–7 menunggu B6/B7/C3 (kalau belum ada, PR dibuka `[r]` "pending B6/B7/C3", uji perangkat diulang di fase 15 / G7).

- [x] 1. Migrasi:
  ```bash
  (cd backend/db && supabase migration list --linked)   # 20261022100000 hanya di kolom Local
  (cd backend/db && supabase db push)
  (cd backend/db && supabase db query --linked "select count(*) from information_schema.columns where table_name = 'push_log' and column_name = 'body'")   # 0
  ```
- [x] 2. Deploy (route spike hilang, `ApnsSender` belum aktif karena `APNS_TOPIC` kosong → `LogSender`):
  ```bash
  pnpm -C backend/api run deploy
  curl -s -o /dev/null -w "%{http_code}\n" -X POST https://shoo-api.afindo-mi01.workers.dev/debug/apns-spike   # 404
  ```
- [x] 3. Hapus secret spike: `(cd backend/api && npx wrangler secret delete SPIKE_KEY)` (jawab `y`).
- [x] 4. Uji cloud `push_log` dari `waitUntil` lewat Hyperdrive (LogSender):
  ```bash
  U=https://shoo-api.afindo-mi01.workers.dev
  tok() { python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])'; }
  GT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke G","mode":"guardian"}' | tok)
  PT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke P","mode":"protected"}' | tok)
  curl -s -X PATCH $U/devices/me -H "authorization: Bearer $GT" -H 'content-type: application/json' -d "{\"apnsToken\":\"$(printf '0%.0s' $(seq 1 64))\"}"; echo
  CODE=$(curl -s -X POST $U/family/code -H "authorization: Bearer $GT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["code"])')
  curl -s -o /dev/null -w "join %{http_code}\n" -X POST $U/family/join -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "{\"code\":\"$CODE\"}"
  BODY=$(python3 -c "import json;f=json.load(open('contracts/fixtures/blocked-92.json'));[f.pop(k) for k in ('id','verdict','screenshotUrl')];print(json.dumps(f))")
  ID=$(curl -s -X POST $U/scans -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "$BODY" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
  sleep 3; (cd backend/db && supabase db query --linked "select result from push_log where scan_id = '$ID'")   # logged
  ```
  Simpan `GT`/`PT` (jangan ditempel) untuk butir 5–6; hapus device di akhir: `curl -s -X DELETE $U/devices/me -H "authorization: Bearer $PT"; curl -s -X DELETE $U/devices/me -H "authorization: Bearer $GT"`.
  Hasil butir 1–4 (22 Okt 2026 ±01:10 WITA, coordinator; mandat malam Alief "just do whatever u need"):
  - 1: `db push` → `20261022100000_push_log_privacy.sql … Finished supabase db push.`; kolom `push_log.body` = `0`.
  - 2: deploy Version `ac2025ec-2ebe-4eb5-9035-071b60cd44b0`; `POST /debug/apns-spike` → `404`.
  - 3: `wrangler secret delete SPIKE_KEY` → `Success! Deleted secret SPIKE_KEY`; sisa secret: `SCREENSHOT_URL_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`.
  - 4: `PATCH /devices/me` apnsToken dummy → `{"ok":true}`; `join 200`; `scan 5e6c625b-…`; `push_log.result` = `logged` (LogSender lewat `waitUntil` + Hyperdrive OK); dua device uji dihapus (`{"ok":true}` ×2).
  - 5–6: **menunggu Alief** (B7 kunci `.p8`, B6, C3). Sesuai PROMPT 6h: bukan blocker kode → PR `[r]` "pending B6/B7/C3", uji perangkat di fase 15 / G7.
- [ ] 5. **Butuh B7** (kunci `.p8` Sandbox). Secret Worker, nilai ditempel di prompt (tidak pernah sebagai argumen):
  ```bash
  cd backend/api
  base64 < ~/Downloads/AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | npx wrangler secret put APNS_KEY_P8_B64
  npx wrangler secret put APNS_KEY_ID      # 10 karakter dari portal
  npx wrangler secret put APNS_TEAM_ID     # Team ID yang sama dengan build D7
  ```
  Lalu set `"APNS_TOPIC": "<SHOO_BUNDLE_ID build iPhone Alief, B6>"` di `wrangler.jsonc` (commit), deploy lagi, ulang butir 4 → harapan `push_log` = `failed:400 BadDeviceToken` (kunci asli, token dummy: membuktikan kunci + HTTP/2 dari edge). `410`/`403 InvalidProviderToken` → tempel hasilnya, agent memeriksa.
- [ ] 6. **Butuh C3 + B6 + B7** (D7): build Debug ke iPhone Alief, ambil token APNs dari log Xcode, `PATCH /devices/me {apnsToken}` sebagai Guardian uji, `POST /scans` sebagai Protected → screenshot notifikasi ("Smoke P hit a blocked site · 92%"), `push_log` = `sent`. Gagal di jalur langsung → catat, agent membuat `RelaySender` + Edge Function (D-alief-B11 a).
- [ ] 7. Ketik lagi: `Saya Alief, track be. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).` Agent memeriksa hasil, membuka PR `feat/BE-push` (stacked on #15), lalu fase 12.

## Catatan handoff

- Fase 12: retensi `push_log` 14 hari pakai index `push_log_created`; `rate_limit_hits` bucket `verdicts_get` juga. Batas push lunak (10 / 10 menit per Guardian) dihitung dari `push_log`, jadi retensi < 10 menit tidak boleh. Cek apakah `String(err)` muncul lagi di kode baru (pakai `errorInfo`).
- Fase 15: teks push dibangun ulang dari `scan_id` + `pushText` (tidak ada `push_log.body`). Tap push → Detail `scanId`.
- Fase 16: `APNS_ENV=production` + kunci Production (B7) + `APNS_TOPIC` build TestFlight (TODO B7).
