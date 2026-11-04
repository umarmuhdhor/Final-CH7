Kerjakan tes perbandingan arsitektur Layer 1-4 di repo Shoo, folder `ai/test-layer-update-full/`. Aku Imelda, pemilik `ai/`.

## Baca dulu (wajib, urut)
1. `CLAUDE.md` (root) dan `ai/CLAUDE.md`
2. `ai/test-layer-update-full/PLAN.md`: ini spesifikasinya. Keputusan K1-K8, batas lulus, dan teks prompt v5 sudah final, jangan ditanya ulang
3. `ai/src/analyze.js`, `ai/src/layer4/reality.js`, `ai/src/layer4/config.js`, `ai/src/layer4/provider.js`, `ai/src/layer4/schema.js`, `ai/src/rdap/rdap.js`, `ai/src/rdap/cache.js`, `ai/prompts/reality-check.js`
4. `ios/ShooExtension/Resources/pipeline.js` (`scoreFrom`, `statusFor`, `validSignals`, `mergeSignals`, `THRESHOLD`)
5. Contoh pola: `ai/test-layer4/run.mjs` (cara membaca `.env`, memuat `detector.js` lewat `vm`, membungkus `fetch`, `--dry`, `--only`, `--report`, menyamarkan domain) dan `ai/test-layer-update-full/.hasil/probe.mjs` (memuat kode lama dan baru berdampingan)

## Yang harus dikerjakan
1. Pastikan branch `feat/AI-M4-thinking-off-asks-otp-boxes` dan commit `2c51aee` ada di riwayat. Muat ulang kode lama dengan perintah di PLAN.md kalau `.hasil/old/` belum ada
2. Tulis `ai/test-layer-update-full/run.mjs` sesuai PLAN.md, dengan opsi `--dry`, `--only <id>`, `--report`
3. `node run.mjs --dry`: tanpa LLM sungguhan. Cek 26 scam + 49 legit, gate tiap versi, body LLM lama = baru, dan payload tidak berisi teks halaman, path/query URL, nilai ketikan, atau umur domain (kecuali opsi C)
4. `node run.mjs --only 01` dan `--only L01`: LLM sungguhan. Cek `usage` ada dan jawaban lolos `parseVerdict`
5. Jalankan penuh, satu per satu, tidak paralel. Simpan ke `.hasil/`
6. `node run.mjs --report`, tulis `HASIL.md` sesuai bagian "Isi HASIL.md" di PLAN.md, dengan link yang beda paling atas
7. Tulis bagian "Analisis" di `HASIL.md`: link mana yang berubah dan kenapa, legit yang terdampak, apakah batas lulus terpenuhi, hasil opsi C dan apakah syaratnya terpenuhi, waktu dan token. Bedakan yang terbukti dan dugaan

## Aturan
- **Jangan ubah** `ai/src/`, `ai/prompts/`, `contracts/`, `detector/`, `ios/`. Cuma tulis di `ai/test-layer-update-full/`
- **Jangan cetak isi `ai/.env`** ke chat, log, `.hasil/`, atau `HASIL.md`. Nama model dan host boleh dicatat
- **Jangan buka situs scam** dan jangan ambil HTML baru. RDAP live boleh, hanya nama domain yang dikirim ke server RDAP
- Domain di `HASIL.md` disamarkan: `bni-diirect[.]com`
- Tiap link satu kali ke LLM. Jangan ulang tes penuh "supaya yakin". Kalau 10 `http_error` berturut-turut, berhenti, simpan hasil sebagian, lalu lapor
- Kalau body LLM lama dan baru tidak sama, jumlah sampel bukan 26 + 49, atau penggantian teks prompt v5 tidak menemukan teks asalnya: berhenti dan lapor, jangan menebak
- Jangan commit. Setelah selesai, laporkan ringkasan (jumlah link beda, legit yang terdampak, lulus atau gagal, hasil opsi C) dan tanya apakah mau di-commit
- Kalau ada yang tidak jelas di PLAN.md, tanya dulu sebelum menebak
