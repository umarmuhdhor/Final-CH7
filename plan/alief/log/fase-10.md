# Log fase 10 — Verdicts + blocklist dari verdict

| Field | Nilai |
|---|---|
| Status | `[m]` berhenti di LANGKAH MANUAL (migrasi + deploy + uji cloud). Belum ada PR |
| Track / branch | be · `feat/BE-verdicts` (worktree sesi `happy-mcnulty-9fc732`) |
| Basis | ditumpuk di atas `feat/BE-scans` (PR #13, stacked on #11) → PR nanti menulis "Stacked on #13" |
| Mulai | 21 Okt 2026 ±23:55 WITA |
| Model | Opus 5.5 |

## Ringkasan rencana

Rencana lengkap: [`fase-10-plan.md`](fase-10-plan.md). `POST /verdicts` (Guardian, satu transaksi + lock per domain, snapshot kelayakan blocklist), `GET /verdicts?domain=` (semua mode, 10/10 s), antrean `blocklist_entries` → review manual → `GET /blocklist`.

## Checklist langkah kerja

- [x] 1. Migrasi `verdicts.global_eligible` + index parsial `verdicts_eligible_domain` (+ pgTAP `verdicts.test.sql`)
- [x] 2. Allowlist statis `backend/api/src/data/allowlist.ts` (bank, e-wallet, layanan publik, sufiks `go.id`/`ac.id`/…, situs populer; subdomain ikut cocok)
- [x] 3. `POST /verdicts`: 404 / 403 `verdict_not_allowed` / 409 `verdict_not_allowed`, Protected → 403 `forbidden`, upsert `(owner_id, domain)`, `by_name` = nama Guardian sekarang, hitung ulang `families`, 60/menit
- [x] 4. `GET /verdicts?domain=`: normalisasi, `{ verdict | null }` untuk owner = saya, 10/10 s + `Retry-After`
- [x] 5. `GET /blocklist`: integrasi verdict → antrean → disetujui → muncul; dihapus → `removed[]`, tidak dihidupkan lagi oleh verdict baru
- [x] 6. ScanResult memakai verdict asli; cocok dua fixture
- [x] 7. Review berurutan: security (T5, T10) → TypeScript → database → cek P1–P13 (tabel di bawah)
- [ ] 8. LANGKAH MANUAL (di bawah) — menunggu Alief

## File dibuat / diubah

- `backend/db/supabase/migrations/20261021180000_verdicts.sql`, `tests/verdicts.test.sql`
- `backend/api/src/routes/verdicts.ts`, `src/db/repo/verdicts.ts`, `src/data/allowlist.ts`, `src/http/{errors,rateLimit,validate}.ts`, `src/routes/scans.ts` (regex domain dibagi), `src/app.ts`
- `backend/api/test/verdicts.test.ts`
- `plan/alief/log/{fase-10,fase-10-plan,DECISIONS}.md`, `PROGRESS.md`, `TODO.md` (D4, C8), `ref/R3` §5, `backend/README.md`

## Hasil verifikasi (lokal)

- `(cd backend/db && supabase db reset && supabase test db)` → **PASS, 77 test** (5 file; baru `verdicts.test.sql`: kolom `global_eligible`, default, index `verdicts_eligible_domain`, CHECK `verdicts_eligible_not_safe`).
- `pnpm -C backend/api exec tsc --noEmit --noUnusedLocals` → bersih. `pnpm -C backend/api test` → **16 file, 242 test lulus** (baru: `verdicts.test.ts` 47, `allowlist.test.ts` 13).
- Semua test wajib file fase ada: Protected → 403; Guardian lain → 403 `verdict_not_allowed`; scan tidak ada → 404; warning → 409; keputusan terakhir menang; berlaku untuk scan lain domain sama pemilik sama, tidak untuk pemilik lain; `www.Example.com` = `example.com`; not_safe Protected → antrean `approved_at` null, tidak di `/blocklist`; disetujui → muncul, `nextSince` maju; verdict lama disetujui belakangan muncul di refresh inkremental; Guardian + scan palsu sendiri → tanpa entri; Guardian + Protected penyerang → menunggu review; allowlist tidak pernah antre; `removed_at` → hilang dari penuh, muncul di `removed[]`; warning di domain ber-verdict tetap `null`. **Diubah** (D-alief-B10 d, privasi): "disconnect setelah verdict → `global_eligible` tetap" diganti "disconnect menghapus verdict Guardian lama; entri yang disetujui tetap tersaji".
- Cloud: belum (LANGKAH MANUAL di bawah).

## DoD

- [x] Semua test hijau; bentuk `Verdict` cocok fixture (`verdicts.test.ts` "ScanResult verdicts match the two contract fixtures").
- [ ] Uji cloud langkah 6: `safe` terlihat di `GET /verdicts` pertama setelah POST, p95 < 300 ms (LANGKAH MANUAL 3).
- [x] C8 tertulis (TODO C8, draf; dikirim Alief setelah uji cloud).

## Review

Berurutan, satu per satu (aturan Alief).

| Reviewer | CRITICAL | HIGH | MEDIUM | Diperbaiki | Commit |
|---|---|---|---|---|---|
| `ecc:security-reviewer` | 0 | 1 | 4 | H: verdict + nama/id Guardian lama tetap terbaca setelah disconnect (P13) → verdict dihapus saat putus hubungan dan `DELETE /devices/me`, `families` dihitung ulang. M: link dibaca `for share` (urutan lock link → domain); `families` dihitung ulang saat device dihapus; maks 10 domain baru per Guardian per 24 jam; lookup 30/10 s. L: FK race → 404; sufiks publik/host bersama tidak antre | `2a8f6b9` |
| `ecc:typescript-reviewer` | 0 | 0 | 2 | M: lock antrean per Guardian (`(5, guardian)`) agar batas tahan paralel (test 15 paralel → 10); baris antrean tanpa dukungan dan belum disetujui dihapus (domain riwayat browsing tidak disimpan tanpa guna). L: urutan lock domain per kunci hash, kurung di fragmen `where`, `PostgresError`, retry sekali untuk 40P01/40001, titik akhir domain ditoleransi, daftar sufiks diperluas, `ISO_MS` dibagi | `4e19dde` |
| `ecc:database-reviewer` | 0 | 0 | 2 | M: konfirmasi ulang domain yang sudah antre tidak gugur karena batas. L: upsert/update tanpa tulis ulang sia-sia; CHECK `global_eligible` hanya untuk `not_safe` (+ pgTAP). M lain (deadlock cron retensi vs `deleteDevice`) → catatan handoff fase 12 | commit fase 10 terakhir |

Ditunda (dicatat): 403 vs 404 membuka keberadaan UUID scan (urutan kontrak); `families` bisa digelembungkan banyak pasangan device (review manual = gerbang; SECURITY T5); index `verdicts_not_safe` mungkin tidak terpakai lagi (cek `pg_stat_user_indexes` di fase 12); daftar sufiks publik subset PSL.

### Cek privasi Apple P1–P13 (D-alief-40)

| # | Hasil | Bukti |
|---|---|---|
| P1 Privacy manifest | N/A (tanpa perubahan iOS) | — |
| P2 Label privasi | OK: tidak ada jenis data baru (domain = Browsing History, nama Guardian = Name, sudah ada); tanpa SDK pihak ketiga | — |
| P3 Hapus data | OK: `DELETE /devices/me` menghapus verdict milik/dibuat device, menghitung ulang antrean, menghapus baris antrean tanpa dukungan | `verdicts.test.ts` "DELETE /devices/me …" |
| P4 Keychain | N/A | — |
| P5 ATS | OK (HTTPS Worker) | — |
| P6 Log | OK: route baru tidak menulis log; error handler hanya pola route; domain di query tidak tercatat (invocation logs mati, D-alief-B09) | `src/routes/verdicts.ts` |
| P7 Izin | N/A | — |
| P8 Pasteboard | N/A | — |
| P9 Screenshot di app | N/A | — |
| P10 Push | N/A (verdict tidak mengirim push) | — |
| P11 Export compliance | N/A | — |
| P12 Kebijakan privasi | Catatan untuk fase 12/16: domain yang di-Not safe dari keluarga terhubung bisa masuk antrean review global (tanpa id/nama), disetujui manual | — |
| P13 Hapus = langsung hilang | **Pelanggaran ditemukan (TINGGI) dan diperbaiki:** setelah putus hubungan, verdict + nama/id Guardian lama tetap terbaca oleh member → sekarang dihapus seketika. Antrean domain tanpa dukungan dihapus. Respons `private, no-store` (default middleware) | `verdicts.test.ts` "disconnect (…)", `cache-headers.test.ts` |

## Deviasi

- D-alief-B10 (detail fase 10).

## LANGKAH MANUAL (Alief) — migrasi + deploy + uji cloud fase 10

Dari root worktree, branch `feat/BE-verdicts`. Tidak ada secret baru. Domain uji memakai `.example` (tidak pernah domain nyata) dan dihapus lagi dari blocklist di akhir.

- [ ] 1. Migrasi:
  ```bash
  (cd backend/db && supabase migration list --linked)   # 20261021180000 hanya di kolom Local
  (cd backend/db && supabase db push)
  ```
- [ ] 2. Deploy:
  ```bash
  pnpm -C backend/api run deploy
  ```
- [ ] 3. Uji cloud (verdict langsung terlihat + latensi):
  ```bash
  U=https://shoo-api.afindo-mi01.workers.dev
  tok() { python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])'; }
  GT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke G","mode":"guardian"}' | tok)
  PT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke P","mode":"protected"}' | tok)
  CODE=$(curl -s -X POST $U/family/code -H "authorization: Bearer $GT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["code"])')
  curl -s -o /dev/null -X POST $U/family/join -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "{\"code\":\"$CODE\"}"
  D=shoo-smoke-$RANDOM.example
  BODY=$(python3 -c "import json;f=json.load(open('contracts/fixtures/blocked-92.json'));[f.pop(k) for k in ('id','verdict','screenshotUrl')];f['domain']='$D';f['url']='https://$D/login';print(json.dumps(f))")
  ID=$(curl -s -X POST $U/scans -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "$BODY" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
  curl -s "$U/verdicts?domain=$D" -H "authorization: Bearer $PT"; echo
  curl -s -X POST $U/verdicts -H "authorization: Bearer $GT" -H 'content-type: application/json' -d "{\"scanId\":\"$ID\",\"value\":\"safe\"}" | python3 -c 'import sys,json;print("post:", json.load(sys.stdin)["verdict"]["value"])'
  curl -s "$U/verdicts?domain=$D" -H "authorization: Bearer $PT" | python3 -c 'import sys,json;print("first get:", (json.load(sys.stdin)["verdict"] or {}).get("value"))'
  for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} %{time_total}\n" "$U/verdicts?domain=$D" -H "authorization: Bearer $PT"; sleep 1.1; done > /tmp/shoo-verdicts.txt
  python3 -c "import statistics as s;r=[l.split() for l in open('/tmp/shoo-verdicts.txt')];t=sorted(float(x[1])*1000 for x in r);print('codes', sorted(set(x[0] for x in r)), 'p50 %.0f ms p95 %.0f ms max %.0f ms'%(s.median(t), t[int(0.95*len(t))-1], t[-1]))"
  curl -s -X POST $U/verdicts -H "authorization: Bearer $GT" -H 'content-type: application/json' -d "{\"scanId\":\"$ID\",\"value\":\"not_safe\"}" > /dev/null
  curl -s -D - -o /dev/null "$U/verdicts?domain=$D" -H "authorization: Bearer $PT" | grep -i '^cache-control'
  echo "domain uji: $D"
  ```
  Harapan: `{"verdict":null}`; `post: safe`; `first get: safe`; `codes ['200'] p95 < 300 ms` (sleep 1.1 s menjaga di bawah 10/10 s); `cache-control: private, no-store`. Tempel angka (tanpa token).
- [ ] 4. Review antrean + setujui domain uji, cek `/blocklist`, lalu hapus lagi:
  ```bash
  (cd backend/db && supabase db query --linked "select domain, families, approved_at from blocklist_entries where domain = '$D'")
  (cd backend/db && supabase db query --linked "update blocklist_entries set approved_at = clock_timestamp(), approved_by = 'alief' where domain = '$D'")
  curl -s "$U/blocklist" -H "authorization: Bearer $PT" | python3 -c "import sys,json;print('$D' in [d['domain'] for d in json.load(sys.stdin)['domains']])"
  (cd backend/db && supabase db query --linked "update blocklist_entries set removed_at = now() where domain = '$D'")
  curl -s "$U/blocklist" -H "authorization: Bearer $PT" | python3 -c "import sys,json;print('$D' in [d['domain'] for d in json.load(sys.stdin)['domains']])"
  curl -s -X DELETE $U/devices/me -H "authorization: Bearer $PT"; curl -s -X DELETE $U/devices/me -H "authorization: Bearer $GT"; echo
  ```
  Harapan: satu baris `families 1`, `approved_at` kosong; lalu `True` (muncul setelah disetujui); `False` (hilang setelah `removed_at`); `{"ok":true}{"ok":true}`.
- [ ] 5. Kirim TODO C8 ke Umar (teks siap). Ketik lagi: `Saya Alief, track be. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).` Agent memeriksa angka, membuka PR `feat/BE-verdicts` (stacked on #13), lalu fase 11.

## Catatan handoff

- Fase 11: `POST /verdicts` tidak mengirim push (kontrak hanya push untuk scan). `decideVerdict` mengembalikan verdict saja.
- Fase 12: retensi tidak menghapus `verdicts` (D-alief-14); `scan_id` jadi null lewat `on delete set null`. **Urutan lock:** cron harus `update verdicts set scan_id = null where scan_id in (…)` **dulu**, baru `delete from scans` (urutan verdict → scan seperti `decideVerdict` dan `deleteDevice`), batch kecil + `lock_timeout`; tanpa itu bisa deadlock dengan `DELETE /devices/me` (review database fase 10 M1). Cek `pg_stat_user_indexes` untuk `verdicts_not_safe` (mungkin dihapus). Baris `rate_limit_hits` bucket `verdicts_get` tumbuh cepat (polling 5 s) → retensi 1 hari wajib.
- D9 (review antrean harian) aktif sejak deploy fase 10.
