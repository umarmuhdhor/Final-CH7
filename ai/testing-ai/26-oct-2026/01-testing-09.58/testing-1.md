# Testing 1: apa yang extension ambil, apa yang server kirim ke LLM, dan kenapa scam Microsoft palsu lolos

> Tanggal: 26 Okt 2026 · `main` @ `a035bb9` · dijalankan dengan `ai/` dan `detector.js` hasil build di repo (tanpa perubahan kode)
> Sampel: satu halaman phishing nyata, ditulis **defanged**: `helpnets[.]info/0442827f6o7cfb43933ba59e2881cc906b7c.html/`
> Penguji: Imelda (dijalankan bersama Claude)

## 1. Tujuan

Mengikuti satu halaman phishing nyata dari awal sampai akhir: apa yang diambil extension, apa yang dikirim ke server, apa yang dikirim server ke LLM, dan skor yang keluar. Tujuannya melihat apakah pipeline Shoo menangkap scam yang bagi manusia (dan bagi AI yang melihat seluruh halaman) jelas phishing.

## 2. Cara tes

1. Halaman diambil sekali lewat `ai/eval/tools/capture.mjs`. Itu GET statis tanpa JavaScript dan tanpa cookie, jadi halaman tidak pernah dibuka di browser (aturan D-imelda-19 dan `capture.mjs`). Hasil disimpan di scratchpad, bukan di repo.
2. `detector.js` (hasil build extension, `ios/ShooExtension/Resources/detector.js`) dijalankan di `vm` untuk layer 1–2.
3. `ai/src/analyze.js` dijalankan dengan `createRealityCheck` yang `fetch`-nya diganti penangkap request. Tidak ada panggilan nyata ke LLM karena API key milik Umar.
4. RDAP dimatikan (`rdap: null`), jadi sinyal `new_domain` tidak ikut.

## 3. Yang dilakukan tiap tahap

### 3.1 Extension → server (`POST /analyze`)

Body: `{ snapshot, localSignals }`. Nilai yang diketik tidak pernah ikut.

| Field | Isi untuk halaman ini |
|---|---|
| `url` | `https://helpnets[.]info/0442827f…c.html/` |
| `domain` | `helpnets.info` |
| `title` | `Sign in to your account` |
| `lang` | `en` |
| `text` | 151 karakter (`Sign in No account? Create one! … Terms of use Privacy & cookies`); email dimasking `[email]` |
| `forms[0].fields` | `email` (`name=loginfmt`, `id=i0116`), `password` (`name=passwd`, `id=i0118`) ×2 |
| `imageAlts` | `["Microsoft"]` |
| `localSignals` | `[]` (layer 2 tidak menemukan apa-apa; layer 1 tidak diuji karena `ShooLists` tidak ada di simulasi) |

### 3.2 Server layer 3

Satu sinyal: `asks_password`, layer 3, bobot 15, evidence `passwd`. Skor aturan = **15**. Itu persis `GATE_MIN_SCORE = 15`, jadi gerbang LLM terbuka.

### 3.3 Server → LLM

`POST https://bandelbanget.xyz/v1/chat/completions`, model `deepseek-v4-flash`, `temperature 0`, `max_tokens 200`, `response_format: json_object`, prompt `reality-check.v2`.

Pesan user yang dikirim:

```
DATA_START
{"site":"helpnets.info","title":"Sign in to your account","fields":[{"type":"email","label":"Enter your email, phone, or Skype."},{"type":"password","label":"passwd"},{"type":"password","label":"Enter the password for"}],"rules":["asks_password"]}
DATA_END
```

Yang **tidak** ikut dikirim: `imageAlts` (`Microsoft`), `text`, path URL, `id` field, dan kata "Microsoft".

### 3.4 Balasan LLM

Dijalankan ulang dengan key OpenRouter milik Imelda (`ai/.env`, model `deepseek/deepseek-v4-flash`, provider yang melayani: Relace). Request-nya sama persis dengan 3.3. Tiga variasi, masing-masing satu kali:

| Variasi | Waktu | `finish_reason` | Token (completion / reasoning) | `content` |
|---|---|---|---|---|
| A. `max_tokens: 200` (setelan kode sekarang) | 6,6 s | `length` | 200 / 218 | **kosong** (`null`) |
| B. `max_tokens: 200` + `reasoning: {enabled: false}` | 3,7 s | `stop` | 31 / 0 | JSON valid (di bawah) |
| C. `max_tokens: 1000` | 8,6 s | `length` | 1000 / 1028 | **kosong** (`null`) |

Balasan nyata pada variasi B:

```json
{"page_type":"other","asks":["password"],"reasonable":true,"confidence":0.6,"evidence":"Sign in to your account"}
```

Tafsiran: LLM menganggap halaman ini **wajar** (`reasonable: true`), jadi `unreasonable_request` (bobot 30) tidak muncul. Sinyal itu hanya muncul kalau `reasonable=false` dan `confidence ≥ 0.6`.

Lewat jalur kode yang sebenarnya (`createRealityCheck`, batas 6 s), hasilnya `timeout`: tidak ada sinyal, skor tetap 15.

Biaya sekitar $0,0001 per panggilan.

## 4. Hasil

| Pertanyaan | Hasil |
|---|---|
| Skor layer 1–3 | **15** (hanya `asks_password`) |
| Ambang peringatan | 30 → **tidak tercapai** |
| LLM dipanggil | Ya (lolos gerbang) |
| Balasan LLM | Nyata (variasi B, reasoning mati): `reasonable: true`, `confidence 0.6`. Dengan setelan kode sekarang: `content` kosong, jadi tidak ada sinyal (lihat T6) |
| `brand_logo_offsite` | **Tidak menyala**, padahal `imageAlts = ["Microsoft"]` di domain non-Microsoft |
| Peringatan untuk pengguna | Kemungkinan **tidak ada**, kecuali RDAP menemukan domain baru (`new_domain`) atau domain ada di blocklist |

## 5. Temuan

**T1. Scam yang jelas bagi manusia tidak tertangkap.** Petunjuknya banyak: alt gambar "Microsoft" di domain `helpnets.info`, ID field `loginfmt`/`i0116`/`i0118` yang khas form login Microsoft, teks "Skype" dan "Sign-in options", dan path URL acak. Semua itu ada di snapshot.

**T2. LLM buta terhadap petunjuk itu.** Pembatas privasi D-imelda-27 membuang `imageAlts`, teks, ID field, dan path sebelum dikirim. Akibatnya halaman terlihat seperti login biasa. Ini bukan kelemahan model, tapi desain input.

**T3. `brand_logo_offsite` tidak menyala.** Belum diselidiki penyebabnya. Kandidat: Microsoft tidak ada di `brands.json`, aturannya hanya membaca `title`, atau butuh syarat lain (`asksData`). Perlu dicek.

**T4. Skor tepat di gerbang.** Skor 15 sama dengan `GATE_MIN_SCORE`, jadi LLM terpanggil, tapi menghabiskan panggilan berbayar untuk hasil yang kemungkinan "wajar".

**T5. Label field bocor jadi nama atribut.** Field password pertama tidak punya `label`, jadi `buildInput` memakai `name` (`passwd`). Ini bukan nilai yang diketik, jadi tidak melanggar privasi, tapi tidak informatif untuk LLM.

**T6. Model reasoning menghabiskan `max_tokens` sebelum menjawab.** Di OpenRouter, `deepseek/deepseek-v4-flash` memakai token reasoning di dalam jatah `max_tokens: 200`, jadi `content` kosong dan `finish_reason=length`. Menaikkan ke 1000 tidak menolong karena reasoning ikut membengkak. Mematikan reasoning (`reasoning: {enabled: false}`) memberi jawaban valid dalam 31 token. `provider.js` tidak mengirim parameter `reasoning`, jadi di jalur OpenRouter layer 4 praktis tidak pernah menghasilkan sinyal. Apakah proxy produksi (`bandelbanget.xyz`) mengalami hal yang sama belum diketahui.

**T7. Latensi dekat batas.** Tiga panggilan variasi A: 3,1 s, 6,6 s, 2,6 s. Batas kode 6 s (`MAX_TIMEOUT_MS`) dan server 6,5 s, jadi sebagian panggilan timeout walau reasoning mati (B: 3,7 s, satu kali).

## 6. Batasan tes ini

- Pengambilan statis: `text` cuma 151 karakter. Di Safari, `innerText` dibaca setelah JavaScript jalan dan bisa lebih panjang.
- Hanya **satu** sampel. Kesimpulan "scam lolos" belum berarti angka recall.
- RDAP dan layer 1 (blocklist) tidak ikut, jadi skor produksi bisa berbeda.
- Balasan LLM hanya satu kali per variasi, jadi belum ada gambaran variasi antar-panggilan. Provider dan versi model di OpenRouter belum tentu sama dengan proxy produksi.
- Belum diuji di Safari iPhone atau simulator (menunggu `xcode-select` ke Xcode penuh, dan TestFlight #55).

## 7. Usulan perbaikan

Urut dari paling murah. Semua menyentuh `ai/` atau `detector/` (milik Umar sejak 23 Okt), jadi jalurnya issue dulu (aturan 7).

1. **Selidiki T3.** Kenapa `brand_logo_offsite` tidak menyala untuk logo Microsoft di domain lain. Test pakai snapshot ini.
2. **Aturan ID field milik merek.** `loginfmt`, `i0116`, `i0118` di domain non-Microsoft. Deterministik, tanpa LLM, hampir tanpa false positive.
3. **Kirim daftar merek yang terdeteksi ke LLM**, misalnya `["Microsoft"]`, bukan teks mentah. Privasi tetap terjaga, dan LLM bisa membandingkannya dengan domain. Butuh perubahan prompt (naik versi `reality-check.v3`) dan eval ulang.
4. **Tambahkan sampel ini ke eval set** (setelah `redacted: true` dan lisensinya jelas), karena ini contoh scam nyata yang kita butuhkan (A4/E-1).

## 8. Pertanyaan terbuka

- Apakah `localSignals` untuk domain ini benar-benar kosong di produksi, setelah layer 1 (190.000 domain) ikut?
- Apakah Umar mau melonggarkan D-imelda-27 untuk satu field turunan (daftar merek)?
- Apakah produksi (`bandelbanget.xyz`) juga mengembalikan `content` kosong karena reasoning? Perlu dicek lewat statistik `outcomes` (`bad_schema` / `timeout`) di Worker, hanya Umar yang bisa.
- Apakah `provider.js` perlu mengirim `reasoning: {enabled: false}` (OpenRouter) atau menaikkan `max_tokens`? Draf issue ada di `issue-draft-reasoning.md` (folder yang sama). Request dan respons mentah LLM: `llm-response.md`. Rekap semua pengukuran kecepatan ada di `../02-testing-10.05/report.md` bagian 4.
