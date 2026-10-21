# R4 — State machine: family code, join, verdict, retensi

## 1. Family code (GD-04)

```mermaid
stateDiagram-v2
  [*] --> Aktif: POST /family/code (guardian)
  Aktif --> Aktif: POST /family/join sukses (multi-pakai selama berlaku)
  Aktif --> Kedaluwarsa: now > expires_at (60 s)
  Aktif --> Diganti: guardian minta kode baru
  Kedaluwarsa --> [*]: dihapus cron (> 1 jam)
  Diganti --> [*]
```

Aturan:
- `POST /family/code` di dalam transaksi: hapus kode lama milik guardian, hapus kode kedaluwarsa yang bentrok, pilih 4 digit acak (`crypto.getRandomValues`) yang tidak sedang aktif (maks 20 percobaan, lalu 503 `code_unavailable`, kode baru di R3 §1), insert `expires_at = now() + 60 s`.
- App Guardian meminta kode baru otomatis saat hitung mundur 0 (GD-04 "ganti tiap 60 detik"), hanya selama layar Family code terbuka.
- Kode tetap bisa dipakai beberapa Protected selama berlaku, sampai keluarga penuh.

## 2. Join (PR-01, PR-03)

```text
POST /family/join {code}  (protected)
 1. Cek batas percobaan (R3 §5) → 429 too_many_attempts
 2. Sudah punya guardian → 409 already_connected
 3. Kode tidak ada → catat gagal, 404 code_invalid
 4. Kode kedaluwarsa → catat gagal, 410 code_expired
 5. Transaksi: advisory lock guardian → count links ≥ 3 → 409 family_full
 6. Insert family_links, catat sukses
 7. 200 { guardian: { deviceId, name, avatarId } }
```

Disconnect: `DELETE /family/members/{id}` (guardian) atau `DELETE /family/guardian` (protected) menghapus baris `family_links`. Akses Guardian ke scan lama langsung hilang (SECURITY T12). Verdict yang sudah dibuat tetap milik pemilik scan.

## 3. Scan → push (GD-06)

```text
POST /scans (device X)
 1. Validasi + simpan scan (owner = X)
 2. Screenshot: lolos batas ukuran, dedupe, kuota → upload; selain itu dibuang
 3. Respons 201 { id }
 4. waitUntil: kalau X mode protected dan punya guardian G dengan apns_token:
      (lookup sebelum respons; maks 10 push / 10 menit per G) kirim push ke G lewat ApnsSender langsung
      (D-alief-B01/B11; teks bahasa G), 410 → kosongkan apns_token (compare-and-clear), tulis push_log (kode hasil saja)
    kalau X mode guardian: tidak ada push (dia melihat popup sendiri)
```

## 4. Verdict → unblock (GD-07, EX-06)

```mermaid
stateDiagram-v2
  [*] --> TanpaVerdict: scan blocked tersimpan
  TanpaVerdict --> Safe: Guardian "It's safe"
  TanpaVerdict --> NotSafe: Guardian "Not safe"
  Safe --> NotSafe: Guardian berubah pikiran (upsert)
  NotSafe --> Safe: Guardian berubah pikiran (upsert)
```

- Verdict berlaku per `(owner_id, domain)` (kontrak). Semua scan **blocked** pemilik itu di domain yang sama ikut menampilkan verdict tersebut; scan warning tetap `verdict: null`.
- `safe` → extension Protected (polling `GET /verdicts?domain=` tiap 5 s) membuka halaman. Target: `GET /verdicts` mencerminkan keputusan ≤ 1 s setelah `POST /verdicts` (cache Hyperdrive dimatikan, D-alief-17); halaman terbuka ≤ 10 s ujung ke ujung. Diukur di Worker cloud, bukan hanya lokal. Halaman yang diblokir tidak pernah terbuka otomatis tanpa verdict.
- `not_safe` → Detail menampilkan "Verified scam by [nama]"; kalau layak (R2 §5), domain masuk antrean `blocklist_entries` dan baru muncul di `GET /blocklist` (layer 1 detector Imelda) setelah review manual (D-alief-25).
- Tidak ada layar konfirmasi di app (GD-07). App menerapkan optimistic update lalu rollback kalau request gagal, dengan pesan error.

## 5. Retensi (harian, Cron Worker `0 19 * * *` UTC = 03:00 WITA)

```text
0. Upsert `ops_heartbeat('cron')` lebih dulu (sinyal anti-pause tidak bergantung pada retensi)
1a. Scan tanpa screenshot: chunk 2000 (maks 25), satu transaksi per chunk, tanpa Storage
1. Ambil batch 100 scan created_at < now() - 14 hari, urut (created_at, id) — tanpa transaksi (D-alief-B12)
2. Path yang tidak dipakai scan di luar batch (dedupe!) → satu `DELETE /storage/v1/object/screenshots` dengan `prefixes`; gagal → baris tetap, dicoba besok
3. Satu transaksi (`lock_timeout`, `statement_timeout` lokal): `verdicts.scan_id = null`, lalu hapus scan batch; ulangi sampai kosong atau 10 batch (batch ke-10 penuh → `backlog: true`)
4. Tombstone Storage (maks 500, umur > 10 menit, tidak ditunjuk scan): hapus objek, lalu tombstone-nya; batch gagal → `attempts`/`last_try_at`, lanjut
5. Hapus family_codes, join_attempts, push_log, rate_limit_hits lama (R2 §6)
6. Log hanya jumlah; tiap langkah berdiri sendiri, error pertama dilempar di akhir (Cron Events)
```

Uji lokal: `curl "http://localhost:8787/cdn-cgi/local/scheduled?cron=0+19+*+*+*"` saat `wrangler dev` jalan.

Karena dedupe screenshot memakai ulang `screenshot_path`, objek hanya dihapus kalau tidak ada scan tersisa yang menunjuk ke path itu.
