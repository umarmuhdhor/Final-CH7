# Plan: kirim 25 link scam + 11 legit ke LLM (Layer 4, prompt v4, deepseek-v4-flash thinking off)

Status: **plan**. Belum dijalankan. Belum ada commit.
Pemilik: **Imelda** (`ai/`). Semua langkah di `ai/test-layer4/`. `src/` dan `prompts/` tidak diubah.
Skrip: `run.mjs` (belum ditulis). Hasil: `HASIL.md`. Data mentah: `.hasil/*.json` (di-gitignore).

## Tujuan

Untuk tiap link, catat:
1. Apa yang **L2** temukan, dan bagian mana yang dikirim ke LLM.
2. Apa yang **L3** temukan, dan bagian mana yang dikirim ke LLM.
3. **Jawaban LLM**: `page_type`, `asks`, `reasonable`, `confidence`, `evidence`, dan apakah sinyal `unreasonable_request` (+30) muncul.
4. **Waktu** panggilan LLM (ms).
5. **Token** (input, output, total).

## Keputusan (dari tanya-jawab 30 Okt 2026)

| # | keputusan |
|---|---|
| K1 | **Semua 25 scam dipaksa dikirim**, gate dilewati. Kolom "gate produksi" tetap dicatat: di produksi link itu dipanggil atau tidak |
| K2 | **Batas waktu 8 dtk** per panggilan (batas ekstensi). Lebih dari 6 dtk ditandai "di produksi kena timeout" (`MAX_TIMEOUT_MS` 6000) |
| K3 | **Tiap link 3 kali**. Laporan: median dan p95 waktu, dan apakah jawabannya sama di ketiga putaran |
| K4 | **Tambah 10 legit** (L01–L10), juga dipaksa dikirim (sama dengan K1) |
| K5 | **Prompt v4 saja** (`reality-check.v4`). Tidak ada perbandingan dengan v3 |
| K6 | **Domain disamarkan** di `HASIL.md` (`bni-diirect[.]com`). Payload mentah hanya di `.hasil/` |
| K7 | **Model `deepseek-v4-flash`, thinking off** (`chat_template_kwargs: {thinking: false}`, cara yang terbukti di `ai/testing/26-oct-2026/16-testing-23.53`). Field ini hanya ditambahkan di skrip tes; `src/layer4/provider.js` belum mengirimnya, jadi produksi masih thinking on |
| K8 | **Tambah 1 sampel legit**: `trap-github-pages-dokumentasi` dari `ai/eval/data/legit/traps.json` (sintetis). Tes 27 Okt: halaman ini jadi false positive setelah info L2 (`freehost`, `path-bait`) dikirim ke LLM. v4 juga mengirim `free_host` / `path_bait`, jadi risikonya dicek langsung |

Total panggilan: 36 link × 3 = **108**. Perkiraan token: ~1,1k per panggilan → **~120k token**.

## Data per link

Sumber: `ai/test-layer3/snapshots/01–25.json` (scam) dan `L01–L10.json` (legit). Semua diambil 28 Okt. Tidak ada permintaan baru ke situs scam.

### L2 (di ekstensi, offline)
- Jalankan `ios/ShooExtension/Resources/detector.js` lewat `vm` (cara yang sama dengan `test-layer2/analyze.mjs`), `analyzeLocal(snapshot)`. Yang dibaca cuma teks URL, tidak ada jaringan. L1 (blocklist) mati karena `ShooLists` tidak ada.
- **Dicatat**: semua sinyal L2 (`suspicious_link` + semua kode, `lookalike_domain`, dst) beserta bobotnya.
- **Dikirim ke LLM**: `link_checks`, yaitu kode dari `suspicious_link` yang ada di `LINK_TEXT` (5 kode: `free_host`, `free_name_bait`, `free_name_number`, `free_file_bait`, `path_bait`).

### L3 (di server, offline)
- `analyze(snapshot, { localSignals, rdap: null, llm: null })`. Sinyal L2 ikut masuk, jadi naiknya bobot kata (D-imelda-31) juga terhitung.
- **Dicatat**: id sinyal + bobot, skor L3, umur domain (`rdapAgeDays` dari snapshot, cuma untuk info).
- **Dikirim ke LLM**: `site`, `title`, `fields` (tanpa hidden/button), `brands`, `rules`. **Umur domain tidak dikirim.**

### L4 (LLM)
- `buildInput(snapshot, ruleIds, localSignals)`, lalu `SYSTEM_PROMPT` + `DATA_START…DATA_END`, persis seperti produksi.
- Panggil provider dari `.env` (`createProvider`) dengan `fetch` yang dibungkus. Bungkusnya mengukur waktu dan membaca `usage` dari respons (`prompt_tokens`, `completion_tokens`, `total_tokens`).
- Jawaban dicek dengan `parseVerdict`. Aturan sinyal sama dengan `reality.js`: sinyal muncul kalau `reasonable: false`, `confidence ≥ 0.6`, dan `asks` tidak kosong.
- Gate dilewati dengan memanggil `buildInput` + provider langsung, bukan `check()`. `check()` dipakai di produksi dan tetap tidak berubah.

## Isi HASIL.md

**Tabel per link** (satu baris per link, 3 putaran dirangkum):

| kolom | isi |
|---|---|
| id, domain | `01`, `bni-diirect[.]com` |
| gate produksi | dipanggil / tidak (alasan: skor < 15, tidak ada field) |
| L2 ditemukan | kode + bobot |
| L2 dikirim | `link_checks` |
| L3 ditemukan | id sinyal + bobot, skor |
| L3 dikirim | `rules`, `brands`, jumlah field + label |
| LLM | `page_type`, `asks`, `reasonable`, `confidence`, `evidence` |
| +30? | ya / tidak |
| konsisten | sama di 3 putaran / beda (sebutkan) |
| waktu | median, maks (ms); tanda kalau > 6 dtk |
| token | input / output / total (rata-rata 3 putaran) |

**Detail per link**: JSON persis yang dikirim (domain disamarkan) + jawaban mentah LLM dari putaran 1.

**Ringkasan**:
- Scam yang dapat +30: X / 25 (dan X / 21 untuk yang lolos gate produksi)
- Legit yang dapat +30: X / 11 (false positive; trap GitHub Pages ditulis terpisah)
- Waktu: median, p95, maks; jumlah > 6 dtk; jumlah timeout 8 dtk
- Token: total, rata-rata per panggilan, input vs output
- Gagal: `bad_schema`, `http_error`, `timeout`
- Jawaban yang berubah antar putaran
- Model + `PROMPT_VERSION` + commit

## Batas lulus (usulan, ditetapkan sebelum mengukur)

| ukuran | batas |
|---|---|
| legit dapat +30 | 0 / 11 |
| `bad_schema` | 0 |
| p95 waktu | ≤ 6 dtk (batas produksi) |
| jawaban berubah antar putaran | 0 link |

Scam yang tertangkap dilaporkan saja, tanpa batas, karena belum ada angka pembanding.

## Prasyarat

| butir | cara cek | kalau tidak ada |
|---|---|---|
| Node ≥ 22 | `node --version` | pasang Node |
| LLM nyala | `grep -c '^LLM_' ai/.env` = `3`. **Jangan cetak isi `.env`** | isi dari `.env.example` |
| Snapshot | `ls ai/test-layer3/snapshots` → `01–25`, `L01–L10` | ambil ulang lewat `test-layer3/PROMPT.md` |
| detector.js | `ios/ShooExtension/Resources/detector.js` ada | `detector/scripts/build.mjs` |
| Versi kode | `git rev-parse --short HEAD`, `git status --short ai/` | catat di hasil |

## Langkah

Waktu di sini = **perkiraan lama mengerjakan**, bukan hasil ukur.

| # | langkah | perkiraan |
|---|---|---|
| 1 | Tulis `run.mjs`: muat snapshot → L2 → L3 → payload → LLM × 3 → `.hasil/l4.json` | 45 mnt |
| 2 | Uji kering: `--dry` (tanpa LLM) cetak payload 01, 11, L01. Cek tidak ada teks halaman, path URL, atau nilai | 10 mnt |
| 3 | Uji 1 link (01) ke LLM. Cek `usage` ada di respons | 5 mnt |
| 4 | Jalankan penuh: 108 panggilan, satu per satu (tidak paralel, supaya waktunya tidak saling ganggu) | ~10 mnt |
| 5 | `run.mjs --report` → tulis `HASIL.md` | 20 mnt |
| 6 | Baca hasil, tulis temuan + usulan perubahan prompt (kalau ada) | 20 mnt |

## Catatan dan risiko

- **Dipaksa ≠ produksi.** Link 11 tidak punya field, jadi `fields: []`. Jawaban LLM di situ cuma info, bukan bukti kemampuan L4. Ringkasan memisahkan "21 yang lolos gate" dan "semua 25".
- **Token bisa tidak ada.** Kalau provider tidak mengirim `usage`, kolom token ditulis `n/a` dan diganti perkiraan (karakter ÷ 4) yang diberi tanda.
- **Data lama.** Snapshot dari 28 Okt. Situs scam mungkin sudah mati, tapi itu tidak penting karena yang dipakai snapshot.
- **Kunci API** hanya dibaca dari `.env`. Tidak pernah dicetak, tidak masuk `.hasil/` atau `HASIL.md`.
- **Biaya**: ~108 panggilan, ~120k token. `LLM_DAILY_CAP` tidak berlaku karena skrip memanggil provider langsung.

## Tidak termasuk

Prompt v3, RDAP live, membuka situs scam, mengubah `src/` / `prompts/` / `contracts/`, Safari / Simulator.
