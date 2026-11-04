# Layer 5: feedback Guardian di atas database ADM

Status: **usulan v2, 4 Nov 2026 (D-imelda-52)**. Menggantikan v1 (3 Nov, D-imelda-51).
Umar sudah setuju Q1–3 di #241 secara lisan (4 Nov). Persetujuannya perlu ditulis di #241. Alief sudah menjawab Q4–6 di #241. Jangan dikoding sebelum persetujuan Umar ada di issue.

Layer 5 tidak memunculkan `Signal`. Isinya: keputusan Guardian per link, data belajar per domain di database admin (ADM-02/04, sudah merged), dan saran LLM yang diputuskan manusia.

## Yang berubah dari v1

| v1 (3 Nov) | v2 (4 Nov) | Alasan |
|---|---|---|
| Tabel sistem baru (`url`, counter Y/N, `result_llm`) | Tidak ada. Pakai `admin.domain_labels`, `admin.domain_intel`, `admin.domain_intel_label` | ADM-02/04 sudah menyimpan data yang sama per domain |
| Counter keputusan pertama per Guardian | Hitungan ADM: keluarga unik (`families_safe` / `families_not_safe`), minimal 2 | Lebih tahan device palsu, sudah jalan |
| `notes` dihapus setelah 14 hari | `notes` disimpan permanen, anonim, setelah disamarkan | Keputusan Imelda: data untuk belajar lebih penting. Risiko di §Privasi |
| Label dihapus saat device dihapus atau family link putus | Label **dianonimkan** (ref dikosongkan), tidak dihapus | Data belajar tetap ada |
| Hasil LLM di tabel sistem | Tabel baru `admin.domain_review` | `run_analysis` menimpa `domain_intel_label` tiap jalan |
| LLM menilai semua laporan baru (minimal 10) | LLM menilai domain di antrean blocklist (`pending`) saja | Lebih murah, hasilnya langsung dipakai admin |
| — | Signals (id, layer, weight) disalin ke tiap label | Satu label = satu contoh latih lengkap |
| — | `case_library`, `ai_lessons` tidak dipakai | Belum ada di flow tim AI |

## Alur

1. Domain di blocklist: layer 1 memblokir untuk semua user. Block screen menampilkan sumber list dan tanggal masuk.
2. Hanya Guardian yang melapor, di Detail app. Protected menunggu.
3. **Y** = link aman untuk keluarga ini. Link terbuka lagi lewat polling yang sudah ada.
4. **N** = tetap diblokir. `notes` wajib.
5. Keputusan masuk `public.verdicts` (per link). Trigger `admin.on_verdict` menyalinnya ke `admin.domain_labels` (per domain) untuk belajar.
6. Domain dengan ≥ 2 keluarga N masuk antrean `public.blocklist_entries` (sudah jalan).
7. Job mingguan meminta saran LLM untuk domain di antrean. Saran disimpan di `admin.domain_review` dan ditampilkan di dashboard.
8. Admin (Alief/Umar) memutuskan lewat `admin.vote`. LLM tidak pernah mengubah blocklist sendiri.

## Whitelist dan blocklist

- **Whitelist per keluarga.** Y dari Guardian = `verdicts.value = 'safe'` untuk `owner_id` itu. Tidak ada whitelist global.
- **Blocklist global.** Hanya lewat `blocklist_entries` yang disetujui admin.
- Allowlist statis (`OFFICIAL`, `POPULAR` di `ai/src/blocklist/allowlist.js`) tetap, tidak diubah layer 5.

## Data

### `public.verdicts` (Alief, perubahan kontrak oleh Umar)

| Kolom | Isi |
|---|---|
| `owner_id`, `url` | Primary key baru, menggantikan `owner_id`, `domain`. `url` = `origin + path` (`shareableUrl`) |
| `domain` | Tetap, untuk antrean global dan `on_verdict` |
| `notes` | Baru. Teks bebas, maks. 280 karakter. Wajib saat `not_safe` |
| lainnya | Tidak berubah |

Baris lama per domain: di-backfill `url` dari `scans.url` bila scan masih ada, sisanya dihapus (usulan Alief di #241).

### `admin.domain_labels` (Alief)

| Perubahan | Isi |
|---|---|
| `signals jsonb` baru | Disalin dari `scans.signals` saat keputusan: `[{id, layer, weight}]`, tanpa `evidence`, `label`, `labelSimple`. `on_verdict` sudah membaca scan (`s.score`), jadi tambahan ini tetap O(1) |
| `note` diisi | Dari `verdicts.notes`, setelah disamarkan (§Privasi) |
| Anonimisasi | Saat device dihapus atau family link putus: `owner_ref`, `by_ref` = `null`, baris tetap. Menggantikan penghapusan D4/P13 untuk tabel ini |

Label anonim tidak ikut dihitung di `families_*`, jadi tidak membuka atau menutup blocklist. Label itu hanya dipakai untuk evaluasi dan tuning. Alasannya: tanpa ref, satu keluarga yang unlink lalu link lagi bisa dihitung dua kali.

`domain_labels` tetap per domain, tanpa URL (SECURITY D1). URL hanya ada di `verdicts`, yang ikut terhapus bersama keluarganya.

### `admin.domain_review` (baru, Alief)

```sql
create table admin.domain_review (
  id           bigint generated always as identity primary key,
  domain       text not null check (domain = lower(domain) and domain !~ '^www\.'),
  result       text check (result in ('scam', 'legit', 'unsure')),   -- null = gagal setelah retry
  confidence   numeric(3,2) check (confidence between 0 and 1),
  reason       text check (char_length(reason) <= 500 and position('<' in reason) = 0),
  suggestion   text not null check (suggestion in ('approve', 'reject', 'none')),
  input        jsonb not null,   -- snapshot yang dikirim: families_*, avg_score, max_score, signal_counts
  model        text not null,
  prompt       text not null,    -- versi prompt, mis. 'review.v1'
  reviewed_at  timestamptz not null default now(),
  decision     text check (decision in ('approve', 'reject')),        -- keputusan admin, diisi admin.vote
  decided_at   timestamptz
);
create index domain_review_domain on admin.domain_review (domain, reviewed_at desc);
```

- Satu baris per review (riwayat), bukan per domain. Dashboard menampilkan yang terbaru.
- `input` menyimpan apa yang dilihat LLM, supaya kelihatan kalau hasilnya sudah usang (labels bisa dianonimkan dan hitungan turun).
- `decision` diisi saat admin memutuskan domain itu. Dari `suggestion` vs `decision` kita dapat precision LLM tanpa label tambahan.
- `admin.v_review_queue` menampilkan `result`, `confidence`, `reason`, `suggestion` terbaru.

### Ringkasan per domain untuk tim AI

Sudah ada: view `admin.v_domain_intel` (`domain_intel` + `domain_intel_label` + status blocklist). Layer 1–3 dibaca dari `signal_counts`. Pemetaan id ke layer ada di `contracts/detector-interface.md`. Tidak perlu tabel ringkasan baru.

## LLM: `POST /review` di `ai/` (Imelda)

- Dipanggil cron mingguan backend (mis. `0 20 * * 1`), hanya untuk domain dengan `blocklist_entries` `pending` yang belum di-review sejak label terakhir berubah.
- **Batch**: satu request berisi maks. N domain, hasil per indeks (permintaan Alief: batas 50 subrequest per cron di Workers Free). Sisa dibawa ke minggu berikutnya.
- Auth: secret server `AI_REVIEW_SECRET` (Wrangler secret di kedua sisi), bukan token device.
- Input per domain: `domain`, `signal_counts`, `avg_score`, `max_score`, `families_safe`, `families_not_safe`. **Tanpa `notes` dan teks halaman** sampai ada penyedia dengan zero data retention tertulis (D-imelda-27/36).
- Output per domain: `{ result, confidence, reason, suggestion }`. Tanpa `Signal`.
- Stateless, tanpa log isi. Kuota sendiri, terpisah dari `LLM_DAILY_CAP` layer 4.
- Gagal: retry maks. 3 kali, lalu `result = null`, `suggestion = 'none'`.
- Shared host: dijawab `suggestion = 'none'`, `reason = 'shared_host'` tanpa memanggil LLM (§Shared host).

Sebelum dipakai: eval di `ai/eval` dengan label dari `domain_labels`. Bandingkan (a) aturan saja: `families_not_safe ≥ 2` dan `avg_score ≥ 50`, dengan (b) LLM. Kalau (b) tidak lebih baik dari (a), saran memakai aturan saja dan LLM tidak dipanggil.

## Shared host

Domain tempat siapa pun bisa membuat halaman. Satu label atau satu saran per domain tidak bermakna di sini: Y atau N untuk satu halaman tidak berlaku untuk halaman lain di host yang sama.

Daftar yang dipakai, tanpa daftar baru:
- `SHARED_HOSTS` di `ai/src/blocklist/allowlist.js`: platform hosting, shortener, CDN (`sites.google.com`, `forms.gle`, `bit.ly`, `github.io`, `vercel.app`, ...).
- `USER_CONTENT` di `ai/src/layer3/official.js`: halaman buatan pengguna di domain resmi (`docs.google.com`, `forms.office.com`, `script.google.com`, ...).

Aturan:
1. Shared host tidak pernah masuk blocklist global (sama dengan D-imelda-25).
2. `/review` tidak memanggil LLM untuk shared host.
3. Verdict per link tetap berlaku untuk keluarga itu. Inilah alasan verdict pindah ke per link.
4. Untuk backend: `ai/` menerbitkan gabungan kedua daftar sebagai satu file JSON (usulan: `ai/data/shared-hosts.json`, dipakai juga oleh kode `ai/`), supaya `backend/` tidak menyalin daftar sendiri.

## Privasi

- `notes` disimpan permanen. Sebelum disalin ke `domain_labels`, backend menyamarkan nomor telepon, email, dan angka ≥ 8 digit (rekening, NIK, kartu) menjadi `[nomor]` / `[email]`. Teks asli tetap di `verdicts.notes` dan hilang bersama keluarga itu.
- Label anonim: tanpa `owner_ref`, `by_ref`, device id, nama, URL.
- Wajib sebelum rilis (Umar): privacy policy dan label App Store menyebut bahwa catatan Guardian yang dianonimkan disimpan untuk meningkatkan deteksi. Ini juga menjawab Q7 di #241.
- `notes` tidak dikirim ke LLM (§LLM).

## Tidak dipakai

- `admin.case_library` dan `admin.ai_lessons`: belum ada di flow tim AI. `run_analysis` tetap mengisi `case_library` otomatis; diabaikan.

## Pekerjaan per pemilik

| Pemilik | Pekerjaan |
|---|---|
| Umar | Tulis persetujuan Q1–3 di #241. `contracts/`: `verdicts` per link, `notes`, `GET /verdicts?url=`, `POST /review`. Extension: lookup per link, `block-memory.js` tidak membersihkan seluruh domain saat `safe`. Privacy policy dan label App Store |
| Alief | Migrasi `verdicts` (`url`, `notes`, baris lama). `domain_labels`: `signals`, `note`, anonimisasi. Penyamaran `notes`. `admin.domain_review` + kolom di `v_review_queue` + `decision` dari `admin.vote`. Cron mingguan. Input `notes` di Detail (perlu frame Figma) |
| Imelda | `POST /review` (batch, auth secret, prompt `review.v1`, fixture, tes). `ai/data/shared-hosts.json`. Eval aturan vs LLM |

## Kriteria tes

Simulator saja, jangan iPhone pribadi.

1. Block layer 1, Guardian memberi Y, link terbuka ulang.
2. Path lain di domain yang sama tetap terblokir.
3. N tanpa `notes` ditolak.
4. `domain_labels.signals` berisi `id`, `layer`, `weight` dari scan, tanpa `evidence`.
5. Nomor telepon, email, dan angka panjang di `notes` tersamar di `domain_labels.note`.
6. Device dihapus: `verdicts` miliknya hilang, `domain_labels` tetap dengan `owner_ref` dan `by_ref` kosong, `families_*` turun.
7. `/review` untuk shared host tidak memanggil LLM.
8. Halaman atau `reason` berisi prompt injection tidak mengubah `blocklist_entries`.
9. Keputusan admin tercatat di `domain_review.decision`.
