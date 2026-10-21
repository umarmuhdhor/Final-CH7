# Fase 10 — Verdicts per domain + blocklist dari verdict

| Field | Nilai |
|---|---|
| Track | be |
| Branch | `feat/BE-verdicts` |
| Prasyarat | 09 |
| Requirement | Mandat Fase B Verdicts (`POST /verdicts` per domain, `GET /verdicts?domain=`), Blocklist; EX-06 (sisi server), GD-07 (sisi server) |
| Model | Opus 5.5 |
| Fase berikutnya | 11 |

## Tujuan

Guardian memutuskan Safe / Not safe untuk satu domain milik pemilik scan, extension Protected bisa polling hasilnya untuk membuka layar blokir, dan domain Not safe masuk blocklist layer 1.

## Bacaan wajib

- `contracts/api.md` Verdicts + Blocklist, fixture `blocked-verified-scam.json`, `blocked-marked-safe.json`
- `ref/R2` verdicts, `blocklist_entries` + §5, `ref/R3` §3–§5, `ref/R4` §4, `SECURITY.md` T5, T10, `log/DECISIONS.md` D-alief-25

## Langkah kerja

1. `POST /verdicts { scanId, value }` (guardian): scan harus milik saya atau Protected aktif saya (selain itu 404), status `blocked` (selain itu 409 `verdict_not_allowed`), dalam satu transaksi: upsert `(owner_id, domain)` dengan `global_eligible` (R2 §5 butir 1) lalu upsert/hitung ulang `blocklist_entries` (butir 2–3) → `{ verdict }`. Migrasi: kolom `verdicts.global_eligible` + tabel `blocklist_entries` (+ grant `shoo_api`, pgTAP).
2. `GET /verdicts?domain=` (semua): normalisasi domain (lowercase, tanpa `www.`), `{ verdict: Verdict | null }` untuk `owner = me`. Rate limit 1 req/2 s.
3. `GET /blocklist` membaca `blocklist_entries` yang sudah disetujui (R2 §5 butir 5). Kalau Umar/Imelda sudah menjawab C6, ikuti jawabannya (mis. persetujuan otomatis). Usulan `removed` (D-alief-18) ditulis di PR. Query review (R2 §5 butir 4) ditulis di `backend/README.md` sebagai prosedur LANGKAH MANUAL berkala.
4. Mapping `verdict` ke ScanResult (fase 09) memakai data asli, hanya untuk scan `blocked`; test cocok dengan dua fixture verdict.
5. `ecc:security-reviewer` fokus T5, T10.
6. LANGKAH MANUAL deploy + **uji cloud**: buat Guardian + Protected uji, join, `POST /scans` blocked, `POST /verdicts safe`, lalu ukur `GET /verdicts?domain=` sebagai Protected 20× melalui Worker cloud (bukan lokal) → harus `safe` di request pertama (≤ 1 s setelah POST) dan p95 < 300 ms. Tempel angka di log. Lalu setujui satu domain uji lewat SQL editor dan pastikan muncul di `GET /blocklist` cloud. Kirim C8 ke Umar (G4).

## Verifikasi

```bash
(cd backend/db && supabase start && supabase db reset && supabase test db)
pnpm -C backend/api exec vitest run verdicts blocklist
```

Test wajib: Protected → 403; Guardian lain → 404; scan warning → 409; safe lalu not_safe → keputusan terakhir menang; verdict berlaku untuk scan lain di domain sama milik pemilik sama; tidak berlaku untuk pemilik lain; `www.Example.com` = `example.com`; not_safe atas scan Protected → entri `blocklist_entries` dengan `approved_at` null dan **tidak** muncul di `/blocklist`; setelah `approved_at` diisi → muncul, `nextSince` maju; verdict lama (sebelum `since`) yang baru disetujui tetap muncul di refresh inkremental; **Guardian baru + scan palsu miliknya sendiri + not_safe → tidak ada entri**; **Guardian + Protected milik penyerang yang sama → entri tetap menunggu review, tidak terkirim**; disconnect setelah verdict → `global_eligible` tetap (snapshot); domain allowlist tidak pernah masuk antrean; `removed_at` terisi → hilang dari hasil penuh; scan warning di domain ber-verdict tetap `verdict: null`.

## Kriteria selesai (DoD)

- [ ] Semua test hijau; bentuk `Verdict` cocok fixture.
- [ ] Uji cloud langkah 6: `safe` terlihat di `GET /verdicts` pertama setelah POST (cache Hyperdrive mati), p95 < 300 ms — bersama polling 5 s memenuhi "halaman terbuka ≤ 10 s".
- [ ] C6 dan C8 tertulis.
