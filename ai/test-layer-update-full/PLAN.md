# Plan: bandingkan arsitektur lama dan baru di 75 link asli, sampai Layer 4

Status: **plan**. Belum dijalankan.
Pemilik: **Imelda** (`ai/`). Semua file baru di `ai/test-layer-update-full/`. `src/` dan `prompts/` tidak diubah.
Skrip: `run.mjs` (belum ditulis). Hasil: `HASIL.md`. Data mentah: `.hasil/*.json` (di-gitignore).
Jalankan dari branch `feat/AI-M4-thinking-off-asks-otp-boxes` (PR #232, commit `2c51aee` atau sesudahnya).

## Pertanyaan yang dijawab

Link mana yang hasilnya berubah dibanding arsitektur sebelumnya?

## Tiga versi yang dibandingkan

| Kolom | Kode | Gate LLM | Bobot flag | Confidence | Yang dikirim ke LLM |
|---|---|---|---|---|---|
| **Lama** | `ai/` di `3459f58` | ada form + skor aturan L3 >= 15, bukan situs resmi | 30 | 0,6 | prompt v4, tanpa umur |
| **Baru (A)** | `ai/` di branch ini | total L1-L3 30-79, bukan situs resmi, form tidak wajib | `max(30, 80 - total)` | 0,7 | prompt v4, tanpa umur |
| **Baru + umur (C)** | sama dengan A | sama dengan A | sama dengan A | 0,7 | prompt v5 hanya di skrip: A ditambah `site_age` |

Skor L1-L2 dan aturan L3 sama di ketiganya.

## Keputusan (tanya-jawab 2 Nov 2026)

| # | Keputusan |
|---|---|
| K1 | Data asli saja, tanpa sintetis. Tiap link **satu kali** ke LLM |
| K2 | L1 mati (`ShooLists` tidak ada), L2 `detector.js` apa adanya dengan batas 25 (#231 belum dijawab), L3 dan L4 jalan penuh |
| K3 | LLM: `reality-check.v4`, `deepseek-v4-flash`, thinking off (sudah di `provider.js`) |
| K4 | RDAP **live**, batas **1 detik**, satu lookup per domain. Hasilnya dipakai ketiga versi, supaya perbedaan hanya datang dari gate, bobot, dan confidence |
| K5 | Batas LLM di tes **6,5 detik**, ditambah RDAP 1 detik. Angka produksi tidak diubah di tes ini |
| K6 | Jawaban LLM dipakai bersama: request yang isinya sama hanya dikirim sekali |
| K7 | Opsi C hanya diuji untuk link yang `new_domain`-nya menyala dan lolos gate baru. Prompt v5 tidak masuk `prompts/` |
| K8 | Domain disamarkan di `HASIL.md` (`bni-diirect[.]com`). Payload mentah hanya di `.hasil/` |

## Sampel: 75 link (26 scam, 49 legit)

| Sumber | Jenis | Jumlah |
|---|---|---|
| `ai/test-layer3/snapshots/01-25.json` | scam | 25 |
| `ai/eval/data/scam/seed.json`, `synthetic !== true` | scam | 1 |
| `ai/test-layer3/snapshots/L01-L10.json` | legit | 10 |
| `ai/eval/data/legit/real.json`, `synthetic !== true` | legit | 35 |
| `ai/eval/data/legit/seed.json`, `synthetic !== true` | legit | 4 |

- `ai/eval/data/scam/real.json` (2 sampel) tidak dipakai: host-nya sama dengan snapshot 04 dan 13.
- Tidak dipakai: `scam/synthetic.json`, `legit/traps.json`, `legit/url-shapes.json`, karena sintetis.
- Skrip harus berhenti kalau jumlahnya bukan 26 + 49.
- Situs scam tidak dibuka. Isi halaman dari snapshot yang sudah ada.

## Alur per link

1. **L2:** `analyzeLocal(snapshot)` dari `ios/ShooExtension/Resources/detector.js` lewat `vm`, hasilnya `localSignals`.
2. **RDAP:** satu lookup live lewat `createRdapClient` dari `ai/src/rdap/rdap.js` dengan `timeoutMs: 1000` dan `fetch` asli, tanpa cache lintas link. Situs resmi tidak di-lookup (`isOfficialHost`). Hasil dipakai sebagai `rdap: { lookupAgeDays: async () => age }` di ketiga versi. Yang dikirim hanya nama domain.
3. **Lama:** `analyze` dan `createRealityCheck` dari `.hasil/old/ai/src/`.
4. **Baru (A):** `analyze` dan `createRealityCheck` dari `ai/src/`.
5. **Baru + umur (C):** seperti A, dengan `fetch` yang mengubah body sebelum dikirim. Hanya untuk link di K7.
6. **Skor dan tingkat:** `validSignals`, `mergeSignals`, `scoreFrom`, `statusFor`, `THRESHOLD` dari `ios/ShooExtension/Resources/pipeline.js` lewat `vm`.

### Cara memuat kode lama

```bash
mkdir -p ai/test-layer-update-full/.hasil/old
git archive 3459f58 ai/src ai/prompts detector/data | tar -x -C ai/test-layer-update-full/.hasil/old
```

Sudah dicoba: `.hasil/old/ai/src/analyze.js` bisa dimuat berdampingan dengan kode baru, dan pada LLM tiruan kedua versi mengirim body yang sama persis. Lihat `.hasil/probe.mjs`.

### Konfigurasi `createRealityCheck` (ketiga versi)

Baca `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` dari `ai/.env`. Isi config lewat skrip, bukan `readConfig`, karena `readConfig` membatasi timeout di 6 detik:

```js
{ baseUrl, apiKey, model, timeoutMs: 6500, dailyCap: 1e6 }
```

Selalu `clientCallsPerHour: Infinity`. `deadline` di `analyze` tidak diisi. Cek nama field config di `ai/src/layer4/config.js` dulu.

### Jawaban LLM dipakai bersama (K6)

`fetch` yang diberikan ke `createRealityCheck` menyimpan promise per isi `init.body`. Request kedua dengan body sama mendapat jawaban yang sama. Catat `ms`, `usage`, dan `outcome` per request asli. Body lama dan baru harus sama persis untuk satu link. Kalau tidak sama, berhenti dan laporkan.

### Prompt v5 di skrip (opsi C)

Teks ini ditetapkan sebelum mengukur. Skrip harus berhenti kalau salah satu penggantian tidak menemukan teks asalnya.

Di system message:

1. Setelah baris yang diawali `- link_checks: codes of our checks on the page address:`, tambahkan baris:
   `- site_age: how old the site's domain is, for example "3 days old"; only present when the domain is under 90 days old`
2. Ganti `rules and link_checks help you understand` menjadi `rules, link_checks and site_age help you understand`.

Di user message, tambahkan `"site_age": "<N> days old"` ke JSON antara `DATA_START` dan `DATA_END`.

`N` = umur dari lookup K4. Flag tetap memakai aturan `reality.js` versi baru.

## Definisi "beda"

Tingkat: **normal** (0-29), **warning 1** (30-49), **warning 2** (50-79), **blokir** (80+).

| Link | Lama | Baru | Dihitung |
|---|---|---|---|
| A | 65, warning 2 | 95, blokir | **beda** |
| B | 85, blokir | 85, blokir | sama |
| C | 40, warning 1 | 45, warning 1 | sama, angkanya dicatat terpisah |

Bandingkan Lama dengan A, dan A dengan C.

## Isi HASIL.md

Ikuti pola `ai/test-layer4/HASIL.md`: blok otomatis dari `run.mjs --report`, lalu bagian "Analisis" yang ditulis tangan.

**Ringkasan:**
- Jumlah link beda (Lama lawan A), per scam dan legit, naik dan turun
- Tabel jumlah link per tingkat untuk tiap versi, scam dan legit terpisah
- Legit yang kena flag dan yang kena blokir di tiap versi
- Panggilan LLM: lama saja, baru saja, keduanya, tidak ditanya; berapa dari halaman tanpa form
- Hasil C: flag tambahan, flag yang hilang, legit yang terkena
- Waktu LLM: median, p95, maks; jumlah > 5,5 dtk dan > 6 dtk; timeout 6,5 dtk
- Token: total dan rata-rata, termasuk total untuk halaman tanpa form
- RDAP: berhasil, gagal, timeout 1 dtk; berapa link yang kehilangan `new_domain` dibanding umur 28 Okt
- Gagal: `bad_schema`, `http_error`
- Model, `PROMPT_VERSION`, commit, tanggal

**Tabel link yang beda** (paling atas), lalu **tabel semua link**:

`id`, domain, jenis, skor L2, skor L3, umur live, umur 28 Okt, ada form, Lama (skor + tingkat), A (skor + tingkat), C (skor + tingkat, `-` kalau tidak diuji), siapa yang bertanya (lama/baru), jawaban LLM (`page_type`, `asks`, `reasonable`, `confidence`), waktu (ms), sebab beda.

**Sebab beda** salah satu dari:
- `gate baru: tanpa form`
- `gate baru: skor aturan < 15`
- `gate baru: total >= 80, LLM dilewati`
- `gate baru: total < 30, LLM dilewati`
- `bobot flag`
- `confidence 0,6-0,7`

**Bagian waktu:** untuk link yang LLM-nya di atas 5,5 dtk, tulis juga tingkat A kalau LLM timeout, karena sisa waktu produksi sekarang ±5,5 dtk kalau RDAP dingin.

## Batas lulus (ditetapkan sebelum mengukur)

| Ukuran | Batas |
|---|---|
| Legit diblokir di A | 0 / 49 |
| Legit yang tingkatnya naik dari Lama ke A | 0 |
| `bad_schema` | dilaporkan |
| Timeout 6,5 dtk | dilaporkan |

Scam hanya dilaporkan, tanpa batas.

**Opsi C dipakai** hanya kalau scam yang kena flag bertambah dan legit yang kena flag tidak bertambah dibanding A. Keputusan akhir tetap di Imelda.

## Prasyarat

| Butir | Cara cek | Kalau tidak ada |
|---|---|---|
| Node >= 22 | `node --version` | pasang Node |
| LLM nyala | `grep -c '^LLM_' ai/.env` >= 3. **Jangan cetak isi `.env`** | laporkan ke Imelda |
| Branch | `git log --oneline -5` berisi `2c51aee` | `git checkout feat/AI-M4-thinking-off-asks-otp-boxes` |
| Snapshot | `ls ai/test-layer3/snapshots` berisi 35 file | laporkan ke Imelda |
| `detector.js` | `ios/ShooExtension/Resources/detector.js` ada | laporkan ke Imelda |

## Langkah

| # | Langkah | Panggilan LLM |
|---|---|---|
| 1 | Muat kode lama, tulis `run.mjs` | 0 |
| 2 | `--dry`: LLM tiruan, semua 75 link. Cek jumlah sampel, gate tiap versi, body lama = baru, payload tanpa teks halaman, path URL, atau umur (kecuali C) | 0 |
| 3 | `--only 01`, `--only L01`: LLM sungguhan. Cek `usage` dan `parseVerdict` | maks 4 |
| 4 | Jalankan penuh, satu per satu, tidak paralel | maks ±75 + C |
| 5 | `--report`, tulis `HASIL.md` | 0 |
| 6 | Tulis "Analisis": bedakan yang terbukti dan dugaan | 0 |

Perkiraan biaya: rata-rata 2.251 token per panggilan di tes lalu, jadi maksimal ±169 ribu token untuk 75 link, ditambah panggilan C.

## Catatan dan risiko

- **Satu putaran.** Jawaban LLM bisa berubah antar panggilan (tes lalu: 2 dari 36 link berubah status). Perbedaan Lama lawan A tidak terpengaruh karena memakai jawaban yang sama, tapi perbedaan A lawan C bisa terpengaruh. Tulis itu di Analisis.
- **Umur live.** Umur domain sudah bertambah sejak 28 Okt, dan domain scam bisa sudah hilang dari RDAP, jadi sebagian bisa kehilangan `new_domain`. Hasilnya bisa lebih rendah daripada saat link itu masih baru.
- **RDAP lama 1,5 dtk tidak diuji.** Kedua versi memakai satu lookup 1 dtk. Efek timeout 1,5 dtk lawan 1 dtk tidak terukur di tes ini.
- **Waktu total tidak terukur.** Yang diukur hanya waktu LLM dan RDAP terpisah, bukan jaringan HP.
- **Halaman tanpa form.** Dengan prompt v4 halaman ini tidak bisa di-flag. Tes menghitung berapa panggilan dan token yang terpakai untuk itu.
- **Salah blokir KYC yang sudah diketahui.** `trap-fintech-kyc-sah` tidak ikut karena sintetis, jadi tidak terlihat di tes ini.
- **Kunci API** hanya dibaca dari `.env`. Tidak pernah dicetak, tidak masuk `.hasil/` atau `HASIL.md`.

## Tidak termasuk

L1 dan blocklist, memori blokir di HP (belum ada kodenya, #231), lepas `LINK_PART_CAP`, Safari atau Simulator, membuka situs scam, mengubah `src/`, `prompts/`, `contracts/`, `detector/`, `ios/`, mengubah angka waktu produksi.
