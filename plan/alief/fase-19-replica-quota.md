# Fase 19 — Kuota salinan halaman per keluarga + sinyal alert (TODO E8, review security 18a M1)

| Field | Nilai |
|---|---|
| Track | c (backend saja) |
| Branch | 19a `feat/EX-07-replica-family-quota` (dari `origin/main` saat mulai) |
| Prasyarat | 18a sudah di `main` (#182 merge 30 Okt 03:25 UTC). Disarankan: LANGKAH MANUAL 3 fase 18 (uji asap cloud) selesai dulu, supaya angka ukuran replica nyata tersedia untuk K2. Jawaban Alief untuk K2 (angka) dan K3 (cadangan) sebelum langkah 3 |
| Urutan | Jawaban K2/K3 → 19a (TDD) → review → PR (reviewer @umarmuhdhor) → merge (CI deploy) → uji asap cloud → fase 20 (= 18c) → fase 21 (monitoring) memakai antarmuka K5 |
| Requirement | TODO E8, review security 18a M1 (`log/fase-18.md`), EX-07 (bukti scan), SECURITY §2 T10, §3 P6, P13 |
| Model + reviewer ECC | Opus 5.5 · `ecc:security-reviewer` → `ecc:database-reviewer` → `ecc:typescript-reviewer` (berurutan, tidak paralel) |
| Fase berikutnya | Fase 20 (18c, hapus screenshot) · fase 21 (monitoring; mengonsumsi event K5) |

## Tujuan

**Masalah.** Kuota replica hari ini punya tiga lapis: per device 50/24 jam, per IP 300/24 jam, dan global 3000 upload + 500 MB/24 jam (`services/replicas.ts:30`, `http/rateLimit.ts:34`). Device gratis dibuat (`POST /devices` 10/jam/IP, `rateLimit.ts:12`; `routes/devices.ts:82`), dan keluarga cukup Guardian + satu Protected milik orang yang sama (`precheckReplica`, `db/repo/scans.ts:190-198`). Penyerang dengan beberapa IP dan beberapa keluarga palsu bisa menghabiskan kuota global; replica keluarga lain lalu dibuang `global_quota`/`global_bytes` (`services/replicas.ts:86`). Satu-satunya jejak hari ini adalah satu baris log `{"event":"replica_dropped","reason":…}` (`services/replicas.ts:40`) yang tidak dibaca siapa pun. App hanya melihat `pageReplicaUrl: null` → "No copy of this page" (18b).

**Hitungan biaya penyerang hari ini** (jalur termurah = byte): replica maksimal 307 200 byte → 500 MB ≈ 1707 upload ≈ **35 device** (50/device), ≥ 6 IP (300/IP), keluarga boleh 4 device (Guardian + 3 Protected, `init.sql:159-163`) → ±9 keluarga.

**Hasil akhir.**
1. Satu keluarga (Guardian + anggotanya) punya batas harian sendiri untuk upload dan byte, sehingga satu keluarga tidak bisa memakan lebih dari porsi kecil kuota global.
2. Sisa terakhir kuota global dicadangkan untuk keluarga "ringan" (K3), supaya banyak keluarga palsu yang berat pun tidak menutup jalan keluarga biasa.
3. Kuota global tetap sebagai pengaman terakhir (R2 Free, ARCHITECTURE §3 baris 67).
4. Alert tidak dibangun di sini. Fase 19 menetapkan dan menghasilkan sinyal log yang stabil (K5); fase 21 memilih kanal dan aturan alert.

Jujur soal batas: tanpa atestasi device (App Attest / DeviceCheck) tidak ada batas yang menghentikan penyerang dengan banyak IP. Fase ini menaikkan biaya serangan ±4× (tabel di K2), dan membuat serangan terlihat.

## Bacaan wajib

- `plan/alief/TODO.md` baris E8; `plan/alief/log/fase-18.md` (tabel review, M1; review database M2: kunci global `(6, 0)`); `fase-18-page-replica.md` K5
- `backend/api/src/services/replicas.ts` (`REPLICA_QUOTA`, `attachReplica`, `dropped`)
- `backend/api/src/db/repo/scans.ts:167-267` (`ReplicaSlot`, `ReplicaQuota`, `precheckReplica`, `reserveReplica`, `clearReplicaPath`)
- `backend/api/src/http/rateLimit.ts` (`replicaIp`, `createDevice`, `createDeviceAll`)
- `backend/api/src/routes/scans.ts:171-183` (replica di `waitUntil` setelah push)
- `backend/api/src/index.ts` (cron per jam), `backend/api/src/cron/notifications.ts`
- `backend/db/supabase/migrations/20261021130000_init.sql:24-30,143-169` (`family_links`, maks 3 Protected), `20261029100000_page_replicas.sql:22-24` (`scans_original_replica`)
- `backend/api/test/replicas.test.ts:213-257,395-447` (helper `family`, `fakeUploads`, test kuota), `test/log-hygiene.test.ts:46`
- `backend/API.md:485-493` (aturan replica), `plan/alief/ARCHITECTURE.md` §3, `SECURITY.md` §2 T10, §3 P6/P13

## Cek kelayakan (diverifikasi terhadap `main` 2720b13, 31 Okt 2026)

| # | Butir | Bisa? | Temuan dari kode | Tindakan |
|---|---|---|---|---|
| C1 | Definisi "keluarga" | Ya | `family_links.protected_id` primary key = satu Guardian per Protected (`init.sql:25`); index `family_links_guardian` (`init.sql:30`); maks 3 Protected per Guardian (`init.sql:159-163`, `errors.ts:27`). Guardian juga bisa jadi owner scan: `precheckReplica` menerima `guardian_id = owner` (`scans.ts:196`), `GET /scans?owner=family` memuat scan Guardian sendiri (`routes/scans.ts:203`) | Akar keluarga = `guardian_id` milik owner kalau owner Protected, selain itu owner sendiri. Anggota = akar + semua `protected_id` dengan `guardian_id = akar` (≤ 4 device). Dihitung dari relasi **saat ini**, tanpa kolom baru |
| C2 | Hitungan murah lewat index yang ada | Ya | `scans_original_replica on scans(created_at) include (owner_id, replica_bytes) where replica_bytes is not null` (`page_replicas.sql:24`). Hitungan per device (`scans.ts:224-226`) dan global (`:229-231`) sudah memindai baris 24 jam di index ini; jumlah barisnya dibatasi kuota global (≤ 3000) | Satu query dengan `count(*) filter (…)` untuk device, keluarga, global; `owner_id` + `replica_bytes` ada di `include`, jadi tetap index-only. **Tanpa migrasi, tanpa index baru.** Rencana query dicek dengan `explain (analyze, buffers)` di 3000 baris lokal (Verifikasi) |
| C3 | Atomik tanpa kunci baru | Ya | Upload baru sudah mengambil kunci owner `(6, hashtext(owner))` (`scans.ts:219`) lalu kunci global `(6, 0)` di sekitar hitungan global (`:228`). Anggota keluarga punya kunci owner berbeda, jadi hitungan keluarga di luar `(6, 0)` bisa terlampaui paralel | Pindahkan seluruh hitungan (device + keluarga + global) ke **sesudah** `(6, 0)` dalam satu statement. Semua upload baru sudah berseri di kunci ini, jadi hitungan keluarga ikut atomik. Kunci ditahan milidetik; `put` R2 tetap setelah commit. Round trip turun satu (hitungan device tidak lagi query terpisah). Harga: owner yang sudah lewat 50 kini juga mengambil `(6, 0)` sebentar |
| C4 | Churn anggota | Sebagian | Hitungan memakai relasi saat ini: Protected yang dilepas lalu dipasangkan ke Guardian lain membawa uploadnya ke keluarga baru, dan keluarga lama mendapat ruang lagi. Hapus device membebaskan kuota sebelum cron menghapus objek (sudah dicatat di `scans.ts:206-208`) | Diterima dan ditulis di komentar + DECISIONS. Dibatasi per device 50, `replicaIp` 300, `POST /devices` 10/jam/IP + 1000/hari global (`rateLimit.ts:12,15`; `routes/devices.ts:82,85,156`), lifecycle R2 17 hari. Alternatif kolom `replica_family` di `scans` ditolak (K1) |
| C5 | Privasi | Ya | Log drop hanya `reason` (`replicas.ts:38-40`, P6); `log-hygiene.test.ts:46` sudah menangkap `replica_dropped` | Tidak ada data pribadi baru: tanpa kolom, tanpa id di log. Event per jam (K5) hanya angka agregat |
| C6 | CPU Worker | Ya | Fakta cloud 31 Okt (`wrangler tail`): `POST /scans` 52–186 ms CPU, semua `outcome: ok`. Replica jalan di `waitUntil` setelah push (`routes/scans.ts:178-182`). Menunggu DB bukan CPU | Perubahan JS hanya satu query + beberapa perbandingan; tidak ada loop baru. Event per jam: satu query di cron jam `:05` (`index.ts:8,15-17`). CPU dicek ulang lewat `wrangler tail` setelah deploy (LANGKAH MANUAL 3) |
| C7 | Kontrak | Tidak perlu diubah | `contracts/api.md:59` tidak menyebut kuota; yang menyebut angka hanya `backend/API.md:489-492` (folder kita) | Hanya `backend/API.md`. Tidak ada issue ke Umar yang wajib; info opsional di #176 setelah merge |
| C8 | Sinyal ke app | Tidak di fase ini | App hanya melihat `pageReplicaUrl: null`; membedakan "dibuang kuota" butuh field kontrak baru (milik Umar) | Tidak ada perubahan app/kontrak (K6) |
| C9 | Kuota screenshot 300/hari global | Tidak perlu | `GLOBAL_DAILY_QUOTA = 300` (`services/scans.ts:18`), tanpa cek keluarga dan tanpa batas IP; drop di-log `console.log` (`:47`). Hanya build lama yang masih mengirim screenshot (extension `main` sejak #178 tidak lagi), dan fase 20 (18c) menghapusnya | Tidak diberi kuota keluarga (K7). Event `screenshot_dropped reason=global_quota` dicantumkan di antarmuka K5 sebagai opsional sampai 18c |
| C10 | Kanal alert | Belum terverifikasi | `observability.enabled = true`, `invocation_logs: false` (`wrangler.jsonc:11`): log JSON kita masuk Workers Logs. Batas Workers Logs di Free (jumlah event/hari, retensi) dan fitur alert berbasis log **belum terverifikasi** | Diputuskan di fase 21. Fase 19 hanya menjamin nama event + field stabil (dipaku test) |

Kesimpulan: semua butir bisa dikerjakan di `backend/` saja, tanpa migrasi, tanpa kontrak, tanpa app.

## Peta dampak (semua sisi)

| Sisi | Bagian | Status | Apa yang berubah / dijaga |
|---|---|---|---|
| Backend | `db/repo/scans.ts` `ReplicaQuota`, `ReplicaSlot`, `reserveReplica` | Ganti | Field `family`, `familyBytes`, `reserveUploads`, `reserveBytes`, `lightFamily`; slot `{ quota: "owner" \| "family" \| "family_bytes" \| "reserve" \| "global" \| "global_bytes" }`; satu query hitungan di bawah `(6, 0)` (C3) |
| Backend | `db/repo/scans.ts` fungsi baru `replicaUsage(sql, quota)` | Baru | Agregat 24 jam untuk event per jam (K5), tanpa id |
| Backend | `services/replicas.ts` `REPLICA_QUOTA`, `Drop`, `QUOTA_DROP` | Ganti | Angka K2/K3, alasan baru `family_quota`, `family_bytes`, `reserve`; komentar anggaran |
| Backend | `index.ts` cabang cron per jam | Ganti | Setelah `runNotifications`, panggil `logReplicaUsage` dalam `try/catch` sendiri (gagal tidak menggagalkan notifikasi) |
| Backend | `routes/scans.ts`, `precheckReplica`, `rateLimit.ts` | Tetap | Urutan murah dulu tetap: kill-switch → reuse/keluarga → `replicaIp` → decode → reserve |
| Backend | Screenshot (`services/scans.ts`) | Tetap → fase 20 | K7 |
| DB | Migrasi | Tidak ada | Index `scans_original_replica` + PK/index `family_links` cukup (C2) |
| DB | pgTAP | Tetap | `retention_indexes.test.sql:19-20` sudah memaku definisi `scans_original_replica`; suite penuh tetap hijau |
| Test | `test/replicas.test.ts` | Ganti | Test kuota keluarga, byte keluarga, cadangan, paralel lintas anggota, churn, urutan alasan; `expect(REPLICA_QUOTA)` diperbarui |
| Test | `test/log-hygiene.test.ts`, test cron baru | Ganti / Baru | Event baru tanpa UUID/domain/path; `replica_quota_usage` berisi field persis K5 |
| App | `ios/ShooApp/` | Tetap | Placeholder "No copy of this page" sudah ada (18b) |
| Extension / kontrak | `contracts/`, `ios/ShooExtension/` | Tetap | C7 |
| CI | `backend.yml` | Tetap | Deploy hanya lewat CI setelah merge |
| Privasi | Log, DB | Tetap | Tidak ada data baru (C5); halaman privasi tidak berubah (kuota bukan data) |
| Biaya Free | R2, Workers, Supabase DB | Tetap / lebih kecil | Kuota global tidak naik; satu query per jam di cron; `rate_limit_hits` tidak bertambah |
| Docs | `backend/API.md:489-492`, `ARCHITECTURE.md` §3 baris 67, `SECURITY.md` T10, `ref/R3` §4, `log/DECISIONS.md`, `TODO.md` E8 | Ganti | Saat implementasi (bukan di file fase ini) |

## Keputusan

**K1 — Cara menghitung keluarga.** (a) Dari relasi `family_links` saat ini, di query yang sama. (b) Kolom baru `scans.replica_family` (akar keluarga saat upload). Rekomendasi **(a)**: tanpa migrasi dan tanpa menyimpan siapa Guardian sebuah scan setelah putus hubungan (P13, data minimum). Kelemahan churn (C4) diterima karena per device 50 tetap berlaku dan pairing butuh device + kode baru.

**K2 — Angka (butuh jawaban Alief, TODO E8).** Rekomendasi, per 24 jam:

| Batas | Hari ini | Usulan |
|---|---|---|
| Per device | 50 | 50 (tetap) |
| Per keluarga (≤ 4 device) | — | **60 upload + 10 MB** |
| Per IP | 300 | 300 (tetap) |
| Global | 3000 + 500 MB | 3000 + 500 MB (tetap) |

Alasan: batas keluarga hanya menaikkan biaya kalau lebih kecil dari yang dihasilkan device termurahnya (keluarga 2 device sudah bisa 100 upload hari ini). Batas byte harus mengikat: 60 × 307 200 = 18,4 MB, jadi 10 MB-lah yang menghentikan replica ukuran maksimal (±34 per keluarga). HTML gzip biasa puluhan KB (fase 18 K5), jadi 60 × 50 KB = 3 MB jauh di bawah 10 MB. Angka final setelah data nyata (LANGKAH MANUAL 1: rata-rata dan p95 `replica_bytes`, upload per keluarga per hari sejak 30 Okt).

Biaya penyerang (jalur termurah) dengan K2 + K3: byte: 400 MB / 10 MB = 40 keluarga berat + 100 MB cadangan / (9 × 300 KB) ≈ 37 keluarga ringan = ±77 keluarga ≈ **154 device** (Guardian + 1 Protected), dibanding **35 device** hari ini; IP tetap ≥ 6 (`replicaIp`). 154 device = ±16 jam-IP `POST /devices` dan 15 % dari `createDeviceAll` 1000/hari.

**K3 — Cadangan untuk keluarga ringan (butuh jawaban Alief).** (a) Tanpa cadangan: hanya batas keluarga. (b) **20 % terakhir global (600 upload + 100 MB) hanya untuk keluarga dengan < 10 upload dalam 24 jam.** Rekomendasi **(b)**: tanpa (b), banyak keluarga palsu yang masing-masing di bawah batas tetap bisa menghabiskan global; dengan (b), keluarga biasa (sedikit halaman berisiko per hari) tetap bisa menyimpan bukti walau global hampir penuh. Biaya: dua perbandingan di query yang sama. Alasan drop baru `reserve`.

**K4 — Letak hitungan.** Satu statement setelah `pg_advisory_xact_lock(6, 0)` (C3), urutan cek: device (`quota`) → keluarga (`family_quota`, `family_bytes`) → global penuh (`global_quota`, `global_bytes`) → cadangan (`reserve`). Alasan pertama yang kena yang di-log. Tanpa kelas kunci baru (kelas 3–6 sudah dipakai).

**K5 — Alert: antarmuka untuk fase 21 (keputusan: tidak membangun kanal di fase 19).** Fase 19 menghasilkan dua sinyal; nama dan field dipaku test sehingga fase 21 bisa memasang aturan tanpa mengubah backend:

1. **Per drop** (sudah ada, diperluas): `console.error` `{"event":"replica_dropped","reason":"<R>"}`. `R` ∈ `disabled`, `no_storage`, `no_family`, `ip_quota`, `quota`, **`family_quota`**, **`family_bytes`**, **`reserve`**, `global_quota`, `global_bytes`, `scan_gone`, `upload_failed`, `invalid`, `too_large`, `not_gzip`, `error`. Tidak ada field lain (P6). Saran aturan fase 21: `global_quota`/`global_bytes` ≥ 1 per jam → alert; `reserve` atau `family_*` > 20 per jam → peringatan.
2. **Gauge per jam** (baru): cron `5 * * * *`, satu baris `{"event":"replica_quota_usage","level":"ok"|"reserve"|"full","uploads":n,"bytes":b,"uploadsMax":3000,"bytesMax":524288000,"families":k,"familiesAtCap":c,"topFamilyUploads":m,"topFamilyBytes":mb}`. Level log: `console.log` untuk `ok`, `console.warn` untuk `reserve` (pemakaian ≥ 80 %), `console.error` untuk `full`. Semua angka agregat, tanpa id. Gauge ini tetap jalan walau tidak ada drop (fase 21 bisa memakai "tidak ada gauge 2 jam" sebagai tanda cron mati).
3. Opsional sampai fase 20: `{"event":"screenshot_dropped","reason":"global_quota"}` (`console.log`, `services/scans.ts:47`), tidak diubah.

Alternatif ditolak: tabel hitungan di DB (data baru, tulisan di jalur panas); kirim email/push dari Worker (kanal = fase 21; push ke Guardian tentang kuota global tidak berguna bagi mereka).

**K6 — Sinyal ke app.** Tidak ada. Membedakan "dibuang karena kuota" butuh field kontrak (`contracts/`, Umar) dan tidak mengubah apa yang bisa dilakukan pengguna. Ditinjau ulang kalau fase 21 menunjukkan drop kuota sering terjadi.

**K7 — Screenshot.** Tidak diberi kuota keluarga: hanya build lama, global 300 sudah menjaga Supabase 1 GB, dan fase 20 menghapus jalur ini. Risiko diterima: penyerang lewat build lama bisa menghabiskan screenshot hari itu (hanya bukti build lama yang hilang).

**K8 — Atestasi device.** Di luar fase ini (butuh extension + kontrak, milik Umar). Dicatat di Catatan handoff sebagai satu-satunya penutup tuntas M1.

## Output

- `backend/api/src/db/repo/scans.ts`: `ReplicaQuota` + field K2/K3; `ReplicaSlot.quota` + `"family" | "family_bytes" | "reserve"`; `reserveReplica` dengan satu query hitungan setelah `(6, 0)` (CTE akar keluarga + anggota dari `family_links`, `count(*) filter`, `sum(replica_bytes) filter`); komentar churn (C4); `replicaUsage(sql)` untuk gauge (agregat per akar keluarga dari baris 24 jam).
- `backend/api/src/services/replicas.ts`: `REPLICA_QUOTA` baru, `Drop` + `QUOTA_DROP` baru, komentar anggaran; `logReplicaUsage(sql)` (level menurut K5).
- `backend/api/src/index.ts`: cabang cron per jam memanggil `logReplicaUsage` setelah `runNotifications`, `try/catch` terpisah, error di-log `{"event":"replica_usage_failed","error":…}` lewat `errorInfo`.
- Test: `test/replicas.test.ts` (kasus di Langkah 1), `test/replica-usage.test.ts` (baru), `test/log-hygiene.test.ts` (diperluas).
- Docs (di PR yang sama): `backend/API.md:489-492`, `plan/alief/ARCHITECTURE.md` §3 baris 67, `SECURITY.md` T10, `ref/R3` §4, `log/DECISIONS.md` (entri baru: K1–K8), `log/fase-19.md`, `TODO.md` E8 ditandai.
- Tidak ada migrasi, endpoint baru, perubahan kontrak, app, atau extension.

## Langkah kerja

### 19a — backend (`feat/EX-07-replica-family-quota`)

1. **Test dulu (merah)**, `superpowers:test-driven-development`, pola `fakeUploads` (`replicas.test.ts:253-257`) + `family()` (`:213`):
   - keluarga: Guardian + 3 Protected; 60 upload palsu tersebar di anggota → upload berikutnya dari anggota mana pun dibuang `family_quota`, tanpa `put`, scan tetap 201; keluarga lain tetap menyimpan.
   - Guardian sendiri sebagai owner ikut dihitung keluarga.
   - byte keluarga: 33 × 307 200 byte → replica kecil lolos, replica 307 200 byte berikutnya `family_bytes`.
   - cadangan: global terisi 2400 oleh keluarga lain; keluarga dengan 10 upload → `reserve`; keluarga dengan 0 upload → tersimpan; global 3000 → `global_quota` untuk semua. Sama untuk byte (400 MB).
   - urutan alasan: device penuh + keluarga penuh → `quota`.
   - paralel: 4 anggota satu keluarga dengan 59 upload → tepat satu tersimpan (bukti C3; dijalankan tanpa perubahan kunci harus merah).
   - churn: Protected dilepas dari Guardian A → upload lamanya tidak lagi dihitung A (perilaku yang diterima, dipaku supaya tidak berubah diam-diam).
   - reuse 24 jam tidak menghitung keluarga.
   - `expect(REPLICA_QUOTA)` memaku angka K2/K3.
   - `replica-usage.test.ts`: field persis K5, level `ok`/`reserve`/`full` → `console.log`/`warn`/`error`, tanpa UUID, domain, path; gagal query → `replica_usage_failed` dan notifikasi tetap jalan.
   - `log-hygiene.test.ts`: alasan baru tanpa id.
2. Kode `reserveReplica` (K4) + `REPLICA_QUOTA` + `QUOTA_DROP` → test langkah 1 hijau; suite `replicas` lama tetap hijau.
3. `replicaUsage` + `logReplicaUsage` + cabang cron `index.ts` → hijau.
4. Ukur query di Supabase lokal: 3000 baris `replica_bytes` + 1000 baris tanpa, `explain (analyze, buffers)` query hitungan → `Index Only Scan using scans_original_replica`, waktu dicatat di log fase.
5. Docs (Output) + `log/fase-19.md`.
6. Review berurutan: `ecc:security-reviewer` (M1 tertutup sejauh mungkin, P6, churn) → `ecc:database-reviewer` (kunci, rencana query, CTE) → `ecc:typescript-reviewer`. Perbaiki, lalu PR (reviewer @umarmuhdhor), body menyebut TODO E8 + M1.

## LANGKAH MANUAL

- [ ] 1. **Sebelum K2 diputuskan (Alief, read-only):** di Supabase cloud (`supabase db query --linked`): `select count(*), avg(replica_bytes), percentile_cont(0.95) within group (order by replica_bytes) from scans where replica_bytes is not null;` dan upload per akar keluarga per hari sejak 30 Okt (query `replicaUsage` versi SQL). Catat angka di `log/fase-19.md`, tanpa id.
- [ ] 2. Jawab K2 (angka) dan K3 (cadangan ya/tidak) di chat/plan; dicatat di DECISIONS.
- [ ] 3. Setelah review Umar: merge PR di menit :10–:40, tidak di 18:30–19:30 UTC (cron `0 19 * * *`). Deploy hanya lewat CI `backend.yml`; tunggu hijau, catat jam.
- [ ] 4. Uji asap cloud dengan `wrangler tail` terbuka: satu `POST /scans` dengan replica dari device uji yang punya keluarga → tersimpan; CPU `POST /scans` tetap tanpa `exceededCpu`; tunggu cron jam `:05` → satu baris `replica_quota_usage` dengan field K5.
- [ ] 5. Beri tahu fase 21 (plan): antarmuka K5 sudah hidup sejak jam deploy.

## Verifikasi

```bash
pnpm -C backend/api exec vitest run replicas replica-usage log-hygiene scans settings   # settings.test.ts menguji runNotifications
pnpm -C backend/api test            # suite penuh
pnpm -C backend/api run typecheck
(cd backend/db && supabase start && supabase test db)   # tanpa migrasi baru, regresi saja
psql "postgres://postgres:postgres@127.0.0.1:54322/postgres" -c "explain (analyze, buffers) <query hitungan>"   # langkah 4
bash plan/alief/qa/replica-e2e.sh   # wire replica lokal tetap lulus
```

## Kriteria selesai (DoD)

- [ ] Keluarga dengan 60 upload atau 10 MB (atau angka K2 final) dalam 24 jam → replica berikutnya dibuang `family_quota`/`family_bytes`, scan tetap 201, keluarga lain tidak terdampak (test).
- [ ] Cadangan K3: keluarga berat dibuang `reserve` saat global ≥ 80 %, keluarga ringan tetap tersimpan sampai global penuh (test), atau K3 ditolak dan dicatat.
- [ ] Hitungan keluarga tidak bisa terlampaui oleh anggota paralel (test merah tanpa kunci, hijau dengan kunci).
- [ ] Query hitungan memakai `Index Only Scan` pada `scans_original_replica` (output `explain` di log fase); tanpa migrasi.
- [ ] `replica_dropped` dan `replica_quota_usage` memakai nama + field persis K5, tanpa id (test + `log-hygiene`); gagal gauge tidak menggagalkan notifikasi (test).
- [ ] Suite penuh vitest + pgTAP + typecheck hijau; `qa/replica-e2e.sh` lulus.
- [ ] Cloud: deploy lewat CI, `POST /scans` tanpa `exceededCpu`, satu gauge per jam terlihat di `wrangler tail`.
- [ ] Docs + DECISIONS + TODO E8 diperbarui; review security tanpa HIGH terbuka.

## Risiko & rollback

- **Batas terlalu ketat untuk keluarga sah** → bukti hilang. Mitigasi: angka dari data (LANGKAH MANUAL 1), gauge `familiesAtCap` memperlihatkannya. Rollback: ubah konstanta `REPLICA_QUOTA` (satu baris, deploy lewat CI); darurat penuh tetap kill-switch `REPLICAS_ENABLED`.
- **Penyerang banyak IP** tetap bisa menghabiskan global (hanya ±4× lebih mahal). Diterima; sinyal K5 membuatnya terlihat; penutup tuntas K8.
- **Churn anggota** membebaskan kuota keluarga (C4). Diterima, dibatasi per device + per IP + pembuatan device.
- **Kunci `(6, 0)` lebih sering diambil** (juga oleh owner yang sudah penuh). Ditahan milidetik, upload replica ≤ 3000/hari; dicek reviewer database.
- **Batas Workers Logs Free** belum terverifikasi (C10): kalau gauge/log terpotong, fase 21 memilih jalur lain; backend tidak perlu diubah.
- Rollback kode = forward-fix atau revert PR (tidak ada migrasi, jadi revert aman).

## Catatan handoff

- Fase 21 (monitoring): konsumsi `replica_dropped` (alasan K5.1) dan `replica_quota_usage` (K5.2); pilih kanal (Workers Logs, email, dsb.) dan verifikasi batas Workers Logs Free. Jangan menambah field id ke event ini.
- Fase 20 (18c): hapus kuota screenshot bersama jalurnya; hapus juga baris opsional `screenshot_dropped` dari aturan fase 21.
- K8: App Attest / DeviceCheck untuk `POST /devices` atau `POST /scans` adalah usulan ke Umar (issue terpisah, template question) kalau fase 21 menunjukkan drop `global_*` nyata.
- Angka K2 ditinjau ulang setelah 2 minggu data gauge.
