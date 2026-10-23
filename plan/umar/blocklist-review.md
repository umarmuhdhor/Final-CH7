# Runbook review antrean blocklist (C6)

> Dibuat 23 Okt 2026 · Pemilik: Umar (lead) · Bersama: Alief (Team App, pemilik `backend/`)
> Status: **draf**, menunggu kesepakatan jadwal dan query dengan Alief (issue: _belum dibuat_)
> Sumber: `contracts/api.md` (Blocklist), `docs/design/blocklist.md`, migrasi `backend/db/supabase/migrations/`
> (`20261021130000_init.sql`, `…150000_blocklist_times.sql`, `…180000_verdicts.sql`, `20261022120000_hardening.sql`,
> `…130000_security_review.sql`), `backend/api/src/db/repo/verdicts.ts`, `backend/api/src/data/allowlist.ts`,
> `plan/alief/fase-10-be-verdicts.md`, `plan/alief/log/fase-10.md`, `plan/alief/ref/R2-skema-db.md` §5,
> `plan/alief/SECURITY.md` T5, `plan/alief/log/DECISIONS.md` D-alief-25, `docs/mandates/umar.md` C6.
> Prasyarat dicek: fase 10 backend merge di PR #15 (21 Okt 2026).

## 1. Tujuan

Domain di `GET /blocklist` diblokir (skor 100, layer 1) di **semua** iPhone pengguna Shoo. Karena siapa pun bisa
mendaftar tanpa login, domain hanya boleh masuk daftar global setelah orang memeriksanya. Review ini memastikan:

1. Situs resmi atau populer (bank, e-wallet, marketplace, pemerintah, `detector/data/brands.json`) **tidak pernah**
   tersaji di `GET /blocklist`.
2. Domain scam yang sudah dikonfirmasi keluarga masuk daftar global dalam hitungan hari, bukan minggu.
3. Kesalahan (domain sah yang terlanjur disetujui) dicabut cepat lewat `removed_at`.

Bukan tujuan: mengubah kode backend, otomatisasi persetujuan, atau review `/public-blocklist` (Team AI, E-3/E-4 ditunda).

## 2. Alur: dari verdict sampai iPhone

```
Guardian tekan "Not safe" (GD-07)
  └─ POST /verdicts { scanId, value: "not_safe" }          backend/api/src/db/repo/verdicts.ts → decideVerdict()
       global_eligible = true hanya kalau SEMUA benar (snapshot saat keputusan):
         • scan milik device bermode protected, dan Guardian ini terhubung ke pemiliknya (family_links)
         • scan berstatus blocked (skor ≥ 80), kalau tidak 409
         • domain bukan allowlist (allowlist.ts: resmi + populer, subdomain ikut) dan bukan sufiks publik /
           host bersama persis (co.id, github.io, vercel.app, …)
         • Guardian ini belum menaruh 10 domain baru di antrean dalam 24 jam terakhir
       └─ recountFamilies(): families = jumlah Guardian berbeda dengan verdict not_safe layak untuk domain itu
            families > 0 → INSERT blocklist_entries(domain, families), approved_at = null   ← ANTREAN
            families = 0 → baris antrean yang belum diputuskan DIHAPUS; baris disetujui/dicabut tetap (families = 0)

Reviewer (Umar/Alief) di SQL editor Supabase, sebagai role postgres
  └─ UPDATE … set approved_at, approved_by                   trigger blocklist_entries_times → clock_timestamp()
       Worker (role shoo_api) TIDAK bisa menulis approved_at/approved_by/removed_at (grant + RLS, fase 12)

GET /blocklist?since=   backend/api/src/db/repo/blocklist.ts
  └─ hanya approved_at not null and removed_at null → domains[]; removed_at > since → removed[]
     Cache-Control: private, max-age=300
       └─ extension lists.js: incremental tiap 1 jam, full tiap 24 jam, removed[] dihapus dari Map
            └─ ShooLists.match(hostname) → db_match (skor 100) di semua iPhone
```

**Kapan muncul di HP:** begitu `approved_at` terisi, request `GET /blocklist` berikutnya sudah memuatnya. HP
mengambil incremental paling lama 1 jam sekali (+ cache klien ≤ 5 menit), jadi ± **≤ 65 menit** untuk HP yang
online. HP offline memakai salinan terakhir (≤ 7 hari). Pencabutan (`removed_at`) mengalir lewat jalur yang sama
(`removed[]`), plus full refresh harian.

**Yang tidak lewat review:** verdict `not_safe` selalu berlaku seketika **untuk keluarga itu** (`GET /verdicts`).
Review hanya menentukan daftar global.

### Apa yang bisa salah

| # | Risiko | Kenapa bisa terjadi | Penangkal |
|---|---|---|---|
| R1 | **Situs resmi masuk blocklist global** (peracunan, SECURITY T5) | Penyerang membuat Guardian + Protected anonim miliknya sendiri, join, kirim scan palsu skor 100 untuk domain sah, lalu Not safe. Lolos filter otomatis | Allowlist memblokir antrean untuk domain yang tercatat; review manual = gerbang terakhir; query Q2 |
| R2 | **Celah allowlist backend vs `brands.json`** | 9 domain resmi di `detector/data/brands.json` **tidak ada** di `allowlist.ts`, jadi bisa masuk antrean: `shopee.com`, `lazada.com`, `jet.co.id`, `gmail.com`, `office.com`, `microsoftonline.com`, `fb.com`, `meta.com`, `paypal.com`. Bank/instansi kecil (BPD, koperasi, pemda non-`go.id`) juga tidak tercakup | Q2 menandai domain `brands.json`; minta Alief menambah 9 domain ke `allowlist.ts` (issue, pertanyaan 4) |
| R3 | `families` digelembungkan | Banyak pasangan device anonim → `families` tinggi. Angka ini hanya petunjuk | Jangan pernah menyetujui hanya karena `families` besar (kriteria §5) |
| R4 | Host sah yang diretas | Situs UMKM/sekolah lama dibobol dan dipakai phishing. Memblokir domainnya memblokir seluruh situs sah | Domain tua dengan riwayat normal → tolak (§5 T4) |
| R5 | Salah ketik di SQL editor | Editor berjalan sebagai `postgres` (melewati grant dan RLS). `UPDATE` tanpa `WHERE` menyetujui seluruh antrean | Hanya pakai template §6 dengan penjaga status + `returning`; cek "1 row" |
| R6 | Baris disetujui dihapus dengan `DELETE` | Tidak ada `removed[]` → domain tetap di HP sampai full refresh (≤ 24 jam) dan catatan reviewer hilang | Jangan pernah `DELETE` baris disetujui/dicabut; cabut dengan `removed_at` |
| R7 | Antrean menumpuk / ditolak muncul lagi | Belum ada status "ditolak" di skema: baris yang ditolak tetap `approved_at null` dan muncul lagi setiap sesi | Kolom `rejected_at` diusulkan ke Alief (issue, pertanyaan 3); sementara lihat §7 |
| R8 | Privasi | Domain di antrean = jejak browsing keluarga yang terhubung | Query hanya membaca domain + angka agregat, tanpa id device, nama, URL, atau judul halaman. Nama domain tidak disalin ke git/chat (§7) |

## 3. Jadwal (usulan)

| Kapan | Siapa | Durasi |
|---|---|---|
| **Senin + Kamis**, 15:00 WITA, mulai Senin 26 Okt 2026 | Alief menjalankan SQL (pemilik backend, akses Supabase), Umar memeriksa kriteria. Dua sesi pertama berdua | ± 15 menit |
| **Setiap hari** selama minggu QA-E2E / demo (fase 16, sesuai D9 Alief) | Bergiliran, satu orang cukup | ± 10 menit |
| **Seketika** kalau ada laporan situs resmi terblokir | Siapa pun yang tahu duluan | langkah §6 "cabut" |

Antrean kosong → sesi selesai setelah Q1 dan Q4–Q5 (cek kesehatan daftar yang sudah tersaji).

## 4. Query baca (SELECT saja)

Jalankan di SQL editor Supabase (project `shoo`, produksi). Bungkus dengan `begin read only;` … `commit;` supaya
satu tab baca tidak bisa mengubah data. Kalau editor menolak `begin`, jalankan SELECT tanpa pembungkus dan jangan
pernah menempel `UPDATE` di tab yang sama.

### Q1 · Antrean yang menunggu review

```sql
begin read only;
select domain, families, first_seen_at,
       date_trunc('hour', now() - first_seen_at) as waiting
from blocklist_entries
where approved_at is null and removed_at is null and families > 0
order by families desc, first_seen_at;
commit;
```

### Q2 · Tanda resmi / pemerintah (antrean dan daftar tersaji)

Daftar `official` = semua domain di `detector/data/brands.json` (23 Okt 2026). Perbarui kalau `brands.json` berubah.
Domain di `allowlist.ts` tidak bisa masuk antrean lewat kode, tetapi bisa sudah tersaji sebelum ditambahkan.

```sql
begin read only;
with official(d) as (values
  ('amazon.com'), ('apple.com'), ('bankbsi.co.id'), ('bankmandiri.co.id'), ('bca.co.id'), ('bni.co.id'),
  ('bpjs-kesehatan.go.id'), ('bpjsketenagakerjaan.go.id'), ('bri.co.id'), ('bukalapak.com'), ('dana.id'),
  ('facebook.com'), ('fb.com'), ('gmail.com'), ('gojek.com'), ('google.co.id'), ('google.com'), ('gopay.co.id'),
  ('icloud.com'), ('instagram.com'), ('jet.co.id'), ('jne.co.id'), ('kemensos.go.id'), ('klikbca.com'),
  ('lazada.co.id'), ('lazada.com'), ('live.com'), ('meta.com'), ('microsoft.com'), ('microsoftonline.com'),
  ('netflix.com'), ('office.com'), ('outlook.com'), ('ovo.id'), ('pajak.go.id'), ('paypal.com'),
  ('posindonesia.co.id'), ('shopee.co.id'), ('shopee.com'), ('tokopedia.com'), ('whatsapp.com'), ('youtube.com')
)
select b.domain,
       case when b.approved_at is null then 'queued'
            when b.removed_at is null then 'SERVED'
            else 'removed' end as state,
       coalesce(o.d, 'gov/edu suffix') as matched
from blocklist_entries b
left join official o on b.domain = o.d or right(b.domain, length(o.d) + 1) = '.' || o.d
where o.d is not null or b.domain ~ '(^|\.)(go|ac|sch|mil|desa)\.id$'
order by state, b.domain;
commit;
```

Hasil yang diharapkan: **kosong**. Baris `SERVED` = insiden, langsung cabut (§6). Baris `queued` = tolak.

### Q3 · Bukti untuk satu domain (agregat, tanpa id/nama)

```sql
begin read only;
select count(*) filter (where v.value = 'not_safe' and v.global_eligible) as eligible_not_safe,
       count(*) filter (where v.value = 'not_safe' and not v.global_eligible) as other_not_safe,
       count(*) filter (where v.value = 'safe')                              as safe_verdicts,
       min(v.decided_at) as first_decision, max(v.decided_at) as last_decision,
       max(s.score)      as max_score,
       (select array_agg(distinct sig->>'id' order by sig->>'id')
          from scans s2, jsonb_array_elements(s2.signals) sig
         where s2.domain = v.domain)                                       as signal_ids
from verdicts v
left join scans s on s.id = v.scan_id
where v.domain = 'GANTI-DOMAIN'
group by v.domain;
commit;
```

`signal_ids` kosong / `max_score` null = scan sudah terhapus retensi 14 hari; nilai dari bukti eksternal saja (§5).

### Q4 · Daftar tersaji yang ditandai aman oleh keluarga lain

```sql
begin read only;
select b.domain, b.approved_at, b.approved_by, b.families,
       count(v.*) as safe_verdicts
from blocklist_entries b
join verdicts v on v.domain = b.domain and v.value = 'safe'
where b.approved_at is not null and b.removed_at is null
group by b.domain, b.approved_at, b.approved_by, b.families
order by safe_verdicts desc;
commit;
```

Baris di sini = kandidat salah blokir: periksa ulang dengan kriteria §5, cabut kalau ragu.

### Q5 · Ringkasan untuk catatan sesi

```sql
begin read only;
select count(*) filter (where approved_at is null and removed_at is null)     as queued,
       count(*) filter (where approved_at is not null and removed_at is null) as served,
       count(*) filter (where removed_at is not null)                         as removed,
       count(*) filter (where approved_at is not null and removed_at is null and families = 0) as served_no_support,
       max(approved_at) as last_approval
from blocklist_entries;
commit;
```

`served_no_support` > 0: semua keluarga yang mendukung sudah menarik dukungan (verdict jadi `safe`, putus
hubungan, atau device dihapus). Tidak otomatis salah, tetapi periksa ulang di sesi itu.

## 5. Kriteria terima / tolak

Periksa satu domain sekaligus, dari atas Q1. Pemeriksaan luar hanya dengan **nama domain**, tidak pernah URL,
path, atau data keluarga.

**Tolak** (cukup satu):
- T1 Domain atau induknya ada di `detector/data/brands.json` (`domains`), `backend/api/src/data/allowlist.ts`, atau
  berakhiran `go.id`, `ac.id`, `sch.id`, `mil.id`, `desa.id` (Q2).
- T2 Domain populer: ada di daftar Tranco top 100 000 (unduh CSV sekali per sesi dari tranco-list.eu dan cari
  lokal, supaya domain antrean tidak dikirim ke pihak ketiga), atau jelas milik perusahaan/instansi resmi yang
  tidak tercatat (bank daerah, koperasi, pemda, sekolah, rumah sakit).
- T3 Ada `safe_verdicts` > 0 dari keluarga lain (Q3) dan tidak ada bukti luar yang kuat.
- T4 Host sah yang diretas: domain berumur > 1 tahun (RDAP/WHOIS) dengan isi normal di luar halaman phishing.
- T5 Satu-satunya sinyal lemah (`cheap_tld`, `new_domain`, `urgent_language`) dan tidak ada bukti luar.

**Terima** (semua harus benar):
- A1 Tidak kena T1–T5.
- A2 Q3: `eligible_not_safe` ≥ 1, `safe_verdicts` = 0, dan sinyal kuat bila masih ada (`lookalike_domain`,
  `brand_plus_keyword`, `asks_pin`, `asks_otp`, `asks_card`, `asks_ktp`, `brand_logo_offsite`, `db_match`).
- A3 Minimal satu bukti luar: domain baru (< 90 hari, RDAP), **atau** ada di feed phishing publik (cari lokal),
  **atau** sudah ada pemindaian publik yang menunjukkan halaman meniru brand (cari, jangan kirim pemindaian baru
  yang memuat data apa pun).
- A4 `families` ≥ 2 **atau** A3 dari dua sumber berbeda. `families` tinggi saja tidak cukup (R3).

**Tahan**: ragu, atau bukti belum lengkap. Biarkan di antrean untuk sesi berikutnya. Ditahan dua sesi berturut-turut
tanpa bukti baru → tolak.

Satu reviewer cukup untuk menolak. Menyetujui domain dengan `families` = 1 butuh persetujuan kedua (orang lain,
bisa lewat pesan singkat berisi hasil Q3 tanpa id) sampai kesepakatan lain di issue.

## 6. Perubahan data (LANGKAH MANUAL, bukan otomatis)

Hanya Alief atau Umar, di tab SQL editor terpisah dari tab baca. **Satu domain per Run.** Setiap template punya
penjaga status di `WHERE` dan `returning`: hasil harus tepat 1 baris; 0 baris = status sudah berubah, jangan diulang
dengan `WHERE` lebih longgar. Trigger mengganti waktu dengan `clock_timestamp()`, jadi `now()` aman dipakai.

```sql
-- Setujui (domain mulai tersaji di GET /blocklist)
update blocklist_entries set approved_at = now(), approved_by = 'umar'   -- atau 'alief'
where domain = 'GANTI-DOMAIN' and approved_at is null and removed_at is null
returning domain, approved_at, approved_by;

-- Cabut (salah blokir / situs resmi): dikirim lewat removed[], hilang dari HP ≤ ± 65 menit
update blocklist_entries set removed_at = now()
where domain = 'GANTI-DOMAIN' and approved_at is not null and removed_at is null
returning domain, removed_at;

-- Pulihkan setelah dicabut (dapat addedAt baru)
update blocklist_entries set removed_at = null
where domain = 'GANTI-DOMAIN' and removed_at is not null
returning domain, approved_at;
```

Dilarang: `UPDATE`/`DELETE` tanpa `domain = '…'`, `DELETE` baris yang disetujui atau dicabut (R6), mengubah
`families` (milik Worker), dan menyetujui massal. Menolak = **tidak mengubah apa pun** sampai ada status ditolak (§7).

Setelah menyetujui atau mencabut: `curl -s "$API/blocklist" -H "authorization: Bearer $TOKEN_UJI"` dan pastikan
domain ada / tidak ada (seperti log fase 10 langkah 4). Token uji tidak ditempel di chat atau berkas.

## 7. Mencatat keputusan

| Apa | Di mana |
|---|---|
| Disetujui: siapa, kapan | DB: `approved_by`, `approved_at` (otomatis) |
| Dicabut: kapan | DB: `removed_at` (otomatis). Alasan pencabutan situs resmi → GitHub issue `C6: removed <domain>` (domain resmi itu publik; tanpa data keluarga) |
| Ditolak / ditahan | Belum ada tempat di DB (R7). Sementara: baris tetap di antrean dan dinilai ulang tiap sesi. Usulan: kolom `rejected_at`, `rejected_by` (migrasi Alief), Q1 lalu memfilter `rejected_at is null` |
| Ringkasan sesi | Tabel di bawah: **angka saja**, tanpa nama domain antrean (jejak browsing keluarga tidak disimpan di git) |

### Log sesi

| Tanggal | Reviewer | Antre (Q5) | Disetujui | Ditolak | Ditahan | Dicabut | Q2 kosong? | Catatan |
|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | Belum ada sesi |

## 8. Pertanyaan terbuka (ke Alief, lewat issue)

1. Jadwal §3 (Senin + Kamis, harian saat QA/demo) dan pembagian peran.
2. Query §4 dan template §6 aman di SQL editor (apakah `begin read only` diterima; apakah editor membungkus satu
   transaksi).
3. Status "ditolak": kolom `rejected_at`/`rejected_by` atau tetap tanpa status.
4. Menambah 9 domain `brands.json` yang belum ada ke `allowlist.ts` (R2).
5. Tempat log sesi: tabel §7 di sini, atau log fase aktif Alief (D9). Satu tempat saja.
