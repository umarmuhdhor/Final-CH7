# Testing 5: tes otomatis setelah perubahan aturan field merek + merek ke LLM (runtime lengkap)

> Tanggal: 26 Okt 2026, 10.54 · menguji perubahan di `../../changes/26-oct-2026/01-changes-10.46/changes.md` · branch lokal `fix/AI-M3-brand-form-fingerprint` (dari `main` @ `a035bb9`, belum di-commit)
> Penguji: Imelda (dijalankan bersama Claude)
> File mentah di folder ini: `output-ai-spec.txt`, `output-detector-spec.txt`, `output-extension-spec.txt`, `per-file.txt`, `slowest.txt`, `new-tests.txt`, `layer3-bench.txt`, `helpnets-offline.txt`, `env.txt`, `time-ai.txt`

## 1. Tujuan

Memastikan perubahan baru (sidik jari field Microsoft di layer 3, `detectBrands` dan prompt v3 di layer 4) tidak merusak tes yang ada, mengukur berapa lama tes berjalan, dan memastikan layer 3 tidak jadi lebih lambat. **Tidak ada panggilan LLM di testing ini** (semua tes memakai `fetch` palsu); lihat bagian 7.

## 2. Lingkungan

| Item | Nilai |
|---|---|
| Mesin | Mac Apple M5, Darwin 25.5.0 arm64 |
| Node | v26.8.1 |
| Runner | `node --test` bawaan Node (reporter `spec`) |
| Commit dasar | `a035bb9` (`main`), dengan perubahan di working tree (belum di-commit) |
| Branch | `fix/AI-M3-brand-form-fingerprint` |
| Jaringan / API key | tidak dipakai (semua panggilan penyedia LLM dan RDAP dipalsukan di tes) |
| Dijalankan | berurutan, satu proses per suite, satu kali (angka waktu dari satu run) |

## 3. Hasil dan runtime per suite

| Suite | Perintah | Tes | Lulus | Gagal | Waktu (duration_ms) |
|---|---|---|---|---|---|
| `ai/` seluruhnya | `cd ai && node --test` | 331 | 331 | 0 | **5.249 ms** (wall-clock 5,30 s; user 7,74 s; sys 0,62 s) |
| `detector/` | `cd detector && node --test` | 38 | 38 | 0 | 810 ms |
| Extension | `node --test ios/ShooExtension/Tests/*.test.mjs` | 151 | 151 | 0 | 527 ms |
| **Total** | | **520** | **520** | **0** | **±6,6 s** |

Catatan: 331 dari `ai/` = 330 tes di 12 file `*.test.mjs` + 1 untuk `test/helpers.mjs`, yang ikut dijalankan sebagai "tes" karena ada di folder `test/`. Sebelum perubahan `ai/` punya 317 tes (testing awal sesi), jadi **+14 tes baru** (semua lulus).

### 3.1 Per file di `ai/`

Dijalankan satu per satu (`node --test <file>`):

| File | Tes | Lulus | Gagal | Waktu |
|---|---|---|---|---|
| `test/analyze.test.mjs` | 22 | 22 | 0 | 237 ms |
| `test/blocklist.test.mjs` | 54 | 54 | 0 | 4.823 ms |
| `test/calibration.test.mjs` | 15 | 15 | 0 | 97 ms |
| `test/content.test.mjs` *(diubah)* | 54 | 54 | 0 | 288 ms |
| `test/fixtures.test.mjs` | 2 | 2 | 0 | 115 ms |
| `test/forms.test.mjs` | 43 | 43 | 0 | 83 ms |
| `test/hardening.test.mjs` | 14 | 14 | 0 | 334 ms |
| `test/layer4.test.mjs` *(diubah)* | 37 | 37 | 0 | 485 ms |
| `test/rdap-kv.test.mjs` | 15 | 15 | 0 | 873 ms |
| `test/rdap.test.mjs` | 27 | 27 | 0 | 582 ms |
| `eval/test/corpus.test.mjs` | 32 | 32 | 0 | 394 ms |
| `eval/test/eval.test.mjs` | 15 | 15 | 0 | 95 ms |

Waktu per file dijumlah (±8,4 s) lebih besar dari 5,2 s karena tiap file dijalankan sendiri-sendiri (start Node dihitung berulang), sedangkan run penuh memakai beberapa proses paralel. `blocklist.test.mjs` memakan sebagian besar waktu.

### 3.2 Tes paling lambat (run penuh)

| Waktu | Tes |
|---|---|
| 2.253 ms | prebuilt: a phone holding the full list still takes the next build's new domains |
| 1.508 ms | size cap: at most MAX_DOMAINS, newest kept |
| 1.112 ms | prebuilt: at most MAX_DOMAINS, newest kept |
| 302 ms | RDAP_KV hanging read + hanging RDAP: the whole lookup still ends at the RDAP deadline |
| 213 ms | run.mjs refuses an option that is missing its value |
| 210 ms | match: text 20,000 chars of repeated near-misses stays fast |
| 207 ms | RDAP_KV hanging read: falls back to RDAP inside the same 1.5 s lookup budget |
| 161 ms | perf: worst NFKC blow-up (18x) stays under 100 ms |

Semuanya tes lama (blocklist dan RDAP, termasuk tes batas waktu yang memang sengaja menunggu). Tidak ada tes baru di daftar ini.

### 3.3 14 tes baru

Semua lulus; masing-masing di bawah 1 ms (0,09–0,72 ms, total ±3,6 ms).

| Tes | Waktu |
|---|---|
| brand form: copied Microsoft form raises brand_logo_offsite (bobot 25, layer 3, tanpa evidence) | 0,72 ms |
| brand form: butuh dua nilai berbeda; satu nilai, walau dua kali, tidak cukup | 0,37 ms |
| brand form: langkah email saja (`loginfmt` + `i0116`) sudah dua nilai | 0,16 ms |
| brand form: cocok persis, tidak peka huruf; nama lebih panjang tidak cocok | 0,23 ms |
| brand form: host Microsoft asli diam; host konten pengguna (`forms.office.com`) tidak dikecualikan | 0,18 ms |
| brand form: tetap satu `brand_logo_offsite` saat alt logo juga cocok; form menang | 0,12 ms |
| brand form: bobot penuh walau tidak ada sinyal `asks_*` | 0,09 ms |
| detectBrands: form Microsoft → `[Microsoft]`; alt "Microsoft" sendirian → kosong | 0,17 ms |
| detectBrands: merek di title dihitung; nama selalu dari `brands.json` | 0,12 ms |
| detectBrands: 3+ merek di alt dilewati; 2 dipertahankan | 0,13 ms |
| detectBrands: tanpa duplikat, maksimal 3 | 0,09 ms |
| brands: form Microsoft mengirim NAMA merek saja, tanpa teks/alt pribadi | 0,49 ms |
| brands: kunci `brands` selalu ada, `[]` bila kosong | 0,62 ms |
| prompt v3: menyebut `brands`, aturan "tidak tepercaya" dan kunci output tetap | 0,11 ms |

## 4. Runtime layer 3 (apakah aturan baru memperlambat?)

`analyzeSnapshot()` pada snapshot `helpnets[.]info`, 5 putaran × 20.000 panggilan setelah 2.000 panggilan pemanasan, tanpa jaringan, Apple M5:

| Versi | Median | Terbaik | Terburuk | Sinyal |
|---|---|---|---|---|
| Sebelum (`main` @ `a035bb9`, worktree sementara) | **43,3 µs/panggilan** | 42,8 µs | 45,6 µs | `asks_password:15` |
| Sesudah (branch ini) | **40,0 µs/panggilan** | 39,8 µs | 43,7 µs | `brand_logo_offsite:25`, `asks_password:15` |

Layer 3 tidak melambat: selisihnya (−3 µs) masih dalam rentang derau antar-putaran. Target di kode (<100 ms CPU) terlampaui jauh (±0,04 ms). Satu panggilan LLM memakan 3.500–11.000 ms (testing 3 dan 4), sehingga layer 3 praktis tidak berpengaruh pada waktu `/analyze`.

## 5. Efek pada sampel `helpnets[.]info` (offline, tanpa LLM)

| | Sebelum | Sesudah |
|---|---|---|
| Sinyal layer 3 | `asks_password` (15) | `brand_logo_offsite` (25, tanpa evidence), `asks_password` (15) |
| Skor layer 3 | 15 | **40** (ambang peringatan 30) |
| Lolos gerbang LLM | ya (skor 15 = `GATE_MIN_SCORE`) | ya |
| Input ke LLM | `{site, title, fields, rules:["asks_password"]}` | `{site, title, fields, brands:["Microsoft"], rules:["brand_logo_offsite","asks_password"]}` |

Detail di `helpnets-offline.txt`.

## 6. Temuan

**T1. Tidak ada regresi.** 520 dari 520 tes di tiga suite lulus; tidak ada tes lama yang berubah hasil.

**T2. Tes lambat berasal dari tes batas waktu lama, bukan kode baru.** Tiga tes `blocklist` (1,1–2,3 s) mendominasi.

**T3. Layer 3 tidak melambat.** 40 µs vs 43 µs per panggilan.

**T4. Skor sampel naik dari 15 ke 40** hanya lewat aturan field (layer 3); belum ada bukti peningkatan dari prompt v3.

## 7. Batasan

- Semua tes memakai LLM palsu. Tidak ada bukti bagaimana model menanggapi prompt v3, dan prompt v3 belum diuji pada situs sah (risiko salah blokir). Karena itu **tidak ada respons LLM nyata** di folder ini; `llm-response.md` hanya memuat request yang akan dikirim.
- Waktu tes dari satu run di satu mesin; tes lambat (blocklist) bergantung CPU dan bisa berubah ±20%.
- Benchmark layer 3 mengukur satu sampel kecil (151 karakter teks, 1 form). Halaman besar dan hostile sudah dicakup tes `hardening` (tetap <100 ms), tidak diukur ulang di sini.
- Tes tidak membuktikan sidik jari Microsoft cocok dengan semua halaman login Microsoft palsu; hanya yang memakai nama field asli.
- Tes extension (151) tidak menyentuh kode yang diubah; dijalankan sebagai pemeriksaan regresi saja.

## 8. Langkah berikutnya

1. Panggilan LLM nyata dengan prompt v3 pada sampel `helpnets` (beberapa kali, karena hasil sebelumnya tidak konsisten). Itu testing 06.
2. Eval dengan sampel situs sah (login bank asli, e-commerce, halaman dengan tombol "Sign in with Google/Microsoft") untuk mengukur salah blokir.
3. Setelah itu baru commit dan buka issue ke Umar.
