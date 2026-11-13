# Matriks edge case: Fase 28 (13 Nov 2026)

| Field | Nilai |
|---|---|
| Plan | [`../fase-28-truth-hunt.md`](../fase-28-truth-hunt.md) (ID temuan, severity, dan nomor draf pertanyaan Q1 sampai Q35, dengan Q7 dan Q22 dipecah a / b, berasal dari sana) |
| Log + cara mengulang | [`../log/fase-28.md`](../log/fase-28.md) |
| Basis | `main` `9e5403ba`, worktree `fase-28-hunt` |
| Sumber | Laporan hunter h1 sampai h5 dan reviewer r1 sampai r3 (laporan mentah tidak disimpan; tabel putusan reviewer disalin ke [`../log/fase-28-review.md`](../log/fase-28-review.md)). **Kalau berbeda, putusan reviewer yang dipakai.** |
| Bukti | [`../log/fase-28-repro/`](../log/fase-28-repro/) (skrip dan test sebagai `.txt`; pohon aksesibilitas sel UI yang dikutip plan sebagai `h4-tree-<konfigurasi>-<sel>.json.txt`), [`img/fase-28/`](img/fase-28/) (screenshot) |

Angka memakai format Indonesia: `1.025` = seribu dua puluh lima, `3,3` = tiga koma tiga. Keluaran program di blok kode tetap apa adanya.

Arti hasil di semua tabel:

- **pass**: hasil sama dengan yang diharapkan.
- **FAIL**: hasil berbeda. Kolom di sebelahnya menyebut ID temuan di plan.
- **n/a**: sel tidak bisa ada, atau tidak punya hasil yang diharapkan. Alasannya ditulis.
- **perlu iPhone**: tidak bisa dijalankan di simulator atau Node. Langkah manualnya ada di §9.
- **tidak dijalankan**: tidak pernah dihitung sebagai pass.

## 1. Metode

Setiap hunter memakai urutan yang sama.

1. **Inventaris.** Daftar semua yang bisa diuji di areanya: rute dan parameter (h1), model dan state layar (h2), panggilan jaringan dan fungsi normalisasi (h3), layar dan elemen (h4), statement SQL dan rute (h5).
2. **Dimensi.** Daftar nilai yang bisa merusak: nilai kosong, nilai batas, tipe salah, teks panjang, jam yang salah, mode gagal jaringan, ukuran layar, ukuran teks, bahasa, tema, peran.
3. **Sel.** Satu sel = satu elemen dengan satu nilai dimensi. Setiap sel punya hasil yang diharapkan dan sumbernya (kontrak, PRD ID, keputusan, issue, frame Figma). Sel tanpa sumber masuk §10, bukan dihitung gagal.
4. **Pasangan.** Dimensi tidak dikali semuanya. Yang dijalankan adalah pasangan yang paling mungkin rusak. Contoh UI: iPhone SE × AX5 × ID, iPhone 17 × AX5 × gelap, iPhone SE × EN, Pro Max × EN × gelap × Bold × Contrast.

Reviewer lalu mencoba membantah: jalankan ulang repro, cek apakah "yang diharapkan" memang diwajibkan, cek apakah sudah diketahui, hitung ulang angka cakupan.

## 2. Cakupan per lapis

| Lapis | Sumber | Total | Dijalankan | Lulus | Gagal | n/a | Perlu iPhone | Catatan |
|---|---|---|---|---|---|---|---|---|
| API: rute × 21 nilai dimensi | h1 | 1.642 | 1.642 | 1.614 | 4 | 24 | 0 | Gagal → B-06 1 sel, B-07 3 sel (5 run: B-06 terlihat di dua file). Di luar 1.642: 4 sel identitas URL gagal → B-04 (§3.4). Tidak dijalankan ulang reviewer |
| Logika app (level model) | h2 | 160 | 160 | 130 | 30 | 0 | 0 | Diulang r2: 20 test, 40 issue |
| Rantai: panggilan jaringan extension × mode gagal | h3 `h3-fail.mjs` | 84 | 84 | 70 | 10 | 4 | 0 | 4 n/a = sudah diketahui (BH-41 = issue #454 butir E: cache verdict 60 s di extension juga untuk `safe`, jadi verdict yang diubah baru berlaku setelah 60 s). Diulang r3: sama |
| Rantai: 33 URL × 13 fungsi normalisasi | h3 `h3-norm.mjs` | 33 baris (429 sel) | 33 | 21 | 12 | 0 | 0 | Dihitung per baris URL. Diulang r3: sama |
| Rantai: skenario lintas komponen | h3 `h3-chain.mjs`, `h3-chain.test.ts` | 216 | 216 | 140 | 76 | 0 | 2 | Dijumlah dari baris §5.3 (plan memakai total yang sama). 2 sel perlu iPhone ada di luar total |
| UI app: satu state di satu konfigurasi | h4, **dihitung ulang r2** | **1.025** | **613** | **470** | **143** | 12 | 14 | 205 sel × 5 konfigurasi. 27 sel tidak valid, 385 tidak dijalankan. n/a dan perlu iPhone adalah baris tambahan di luar total |
| UI web: join, terms, privacy, support | h4 | 32 | 32 | 26 | 6 | 20 | 1 | Tidak dicek ulang r2 |
| Performa: baris yang dijalankan | h5 | 9 | 9 | 2 | 2 | 5 | 0 | 5 n/a = tidak ada anggaran latensi tertulis (Q23) |

UI app + web menurut r2: 645 dijalankan, 496 lulus, 149 gagal.

**Empat catatan wajib untuk angka UI.**

1. **Kira-kira 1 dari 8 tanda gagal adalah positif palsu dari aturan skrip cek.** Sampel r2: 29 sel gagal dilihat, 24 menunjukkan temuannya, 3 tidak, 2 lemah. Perlakukan total UI sebagai ± 10 %.
2. **Konfigurasi B, D, dan E hanya menjalankan set kecil 52 method** (dari 147). Sel di luar set itu ditulis "-" dan tidak dihitung lulus.
3. **Pro Max (konfigurasi B) kehilangan 12 method terakhir.** Run berhenti di 40 dari 52 karena Mac berada di load average 400 sampai 900. Yang hilang: halaman Profile dan sebagian sheet alasan aman.
4. **Dynamic Type AX3 tidak pernah dijalankan.** AX3 adalah batas yang ditulis proyek ("sampai XL", `ref/R5-konvensi.md:11`; XL di repo ini = `accessibility-extra-large`). Hunter hanya menjalankan ukuran default dan AX5. Temuan yang hanya muncul di AX5 berada di luar batas tertulis sampai diukur di AX3 (sub-fase 28n).

## 3. Lapis API (h1)

Test: [`h1-matrix.test.ts.txt`](../log/fase-28-repro/h1-matrix.test.ts.txt), [`h1-truth.test.ts.txt`](../log/fase-28-repro/h1-truth.test.ts.txt), [`h1-identity.test.ts.txt`](../log/fase-28-repro/h1-identity.test.ts.txt), [`h1-extra.test.ts.txt`](../log/fase-28-repro/h1-extra.test.ts.txt), [`h1-concurrency.test.ts.txt`](../log/fase-28-repro/h1-concurrency.test.ts.txt). DB: `shoo_f28`.

### 3.1 Dimensi

- **21 nilai untuk setiap field body, query, dan path:** tidak ada, `null`, kosong, spasi saja, 5.000 karakter, 0, -1, NaN, 1.5, 1e308, 2^53+1, boolean, array, objek, emoji, RTL override, zero-width, HTML, nilai enum tak dikenal, teks SQL, NUL.
- **Bentuk body:** bukan JSON, kosong, array, `null`, string, key ganda, 17 KB, 300 KB, 2 MB.
- **Auth, 7 nilai × 20 rute:** tanpa token, skema `Basic`, token `Bearer` pendek, `bearer` huruf kecil, token + spasi, token berbentuk benar tetapi tak dikenal, token 5.000 karakter. Ditambah: token device yang sudah dihapus, Guardian keluarga lain, Protected keluarga lain, Guardian yang baru diputus.
- **Batas waktu:** kode keluarga 301 s / 299 s, join 2 s sebelum / 1 s sesudah kedaluwarsa, retensi 14 hari ± detik, heartbeat 24 jam ± detik, kunci verdict 1 ms sebelum / tepat / 1 ms sesudah Minggu 18:00 UTC, `detectedAt` +4 menit / +6 menit / -400 hari.
- **Identitas URL:** query, fragment, `:443`, host huruf besar, userinfo, port lain, `http`, slash di akhir, huruf besar di path, `www`, subdomain, titik di akhir host, dot segment, port kosong, path non-ASCII mentah, IDN.
- **Paging:** limit × jumlah baris 1×5, 2×5, 5×5, 5×6, 3×10, 50×51; separuh baris berbagi satu `detectedAt`; blocklist 999, 1.000, 1.001, 2.500 baris.
- **Balapan (5 ronde masing-masing):** safe ∥ not_safe, disconnect ∥ verdict, join ∥ refresh kode, hapus akun ∥ `POST /scans`.

Arti "pass" di lapis ini: kelas status yang dijanjikan kontrak (`contracts/api.md:14`). Body salah 422, JSON rusak 400, terlalu besar 413, token salah 401, mode salah 403, bukan milikmu 404, dan tidak pernah 5xx.

### 3.2 Cakupan per grup rute

Jumlah sel per grup dibaca dari keluaran `h1-matrix.test.ts` (7 grup, 1.620 sel). Sisa 22 sel dari total 1.642 berasal dari run tambahan. Hunter tidak merinci pembagian 22 sel itu; isinya antara lain domain dengan limiter mati, batas 2.048 karakter, dan path NUL di `h1-extra`.

| Grup | Rute | Total | Dijalankan | Lulus | Gagal | n/a |
|---|---|---|---|---|---|---|
| `devices` | `POST /devices`, `POST /devices/me/protected`, `POST /live` | 300 | 300 | 300 | 0 | 0 |
| `patch` | `PATCH /devices/me` (11 field + key tak dikenal + body) | 261 | 261 | 261 | 0 | 0 |
| `scans` | `POST /scans` (semua field + body) | 324 | 324 | 324 | 0 | 0 |
| `verdicts` | `POST /verdicts` | 93 | 93 | 93 | 0 | 0 |
| `family` | `POST /family/code`, `POST /family/join`, `PATCH /family/members/{id}` | 153 | 153 | 153 | 0 | 0 |
| `query` | `GET /scans`, `GET /scans/{id}`, `GET /verdicts`, `GET /blocklist`, `DELETE /family/members/{id}`, `POST …/remind`, `GET /j/{code}`, `/replicas`, `/favicons`, `/screenshots` | 276 | 276 | 249 | 3 | 24 |
| `auth` | 20 rute × 7 nilai auth, `GET /ops/status`, token terhapus, keluarga lain, Guardian terputus | 213 | 213 | 213 | 0 | 0 |
| tambahan | antara lain `GET /verdicts` domain saja dengan limiter mati, URL 2.048 / 2.100 karakter, path `a%00b` | 22 | 22 | 21 | 1 | 0 |
| **Total** | | **1.642** | **1.642** | **1.614** | **4** | **24** |

24 n/a: `GET /verdicts` menjawab `429` dari binding rate limit miniflare di runtime test. 15 di antaranya diulang dengan binding mati di `h1-extra` dan lulus.

Sel kebenaran dan batas (di luar hitungan 1.642, semua dijalankan): kebenaran Activity terhadap fixture hitung tangan (14 asersi), paging cursor (7), kode keluarga (2), join (2), ukuran keluarga (2), retensi (3), `extensionActive` (3), kunci verdict (5), identitas scan (14), `GET /verdicts` setelah `safe` (14), round trip verdict (7), cakupan `not_safe` (9), blocklist (12), kebenaran config dan kode (3), oracle halaman join (1), balapan (20). Yang gagal dari kelompok ini hanya 4 sel B-04 di §3.4.

### 3.3 Sel gagal dalam 1.642

| Rute | Parameter | Nilai | Diharapkan (sumber) | Kenyataan | Temuan |
|---|---|---|---|---|---|
| `GET /verdicts` | `url` (dengan `domain`) | URL `https` valid lebih dari 2.048 karakter (3.000 di matriks, 2.100 di `h1-extra`: sel yang sama, 2 run) | `422 invalid_body` (`contracts/api.md:14`) | `500 internal` (`TypeError`) | **B-06** (P3) |
| `DELETE /family/members/{id}` | `id` | `a%00b` | `404 not_found` | `500 internal` (Postgres 22021) | **B-07** (P3) |
| `POST /family/members/{id}/remind` | `id` | `a%00b` | `404 not_found` | `500 internal` | **B-07** (P3) |
| `PATCH /family/members/{id}` | `id` | `a%00b` | `404 not_found` | `500 internal` | **B-07** (P3) |

### 3.4 Sel gagal di test kebenaran

| Test | Nilai | Diharapkan (sumber) | Kenyataan | Temuan |
|---|---|---|---|---|
| Identitas scan (baris yang sama?) | dot segment `https://toko.example/x/../a` | baris yang sama dengan `/a` (#241: link = origin + path) | baris lain | **B-04** (P3) |
| Identitas scan | port kosong `https://toko.example:/a` | baris yang sama | baris baru tiap post (`verdict_link` null) | **B-04** (P3) |
| Round trip verdict (URL scan tersimpan → `GET /verdicts` dengan URL yang sama) | path non-ASCII mentah `/päth` | `safe` | `null` | **B-04** (P3) |
| Round trip verdict | dot segment | `safe` | `null` | **B-04** (P3) |

Sel lain yang gagal di file repro tetapi **bukan sel matriks**: B-01, B-01b, B-01c (aturan tertulis, Q1), B-02a, B-02b (B-02), B-03 (aturan tertulis, Q3), B-05 (ditolak reviewer). Bukti per temuan ada di log.

### 3.5 Sel n/a dan sel tanpa hasil yang diharapkan

| Sel | Hasil | Kenapa | Rujukan |
|---|---|---|---|
| Round trip verdict, host IDN sebagai Unicode | n/a | Data test salah (punycode tidak cocok dengan host), `POST /scans` 422 | tidak ada |
| Paging cursor, baris dikunjungi lagi di antara halaman 1 dan 2 | pass, "lompat" n/a | Tidak ada duplikat. Baris yang pindah dilewati di putaran ini; refresh menampilkannya | tidak ada |
| Ringkasan mingguan vs statistik Profile (1 link, 3 kunjungan blocked) | tanpa harapan | Push menulis "1 site blocked", Profile "3". Tidak ada spesifikasi satuan | **Q14** |
| `POST /devices` nama dengan zero-width | pass (diterima) | Tidak ada aturan untuk `\p{Cf}` | **Q13** |
| `PATCH /devices/me` key tak dikenal → `200` | pass | Bukan bug hari ini; strict atau tidak belum diputuskan | **Q12** |
| `GET /scans?limit=` kosong → 422 | pass (fail-closed) | Tidak konsisten dengan `owner`, `status`, `cursor` (kosong = tidak ada). Dicatat saja | tidak ada |

## 4. Lapis logika app (h2)

Test: [`h2-H2TruthTests.swift.txt`](../log/fase-28-repro/h2-H2TruthTests.swift.txt) (20 test, level model, simulator "Shoo F28"), [`h2-poison.test.ts.txt`](../log/fase-28-repro/h2-poison.test.ts.txt), [`h2-l10n-audit.py.txt`](../log/fase-28-repro/h2-l10n-audit.py.txt). Nilai tepat per sel ada di daftar argumen test.

### 4.1 Dimensi

- **Layar (8):** `activity.me`, `activity.family`, `guardianHome.family`, `guardianHome.personal`, `protectedHome`, `detail`, `profile`, `memberDetail`.
- **Muatan:** muat pertama gagal × 5 jenis error (network, decoding, internal, rate_limited, forbidden); refresh gagal setelah muat sukses.
- **Jenis jawaban HTTP (13):** 200 field hilang, 200 bukan JSON, 200 body `null`, 200 mode tak dikenal, 401 berbentuk kontrak, 401 dari proxy, 404 HTML, 429 dengan `Retry-After`, 429 tanpa, 500 kosong, 502 HTML, 503 `code_unavailable`, offline.
- **Baris beracun di daftar (8):** `status=reviewing`, `verdict.value=unsure`, `signal.layer=six`, `score=91.5`, `detectedAt` angka, `ownerName=null`, `faviconUrl` kosong, `pageTitle` angka.
- **Bentuk `url` yang disimpan backend (21):** antara lain backslash di path dan spasi di tepi.
- **Selisih jam HP untuk hitung mundur kode:** 0, ±60, +300, ±600, ±2.400 s.
- **Umur heartbeat extension:** +60 s, +301 s, +1 jam, +1 hari, +30 hari, +365 hari; 9 tepi di sekitar jendela 24 jam.
- **Skor:** 13 nilai di tepi band; teks persen 7 nilai × EN / ID.
- **Waktu:** 4 batas kunci verdict; jendela pending 24 jam tepat, +1 s, cap masa depan; tengah malam WIB; hari terlindungi WIB dan UTC; `lastSeen` +3 s di depan jam HP.
- **Katalog string:** 650 key × (ID hilang, ID kosong, placeholder tidak cocok, variasi jamak).

### 4.2 Cakupan

| Kelompok | Total | Dijalankan | Lulus | Gagal | Temuan untuk yang gagal |
|---|---|---|---|---|---|
| Refresh gagal setelah muat (8 layar) | 8 | 8 | 2 | 6 | A-01 (3 sel Home), Q16 (3 sel: Detail, Profile, Member detail) |
| Muat pertama gagal (8 layar × 5 error) | 40 | 40 | 40 | 0 | - |
| Jenis jawaban HTTP | 13 | 13 | 13 | 0 | - |
| Satu baris beracun di daftar Activity | 8 | 8 | 0 | 8 | A-03 A-10 |
| Decode `url` (21 bentuk) | 21 | 21 | 19 | 2 | A-03 A-10 (akar di backend: B-04 A-09) |
| Hitung mundur kode × selisih jam | 8 | 8 | 1 | 7 | A-04 (desain diputuskan, Q4) |
| Umur heartbeat | 6 | 6 | 1 | 5 | A-05 (Q5) |
| Tepi status extension | 9 | 9 | 9 | 0 | - |
| Band skor + badge | 13 | 13 | 13 | 0 | - |
| Teks persen | 14 | 14 | 14 | 0 | - |
| Batas kunci verdict | 4 | 4 | 4 | 0 | - |
| Jendela pending Home | 3 | 3 | 3 | 0 | - |
| Peran Home | 2 | 2 | 2 | 0 | - |
| Hari terlindungi | 5 | 5 | 5 | 0 | - |
| Strip statistik Profile | 1 | 1 | 1 | 0 | - |
| Pengelompokan hari Activity | 2 | 2 | 2 | 0 | - |
| Waktu verdict +240 s | 1 | 1 | 1 | 0 | - |
| `lastSeen` anggota +3 s, EN dan ID | 2 | 2 | 0 | 2 | A-08 |
| **Total** | **160** | **160** | **130** | **30** | |

Di luar 160: katalog `Localizable.xcstrings` lulus untuk ID hilang 0, ID kosong 0, placeholder tidak cocok 0. Baris variasi jamak gagal (0 variasi, 11 key berisi angka) → **A-14**.

### 4.3 Sel gagal

| Layar / model | Elemen | Nilai | Diharapkan (sumber) | Kenyataan | Temuan |
|---|---|---|---|---|---|
| `guardianHome.family`, `guardianHome.personal`, `protectedHome` | refresh setelah muat | gagal | isi lama tetap **dan** ada tanda "mungkin sudah lama" (D-alief-A12) | isi lama, tanpa tanda | **A-01** (P1) |
| `detail`, `profile`, `memberDetail` | refresh setelah muat | gagal | sama, menurut bacaan hunter | isi lama, tanpa tanda | **bukan bug: pertanyaan Q16** (A12 hanya menyebut "daftar dan kartu Shield"; putusan r2) |
| Daftar Activity | satu baris beracun | 8 racun di §4.1 | baris lain tetap tampil | 0 baris, `.decoding` | **A-03 A-10** (P3; toleransi baris = Q11) |
| Decode scan | `url` | backslash di path; spasi di tepi | ter-decode atau baris dilewati | seluruh daftar gagal | **A-03 A-10** (P3) |
| Kode keluarga | hitung mundur | selisih ±60, +300, ±600, ±2.400 s | 360 s (waktu server) | 300 / 420 / 60 / 1.800 / 960 / 1.800 / 1.800 s | **A-04** (P3; jam HP dengan clamp = D-alief-C09, #227; Q4) |
| `ExtensionStatus` | umur heartbeat | +301 s, +1 jam, +1 hari, +30 hari, +365 hari | tidak Active | Active | **A-05** (P3; disengaja menurut komentar kode; Q5) |
| Member detail | terakhir aktif | +3 s di depan jam HP, EN dan ID | "just now" | "active in 0s" / "active dlm 0 dtk" | **A-08** (P3) |
| `Localizable.xcstrings` | variasi jamak | 11 key berisi angka | bentuk jamak | tidak ada | **A-14** (P3) |

Temuan app yang **bukan sel matriks** (repro sendiri atau baca kode): A-02, A-06, A-07, A-12, A-15. Ditolak reviewer: A-11, A-16. Sudah diketahui: A-13 (#476), A-17 (BH-31: hero Guardian Home hanya membaca scan pending, jadi bisa menulis "Family protected!" yang tidak didukung keadaan keluarga; pertanyaan desain untuk PM). File BH (`log/bughunt-2026-11-12.md`) lokal di checkout Alief, tidak di-commit; isinya diringkas di sini dan di plan.

## 5. Lapis rantai: extension, ai, backend (h3)

Skrip: [`h3-norm.mjs.txt`](../log/fase-28-repro/h3-norm.mjs.txt), [`h3-fail.mjs.txt`](../log/fase-28-repro/h3-fail.mjs.txt), [`h3-chain.mjs.txt`](../log/fase-28-repro/h3-chain.mjs.txt), [`h3-chain.test.ts.txt`](../log/fase-28-repro/h3-chain.test.ts.txt), [`h3-gen-backend-cases.mjs.txt`](../log/fase-28-repro/h3-gen-backend-cases.mjs.txt). Skrip memuat modul asli extension, detector, dan ai. Tidak ada iPhone dan tidak ada simulator di lapis ini.

### 5.1 Normalisasi domain dan link: 33 URL × 13 fungsi

**13 fungsi:** domain PSL extension, fallback `content.js`, cek `DOMAIN` backend, host-di-dalam-domain backend, link extension, link ≤ 2.048, kunci block memory, kandidat daftar, host pencarian daftar detector, gerbang live island, domain RDAP ai, domain blocklist ai, host resmi ai.

**Dimensi URL:** huruf besar, `www.`, titik di akhir, port, port default, IDN / punycode, subdomain dalam, suffix privat, shared host, IPv4, IPv6, localhost, garis bawah, userinfo + query + fragment, tanpa path, slash ganda, path ter-encode, suffix telanjang, `www.<suffix>`, tingkat kedua `.id`, link pendek, path 2.121 karakter.

Diharapkan untuk setiap baris: semua bagian menyebut situs dan link yang sama.

| Hasil | Baris | Isi | Temuan |
|---|---|---|---|
| pass | 21 | Huruf besar, `www.`, titik di akhir, port, punycode, userinfo / query / fragment: semua sepakat | - |
| FAIL | 5 | Baris bertanda `POST /scans would 422` di keluaran skrip, antara lain IPv6 literal, `localhost`, `shop_x.web.app`, `www.co.id`. r3 mempersempit X-06 ke 4 bentuk yang bisa terjadi: IPv6 literal, host satu label, `www.co.id`, `www.com` | **X-06** (P3, Umar; Q7b) |
| FAIL | 6 | Baris bertanda `fallback≠PSL`: fallback `content.js` (host tanpa `www.`) ≠ jawaban PSL. Contoh: `login.bca.co.id.verifikasi.xyz`, `sites.google.com`, `a_b.example.com` | **dijelaskan, bukan temuan** (§12; plan → Inventaris fallback → "Fail-wrong yang diperiksa dan bukan temuan") |
| FAIL | 1 | Domain RDAP ai ≠ domain extension | **X-11** (P3, Imelda) |

Dua baris massal dari skrip yang sama:

| Uji | Total | Berbeda | Temuan |
|---|---|---|---|
| Domain terdaftar, extension vs ai, untuk setiap suffix PSL multi-label | 8.637 | 7.607 | **X-11**. Dibaca ulang r3: hitungan itu memuat aturan privat juga, dan untuk suffix privat jawaban ai memang benar untuk RDAP. Yang berdiri: **6 suffix `.id`** |
| Klasifikasi shared host di tiga daftar (block memory extension, `verdict_shared` backend, `ai/data/shared-hosts.json`) | 99 host | 23 baris | **sudah diketahui**: X-03 = issue #325 + `backend/api/test/fixtures/domain-lists-expected-diff.json` |

### 5.2 Panggilan jaringan extension × mode gagal: 84 sel

**8 mode:** ok, jaringan putus, timeout, 401, 429, 500, 200 dengan HTML, 200 dengan `{}`. Ditambah bentuk body 200 yang rusak per panggilan.

| Panggilan | Nilai | Sel | Diharapkan | Lulus | Gagal | n/a | Temuan |
|---|---|---|---|---|---|---|---|
| `POST /analyze`, halaman dengan layer 2 = 14 | 8 mode | 8 | Gagal → "Online check unavailable" | 7 | 1 | 0 | X-10 (200 `{}` → "Low risk") |
| `POST /analyze` 200 | 6 bentuk body: `signals` bukan array, bentuk salah, `weight` string, layer 2 dari server, `null`, objek error | 6 | Bukan "Low risk" | 0 | 6 | 0 | X-10 |
| `getSession` | belum onboarding, native tidak terjangkau, tanpa URL AI | 3 | Tanpa panggilan jaringan, bukan "Low risk" | 3 | 0 | 0 | - |
| `GET /verdicts` di halaman warning | 8 mode | 8 | Warning tetap | 8 | 0 | 0 | - |
| `GET /verdicts` di blokir yang diingat | 8 mode | 8 | Tetap terblokir | 8 | 0 | 0 | - |
| `GET /verdicts` 200 | 6 nilai: `unsure`, `SAFE`, string, `safe` tanpa nama, `not_safe`, `safe` | 6 | Nilai tak dikenal = tanpa verdict | 6 | 0 | 0 | - |
| `safe` dari cache lalu gagal / server `null` | 500, jaringan, 401, verdict dicabut | 4 | Berlaku seketika | 0 | 0 | 4 | **sudah diketahui**: BH-41 = #454 butir E (cache verdict 60 s di extension juga untuk `safe`: basi sampai 60 s) |
| `GET /config/public` | 8 mode + 5 body | 13 | Bawaan 30/80 atau pasangan valid | 13 | 0 | 0 | - |
| `GET /blocklist` refresh inkremental | 8 mode | 8 | Domain terdaftar tetap cocok | 8 | 0 | 0 | - |
| `GET /blocklist` refresh penuh 200 | `{}`, objek error, `domains: null`, daftar kosong | 4 | Body rusak menjaga salinan | 1 | 3 | 0 | X-09 (daftar kosong yang sah = sesuai desain) |
| `POST /scans` halaman blocked | 8 mode + 5 body | 13 | Baris "Link sent to" hanya kalau tersimpan | 13 | 0 | 0 | - (scan hilang = BH-06 = #449, sudah diketahui: `POST /scans` yang gagal sekali tidak diulang, kunjungan berikutnya dari block memory tidak dilaporkan) |
| `profile` | belum onboarding, native tidak terjangkau, tanpa nama Guardian | 3 | Nama tidak bocor, tanpa poll tanpa sesi | 3 | 0 | 0 | - |
| **Total** | | **84** | | **70** | **10** | **4** | X-10 7, X-09 3 |

### 5.3 Skenario lintas komponen

| Skenario | Sel | Diharapkan | Lulus | Gagal | Temuan |
|---|---|---|---|---|---|
| Rantai heartbeat: 31 detak per jam, akses dipersempit setelah detak pertama | 1 skenario | Tidak ada heartbeat "aktif" ke backend selama akses sempit | 0 | 1 (30 PATCH terkirim) | **X-01** (P2, paruh app; paruh extension lewat Q6). Stub `fetchJSON` selalu sukses: yang terbukti "tidak ada cek akses di kode" |
| Flag layer 4 × ambang: 3 total layer 1 sampai 3 × 6 pasangan ambang | 18 | Halaman ber-flag diblokir | 9 | 9 | **sudah diketahui**: X-02 = issue #323 |
| Block memory × shared host: 4 platform shared di backend saja + 1 kontrol | 5 | Halaman lain di platform itu dipindai | 1 | 4 | **sudah diketahui**: X-03 = issue #325 |
| Pill vs island: analyze gagal, analyze ok, verdict aman | 3 | Island tidak pernah bilang lebih dari pill | 1 | 2 | **X-04** (Umar; Q8) |
| Tingkat 2 extension vs island: 5 pasangan ambang × setiap skor warning | 160 | Tingkat sama | 112 | 48 | **X-05** (P3 laten, Umar; catatan di Q8) |
| Identitas di platform bersama: 4 platform non-PSL + 3 kontrol | 7 | Nama yang tampil = tempat halaman berada | 3 | 4 | **X-08** (perlu pertanyaan, Q7a) |
| `POST /scans` + `GET /verdicts` dengan keluaran extension (DB `shoo_f28`) | 15 URL | 201 / 200 | 9 | 6 | **X-06** (4 bentuk nyata; `shop_x.web.app` tidak bisa ada; link 2.121 karakter = B-06) |
| `POST /scans` dengan sinyal detector + `/analyze` asli (11 sinyal, skor 100) | 1 | 201 | 1 | 0 | - |
| Aturan verdict 2 pada shared host | 6 pasangan | Halaman lain → `null` | 4 | 2 | **X-07** (P3; Q7a butir 2) |
| **Total** | **216** | | **140** | **76** | |

Suite yang sudah ada, dijalankan apa adanya: extension 314 / 314, detector 72 / 72, chrome 49 / 49 lulus. `ai`: 184 lulus, 10 file gagal dengan `Cannot find package 'hono'` (worktree ini tanpa `node_modules`): **n/a, lingkungan, bukan temuan**.

Dua sel **perlu iPhone** (langkah di §9): teks dan warna Dynamic Island (X-04, X-05, X-08); alarm per jam tanpa halaman terbuka (X-01).

## 6. Lapis performa (h5): 9 baris yang dijalankan

DB `shoo_f28_perf` (320.000 scan), role `shoo_api`. Angka lengkap dan plan EXPLAIN ada di log.

| Rute / job | Parameter | Nilai | Diharapkan (sumber) | Kenyataan | Hasil |
|---|---|---|---|---|---|
| `GET /scans` | `owner=family` | keluarga terberat, 986 scan | tidak ada anggaran | 1.396 ms SQL, 4 statement | n/a (Q23) |
| `GET /scans` | `owner=family` | keluarga median, 139 scan | tidak ada anggaran | 9,8 ms SQL | n/a (Q23) |
| `GET /scans` | `owner=me&limit=50` | owner terberat, 908 scan | tidak ada anggaran | 109 ms SQL, 70.392 B | n/a (Q23) |
| cron notifikasi | klaim ringkasan mingguan | 40 Guardian, 320.000 scan | < 10.000 ms (`20261022120000_hardening.sql:5`) | 6.101 ms (ulang r1: 6.791 ms) | pass. Sisa waktu tipis: H5-02 (P3 laten) |
| cron retensi | chunk 2.000 | 20.000 scan lewat waktu | tanpa kunci tabel; < 20 s | 36 sampai 45 ms per chunk, kunci baris saja | pass |
| `bundle-size.mjs` | mentah / gzip | `main` | ≤ 295.000 / 97.500 B | 317.017 / 103.739 B | **FAIL → H5-03** |
| Ukuran DB | volume 14 hari | 320.000 scan | 500 MB ≈ 300 ribu scan (`backend/README.md:230`) | 1.260 MB (dibaca ulang r1: 1.258 MB, ≈ 150 MB artefak seed) | **FAIL → H5-01** |
| `POST /scans` | link baru | anggota protected | tidak ada anggaran | 13 statement, 2,41 ms SQL, 26 KB WAL | n/a (Q23) |
| `POST /verdicts` | `not_safe` | Guardian pada scan anggota | tidak ada anggaran | 18 statement, 5,18 ms SQL, 69 KB WAL | n/a (Q23) |

## 7. Lapis UI (h4, dikoreksi r2)

Cakupan: semua yang terlihat di `ios/ShooApp` dan empat halaman web Worker (join, terms, privacy, support). Test: [`h4-Fase28MatrixUITests.swift.txt`](../log/fase-28-repro/h4-Fase28MatrixUITests.swift.txt) (147 method), cek pohon: [`h4-check.py.txt`](../log/fase-28-repro/h4-check.py.txt), pembuat matriks: [`h4-gen-matrix.py.txt`](../log/fase-28-repro/h4-gen-matrix.py.txt), banding teks Figma: [`h4-figcmp.py.txt`](../log/fase-28-repro/h4-figcmp.py.txt), halaman web: [`h4-pages.test.ts.txt`](../log/fase-28-repro/h4-pages.test.ts.txt).

Satu sel = satu state yang direkam (satu screenshot + satu pohon aksesibilitas) di satu konfigurasi. Repo menyimpan 24 pohon yang dikutip plan (`../log/fase-28-repro/h4-tree-*.json.txt`, data mock); sisanya tidak disimpan.

### 7.1 Inventaris

| Layar | Elemen yang dicek |
|---|---|
| Splash carousel (ON-01) | 3 halaman, judul, isi, titik halaman, tombol Start |
| Name (ON-02) | judul, baris avatar, kolom nama, tombol hapus, penghitung n/20, Continue (footer menempel), keyboard |
| Turn on extension (ON-04) | ilustrasi, langkah, petunjuk status (switchedOff / someSitesOnly / notSeen), checkbox consent, link "see data sent" + sheet, CTA, link tutorial (footer menempel) |
| Safari default, Extension on, Guardian intro, pertanyaan consent data | judul, langkah / isi, tombol utama + kedua |
| Session expired | badge, judul, isi, "Set up again" |
| Guardian Home (GD-01) | toggle mode, tombol profil, judul hero per state, kartu pending (domain, skor, pemilik, alasan, Aman / Bahaya), kartu pemberitahuan (gagal muat, gagal simpan), strip keluarga, baris terbaru (domain, pemilik, waktu, badge), See all, tab bar |
| Home Pribadi | hero, kartu extension, statistik, carousel scam, baris terbaru |
| Protected Home (PR-04) | hero, pill Guardian, kartu blokir terakhir, state verdict, kartu supervised, carousel scam, baris terbaru |
| Activity (GD-05) | judul, pemilih orang, 3 segmen filter, header tanggal, baris (domain, badge, pemilik, waktu), state kosong / gagal / refresh gagal / load-more gagal / extension mati |
| Detail (DT-01, GD-07) | kembali, hero, pill link, judul, baris diakses, skor, chip profil, sinyal, kartu bukti + zoom, footer verdict (pertanyaan, Aman, Bahaya), hasil verdict + Change, catatan terkunci, state memuat / gagal / hilang |
| Profile (PF-01) + halaman | header, slot keluarga, undang, baris; halaman: mode, edit profil, koneksi, notifikasi, bahasa, tema, aksesibilitas, tentang |
| Member detail (GD-03) | kartu header, pill status, statistik, toggle notify, scan terbaru, See all, putuskan, state gagal / hilang |
| Sheet dan alert | avatar, edit nama, quiet hours, alasan aman, matikan extension, nyalakan (protected), hapus akun (guardian / protected), undang (penuh), alert notify gagal, alert notifikasi mati, pemberitahuan undangan deep link |
| Connect (PR-01 / PR-02) | tab Code / Scan QR, 6 kotak kode, baris error per kode error, hitung mundur coba lagi, catatan 14 hari, Connect, Later, layar sukses |
| Web: join | valid, kedaluwarsa, tak dikenal, bentuk salah, kode terlalu panjang; baris kode, salin, tombol install, petunjuk, "minta kode baru" |
| Web: terms, privacy, support | judul, daftar, link, ganti bahasa lewat `Accept-Language` |

### 7.2 Dimensi

| Dimensi | Nilai | Dijalankan |
|---|---|---|
| Ukuran data | kosong, 1, 3 (keluarga penuh), berat (1.284 scan), akhir paging | ya (skenario empty, oneMember, threeMembers, heavy) |
| Teks | nama panjang, nama emoji, domain panjang (63+ karakter), domain punycode, nama di batas 20 karakter, mengetik melewati batas | ya (skenario edge + mengetik) |
| Teks | nama RTL di data, domain 253 karakter, host alamat IP, IDN bentuk Unicode | **tidak: butuh skenario** (tidak ada `MockScenario`) |
| State data | memuat, termuat, gagal, lama + refresh gagal, hilang (404), sesi berakhir, extension mati (4 alasan), notifikasi ditolak | ya |
| Peran / mode | Guardian family, Guardian Pribadi, Protected terhubung, Protected sendiri | ya |
| Perangkat | iPhone SE generasi 3 (375 pt), iPhone 17 (402 pt), iPhone 17 Pro Max (440 pt) | ya |
| Dynamic Type | default (L), AX5 | ya. **AX3 (batas proyek) tidak dijalankan** |
| Tema | terang, gelap | ya |
| Bahasa | ID, EN | ya |
| Bold text, Increase contrast | saklar in-app (`-settings.boldText`, `-settings.highContrast`) + Increase Contrast simulator | hanya konfigurasi B |
| Bold Text sistem, Reduce Motion, Reduce Transparency | pengaturan sistem | perlu iPhone (test berjalan dengan `-UITestStillLoops`) |
| Interaksi | double tap verdict, tarik saat memuat, toggle mode cepat, tutup sheet saat submit, keyboard naik | A dan F |
| Pasangan | SE × AX5 × ID (F), 17 × AX5 × gelap (D), SE × EN (E), Max × EN × gelap × bold × contrast (B) | ya |

### 7.3 Konfigurasi

| Tag | Perangkat · bahasa · ukuran · tema | Simulator | Method | Sel dijalankan (r2) |
|---|---|---|---|---|
| A | iPhone 17 · ID · default · terang | "Shoo F28" | 147: 146 lulus; `test005_on_ext_switchedOff` mulai tetapi tanpa baris hasil dan tanpa sel | 194 |
| F | iPhone SE generasi 3 · ID · AX5 · terang | "Shoo F28 SE" | 147: 144 lulus, 3 gagal (`test001`, `test002`, `test082`: kolom tidak bisa difokus di AX5) | 191 |
| D | iPhone 17 · ID · AX5 · gelap | "Shoo F28" | **set kecil 52**: 51 lulus, 1 gagal (`test082`) | 82 |
| E | iPhone SE generasi 3 · EN · default · terang | "Shoo F28 SE" | **set kecil 52**: 52 lulus | 83 |
| B | iPhone 17 Pro Max · EN · default · gelap · Bold + Contrast in-app + Increase Contrast simulator | "Shoo F28 Max" | **set kecil 52, berhenti di 40**: 38 lulus, 2 gagal karena infrastruktur (`test059` timeout event, `test071` app tanpa proses), **12 tidak dijalankan** | 63 |

Jumlah sel dijalankan: 194 + 191 + 82 + 83 + 63 = 613. Hunter menulis 203 / 201 / 85 / 86 / 65 untuk kolom yang sama; itu hitungan file gambar, bukan sel yang valid. Angka r2 yang dipakai.

Set kecil 52 method mencakup onboarding, tiga Home, Activity, Detail, Profile, dan sheet alasan aman dengan skenario figma dan edge. Semua test berjalan dengan `-test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 -only-testing:ShooAppUITests/Fase28MatrixUITests`.

### 7.4 Cakupan per layar (app)

"Total" = sel berbeda × 5 konfigurasi. n/a dan perlu iPhone adalah baris tambahan (nilai dimensi yang tidak bisa direkam suite) dan **tidak** masuk "Total".

| Layar | Total | Dijalankan | Lulus | Gagal | n/a | Perlu iPhone | Tidak valid / butuh skenario | Tidak dijalankan |
|---|---|---|---|---|---|---|---|---|
| Onboarding (ON-01..ON-05) | 105 | 62 | 44 | 18 | 0 | 2 | 5 | 38 |
| Session expired | 5 | 5 | 5 | 0 | 1 | 0 | 0 | 0 |
| Guardian Home (GD-01) | 100 | 65 | 54 | 11 | 2 | 4 | 2 | 33 |
| Home Pribadi | 30 | 18 | 15 | 3 | 2 | 0 | 0 | 12 |
| Protected Home (PR-04) | 85 | 55 | 46 | 9 | 2 | 0 | 0 | 30 |
| Activity (GD-05) | 125 | 75 | 38 | 37 | 1 | 1 | 7 | 43 |
| Detail (DT-01, GD-07) | 180 | 114 | 69 | 45 | 1 | 4 | 0 | 66 |
| Profile + halaman (PF-01) | 180 | 110 | 102 | 8 | 0 | 1 | 2 | 68 |
| Member detail (GD-03) | 50 | 29 | 19 | 10 | 2 | 0 | 1 | 20 |
| Sheet | 70 | 36 | 35 | 1 | 1 | 1 | 8 | 26 |
| Pairing: Connect + deep link (PR-01, PR-02, PR-03) | 60 | 30 | 29 | 1 | 0 | 1 | 2 | 28 |
| Interaksi | 35 | 14 | 14 | 0 | 0 | 0 | 0 | 21 |
| **Total app** | **1.025** | **613** | **470** | **143** | **12** | **14** | **27** | **385** |

Baris Home Pribadi sudah memuat koreksi r2: sel `home-pb` jatuh ke kelompok "Other" di skrip hunter dan tidak tercetak. Tambahannya: total +5, dijalankan +2, lulus +1 (`A`), gagal +1 (`F`, U-04), tidak dijalankan +3. Tabel hunter (dan tabel per layar di plan) menulis baris itu 25 / 16 / 14 / 2 / 9 dengan total 1.020 / 611 / 469 / 142 / 382.

Tabel per layar di §7.7 dihitung ulang dengan skrip saat dokumen ini ditulis: 205 sel berbeda, 613 dijalankan, 470 pass, 143 FAIL, 27 tidak valid, 385 tidak dijalankan, 146 tanda temuan. Sama dengan hitungan r2.

**Sel gagal per temuan:** U-01 2 · U-02 2 · U-03 8 · U-04 19 · U-05 15 · U-06 17 · U-07 40 · U-08 1 · U-09 1 · U-11 1 · U-12 33 · U-17 7 = 146 tanda. 3 sel membawa dua temuan, jadi 143 sel. U-10 dihitung di tabel target sentuh (§7.9). U-13 sampai U-15 dihitung di tabel web (§7.8). U-16 dan U-18 adalah temuan teks tanpa sel sendiri.

### 7.5 Cara membaca "pass" dan "FAIL" di lapis ini

Test matriks **tidak menegaskan nilai**. Test hanya merekam layar dan pohon aksesibilitas. Tanda pass / FAIL dipasang sesudahnya oleh skrip.

- **"pass" bukan berarti cek otomatis bersih.** Skrip pembuat matriks tidak membaca hasil cek (`chk-*.txt`). 50 sel "pass" punya baris OVERLAP / OFFX / UNDERTAB / NOTE / EN. Kebanyakan derau cek: carousel scam horizontal memberi OFFX, teks di bawah bagian footer Detail yang tidak tembus memberi OVERLAP, tip keyboard memberi EN.
- **Minimal 2 temuan nyata tersembunyi di kolom pass:** `E/on-ext` dan `E/on-ext-switchedOff` (U-06 pada ukuran default di iPhone SE; bukti: [`U-06_se-default-extension-steps-hidden.jpg`](img/fase-28/U-06_se-default-extension-steps-hidden.jpg), [`h4-tree-E-on-ext.json.txt`](../log/fase-28-repro/h4-tree-E-on-ext.json.txt)). Ditandai [a] di tabel.
- **105 dari 146 tanda FAIL** (U-05, U-06, U-07, U-08, U-12) berasal dari nama sel + konfigurasi, bukan dari pohon. 81 dari 143 sel gagal tidak punya baris cek sama sekali.
- **Sampel r2: 29 sel gagal dilihat.** 24 menunjukkan temuannya. 3 tidak: `D/on-name`, `D/dt-g-blocked-end`, `D/dt-g-edge-long-end` (ditandai [b]: **false positive check script**). 2 lemah: `F/member-edge-long` (baris tidak ada di frame), `F/pf-fail-me` (tombol terpotong, bukan kolom terjepit) (ditandai [c]).
- `D/member-disconnect-confirm` berisi layar Detail, layar yang salah di bawah nama itu, dan dihitung pass (ditandai [d]).
- 16 dari 19 sel U-04 ditandai aturan lebar, bukan cek. 32 dari 40 sel U-07 punya baris OVERLAP. Semua 33 sel U-12 ditandai nama + konfigurasi; 6 dari 6 yang disampel benar.
- Tidak semua sel pass dilihat mata. Yang dilihat ada di §7.12.

### 7.6 Hasil yang diharapkan per layar

| Layar | Diharapkan untuk setiap sel layar itu (sumber) |
|---|---|
| Onboarding | judul, langkah, dan kedua tombol terbaca dan terjangkau; petunjuk status cocok dengan state extension; teks consent lengkap (PRD ON-01..ON-05, frame onboarding Figma) |
| Session expired | teks "Sesi berakhir" dan satu tombol (frame state Figma 1685:5288) |
| Guardian / Pribadi / Protected Home | teks hero cocok dengan state data: tidak pernah "protected" tanpa data termuat; kartu di dalam lebar layar; tidak ada yang dibutuhkan tersembunyi di bawah tab bar (PRD GD-01, PR-04; Figma 1382:2599, 1665:3038, 1665:3183, 1742:5421) |
| Activity | baris menampilkan domain terdaftar, pemilik, waktu, badge; tiap state (kosong, gagal, refresh gagal, load-more gagal, extension mati) menampilkan teksnya sendiri (PRD GD-05; Figma 416:9208, 1685:5288) |
| Detail | link, judul, skor, alasan terbaca; pertanyaan footer dan kedua tombol terbaca; state memuat / gagal / hilang dengan teksnya (PRD DT-01, GD-07; Figma 1211:19924, 1685:5288) |
| Profile + halaman | setiap label dan nilai baris terbaca; halaman ter-render (PRD PF-01) |
| Member detail | header, statistik, toggle, scan terbaca; state gagal / hilang (PRD GD-03) |
| Sheet | judul, isi, aksi utama terjangkau, juga saat keyboard naik |
| Pairing | tiap kode error server menampilkan barisnya; hitung mundur saat terkunci; catatan terbaca (PRD PR-01, PR-02, PR-03; Figma 1619:2259) |
| Interaksi | tap kedua / tarik / tutup saat permintaan berjalan menyisakan satu state yang konsisten, tanpa permintaan ganda |

### 7.7 Tabel per layar

Kolom = konfigurasi A, F, D, E, B (§7.3). `pass` = tanda skrip, lihat §7.5. `FAIL U-nn` = ID temuan di plan. `-` = tidak direkam di konfigurasi itu (di luar set kecil, atau run berhenti). `tidak valid` = sel direkam tetapi tidak sah (alasan di §7.11).

Catatan koreksi r2: [a] dihitung pass, tetapi U-06 nyata di sel ini · [b] false positive check script: tidak ada yang tertutup · [c] bukti lemah · [d] layar salah di bawah nama ini · [e] sel yang hilang dari tabel hunter.

Catatan koreksi ronde 6 (dari pohon, bukan dari tanda skrip): [f] pohon: tombol di bawah keyboard (`safeReason.submit` y 497,5 sampai 553,5; input view mulai y 407, keyboard y 451); screenshot tanpa keyboard (diambil sebelum pohon): tidak sah sebagai pass; tanda pass dari aturan U-11 yang hanya berlaku di A (`h4-gen-matrix.py.txt:53`), walau skrip cek menandai `UNDERKB` ([`h4-tree-E-sheet-safeReason-kb.json.txt`](../log/fase-28-repro/h4-tree-E-sheet-safeReason-kb.json.txt), [`U-11_se-en-cell-E-screenshot-without-keyboard.jpg`](img/fase-28/U-11_se-en-cell-E-screenshot-without-keyboard.jpg)) · [g] pohon: pesan di bawah tepi atas tab bar (D: pesan berakhir y 814,3, tab bar y 791, 23,3 pt; B: berakhir y 881,3, tab bar y 873, 8,3 pt); negatif palsu skrip: aturan U-02 ([`h4-gen-matrix.py.txt`](../log/fase-28-repro/h4-gen-matrix.py.txt) `:33-36`) hanya membandingkan tombol `state.notice.action` ("Coba lagi" / "Try again") dengan tombol tab (D: tombol berakhir y 689,3 < 795; B: 871,3 < 877), bukan seluruh pesan dengan `Tab Bar` ([`h4-tree-D-home-g-verdict-failed.json.txt`](../log/fase-28-repro/h4-tree-D-home-g-verdict-failed.json.txt), [`h4-tree-B-home-g-verdict-failed.json.txt`](../log/fase-28-repro/h4-tree-B-home-g-verdict-failed.json.txt)). Sel yang dipakai sebagai penjaga di plan dicek dengan angka pohon di langkahnya, bukan dari tanda `pass` ini.

#### Onboarding (ON-01..ON-05)

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `consent-question` | pass | FAIL U-08 | - | - | - |
| `guardian-intro` | pass | pass | - | - | - |
| `on-connected` | tidak valid | tidak valid | tidak valid | tidak valid | tidak valid |
| `on-datasent-sheet` | pass | pass | pass | pass | pass |
| `on-ext` | pass | FAIL U-06 | FAIL U-06 | pass [a] | pass |
| `on-ext-agreed` | pass | FAIL U-06 | FAIL U-06 | pass | pass |
| `on-ext-consent-unanswered` | pass | FAIL U-06 | - | - | - |
| `on-ext-consent-unanswered-end` | pass | FAIL U-06 | - | - | - |
| `on-ext-notSeen` | pass | FAIL U-06 | - | - | - |
| `on-ext-someSitesOnly` | pass | FAIL U-06 | - | - | - |
| `on-ext-switchedOff` | - | FAIL U-06 | FAIL U-06 | pass [a] | pass |
| `on-ext-switchedOff-end` | - | FAIL U-06 | FAIL U-06 | pass | pass |
| `on-extensionOn` | pass | FAIL U-06 | - | - | - |
| `on-name` | pass | FAIL U-06 | FAIL U-06 [b] | pass | pass |
| `on-name-rtl-emoji-kb` | pass | - | - | - | - |
| `on-name-toolong-kb` | pass | - | pass | pass | pass |
| `on-name-typed-kb` | pass | - | pass | pass | pass |
| `on-safariDefault` | pass | FAIL U-06 | FAIL U-06 | pass | pass |
| `on-splash-1` | pass | pass | - | - | - |
| `on-splash-2` | pass | pass | - | - | - |
| `on-splash-3` | pass | pass | - | - | - |

#### Session expired

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `session-expired` | pass | pass | pass | pass | pass |

#### Guardian Home (GD-01)

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `home-g-allSafe` | pass | pass | - | - | - |
| `home-g-edge` | pass | pass | pass | pass | pass |
| `home-g-edge-end` | pass | FAIL U-04 | FAIL U-04 | pass | pass |
| `home-g-edge-mid` | pass | pass | pass | pass | pass |
| `home-g-empty` | pass | pass | - | - | - |
| `home-g-empty-end` | pass | pass | - | - | - |
| `home-g-extoff` | pass | pass | pass | pass | pass |
| `home-g-fail` | pass | pass | pass | pass | pass |
| `home-g-figma` | pass | pass | pass | pass | pass |
| `home-g-figma-end` | pass | FAIL U-04 | FAIL U-04 | pass | pass |
| `home-g-figma-mid` | pass | pass | pass | pass | pass |
| `home-g-heavy` | pass | pass | - | - | - |
| `home-g-loading` | FAIL U-01 | FAIL U-01 | - | - | - |
| `home-g-mixed` | pass | FAIL U-03 | - | - | - |
| `home-g-notif-denied-alert` | pass | pass | - | - | - |
| `home-g-one` | pass | pass | - | - | - |
| `home-g-three` | pass | FAIL U-03 | - | - | - |
| `home-g-three-end` | pass | FAIL U-03 | - | - | - |
| `home-g-verdict-failed` | FAIL U-02 | FAIL U-02 | pass [g] | pass | pass [g] |
| `home-g-verdict-safe-tapped` | tidak valid | tidak valid | - | - | - |

#### Home Pribadi

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `home-pb-alone` | pass | pass | pass | pass | pass |
| `home-pb-alone-end` | pass | FAIL U-04 | pass | pass | pass |
| `home-pb-checking` | pass | pass | - | - | - |
| `home-pb-end` | pass | pass | - | - | - |
| `home-pb` | pass [e] | FAIL U-04 [e] | - | - | - |
| `home-pb-extoff` | pass | FAIL U-04 | - | - | - |

#### Protected Home (PR-04)

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `home-p-checking` | pass | pass | - | - | - |
| `home-p-edge` | pass | FAIL U-03 | FAIL U-03 | pass | pass |
| `home-p-edge-end` | pass | FAIL U-03 | FAIL U-03 | pass | pass |
| `home-p-extoff` | pass | FAIL U-03 | - | - | - |
| `home-p-fail` | pass | pass | pass | pass | pass |
| `home-p-loading` | pass | pass | - | - | - |
| `home-p-protectedAlone` | pass | pass | pass | pass | pass |
| `home-p-protectedAlone-end` | pass | FAIL U-04 | pass | pass | pass |
| `home-p-protectedBlocked` | pass | pass | pass | pass | pass |
| `home-p-protectedBlockedSafe` | pass | pass | - | - | - |
| `home-p-protectedBlockedSafe-end` | pass | FAIL U-04 | - | - | - |
| `home-p-protectedBlockedScam` | pass | pass | - | - | - |
| `home-p-protectedQuiet` | pass | FAIL U-04 | - | - | - |
| `home-p-protectedWarning` | pass | pass | - | - | - |
| `home-p-protectedWarning-end` | pass | FAIL U-04 | - | - | - |
| `home-p-protectedWarningSafe` | pass | pass | pass | pass | pass |
| `home-p-protectedWarningScam` | pass | pass | - | - | - |

#### Activity (GD-05)

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `act-empty` | pass | FAIL U-12 | FAIL U-12 | pass | pass |
| `act-empty-warning` | pass | FAIL U-12 | FAIL U-12 | pass | pass |
| `act-fail` | pass | FAIL U-12 | FAIL U-12 | pass | pass |
| `act-g-allSafe-blocked` | pass | FAIL U-12 | - | - | - |
| `act-g-edge` | FAIL U-05 | FAIL U-05,U-12 | FAIL U-05,U-12 | FAIL U-05 | FAIL U-05 |
| `act-g-edge-picker` | tidak valid | tidak valid | - | - | - |
| `act-g-empty-family` | pass | FAIL U-12 | - | - | - |
| `act-g-figma` | pass | FAIL U-12 | FAIL U-12 | pass | pass |
| `act-g-figma-end` | pass | FAIL U-12 | FAIL U-12 | pass | pass |
| `act-g-heavy` | pass | FAIL U-12 | - | - | - |
| `act-g-heavy-end` | pass | FAIL U-12 | - | - | - |
| `act-g-one-person` | pass | FAIL U-12 | - | - | - |
| `act-g-picker` | tidak valid | tidak valid | tidak valid | tidak valid | tidak valid |
| `act-g-warning` | pass | FAIL U-12 | - | - | - |
| `act-loading` | pass | FAIL U-12 | - | - | - |
| `act-loadmore-failed` | pass | FAIL U-12 | - | - | - |
| `act-off` | pass | FAIL U-12 | FAIL U-12 | pass | pass |
| `act-p-blocked` | pass | FAIL U-12 | - | - | - |
| `act-p-edge` | FAIL U-05 | FAIL U-05,U-12 | - | - | - |
| `act-p-empty` | pass | FAIL U-12 | - | - | - |
| `act-p-fail` | pass | FAIL U-12 | - | - | - |
| `act-p-figma` | pass | FAIL U-12 | FAIL U-12 | pass | pass |
| `act-p-figma-end` | pass | FAIL U-12 | FAIL U-12 | pass | pass |
| `act-pb-figma` | pass | FAIL U-12 | - | - | - |
| `act-refresh-failed` | pass | FAIL U-12 | FAIL U-12 | pass | - |

#### Detail (DT-01, GD-07)

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `dt-after-notsafe` | pass | FAIL U-07 | - | - | - |
| `dt-fail` | pass | FAIL U-07 | FAIL U-07 | pass | pass |
| `dt-g-blocked` | pass | FAIL U-07 | FAIL U-07 | FAIL U-17 | FAIL U-17 |
| `dt-g-blocked-end` | pass | FAIL U-07 | FAIL U-07 [b] | pass | pass |
| `dt-g-blocked-mid` | pass | FAIL U-07 | FAIL U-07 | pass | pass |
| `dt-g-edge-long` | FAIL U-17 | FAIL U-07 | FAIL U-07 | FAIL U-17 | FAIL U-17 |
| `dt-g-edge-long-end` | pass | FAIL U-07 | FAIL U-07 [b] | pass | pass |
| `dt-g-edge-long-mid` | pass | FAIL U-07 | FAIL U-07 | pass | pass |
| `dt-g-edge-one` | pass | FAIL U-07 | - | - | - |
| `dt-g-edge-one-end` | pass | FAIL U-07 | - | - | - |
| `dt-g-edge-one-mid` | pass | FAIL U-07 | - | - | - |
| `dt-g-none` | pass | FAIL U-07 | - | - | - |
| `dt-g-notsafe` | pass | FAIL U-07 | - | - | - |
| `dt-g-notsafe-end` | pass | FAIL U-07 | - | - | - |
| `dt-g-notsafe-mid` | pass | FAIL U-07 | - | - | - |
| `dt-g-safe` | pass | FAIL U-07 | FAIL U-07 | pass | - |
| `dt-g-safe-end` | pass | FAIL U-07 | FAIL U-07 | pass | - |
| `dt-g-safe-mid` | pass | FAIL U-07 | FAIL U-07 | pass | - |
| `dt-g-warning` | pass | FAIL U-07 | - | - | - |
| `dt-g-warning-end` | pass | FAIL U-07 | - | - | - |
| `dt-g-warning-mid` | pass | FAIL U-07 | - | - | - |
| `dt-gone` | pass | FAIL U-07 | FAIL U-07 | pass | pass |
| `dt-loading` | pass | pass | - | - | - |
| `dt-p-blocked` | pass | pass | pass | pass | pass |
| `dt-p-blocked-end` | pass | pass | pass | pass | pass |
| `dt-p-blocked-mid` | pass | pass | pass | pass | pass |
| `dt-p-safe` | pass | pass | - | - | - |
| `dt-p-safe-mid` | pass | pass | - | - | - |
| `dt-p-verdict` | pass | pass | - | - | - |
| `dt-p-verdict-mid` | pass | pass | - | - | - |
| `dt-p-warning` | pass | pass | - | - | - |
| `dt-p-warning-mid` | pass | pass | - | - | - |
| `dt-pb-own` | pass | FAIL U-07 | - | - | - |
| `dt-pb-own-mid` | pass | FAIL U-07 | - | - | - |
| `dt-screenshot-zoom` | pass | FAIL U-07 | - | - | - |
| `dt-verdict-failed` | FAIL U-17 | FAIL U-07 | FAIL U-07 | pass | FAIL U-17 |

#### Profile + halaman (PF-01)

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `pf-fail-family` | pass | pass | - | - | - |
| `pf-fail-me` | pass | FAIL U-04 [c] | pass | pass | pass |
| `pf-g-edge` | pass | pass | pass | pass | pass |
| `pf-g-edge-mid` | pass | pass | pass | pass | pass |
| `pf-g-empty` | pass | pass | - | - | - |
| `pf-g-extoff` | pass | pass | - | - | - |
| `pf-g-figma` | pass | pass | pass | pass | pass |
| `pf-g-figma-end` | pass | FAIL U-04 | FAIL U-04 | pass | pass |
| `pf-g-heavy` | pass | pass | - | - | - |
| `pf-g-three` | pass | pass | - | - | - |
| `pf-loading` | pass | pass | - | - | - |
| `pf-mode-from-supervised` | pass | pass | - | - | - |
| `pf-mode-locked` | pass | pass | - | - | - |
| `pf-p` | pass | pass | pass | pass | pass |
| `pf-p-alone` | pass | pass | - | - | - |
| `pf-p-alone-page-connection` | pass | pass | - | - | - |
| `pf-p-edge` | pass | pass | - | - | - |
| `pf-p-edge-page-connection` | pass | pass | - | - | - |
| `pf-p-end` | pass | FAIL U-04 | FAIL U-04 | pass | pass |
| `pf-p-page-connection` | pass | pass | - | - | - |
| `pf-p-page-editProfile` | pass | pass | - | - | - |
| `pf-p-page-mode` | pass | pass | - | - | - |
| `pf-p-page-notifications` | pass | FAIL U-04 | - | - | - |
| `pf-page-about` | pass | pass | pass | pass | - |
| `pf-page-about-end` | pass | pass | pass | pass | - |
| `pf-page-accessibility` | pass | pass | pass | pass | pass |
| `pf-page-accessibility-end` | pass | pass | pass | pass | pass |
| `pf-page-connection` | tidak valid | tidak valid | - | - | - |
| `pf-page-editProfile` | pass | pass | - | - | - |
| `pf-page-language` | pass | pass | - | - | - |
| `pf-page-mode` | pass | pass | pass | pass | pass |
| `pf-page-notifications` | pass | FAIL U-04 | pass | pass | pass |
| `pf-page-notifications-end` | pass | pass | pass | pass | pass |
| `pf-page-theme` | pass | pass | - | - | - |
| `pf-pb` | pass | pass | - | - | - |
| `pf-pb-end` | pass | FAIL U-04 | - | - | - |

#### Member detail (GD-03)

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `member-disconnect-confirm` | pass | tidak valid | pass [d] | pass | - |
| `member-edge-bayu` | pass | pass | - | - | - |
| `member-edge-long` | FAIL U-05 | FAIL U-05 [c] | FAIL U-05 | FAIL U-05 | - |
| `member-edge-long-end` | FAIL U-05 | FAIL U-05 | FAIL U-05 | FAIL U-05 | - |
| `member-fail` | pass | FAIL U-07 | - | - | - |
| `member-figma` | pass | pass | pass | pass | - |
| `member-figma-end` | pass | pass | pass | pass | - |
| `member-gone` | pass | FAIL U-07 | - | - | - |
| `member-heavy` | pass | pass | - | - | - |
| `member-notify-failed` | pass | pass | - | - | - |

#### Sheet

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `sheet-avatar` | pass | pass | - | - | - |
| `sheet-delete-guardian` | pass | pass | pass | pass | - |
| `sheet-delete-protected` | pass | pass | - | - | - |
| `sheet-invite` | tidak valid | tidak valid | tidak valid | tidak valid | - |
| `sheet-invite-fail` | tidak valid | tidak valid | - | - | - |
| `sheet-invite-full` | pass | pass | pass | pass | - |
| `sheet-invite-loading` | tidak valid | tidak valid | - | - | - |
| `sheet-name-edit` | pass | pass | pass | pass | - |
| `sheet-name-edit-typed-kb` | pass | pass | pass | pass | - |
| `sheet-quiet-hours` | pass | pass | pass | pass | - |
| `sheet-safeReason` | pass | pass | pass | pass | pass |
| `sheet-safeReason-kb` | FAIL U-11 | - | - | pass [f] | pass |
| `sheet-turnOff` | pass | pass | - | - | - |
| `sheet-turnOn-protected` | pass | pass | - | - | - |

#### Pairing: Connect + deep link (PR-01, PR-02, PR-03)

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `connect-err-already` | pass | pass | pass | pass | - |
| `connect-err-attempts` | pass | pass | pass | pass | - |
| `connect-err-expired` | pass | pass | - | - | - |
| `connect-err-full` | pass | pass | - | - | - |
| `connect-err-invalid` | pass | pass | - | - | - |
| `connect-err-ratelimit` | pass | pass | - | - | - |
| `connect-kb` | pass | pass | pass | pass | - |
| `connect-prefilled` | pass | pass | pass | pass | - |
| `connect-scan-tab` | FAIL U-09 | pass | - | - | - |
| `connect-success` | pass | pass | - | - | - |
| `invite-notice-pribadi` | tidak valid | tidak valid | - | - | - |
| `invite-notice-protected-paired` | pass | pass | - | - | - |

#### Interaksi

| Sel | A | F | D | E | B |
|---|---|---|---|---|---|
| `ix-activity-pull-after-load` | pass | pass | - | - | - |
| `ix-activity-pull-during-load` | pass | pass | - | - | - |
| `ix-mode-toggle-rapid` | pass | pass | - | - | - |
| `ix-safeReason-dismiss-done` | pass | pass | - | - | - |
| `ix-safeReason-dismiss-inflight` | pass | pass | - | - | - |
| `ix-verdict-doubletap-done` | pass | pass | - | - | - |
| `ix-verdict-doubletap-inflight` | pass | pass | - | - | - |

### 7.8 Halaman web (Worker)

Di-render lewat handler rute asli di vitest ([`h4-pages.test.ts.txt`](../log/fase-28-repro/h4-pages.test.ts.txt), DB `shoo_f28`). HTML diekspor dan dibuka di Chrome headless di dalam iframe 320 px dan 430 px. Tidak di-render ulang oleh reviewer.

| Halaman | State | Sel (ID / EN × 320 / 430) | Dijalankan | Lulus | Gagal | Temuan |
|---|---|---|---|---|---|---|
| `/join/:code` | kode valid | 4 | 4 | 2 | 2 | **U-13** (320 px, dua bahasa: baris kode melewati padding) |
| `/join/:code` | kedaluwarsa | 4 | 4 | 4 | 0 | - |
| `/join/:code` | tak dikenal | 4 | 4 | 4 | 0 | - |
| `/join/:code` | bentuk salah | 4 | 4 | 4 | 0 | - |
| `/join/:code` | terlalu panjang | 4 | 4 | 4 | 0 | - |
| `/terms` | - | 4 | 4 | 0 | 4 | **U-14** (`(/privacy)` teks biasa) |
| `/privacy` | - | 4 | 4 | 4 | 0 | - (hanya 1.400 px pertama yang dilihat) |
| `/support` | - | 4 | 4 | 4 | 0 | - |
| **Total web** | | **32** | **32** | **26** | **6** | |

- **U-15** (petunjuk ID bilang link "sudah kami salin" sebelum ada tap) adalah temuan teks di halaman kode valid. Dihitung di halaman U-13, bukan sel tambahan.
- Empat state tidak valid: diharapkan satu pesan netral tanpa petunjuk apakah kode pernah ada (keputusan PR-03). Kenyataan: empat halaman hanya berbeda di nonce CSP dan cocok dengan Figma 1619:7334.
- Mode gelap: halaman join menyatakan `color-scheme: light` (**n/a, 20 sel**). Terms, privacy, support punya gaya `prefers-color-scheme: dark` yang **tidak dijalankan** (12 sel). Zoom teks browser: **tidak dijalankan**. Safari iOS asli: perlu iPhone (§9 nomor 7).

### 7.9 Target sentuh (konfigurasi A, elemen × ukuran ≥ 44 pt)

Elemen interaktif berbeda dengan pengenal di konfigurasi A: **164**. Pass (≥ 44 pt di sisi pendek): **128**. FAIL: **36** → **U-10** (P3, confidence "likely"). Ukuran = frame aksesibilitas, bukan area sentuh: 36 adalah batas atas. Tidak dihitung ulang r2 dari pohon. Cek satu per satu di iPhone sebelum memperbaiki (§9).

| Elemen | Ukuran (pt) | Elemen | Ukuran (pt) |
|---|---|---|---|
| `pencil` | 12 × 12 | `safeReason.chip.other` | 75 × 36 |
| `xmark.circle.fill` | 17 × 17 | `accessibility.bold` | 320 × 36 |
| `detail.verdictChange` | 35 × 18 | `accessibility.contrast` | 320 × 36 |
| `activity.loadMoreRetry` | 210 × 18 | `accessibility.haptics` | 320 × 36 |
| `profile.name` | 279 × 22 | `turnOn.close` | 68 × 36 |
| `extension.consent` | 354 × 24 | `member.notify` | 320 × 42 |
| `invite.close` | 27 × 36 | `linked.autoSend` | 320 × 42 |
| `filter.all` | 114 × 28 | `linked.shareWarnings` | 320 × 42 |
| `filter.warning` | 114 × 28 | `notifications.blocked` | 320 × 42 |
| `filter.blocked` | 114 × 28 | `notifications.family` | 320 × 42 |
| `invite.done` | 28 × 36 | `notifications.protectionOff` | 320 × 42 |
| `notifications.quietHours` | 320 × 28 | `notifications.summary` | 320 × 42 |
| `activity.refreshFailed` | 199 × 30 | `profile.sheet.close` | 42 × 42 |
| `family.invite` | 92 × 34 | `safeReason.close` | 42 × 42 |
| `quiet.save` | 81 × 35 | `xmark` | 42 × 42 |
| `safeReason.chip.official_site` | 94 × 36 | `turnOff.close` | 42 × 42 |
| `safeReason.chip.known_site` | 141 × 36 | `extension.dataSent` | 155 × 42 |
| `safeReason.chip.used_before` | 158 × 36 | | |
| `safeReason.chip.trusted_sender` | 207 × 36 | | |

Catatan r2 dari kode: `activity.loadMoreRetry` punya `.frame(maxWidth: .infinity, minHeight: 44)` di dalam labelnya (`ActivityView.swift:216`), jadi area sentuhnya kemungkinan cukup. `detail.verdictChange` punya frame 44 pt di luar Button (`DetailFooter.swift:220`), yang tidak memperbesar area sentuh.

### 7.10 Sel n/a (dengan alasan)

| Layar | n/a | Nilai dimensi → alasan |
|---|---|---|
| Session expired | 1 | keyboard → tidak ada kolom teks |
| Guardian Home | 2 | keyboard → tidak ada kolom teks; peran Protected → rute tidak ada untuk peran itu |
| Home Pribadi | 2 | keyboard → tidak ada kolom teks; peran Protected → sama |
| Protected Home | 2 | keyboard → tidak ada kolom teks; peran Guardian → sama |
| Activity | 1 | keyboard → tidak ada kolom teks |
| Detail | 1 | bahasa EN / ID di dalam kartu bukti → teksnya milik halaman scam |
| Member detail | 2 | keyboard → tidak ada kolom teks; peran Protected → layar khusus Guardian |
| Sheet | 1 | peran Protected × sheet undang → khusus Guardian |
| **Total app** | **12** | |
| Halaman web join | 20 | tema gelap → halaman menyatakan `color-scheme: light` |

### 7.11 Tidak dijalankan (tidak pernah dihitung pass)

| Apa | Yang dibutuhkan |
|---|---|
| Sheet undang dengan kode hidup (QR, kode, salin, bagikan, hitung mundur) dan state gagalnya | Keluarga mock dengan kurang dari 3 anggota, dibuka lewat Profile → Invite. Sel hunter memakai skenario `figma` (3 anggota), jadi hanya "keluarga penuh" yang terlihat. Sel `sheet-invite`, `sheet-invite-fail`, `sheet-invite-loading` tidak valid |
| State Home `verdict_not_allowed` ("Can't be marked yet") | Scan pending yang verdict-nya ditolak server. Sel `home-g-verdict-safe-tapped` tidak valid |
| Pemilih orang Activity terbuka (baris menu, nama panjang di menu) | `-debug.activityPicker` tidak membuka menu di bawah XCUITest. Sel `act-g-picker`, `act-g-edge-picker` tidak valid |
| Langkah onboarding "Connected" | Flag debug tidak menangani `connected`. Sel `on-connected` tidak valid |
| Pemberitahuan undangan deep link di Pribadi tanpa alert notifikasi di atasnya | Mock dengan notifikasi sudah diizinkan. Sel `invite-notice-pribadi` tidak valid |
| `pf-page-connection`, `F/member-disconnect-confirm` | Sel direkam tetapi tidak sah |
| Nama anggota RTL (Arab / Ibrani) di baris, pill, dan judul | Skenario dengan `displayName` RTL (kolom Name menerima input RTL + emoji di A) |
| Domain 253 karakter, host alamat IP, IDN tampil sebagai Unicode | Baris skenario dengan host itu |
| Sel keyboard di AX5 (kolom Name, catatan alasan aman) | Di AX5 kolom tidak bisa difokus dari test (lihat U-06) |
| **Dynamic Type AX3** | Tidak dijalankan. Sub-fase 28n; hasilnya masuk `log/fase-28.md` |
| Konfigurasi D, E, B untuk sel di luar set kecil 52 test; 12 method terakhir B | Tidak dijalankan (waktu, beban Mac). Kolom menampilkan "-" |
| Indonesia di iPhone SE ukuran default | E = Inggris. Tidak ada konfigurasi SE × ID × default |
| `test005_on_ext_switchedOff` di A | Tanpa baris hasil; dua selnya "-" di A |

### 7.12 Screenshot yang dilihat

- Hunter: A semua 203 gambar di contact sheet; F semua 201; D 26 sel (onboarding, Home, Activity, Detail, Protected Home, Home Pribadi); E 40 sel (onboarding, Home, Activity, Detail, Profile, sheet alasan aman); B 20 sel (onboarding, Home, Activity, Detail). Sisa sel D / E / B hanya dicek skrip. Setiap sel gagal dilihat minimal sekali di konfigurasi tempat ia gagal.
- Reviewer r2: 29 sel gagal di F, D, B, ditambah 12 gambar bukti.
- Figma: 65 frame hanya dibandingkan teksnya, bukan piksel. Reviewer tidak membuka Figma.

## 8. Peta sel gagal → temuan

Setiap sel gagal menunjuk ke ID yang ada di plan, atau ditandai. Tanda yang dipakai: **false positive check script** · **ditolak reviewer** · **sudah diketahui** (dengan rujukan) · **pertanyaan** (nomor draf) · **dijelaskan, bukan temuan** (alasan di plan).

| Lapis | Sel gagal | Peta |
|---|---|---|
| API, dalam 1.642 | 4 | B-06 1 · B-07 3 |
| API, test kebenaran | 4 | B-04 4 |
| Logika app | 30 | A-01 3 · pertanyaan Q16 3 (Detail, Profile, Member detail) · A-03 A-10 10 · A-04 7 (desain diputuskan, Q4) · A-05 5 (Q5) · A-08 2 |
| Rantai, jaringan | 10 | X-10 7 · X-09 3. Tambahan 4 n/a = sudah diketahui BH-41 = #454 butir E (cache verdict 60 s juga untuk `safe`) |
| Rantai, normalisasi | 12 baris | X-06 5 · X-11 1 · dijelaskan, bukan temuan 6 (fallback `content.js`, §12) |
| Rantai, skenario | 76 | X-01 1 · X-05 48 · X-06 6 · X-04 2 · X-07 2 · pertanyaan Q7a 4 (X-08) · sudah diketahui 13 (X-02 9 = #323; X-03 4 = #325) |
| UI app | 143 (146 tanda) | U-01 2 · U-02 2 · U-03 8 · U-04 19 · U-05 15 · U-06 17 · U-07 40 · U-08 1 · U-09 1 · U-11 1 · U-12 33 · U-17 7. Di dalamnya: 3 false positive check script (`D/on-name`, `D/dt-g-blocked-end`, `D/dt-g-edge-long-end`), 2 bukti lemah (`F/member-edge-long`, `F/pf-fail-me`) |
| UI web | 6 | U-13 2 · U-14 4 |
| Performa | 2 | H5-03 1 · H5-01 1 |
| **Jumlah** | **287** | **287 terpetakan: 281 ke ID · 6 dijelaskan, bukan temuan** |

Di luar jumlah itu (baris massal, bukan sel): 7.607 dari 8.637 suffix PSL → X-11 (dibaca ulang r3, yang berdiri 6 suffix `.id`); 23 dari 99 shared host → X-03, sudah diketahui (#325); 36 dari 164 target sentuh → U-10; baris variasi jamak katalog → A-14.

Temuan di plan yang **tidak punya sel matriks** (bukti dari repro sendiri atau baca kode; lihat log): A-02, A-06, A-07, A-12, A-15, B-01, B-02, B-03, U-15, U-16, U-18, X-12, H5-02, OPT-01 sampai OPT-12. **Ditolak reviewer:** B-05, A-11, A-16, PR-C-11. **Sudah diketahui:** B-08 dan A-13 (#476), A-17 (BH-31: hero hanya membaca scan pending), OPT-08 (fase 22 K5).

## 9. Perlu iPhone

Tidak bisa dijalankan di simulator atau Node. Belum ada yang dijalankan.

### 9.1 UI: 9 cek, 14 sel

Pembagian 14 sel per layar: cek 1 = 4 layar, cek 2 = 3, cek 3 = 2, cek 4 = 2, dan masing-masing 1 untuk cek 5, 6, 8. Cek 7 adalah web. Cek 9 di luar cakupan.

| # | Sel | Langkah | Diharapkan |
|---|---|---|---|
| 1 | Bold Text sistem × setiap tab | Settings → Accessibility → Display & Text Size → Bold Text nyala. Buka Shoo: Home, Activity, satu Detail, Profile | Tidak ada label terpotong yang tidak terpotong tanpa Bold |
| 2 | Reduce Motion × splash, hero Home, hero Detail | Settings → Accessibility → Motion → Reduce Motion nyala. Cold start Shoo, buka satu Detail | Tidak ada animasi berulang; hanya cross-fade |
| 3 | Reduce Transparency × tab bar dan sheet | Settings → Accessibility → Display & Text Size → Reduce Transparency nyala. Gulung Home sampai baris lewat di bawah tab bar | Tab bar tidak tembus; tidak ada yang terbaca menembusnya |
| 4 | Urutan VoiceOver di kartu pending Home dan footer Detail | VoiceOver nyala, usap kanan dari hero | domain → skor → pemilik → alasan → Aman → Bahaya; footer terjangkau |
| 5 | Push asli → Detail | Dari HP kedua picu situs blocked; ketuk notifikasi di HP Guardian | Detail scan itu terbuka, bukan Home |
| 6 | Pindai QR dengan kamera (Connect → Scan QR) | Guardian menampilkan QR undangan; Protected memindainya | Kode terisi, Connect aktif; state kamera ditolak menampilkan teks "masukkan kodenya" |
| 7 | Halaman join di Safari iOS asli pada 320 pt (iPhone SE generasi 1 / Display Zoom) | Buka `https://<api>/join/<kode valid>` | Enam digit di dalam padding kartu (U-13); tombol install menyalin link lalu membuka store |
| 8 | Petunjuk status extension Safari (ON-04) dengan saklar asli | Matikan extension / pilih "some sites only" di Settings → Safari → Extensions, kembali ke Shoo | Petunjuk cocok dengan state asli |
| 9 | Dynamic Island / Live Activity | Di luar cakupan `ios/ShooApp` (owner Umar) | - |

### 9.2 Rantai: 2 sel

| Sel | Temuan | Langkah | Yang dibaca |
|---|---|---|---|
| Teks dan warna Dynamic Island | X-04, X-05, X-08 | Hentikan layanan AI, biarkan backend hidup. Buka satu halaman di Safari dengan extension menyala | Teks island dibanding teks pill di halaman |
| Alarm per jam tanpa halaman terbuka | X-01 | Set Shoo ke "Deny" untuk semua situs. Biarkan Safari terbuka lebih dari satu jam | Nilai `ext_last_seen_at` device itu di server (baca saja) |

### 9.3 Di luar sel

| Apa | Temuan | Langkah |
|---|---|---|
| Jalur extension pada akses dipersempit | X-01 paruh extension (Q6 butir 2) | Ubah akses Safari untuk Shoo dari "All websites" ke beberapa situs. Buka halaman di situs yang diizinkan. Cek apakah `PATCH /devices/me` dari background page sampai (nilai `ext_last_seen_at` berubah atau tidak) |
| 36 target sentuh | U-10 | Untuk tiap elemen di §7.9: ketuk di tepi frame yang terlihat. Catat mana yang tidak merespons di area 44 × 44 pt |
| Catatan 14 hari di tab Pindai QR dengan kamera asli | U-09 | Connect → Pindai QR di iPhone 17, ID, ukuran default. Lihat apakah catatan berjalan di bawah "Nanti saja" |
| Ukuran performa di perangkat | lihat plan §Batas audit | Waktu launch, frame rate, biaya decode daftar Family Home, biaya extension di Safari |

## 10. Sel tanpa hasil yang diharapkan

Sel ini tidak punya sumber yang menetapkan hasil yang benar. Tidak dihitung gagal sebagai bug. Nomor draf merujuk ke plan → "Draf pertanyaan (belum dibuka)".

| Lapis | Sel | Yang belum ditetapkan | Draf |
|---|---|---|---|
| API | Push pertama per situs ditahan (quiet hours, tanpa token, saklar mati, batas) | "Kunjungan pertama" atau "pertama terkirim" (B-01) | Q1 |
| API | `notified` saat push gagal | Kata "got" di kontrak vs "queued" di `backend/API.md` (B-05 ditolak) | Q2 |
| API | `detectedAt` +6 menit → 422 | Nasib scan dari HP dengan jam terlalu cepat (B-03) | Q3 |
| API | Key tak dikenal di `PATCH /devices/me` → 200 | Strict atau tidak | Q12 |
| API | Nama dengan zero-width diterima | Tolak `\p{Cf}` atau tidak | Q13 |
| API | Ringkasan mingguan "1 site", Profile "3" | Satuan tiap angka | Q14 |
| Logika app | Hitung mundur kode × selisih jam (7 sel) | Boleh memakai `Date` / `serverNow` (A-04) | Q4 |
| Logika app | Heartbeat dari masa depan (5 sel) | Toleransi yang dimaksud (A-05) | Q5 |
| Logika app | Refresh gagal di Detail, Profile, Member detail (3 sel) | Apakah A12 berlaku di tiga layar itu | Q16 |
| Logika app | Satu baris beracun (8 sel) | Decode per baris, case `unknown`, `url` sebagai `String` (A-03 A-10) | Q11 |
| Rantai | Akses Safari dipersempit | Yang seharusnya dilihat Guardian (X-01) | Q6 |
| Rantai | Identitas di platform bersama (4 sel) | Arti "situs" untuk shared host (X-08) | Q7a butir 1 |
| Rantai | `not_safe` di shared host menjangkau host lain (2 sel) | Kasus `host_path` (X-07) | Q7a butir 2 |
| Rantai | Host tanpa domain terdaftar ditolak 422 | Isi `domain` untuk host itu (X-06) | Q7b |
| Rantai | Island "Aman" saat pill tidak (2 sel), tingkat warning 2 (48 sel) | Aturan badge / pill belum dibawa ke island (X-04, X-05) | Q8 |
| Rantai | Verdict `safe` vs entri blocklist global yang datang kemudian | Dimaksudkan atau tidak | Q9 |
| Rantai | Jawaban blocklist kosong / rusak (3 sel) | Klien menjaga salinan atau tidak (X-09) | Q10 |
| UI | `home-g-loading` (2 sel) | Teks hero saat memuat; tidak ada frame Figma (U-01) | Q15 |
| UI | Semua sel yang hanya gagal di AX5 (U-03, U-04, U-07, U-08, U-12, bagian AX5 dari U-06) | Batas Dynamic Type yang didukung: AX3 atau AX5 | Q18 (ukur AX3 dulu: 28n) |
| UI | `dt-g-blocked`, `dt-g-edge-long`, `dt-verdict-failed` pada ukuran default (7 sel) | Fade footer memang diinginkan atau tidak (baris yang tidak terbaca bukan pertanyaan: U-17) | Q19 |
| UI | Tema gelap: halaman tetap terang | Pilihan "Dark" tetap, ganti nama, atau disembunyikan | Q20 butir 4 |
| UI | Teks app vs frame state Figma (U-16) | Sisi mana yang benar | Q22a |
| UI | "belajar mingguan" untuk "weekly review" (A-15) | Kata yang dipakai | Q22b |
| UI | Teks "Anda" dan "kamu" tercampur | Suara produk | Q21 |
| Performa | 5 baris tanpa anggaran latensi | Anggaran waktu jawab per rute | Q23 |
| Performa | Gerbang bundle gagal | Step CI dan batas baru (H5-03) | Q26 |

## 11. Screenshot

Semua dari simulator sesi ini. Nama file = ID temuan.

| Temuan | File | Isi |
|---|---|---|
| U-01 | [`U-01_guardian-home-loading-says-protected.jpg`](img/fase-28/U-01_guardian-home-loading-says-protected.jpg) | Guardian Home saat muatan pertama: "Keluarga Terlindungi!" di atas baris skeleton |
| U-02 | [`U-02_verdict-failed-notice-under-tabbar.jpg`](img/fase-28/U-02_verdict-failed-notice-under-tabbar.jpg) | Pesan gagal simpan setengah tertutup tab bar |
| U-03 | [`U-03_se-ax5-home-wider-than-screen.jpg`](img/fase-28/U-03_se-ax5-home-wider-than-screen.jpg) | SE × AX5: halaman Home lebih lebar dari layar |
| U-04 | [`U-04_se-ax5-recent-row-domain-squeezed.jpg`](img/fase-28/U-04_se-ax5-recent-row-domain-squeezed.jpg) | SE × AX5: domain tercetak 1 sampai 2 karakter per baris |
| U-05 | [`U-05_activity-row-tail-truncates-host.jpg`](img/fase-28/U-05_activity-row-tail-truncates-host.jpg) | Baris Activity memotong ekor host (kiri Activity, kanan kartu Home) |
| U-06 | [`U-06_se-default-extension-steps-hidden.jpg`](img/fase-28/U-06_se-default-extension-steps-hidden.jpg) | SE × ukuran default × EN (sel `E/on-ext`, dihitung "pass" oleh skrip): judul dan baris consent tampil, tiga langkah di belakang footer. Bagian yang membuat U-06 P2 |
| U-06 (AX5, P3) | [`U-06_se-ax5-onboarding-footer-covers-content.jpg`](img/fase-28/U-06_se-ax5-onboarding-footer-covers-content.jpg) | SE × AX5: footer onboarding menutup isi |
| U-07 | [`U-07_se-ax5-detail-footer-overlaps.jpg`](img/fase-28/U-07_se-ax5-detail-footer-overlaps.jpg) | SE × AX5: footer Detail menimpa judul |
| U-08 | [`U-08_se-ax5-consent-buttons-truncated.jpg`](img/fase-28/U-08_se-ax5-consent-buttons-truncated.jpg) | SE × AX5: tombol consent terpotong |
| U-09 | [`U-09_connect-scan-note-clipped.jpg`](img/fase-28/U-09_connect-scan-note-clipped.jpg) | Connect, tab Pindai QR: catatan di bawah "Nanti saja" |
| U-11 | [`U-11_safe-reason-submit-under-keyboard.jpg`](img/fase-28/U-11_safe-reason-submit-under-keyboard.jpg) | Sheet alasan aman: tombol di bawah keyboard |
| U-13 | [`U-13_join-page-320-code-row.png`](img/fase-28/U-13_join-page-320-code-row.png) | Halaman join pada 320 px: baris kode melewati padding |
| U-17 | [`U-17_se-detail-heading-shows-through-footer.jpg`](img/fase-28/U-17_se-detail-heading-shows-through-footer.jpg) | SE ukuran default: judul tembus di belakang pertanyaan footer |

Tanpa screenshot: U-10 (daftar di §7.9), U-12 (sel `act-*` di F dan D; gambarnya tidak disimpan di repo), U-14 sampai U-16 dan U-18 (baca kode atau pohon).

## 12. Belum terpetakan

Kosong sejak review plan ronde 1 (14 Nov 2026). Satu-satunya kelompok yang dulu di sini sekarang dijelaskan:

| Lapis | Sel | Kenyataan | Putusan |
|---|---|---|---|
| Rantai, normalisasi (`h3-norm.mjs`) | 6 baris URL bertanda `fallback≠PSL`, antara lain `https://login.bca.co.id.verifikasi.xyz/a`, `https://sites.google.com/view/x`, `https://docs.google.com./forms/d/1`, `https://a_b.example.com/a` | Fallback `registrableDomain` di `content.js:18-30` (dua kali coba, lalu host tanpa `www.`) memberi host penuh, bukan jawaban PSL. Chip dan lookup verdict di halaman itu lalu memakai host penuh; `blocked-page.js:146-153` tidak poll | **Dijelaskan, bukan temuan.** Hanya menyala kalau background page tidur dua kali; background menurunkan ulang domain sebelum `POST /scans` (#375, `background.js:38-45,217`). Hunter 3 mencatatnya "no (rare)". Baris di plan → Inventaris fallback → "Fail-wrong yang diperiksa dan bukan temuan". Satu baris catatan untuk Umar ikut laporan LANGKAH MANUAL |

## Retest

Belum ada. Blok ini diisi setelah 28a dan 28b merge (plan → Kriteria selesai, R7 §4): sel yang diulang, konfigurasi, hasil, nomor PR.
