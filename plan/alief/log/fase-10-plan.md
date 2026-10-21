# Rencana fase 10 — Verdicts + blocklist dari verdict (feat/BE-verdicts, stacked on #13)

Sumber: `fase-10-be-verdicts.md`, `contracts/api.md` Verdicts + Blocklist, fixture `blocked-verified-scam.json` + `blocked-marked-safe.json`, R2 §5, R3 §3–§5, R4 §4, SECURITY T5/T10 + §3 P1–P13 (D-alief-40), D-alief-25.

1. **Migrasi** `verdicts.global_eligible boolean not null default false` + index parsial `(domain) where value = 'not_safe' and global_eligible` untuk hitung `families`; pgTAP.
2. **Allowlist statis** `backend/api/src/data/allowlist.ts`: domain resmi bank/e-wallet/layanan publik Indonesia + domain populer + sufiks pemerintah/pendidikan (`go.id`, `ac.id`, …). Cocok = sama atau subdomain.
3. **`POST /verdicts {scanId, value}`** (guardian; Protected → 403 `forbidden`), body ≤ 1 KB, 60/menit per Guardian. Satu transaksi + advisory lock per domain: scan tidak ada → 404; bukan milik saya dan bukan Protected aktif saya → 403 `verdict_not_allowed`; bukan `blocked` → 409 `verdict_not_allowed`; upsert `(owner_id, domain)` dengan `by_name` = nama Guardian sekarang, `global_eligible` snapshot (R2 §5 butir 1); hitung ulang `families` (butir 2–3; entri yang disetujui/dihapus tidak disentuh selain `families`) → `{ verdict }`.
4. **`GET /verdicts?domain=`** (semua mode): normalisasi (trim, lowercase, tanpa `www.`), regex domain yang sama dengan `POST /scans`, `{ verdict | null }` untuk owner = saya; 10 req / 10 s per device (DB, `Retry-After`). R3 §5 tabel lama "1 / 2 s memori" diselaraskan ke 10/10 s (T10, file fase).
5. **`GET /blocklist`** sudah membaca entri disetujui sejak fase 07; test integrasi verdict → antrean → disetujui → muncul / dihapus → `removed[]`.
6. **ScanResult**: verdict dari data asli lewat `POST /verdicts`, cocok dengan dua fixture; scan warning di domain ber-verdict tetap `null`.
7. Test wajib dari file fase (semua butir) + privasi: respons `private, no-store`, tanpa log domain/id.
8. Review berurutan: security (T5, T10) → TypeScript → database → cek P1–P13. LANGKAH MANUAL: migrasi + deploy + uji cloud 20× `GET /verdicts` (p95 < 300 ms, `safe` di request pertama) + setujui satu domain uji → `[m]`. C8 ditulis (draf).
