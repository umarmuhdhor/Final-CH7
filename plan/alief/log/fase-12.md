# Log fase 12 — Retensi + hardening + deploy

| Field | Nilai |
|---|---|
| Status | `[r]` LANGKAH MANUAL 1–3, 5, 7 selesai di cloud (22 Okt, Worker `bdc661e8`); PR stacked on #17, **pending: bukti run cron 03:00 WITA (butir 6, coordinator), screenshot Triggers + toggle Data API (butir 3/4, butuh login dashboard Alief)** |
| Track / branch | be · `feat/BE-retention-hardening` (worktree sesi `happy-mcnulty-9fc732`) |
| Basis | ditumpuk di atas `feat/BE-push` (PR #17, stacked on #15) → PR nanti menulis "Stacked on #17" |
| Mulai | 22 Okt 2026 ±01:15 WITA |
| Model | Opus 5.5 |

## Ringkasan rencana

Rencana lengkap: [`fase-12-plan.md`](fase-12-plan.md) (`ecc:planner`). Keputusan: D-alief-B12. Cron harian menghapus scan + screenshot setelah 14 hari (baris + tombstone dalam satu transaksi, lalu objek Storage; batch 100 × 10, scan tanpa screenshot chunk 2000 × 25), tabel kecil ikut dipangkas, heartbeat anti-pause. Hardening: timeout role `shoo_api`, Worker tidak bisa menyetujui domain blocklist, header keamanan + 413 awal, batas 401 per IP, HMAC untuk kunci rate limit, `GET /privacy`. Review keamanan penuh atas seluruh `backend/` → perbaikan HIGH (`service_role`) + MEDIUM (secret wajib, tombstone Storage, policy blocklist, batas global, cleanup lebih panjang) + LOW.

## Checklist langkah kerja

- [x] 1. `cron/retention.ts` + `scheduled()` + `triggers.crons ["0 19 * * *"]` (`0ba2025`, `ce29cea`)
- [x] 2. Hardening: migrasi timeout role + grant kolom blocklist (`8866425`); header keamanan, 413 awal, CORS tertutup, `auth_fail` (`70b9a5c`); HMAC `RATE_KEY_SECRET` (`27eac88`); `GET /privacy` (`261d090`); test kebersihan log + cakupan semua bucket (`bd929bd`)
- [x] 3. Review penuh berurutan: `ecc:security-reviewer` → perbaikan (`8d42f44`, `8ccbbfa`) → `ecc:database-reviewer` → perbaikan (`379382b`) → `ecc:typescript-reviewer` → perbaikan (`cfecd73`) (tabel di bawah)
- [x] 4. Estimasi kuota (`207c07e`, angka di bawah); anti-pause: cron + `/healthz/db` menulis `ops_heartbeat`
- [x] 5. `backend/ci/backend.yml` (dry-run deploy + gitleaks) + `ci/README.md`; C2 diperbarui (`2c1bdca`)
- [x] 6. `backend/README.md` final: retensi, kuota, rollback, `/privacy`, env `RATE_KEY_SECRET` (`2c1bdca`, `8d42f44`)
- [x] 7. LANGKAH MANUAL deploy + uji asap cloud (di bawah)

## File dibuat / diubah

- Baru: `backend/api/src/cron/retention.ts`, `src/http/keyHash.ts`, `src/routes/privacy.ts`, `src/db/repo/tombstones.ts`, migrasi `20261022120000_hardening.sql`, `20261022130000_security_review.sql`, pgTAP `hardening.test.sql`, `security_review.test.sql`, test `retention`, `security-headers`, `privacy`, `log-hygiene`, `security-review`, `backend/db/scripts/quota-estimate.sql`, `backend/.gitleaksignore`
- Diubah: `src/index.ts`, `src/app.ts`, `src/env.ts`, `src/http/{auth,crypto,rateLimit}.ts`, `src/routes/{devices,family,screenshots}.ts`, `src/services/{scans,screenshots}.ts`, `src/db/repo/{scans,devices}.ts`, `wrangler.jsonc` (cron, `placement.mode = "smart"`), `vitest.config.ts` (`DB_ADMIN`, secret uji), `.dev.vars.example`, `test/helpers/resetDb.ts` (`adminSql`), test lama yang memakai `keyHash`, pgTAP `grants.test.sql`, `backend/ci/{backend.yml,README.md}`, `backend/README.md`
- Plan: `log/{fase-12,fase-12-plan,DECISIONS}.md` (D-alief-B12), `ref/R2` §3/§6, `ref/R4` §5, `SECURITY.md` T10/P12, `TODO.md` (B5, C2, C21, E6, E7), `PROGRESS.md`

## Hasil verifikasi (lokal)

- `(cd backend/db && supabase db reset && supabase test db)` → **PASS, 113 test** (8 file; baru `hardening.test.sql` 9: setelan timeout role, grant kolom blocklist; `security_review.test.sql` 12: `service_role` tanpa hak di `public`, tabel + grant + CHECK `storage_tombstones`, policy blocklist per perintah, index `scans_original_shot` + `scans_shot_path`).
- `EXPLAIN` kuota global (50k scan lokal): `Index Only Scan using scans_original_shot`.
- `pnpm -C backend/api exec tsc --noEmit` → bersih. `pnpm -C backend/api test` → **24 file, 310 test lulus** (baru: `retention`, `security-headers`, `privacy` 2, `log-hygiene` 2, `security-review` 17).
- Trigger cron lokal (`wrangler dev --test-scheduled`): `curl "http://localhost:8787/__scheduled?cron=0+19+*+*+*"` → `Ran scheduled event`, log `{"event":"retention","scans":…,"failed":0}`, `ops_heartbeat.cron` terisi.
- Estimasi kuota (1000 scan seed, rollback): tabel `scans` ≈ 1416 kB per 1000 scan; `rate_limit_hits` ≈ 3896 kB per 17k baris; DB total 19 MB; Storage lokal 333 screenshot. Ekstrapolasi: 500 MB DB ≈ 300k scan aktif (jauh di atas demo); Storage dibatasi 300/hari global ≈ 675 MB maks (pemicu R2 700 MB = TODO E1).
- `gitleaks dir . --no-banner` → **no leaks found** (setelah secret uji diubah ke `padEnd`, `8ccbbfa`).

## DoD

- [x] Retensi terbukti di test (umur 15/13 hari, path dedupe bersama, backlog, Storage gagal → baris tetap terhapus + tombstone, lock verdict `55P03`, tiap tabel, heartbeat, `scheduled()` di-await) + trigger lokal. Cron terdaftar di cloud + satu run di `ops_heartbeat` = LANGKAH MANUAL 3 + 6.
- [x] Tidak ada temuan CRITICAL/HIGH terbuka (HIGH `service_role` diperbaiki di migrasi `20261022130000`).
- [x] Uji asap cloud (deploy branch fase 12) lulus (LANGKAH MANUAL 5, Worker `bdc661e8`). Latensi `GET /verdicts` p95 317 ms vs target 300 ms: deviasi kecil diterima (D-alief-B12 k).
- [x] `gitleaks` 0 temuan.
- [x] C2 tertulis untuk Umar (TODO C2, dikirim Alief).

## Review

Berurutan, satu per satu (aturan Alief).

| Reviewer | CRITICAL | HIGH | MEDIUM | Diperbaiki | Commit |
|---|---|---|---|---|---|
| `ecc:security-reviewer` (seluruh `backend/`) | 0 | 1 | 6 | H: kunci rahasia Storage = `service_role` + Data API melewati RLS → `revoke all … from service_role` + default privileges (+ matikan Data API, LANGKAH MANUAL). M: `RATE_KEY_SECRET` opsional jatuh ke sha256 → wajib ≥ 32, gagal tertutup; objek Storage tertinggal kalau remove gagal → `storage_tombstones` + cron; Worker bisa menghapus entri blocklist disetujui → policy per perintah; tanpa batas global → `devices_create_all` 1000/hari + screenshot 300/24 jam; cleanup `rate_limit_hits` 5 chunk → 50. L: rantai dedupe → hanya upload asli (≤ 15 hari); `/privacy` dilengkapi; panjang minimum secret. Ditunda: M `faviconUrl` dimuat langsung app (fase 13, handoff), L Content-Type + query URL (usulan C21), L device tidak aktif (TODO E7), L pin checksum/SHA action (C2) | `8d42f44`, `8ccbbfa` |
| `ecc:database-reviewer` | 0 | 0 | 7 | M1 upload terlambat / Worker mati → objek tanpa tombstone, M2 `reserveScreenshot` tanpa cek baris (D-alief-40: celah P13 = TINGGI) → tombstone sebagai log niat di transaksi reservasi, dihapus hanya setelah remove terkonfirmasi + > 10 menit, `gone` tanpa upload. M3 satu batch gagal memblokir drain → `attempts`/`last_try_at`, lanjut ke batch berikut. M4 retensi maks 1000 scan/hari → chunk scan tanpa screenshot 2000 × 25 + batas global `POST /scans` 2000/jam. M5 deadlock `deleteDevice` ↔ retensi → urutan lock tetap + coba ulang sekali. M6 kuota global sort semua scan 24 jam → index parsial `scans_original_shot` (index-only, diverifikasi `EXPLAIN`). L1 index `scans_shot_path`; L3 CHECK tombstone hanya panjang (pola ketat bisa menggagalkan hapus akun); L5 komentar CTE `hitLight`. Ditunda: M7 device tidak aktif (TODO E7, keputusan Alief); L6 hitungan subrequest Hyperdrive (dicek di run cron cloud, LANGKAH MANUAL) | `379382b` |
| `ecc:typescript-reviewer` | 0 | 0 | 5 | M2 Storage mati menahan baris scan > 14 hari (janji `/privacy`, diperlakukan TINGGI) → tombstone di transaksi hapus, baris selalu hilang hari ke-14, objek dicoba ulang. M1 `scheduled()` di `waitUntil` → di-`await` (Cron Events gagal terlihat). M3 batas global terpakai body tidak valid → dihitung setelah validasi (risiko DoS diterima, D-alief-B12 i). M4 token mati dapat 429 → tetap 401 + `Retry-After`. M5 test: kode `55P03` diperiksa, log kegagalan Storage tanpa path, `vi.waitFor` ganti `setTimeout`. L: import kunci HMAC gagal tidak di-cache, jeda 100 ms sebelum coba ulang hapus, `clearScreenshotPath` gagal tidak melewati discard. Diterima: `backlog` bisa positif palsu di batch terakhir; `removed` menghitung tombstone muda | `cfecd73` |

### Cek privasi Apple P1–P13 (D-alief-40)

| # | Hasil | Bukti |
|---|---|---|
| P1 Privacy manifest | Tidak berlaku (app, fase 01) | – |
| P2 Label privasi | Data baru: tidak ada. `storage_tombstones` hanya path objek yang sedang dihapus | migrasi `20261022130000` |
| P3 Hapus data | Scan + screenshot otomatis 14 hari (objek ≤ 15 hari); `DELETE /devices/me` men-tombstone path di transaksinya, objek dihapus sesudahnya dan dicoba ulang cron kalau gagal; race dengan retensi tidak menggagalkan hapus (urutan lock + coba ulang) | `retention.test.ts`, `security-review.test.ts` "tombstones" |
| P4 Keychain | Tidak berlaku (app) | – |
| P5 ATS | Header HSTS di semua respons; tidak ada host baru | `security-headers.test.ts` |
| P6 Log | Log retensi hanya jumlah; kunci rate limit HMAC (IP tidak bisa dibalik); test alur penuh tanpa token/kode/IP/nama/secret di log | `log-hygiene.test.ts`, `retention.test.ts` |
| P7 Izin | Tidak berlaku (app) | – |
| P8 Pasteboard | Tidak berlaku | – |
| P9 Screenshot | Dedupe hanya upload asli; batas global 300/24 jam; setiap objek punya tombstone sejak sebelum upload sampai remove terkonfirmasi (juga upload terlambat / Worker mati) | `security-review.test.ts` |
| P10 Push | Tidak berubah; `push_log` dipangkas 14 hari | `retention.test.ts` |
| P11 Export compliance | Tidak berlaku | – |
| P12 Kebijakan privasi | `GET /privacy` EN/ID: data, retensi, hapus data, tanpa tracking, prosesor; kontak = TODO E6 | `privacy.test.ts` |
| P13 Hapus = langsung hilang | Baris hilang seketika (link screenshot 404 di request berikutnya); objek Storage dihapus sesaat kemudian dengan tombstone; tidak ada salinan di cache (`private, no-store`, D-alief-B09) | `security-review.test.ts`, `screenshots.test.ts` |

## Placeholder aktif

- `TODO(sync:alief): team contact address` di `backend/api/src/routes/privacy.ts` → TODO E6 (sebelum TestFlight eksternal).
- `TODO(sync:alief): App Store link` di `join-page.ts` (fase 16, tidak berubah).

## LANGKAH MANUAL (Alief / coordinator) — migrasi + secret + deploy + uji cloud fase 12

Dari root worktree, branch `feat/BE-retention-hardening` (PR 07–11 masih terbuka → tetap stacked on #17, tanpa rebase). **Urutan penting:** butir 2 (secret) sebelum butir 3 (deploy) — kode fase 12 gagal tertutup tanpa `RATE_KEY_SECRET` (semua request ber-rate-limit → 500). Tidak ada kunci Apple yang dibutuhkan.

- [x] 1. Migrasi (2 file: `20261022120000_hardening`, `20261022130000_security_review`):
  ```bash
  (cd backend/db && supabase migration list --linked)   # dua migrasi di atas hanya di kolom Local
  (cd backend/db && supabase db push)
  (cd backend/db && supabase db query --linked "select unnest(setconfig) from pg_db_role_setting where setrole = 'shoo_api'::regrole")   # statement_timeout=10s, idle_in_transaction_session_timeout=15s, lock_timeout=5s
  (cd backend/db && supabase db query --linked "select count(*) from information_schema.role_table_grants where grantee = 'service_role' and table_schema = 'public'")   # 0
  (cd backend/db && supabase db query --linked "select count(*) from storage_tombstones")   # 0
  ```
  Catatan: Worker lama (`ac2025ec`) tetap jalan dengan skema baru (kolom/tabel lama tidak berubah; Worker lama tidak menyentuh `storage_tombstones`, dan grant `blocklist_entries` lama yang dipakainya — insert `(domain, families)`, update `families`, hapus baris belum diputus — tetap diizinkan).
- [x] 2. Secret baru (nilai tidak pernah tampil; 44 karakter base64):
  ```bash
  openssl rand -base64 32 | tr -d '\n' | pnpm -C backend/api exec wrangler secret put RATE_KEY_SECRET
  pnpm -C backend/api exec wrangler secret list   # RATE_KEY_SECRET, SCREENSHOT_URL_SECRET, SUPABASE_SERVICE_ROLE_KEY
  ```
  `SCREENSHOT_URL_SECRET` (fase 09) dibuat dengan `openssl rand -base64 32` = 44 karakter, jadi lolos batas ≥ 32; butir 5 membuktikannya (`screenshotUrl` tidak null).
- [x] 3. Deploy (cron + Smart Placement ikut):
  ```bash
  pnpm -C backend/api run deploy   # output harus memuat "schedule: 0 19 * * *"
  ```
  Screenshot dashboard Cloudflare → Workers → `shoo-api` → Settings → Triggers (Cron `0 19 * * *`) → simpan di `plan/alief/qa/img/fase-12-cron-trigger.png`.
- [ ] 4. (dilewati malam ini — butuh login dashboard Alief; opsional) (Opsional, pertahanan berlapis) Supabase dashboard → Project Settings → Data API → matikan "Enable Data API". Worker tidak memakai PostgREST (Storage punya API sendiri); `service_role` sudah tanpa hak di `public` setelah butir 1.
- [x] 5. Uji asap semua endpoint dengan dua device uji (batas `POST /devices` 10/jam per IP):
  ```bash
  U=https://shoo-api.afindo-mi01.workers.dev
  tok() { python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])'; }
  curl -s -D - -o /dev/null $U/healthz | grep -iE '^(HTTP|x-content-type-options|strict-transport-security|content-security-policy|referrer-policy|x-frame-options|cache-control)'
  curl -s -o /dev/null -w "healthz/db %{http_code}\n" $U/healthz/db                       # 200 (HMAC jalan → RATE_KEY_SECRET terpasang)
  curl -s -o /dev/null -w "options %{http_code}\n" -X OPTIONS $U/healthz                  # 404, tanpa access-control-*
  head -c 300000 /dev/zero | curl -s -o /dev/null -w "413 %{http_code}\n" -X POST $U/devices -H 'content-type: application/json' --data-binary @-
  curl -s "$U/privacy?lang=id" | grep -c "15 hari"                                       # 1
  curl -s -o /dev/null -w "bad token %{http_code}\n" $U/devices/me -H "authorization: Bearer shoo_$(printf 'A%.0s' $(seq 1 43))"   # 401
  GT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke G","mode":"guardian"}' | tok)
  PT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke P","mode":"protected"}' | tok)
  CODE=$(curl -s -X POST $U/family/code -H "authorization: Bearer $GT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["code"])')
  curl -s -o /dev/null -w "join %{http_code}\n" -X POST $U/family/join -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "{\"code\":\"$CODE\"}"
  SHOT=$(python3 -c 'import base64;print(base64.b64encode(bytes([0xff,0xd8,0xff,0xe0,0,16])+b"JFIF\0\1\1\0\0\1\0\1\0\0"+bytes([0xff,0xc0,0,17,8,0,10,0,10,3,1,0x22,0,2,0x11,1,3,0x11,1,0xff,0xd9])).decode())')
  D=shoo-smoke-$RANDOM.example
  BODY=$(python3 -c "import json;f=json.load(open('contracts/fixtures/blocked-92.json'));[f.pop(k) for k in ('id','verdict','screenshotUrl')];f['domain']='$D';f['url']='https://$D/login';f['screenshotBase64']='$SHOT';print(json.dumps(f))")
  ID=$(curl -s -X POST $U/scans -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "$BODY" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])'); echo "scan ${ID:0:8}"
  curl -s "$U/scans?owner=family" -H "authorization: Bearer $GT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("family items", len(d["items"]))'
  SURL=$(curl -s $U/scans/$ID -H "authorization: Bearer $GT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["screenshotUrl"])')
  curl -s -o /dev/null -w "screenshot %{http_code} %{content_type}\n" "$SURL"
  (cd backend/db && supabase db query --linked "select count(*) from storage_tombstones")   # 1 (log niat upload)
  curl -s -X POST $U/verdicts -H "authorization: Bearer $GT" -H 'content-type: application/json' -d "{\"scanId\":\"$ID\",\"value\":\"not_safe\"}" | python3 -c 'import sys,json;print("verdict", json.load(sys.stdin)["verdict"]["value"])'
  curl -s "$U/verdicts?domain=$D" -H "authorization: Bearer $PT" | python3 -c 'import sys,json;print("lookup", (json.load(sys.stdin)["verdict"] or {}).get("value"))'
  curl -s -o /dev/null -w "blocklist %{http_code}\n" $U/blocklist -H "authorization: Bearer $PT"
  for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} %{time_total}\n" "$U/verdicts?domain=$D" -H "authorization: Bearer $PT"; sleep 1.1; done > /tmp/shoo-verdicts-12.txt
  python3 -c "import statistics as s;r=[l.split() for l in open('/tmp/shoo-verdicts-12.txt')];t=sorted(float(x[1])*1000 for x in r);print('codes', sorted(set(x[0] for x in r)), 'p50 %.0f ms p95 %.0f ms max %.0f ms'%(s.median(t), t[int(0.95*len(t))-1], t[-1]))"
  curl -s -X DELETE $U/devices/me -H "authorization: Bearer $PT"; curl -s -X DELETE $U/devices/me -H "authorization: Bearer $GT"; echo
  curl -s -o /dev/null -w "screenshot after delete %{http_code}\n" "$SURL"
  (cd backend/db && supabase db query --linked "select domain, families, approved_at from blocklist_entries where domain = '$D'")   # 0 baris (antrean tanpa pendukung dihapus)
  echo "domain uji: $D"
  ```
  Harapan: header `nosniff`, HSTS, CSP `default-src 'none'`, `no-referrer`, `DENY`, `private, no-store`; `healthz/db 200`; `options 404`; `413 413`; `1`; `bad token 401`; `join 200`; `scan <8 hex>`; `family items 1`; `screenshot 200 image/jpeg`; tombstone `1`; `verdict not_safe`; `lookup not_safe`; `blocklist 200`; `codes ['200']` + p50/p95 (bandingkan dengan 435 / 1547 ms di fase 10, Smart Placement); `{"ok":true}{"ok":true}`; `screenshot after delete 404`; blocklist 0 baris. Tempel angka (tanpa token, tanpa `$SURL`). Tombstone upload tinggal sampai cron (umur < 10 menit saat delete, lalu dihapus run 03:00 WITA; objeknya sendiri sudah dihapus `DELETE /devices/me`).
- [ ] 6. Bukti run cron pertama (03:00 WITA = 19:00 UTC berikutnya):
  ```bash
  (cd backend/db && supabase db query --linked "select source, at from ops_heartbeat order by source")   # baris cron dengan at setelah 19:00 UTC
  (cd backend/db && supabase db query --linked "select count(*) from storage_tombstones")              # 0 (tombstone uji butir 5 terkuras)
  ```
  Plus dashboard → Workers → `shoo-api` → Observability / Logs (filter `"event":"retention"`): satu baris dengan jumlah baris terhapus, `failed: 0`. Kalau ada `retention_step_failed`, tempel nama step + error (tanpa path). Catat juga apakah run memakai < 50 subrequest (review database L6).
- [ ] 7. Pemakaian index setelah uji asap:
  ```bash
  (cd backend/db && supabase db query --linked "select indexrelname, idx_scan from pg_stat_user_indexes where indexrelname in ('verdicts_not_safe','scans_original_shot','scans_shot_path')")
  ```
  Hasil butir 1–3, 5, 7 (22 Okt 2026 ±02:10 WITA, coordinator; mandat malam Alief):
  - 1: `db push` → `20261022120000_hardening.sql`, `20261022130000_security_review.sql`. `shoo_api`: `statement_timeout=10s`, `idle_in_transaction_session_timeout=15s`, `lock_timeout=5s`; grant `service_role` di `public` = `0`; `storage_tombstones` = `0`.
  - 2: `RATE_KEY_SECRET` dibuat acak lewat pipe (tidak pernah tampil) → `Success!`; secret list: `RATE_KEY_SECRET`, `SCREENSHOT_URL_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`.
  - 3: deploy Version `bdc661e8-3776-4b8f-9e22-2ae2cd5c8745`, output memuat `schedule: 0 19 * * *`. Screenshot dashboard Triggers **belum** (butuh login Alief).
  - 5: header `private, no-store`, HSTS `max-age=31536000; includeSubDomains`, CSP `default-src 'none'; frame-ancestors 'none'`, `no-referrer`, `nosniff`, `DENY`; `healthz/db 200`; `options 404`; `413 413`; privacy `1`; `bad token 401`; `join 200`; `scan 92bc0964`; `family items 1`; `screenshot 200 image/jpeg`; tombstone `1`; `verdict not_safe`; `lookup not_safe`; `blocklist 200`; `codes ['200'] p50 252 ms p95 317 ms max 347 ms` (fase 10: p50 435 / p95 1547 ms → Smart Placement membantu; p95 masih 17 ms di atas target 300 ms); delete `{"ok":true}{"ok":true}`; `screenshot after delete 404`; blocklist untuk `shoo-smoke-11552.example` = 0 baris.
  - 7: `scans_original_shot` idx_scan 2, `scans_shot_path` 1, `verdicts_not_safe` 0 (belum ada jalur yang memakainya di uji asap ini).
  - 6: menunggu run cron 03:00 WITA — coordinator memeriksa setelahnya.
- [ ] 8. Ketik lagi: `Saya Alief, track be. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).` Agent memeriksa angka, membuka PR `feat/BE-retention-hardening` (stacked on #17), status `[r]`. Track be lalu selesai kode; G6 menunggu merge 07–12 + TODO D8.

## Catatan handoff

- **Fase 13 (app):** `faviconUrl` dari scan **jangan dimuat langsung** dari app Guardian (IP Guardian bocor ke situs penipu, review keamanan M7) — tampilkan ikon default; proxy lewat Worker kalau nanti dibutuhkan (usulan terpisah). Semua body JSON dikirim dengan `Content-Type: application/json` (usulan C21; backend belum mewajibkan). `DELETE /devices/me` bisa 500 kalau DB bermasalah: tombol hapus data di app harus menampilkan error + coba lagi (jangan menganggap terhapus).
- **TODO D8 (setelah merge 07–12):** deploy dari `main` + ulang butir 5. Secret `RATE_KEY_SECRET` tetap (jangan diganti: semua penghitung reset sekali, aman tetapi tidak perlu).
- **Kuota:** pantau log `backlog: true` dan `global_quota` di Observability; pemicu R2 = Storage > 700 MB (TODO E1).
- **Ditunda:** C21 (Content-Type + query/fragment URL), E6 (kontak + domain kebijakan privasi), E7 (hapus device tidak aktif), pin checksum/SHA Action (C2, setelah Umar memindahkan workflow).
