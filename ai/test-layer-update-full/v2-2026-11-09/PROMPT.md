Kerjakan tes v2 Layer 4 di repo Shoo, folder `ai/test-layer-update-full/v2-2026-11-09/`. Aku Imelda, pemilik `ai/`.

## Baca dulu (wajib, urut)
1. `CLAUDE.md` (root) dan `ai/CLAUDE.md`
2. `ai/test-layer-update-full/v2-2026-11-09/PLAN.md`: ini spesifikasinya. Keputusan K1-K12, batas lulus, dan teks prompt sudah final, jangan ditanya ulang
3. `ai/src/analyze.js`, `ai/src/layer4/reality.js`, `ai/src/layer4/provider.js`, `ai/src/layer4/schema.js`, `ai/src/layer4/config.js`, `ai/prompts/reality-check.js`
4. `ios/ShooExtension/Resources/pipeline.js` (`scoreFrom`, `statusFor`, `validSignals`, `mergeSignals`, `THRESHOLD`)
5. Contoh pola: `ai/test-layer-update-full/v1-2026-11-02/run.mjs` (cara memuat sampel, `detector.js` lewat `vm`, RDAP, `--dry`, `--only`, `--report`, menyamarkan domain)

## Yang harus dikerjakan
1. Cek prasyarat di PLAN.md
2. Tulis `trap-brand.json` dan `run.mjs` di folder ini, dengan opsi `--dry`, `--only <id>`, `--resume`, `--report`
3. `node run.mjs --dry`: tanpa LLM sungguhan. Cek semua butir langkah 2 di PLAN.md
4. `node run.mjs --only 05`, `--only lphone-login`, `--only L03`: LLM sungguhan. **Berhenti di sini**, tunjukkan hasilnya ke aku, dan tunggu aku bilang lanjut
5. Jalankan penuh, satu per satu, tidak paralel. Simpan ke `.hasil/`
6. `node run.mjs --report`, tulis `HASIL.md` sesuai bagian "Isi HASIL.md" di PLAN.md
7. Tulis bagian "Analisis": hasil tiap batas lulus, link yang berubah dan kenapa, waktu dan token, isi `usage` yang janggal di tes 2 Nov sudah terjawab atau belum. Bedakan yang terbukti dan dugaan
8. Salin `.hasil/` ke luar repo sesuai langkah 6 di PLAN.md

## Aturan
- **Jangan ubah** `ai/src/`, `ai/prompts/`, `contracts/`, `detector/`, `ios/`. Cuma tulis di folder ini
- **Jangan cetak isi `ai/.env`** ke chat, log, `.hasil/`, atau `HASIL.md`. Nama model dan host boleh dicatat
- **Jangan buka situs scam** dan jangan ambil HTML baru. RDAP live boleh, hanya nama domain yang dikirim. Domain di `trap-brand.json` tidak dihubungi sama sekali
- Domain di `HASIL.md` disamarkan: `bni-diirect[.]com`, ditulis host + path, tanpa query dan fragment
- Ke LLM tidak boleh ada teks halaman selain yang sudah ada di `buildInput`, path URL, nilai ketikan, umur domain, atau `evidence` mentah dari client
- Jangan ulang tes penuh "supaya yakin". Kalau 10 `http_error` berturut-turut, berhenti, simpan hasil sebagian, lalu lapor
- Kalau jumlah sampel salah, body versi A tidak sama dengan production, atau penggantian teks prompt tidak menemukan teks asalnya: berhenti dan lapor, jangan menebak
- Jangan commit. Setelah selesai, laporkan ringkasan dan tanya apakah mau di-commit
- Kalau ada yang tidak jelas di PLAN.md, tanya dulu sebelum menebak
