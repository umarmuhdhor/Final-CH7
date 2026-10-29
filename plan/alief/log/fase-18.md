# Log fase 18 — Page replica: EX-07 backend, DT-04 Detail

- **Status:** [ ] — rencana di PR plan `docs/alief-EX-07-replica-plan`; 18f/18a/18b belum mulai.
- **Model:** Claude Opus 5.5. 29 Okt 2026.
- **Rencana:** `log/fase-18-plan.md`, `fase-18-page-replica.md`.

## LANGKAH MANUAL 1 — infra R2 (sebelum merge 18a)

29 Okt 2026, Wrangler 4.151.3, akun Cloudflare Worker yang sama (login OAuth Alief).

| Langkah | Hasil |
|---|---|
| R2 subscription | Aktif, diklik Alief sendiri di dashboard ($0,00, kartu terdaftar) |
| `wrangler r2 bucket create shoo-replicas --location apac` | Dibuat 2026-10-29T04:09:24Z, storage class Standard. Tawaran Wrangler menambah binding ke `wrangler.jsonc` ditolak (binding `REPLICAS` masuk di 18a langkah 2) |
| `wrangler r2 bucket lifecycle add shoo-replicas expire-17d --expire-days 17` | Aktif: `expire-17d`, semua prefix, hapus objek setelah 17 hari. Rule bawaan "Default Multipart Abort Rule" (7 hari) tetap ada |
| `wrangler r2 bucket dev-url get` | "Public access via the r2.dev URL is disabled." |
| `wrangler r2 bucket domain list` | Tidak ada custom domain |
| `wrangler r2 bucket cors list` | Tidak ada konfigurasi CORS (API code 10059) |
| `wrangler r2 bucket info shoo-replicas` | location **APAC**, 0 objek, 0 B |

Belum: notifikasi billing/usage R2, cek izin token CI `CLOUDFLARE_API_TOKEN` untuk binding R2, ukur `storage.objects` Supabase (TODO D10).
