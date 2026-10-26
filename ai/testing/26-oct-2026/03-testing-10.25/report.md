# Testing 3: layer 3 + 4 di bandelbanget (penyedia yang sama dengan produksi), 10 run

> Tanggal: 26 Okt 2026, 10.25 · lanjutan dari testing 1 dan 2 · `main` @ `a035bb9` · tidak ada kode repo yang diubah
> Sampel: sama dengan testing 1, `helpnets[.]info/0442827f…c.html/` (login Microsoft palsu)
> Penguji: Imelda (dijalankan bersama Claude)
> Koreksi 26 Okt 10.35: hitungan awal salah (timeout 4, reasonable 5); yang benar timeout 5, reasonable 4, sesuai tabel run.

## 1. Tujuan

Mengulang tes layer 3 (aturan) dan layer 4 (LLM) dengan link yang sama, sekarang lewat **bandelbanget.xyz**, penyedia yang dipakai produksi (D-imelda-36), bukan OpenRouter. Dicatat juga waktu tiap layer. Reasoning dibiarkan menyala (bawaan, tidak ada parameter `reasoning` yang dikirim).

## 2. Setelan

| Item | Nilai |
|---|---|
| Penyedia | `https://bandelbanget.xyz/v1` (OpenAI-compatible) |
| Model | `deepseek-v4-flash` |
| Reasoning | bawaan (menyala; tidak dikirim parameter `reasoning`) |
| Jalur kode | asli: `analyze()` → `createRealityCheck()` dari `ai/src`, tanpa modifikasi |
| `LLM_TIMEOUT_MS` | 6000 (batas atas keras di `config.js`) |
| `LLM_DAILY_CAP` | 5000 |
| Batas server | `/analyze` menjawab maks 6,5 s sejak request masuk (`SERVER_DEADLINE_MS`) |
| Input ke LLM | sama persis dengan testing 1 (`site`, `title`, 3 label field, `rules: ["asks_password"]`), prompt `reality-check.v2` |
| RDAP | dimatikan (`rdap: null`), jadi sinyal `new_domain` tidak ikut dan tidak ada domain scam terkirim ke registry |
| Jumlah run | 10, berurutan |
| Mesin / jaringan | Mac Imelda, bukan dari Cloudflare Worker (angka produksi bisa berbeda) |

## 3. Waktu per layer

| Layer | Waktu | Catatan |
|---|---|---|
| Layer 1–2 (detector di extension, disimulasikan di `vm`) | **1,4 ms** | 0 sinyal; layer 1 (blocklist) tidak ikut karena `ShooLists` tidak ada |
| Layer 3 (aturan form + isi) | **0,6 ms** | 1 pengukuran; menghasilkan `asks_password` (15) |
| Layer 4 (LLM), run yang selesai (n = 5) | **3,5 – 5,7 s**, median 4,4 s, rata-rata 4,7 s | termasuk jaringan ke bandelbanget |
| Layer 4, run timeout (n = 5) | 6,0 s (dipotong oleh batas 6 s) | tidak ada jawaban |

Total layer 3+4 sama dengan waktu layer 4 ditambah <1 ms, karena layer 3 hampir tidak butuh waktu. Jadi **hampir seluruh waktu `/analyze` habis menunggu LLM**.

## 4. Hasil 10 run

| Run | Waktu layer 3+4 | Hasil layer 4 | Sinyal akhir | Skor |
|---|---|---|---|---|
| 1 | 5.680 ms | **flagged** (`reasonable: false`, confidence 0,82) | `unreasonable_request` 30 + `asks_password` 15 | **45** |
| 2 | 4.151 ms | reasonable (confidence 0,55) | `asks_password` 15 | 15 |
| 3 | 6.002 ms | timeout | `asks_password` 15 | 15 |
| 4 | 6.003 ms | timeout | `asks_password` 15 | 15 |
| 5 | 3.539 ms | reasonable | `asks_password` 15 | 15 |
| 6 | 6.008 ms | timeout | `asks_password` 15 | 15 |
| 7 | 6.003 ms | timeout | `asks_password` 15 | 15 |
| 8 | 4.365 ms | reasonable | `asks_password` 15 | 15 |
| 9 | 5.604 ms | reasonable | `asks_password` 15 | 15 |
| 10 | 6.004 ms | timeout | `asks_password` 15 | 15 |

Ringkasan: **flagged 1, reasonable 4, timeout 5** dari 10.

Detail dua run yang dicatat penuh:

- **Run 1 (flagged):** `{"page_type":"other","asks":["password","personal_data"],"reasonable":false,"confidence":0.82,"evidence":"Sign in to your account"}`; usage prompt 1747, completion 1542, reasoning 483 token.
- **Run 2 (reasonable):** `{"page_type":"other","asks":["password","personal_data"],"reasonable":true,"confidence":0.55,"evidence":"Sign in to your account"}`; usage prompt 1747, completion 1461, reasoning 402 token.

## 5. Temuan

**T1. Di bandelbanget layer 4 menjawab, beda dengan OpenRouter.** Dengan reasoning bawaan dan `max_tokens: 200` di kode, 5 dari 10 run mengembalikan JSON valid dengan `finish_reason: stop`. Di OpenRouter (testing 2) 0 dari 7 setelan reasoning menjawab di batas 6 s. Bandelbanget tampaknya tidak memotong jawaban di `max_tokens` (completion yang dilaporkan 1461–1542 token, jauh di atas 200).

**T2. Hasilnya tidak konsisten untuk input yang sama.** Dari 5 jawaban: 1 `reasonable: false` (0,82), 4 `reasonable: true`. Pada `temperature: 0`. Jadi satu sampel scam ini hanya terdeteksi layer 4 sekitar 1 dari 10 kali (10%), dan skornya naik ke 45 hanya pada run itu. Skor 45 pun masih di bawah ambang blokir 50 dan 80, hanya di atas 30.

**T3. 50% panggilan timeout.** 5 dari 10 run melewati 6 s. Waktu run yang selesai (3,5–5,7 s) mepet ke batas, jadi sebagian besar run lambat akan terpotong. Pada timeout layer 4 diam dan skor tetap 15.

**T4. Layer 3 praktis gratis.** 0,6 ms untuk satu pengukuran. Waktu `/analyze` hampir sepenuhnya waktu LLM.

**T5. Token yang dilaporkan jauh lebih besar dari yang kita kirim.** Prompt 1747 token, sedangkan kita mengirim ±460 token di OpenRouter. Belum jelas apakah bandelbanget menambah teks sendiri atau menghitung berbeda. Relevan untuk biaya dan privasi, perlu dicek ke Umar.

**T6. Penyebab skor rendah tetap input.** Di semua 5 jawaban, LLM tidak pernah menyebut Microsoft karena kata itu tidak ikut dikirim (D-imelda-27). Satu-satunya jawaban "tidak wajar" kemungkinan kebetulan, bukan pemahaman merek.

## 6. Batasan

- Satu sampel, 10 run, satu mesin, satu waktu. Variasi antar-jam atau antar-hari belum diukur.
- Layer 3 hanya diukur sekali (0,6 ms); angka itu perlu diulang untuk median yang andal.
- Reasoning mati tidak diuji di bandelbanget. Parameter yang diterima proxy ini belum diketahui, dan `max_tokens` tampaknya diabaikan.
- Layer 1 (blocklist) dan RDAP tidak ikut, jadi skor produksi bisa berbeda.
- Dari Cloudflare Worker latensi ke bandelbanget bisa lebih rendah atau lebih tinggi daripada dari Mac.
- Tidak diperiksa apakah ada rate limit atau biaya di sisi bandelbanget selama 10 run.

## 7. Rekomendasi

1. **Naikkan batas layer 4 atau cari model lebih cepat.** Dengan 50% timeout di 6 s dan waktu normal 3,5–5,7 s, layer 4 kehilangan hampir separuh panggilannya. Opsi: model non-reasoning, atau tanya Umar apakah proxy punya parameter untuk mematikan reasoning.
2. **Jangan mengandalkan layer 4 untuk sampel ini.** Hasil 1 dari 10 tidak cukup. Tambahkan nama merek yang terdeteksi ke input LLM (usulan 3 di testing 1) dan ukur ulang dengan 10 run yang sama.
3. **Laporkan T2 dan T3 ke Umar** lewat issue (draf di `../01-testing-09.58/issue-draft-reasoning.md`; perlu ditambah temuan bandelbanget, karena draf itu ditulis untuk OpenRouter).
4. **Cek T5** (kenapa prompt 1747 token) dengan Umar.
5. **Ulangi dengan sampel legit** (login bank asli, e-commerce) untuk melihat apakah layer 4 salah menandai situs resmi.
