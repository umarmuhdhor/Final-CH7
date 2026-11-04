# Layer 5: feedback Guardian di atas database ADM

Status: **usulan v2, 4 Nov 2026 (D-imelda-52, D-imelda-53)**. Menggantikan v1 (3 Nov, D-imelda-51).
Umar sudah setuju Q1–3 di #241 secara lisan (4 Nov). Persetujuannya perlu ditulis di #241. Alief sudah menjawab Q4–6 di #241. Jangan dikoding sebelum persetujuan Umar ada di issue.

Layer 5 tidak memunculkan `Signal`. Isinya: keputusan Guardian per link, data belajar di database admin (ADM-02/04, sudah merged) termasuk satu tabel siap pakai untuk tim AI (`admin.ai_dataset`), dan saran LLM yang diputuskan manusia.

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
| Tim AI menulis join sendiri dari beberapa tabel | Tabel `admin.ai_dataset`: satu baris per keputusan Guardian, berisi URL, RDAP, hasil tiap layer, label, ringkasan domain, saran LLM | Tim AI cukup `select`, tanpa query manual (D-imelda-53) |
| Data permanen tanpa URL | `ai_dataset.url` permanen (`origin + path`, tanpa query) | Dibutuhkan untuk verifikasi dan menjalankan ulang layer 1–2. Sudah dibicarakan dengan Alief, perlu ok Umar (Q7) |

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

`domain_labels` tetap per domain, tanpa URL. URL permanen hanya disimpan di `admin.ai_dataset` (§ di bawah). Ini mengubah SECURITY D1 untuk satu tabel itu dan perlu ok Umar.

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

### `admin.ai_dataset` (baru, Alief)

Satu tabel siap pakai untuk tim AI: satu baris per keputusan Guardian, sudah digabung dengan hasil detector saat itu dan ringkasan domainnya. Tim AI cukup `select`, tanpa join. Isi teks halaman (snapshot) **tidak** disimpan, hanya hasil tiap layer.

```sql
create table admin.ai_dataset (
  id                 bigint generated always as identity primary key,
  label_id           bigint unique references admin.domain_labels (id) on delete set null,

  -- link
  url                text not null,          -- origin + path, tanpa query (shareableUrl)
  domain             text not null,
  rdap_registered_at date,                   -- tanggal daftar domain menurut RDAP saat scan
  rdap_age_days      int,                    -- umur domain saat scan; dicek ulang saat verifikasi

  -- hasil tiap layer saat scan: [{id, weight, evidence}]
  layer1             jsonb not null default '[]',   -- blocklist
  layer2             jsonb not null default '[]',   -- link, lookalike, brand, TLD
  layer3             jsonb not null default '[]',   -- form, teks, new_domain
  layer4             jsonb not null default '[]',   -- LLM
  layer1_score       int not null default 0,
  layer2_score       int not null default 0,
  layer3_score       int not null default 0,
  layer4_score       int not null default 0,
  score              int,                    -- total saat itu (maks. 100)
  status             text check (status in ('warning', 'blocked')),
  thresholds_version int,
  scanned_at         timestamptz not null,

  -- label
  is_scam            boolean not null,       -- keputusan Guardian (N = true)
  note               text,                   -- sudah disamarkan (§Privasi)
  decided_at         timestamptz not null,
  anonymous          boolean not null default false,

  -- ringkasan domain (diperbarui run_analysis)
  domain_scans       bigint,
  domain_avg_score   int,
  domain_max_score   int,
  families_safe      int,
  families_not_safe  int,
  final_label        text check (final_label in ('scam_strong', 'scam_weak', 'safe')),
  shared_host        boolean not null default false,

  -- saran LLM terbaru (admin.domain_review)
  review_result      text,
  review_suggestion  text,
  review_decision    text,

  updated_at         timestamptz not null default now()
);
create index ai_dataset_domain on admin.ai_dataset (domain);
create index ai_dataset_decided on admin.ai_dataset (decided_at);
```

Cara terisi (backend, bukan tim AI):

| Kapan | Yang ditulis |
|---|---|
| Guardian memutuskan (`on_verdict`) | Baris baru: `url`, `domain`, `rdap_*`, `layer1`–`layer4` + skornya (dipecah dari `scans.signals` menurut field `layer`), `score`, `status`, `thresholds_version`, `scanned_at`, `is_scam`, `note` (disamarkan), `decided_at`, `shared_host` |
| Guardian mengubah keputusan | Baris baru (sama dengan `domain_labels`, `revision_of`), baris lama tetap |
| `run_analysis` | `domain_*`, `families_*`, `final_label` untuk domain yang berubah |
| `/review` selesai | `review_result`, `review_suggestion` |
| Admin memutuskan (`admin.vote`) | `review_decision` |
| Device dihapus / family link putus | Baris tetap, `anonymous = true` |

Catatan:
- `evidence` ikut disimpan (teks persis dari halaman yang memicu sinyal, mis. `urgent_language`). Teks ini pendek dan berguna untuk verifikasi, tapi tetap teks halaman: masuk pertanyaan privasi Q7.
- **RDAP belum tersimpan di mana pun.** Umur domain sekarang hanya muncul di label sinyal `new_domain`, dan hanya kalau domainnya muda. Perlu: `/analyze` mengembalikan `rdapRegisteredAt` (Imelda), extension meneruskannya di `POST /scans` (Umar, kontrak), backend menyimpannya di `scans` (Alief).
- Layer 1–2 bisa dijalankan ulang dari `url` + `rdap_*`. Layer 3–4 hanya bisa diverifikasi dari hasilnya, karena isi halaman tidak disimpan.
- Akses: grant `select` ke role read-only untuk tim AI (usulan: role baru `shoo_ai`), bukan seluruh `shoo_admin`.

Ringkasan per domain tanpa label tetap ada di view `admin.v_domain_intel`.

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
- Label anonim: tanpa `owner_ref`, `by_ref`, device id, nama.
- `admin.ai_dataset` menyimpan `url` (tanpa query) dan `evidence` secara permanen. Tanpa device id, nama, atau isi halaman lengkap.
- Wajib sebelum rilis (Umar): privacy policy dan label App Store menyebut bahwa catatan Guardian yang dianonimkan disimpan untuk meningkatkan deteksi. Ini juga menjawab Q7 di #241.
- `notes` tidak dikirim ke LLM (§LLM).

## Tidak dipakai

- `admin.case_library` dan `admin.ai_lessons`: belum ada di flow tim AI. `run_analysis` tetap mengisi `case_library` otomatis; diabaikan.

## Pekerjaan per pemilik

| Pemilik | Pekerjaan |
|---|---|
| Umar | Tulis persetujuan Q1–3 di #241. Ok privasi untuk URL + `evidence` permanen di `ai_dataset` (Q7). `contracts/`: `verdicts` per link, `notes`, `GET /verdicts?url=`, `POST /review`, `rdapRegisteredAt` di respons `/analyze` dan `POST /scans`. Extension: lookup per link, `block-memory.js` tidak membersihkan seluruh domain saat `safe`. Privacy policy dan label App Store |
| Alief | Migrasi `verdicts` (`url`, `notes`, baris lama). `domain_labels`: `signals`, `note`, anonimisasi. Penyamaran `notes`. `admin.domain_review` + kolom di `v_review_queue` + `decision` dari `admin.vote`. `admin.ai_dataset` + pengisiannya + role `shoo_ai`. Kolom RDAP di `scans`. Cron mingguan. Input `notes` di Detail (perlu frame Figma) |
| Imelda | `POST /review` (batch, auth secret, prompt `review.v1`, fixture, tes). `rdapRegisteredAt` di respons `/analyze`. `ai/data/shared-hosts.json`. Eval aturan vs LLM dari `ai_dataset` |

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
9. Keputusan admin tercatat di `domain_review.decision` dan `ai_dataset.review_decision`.
10. Satu keputusan Guardian = satu baris `ai_dataset`, sinyal terbagi benar ke `layer1`–`layer4` dan skor per layer sama dengan jumlah bobotnya.
11. `ai_dataset.url` tanpa query, `rdap_*` terisi untuk domain yang RDAP-nya berhasil.
12. Device dihapus: baris `ai_dataset` tetap dengan `anonymous = true`.
