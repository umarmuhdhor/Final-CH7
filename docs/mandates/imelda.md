# Mandat — Imelda (Team AI)

> Dari: Umar (lead) · Untuk: Imelda (@imeldamayanti) dan Claude-nya
> Cara pakai: di Claude Code, ketik `/mandate`. Claude akan membaca file ini, memilih tugas berikutnya yang belum dicentang, lalu mulai kerja.

## Peran
Kamu yang menentukan **seberapa berbahaya sebuah halaman**. Semua yang menghasilkan sinyal dan bobot skor adalah tanggung jawabmu. Extension (Umar) cuma menjumlahkan bobot dan menampilkan UI. App (Alief) cuma menampilkan hasilnya.

| Boleh diedit | Jangan disentuh |
|---|---|
| `detector/`, `ai/`, `ios/ShooExtension/Resources/detector.js` (hasil sync saja) | `contracts/`, `ios/` lainnya, `backend/` |

Wajib dibaca sebelum mulai: `contracts/detector-interface.md`, `contracts/scan-result.schema.json`, `contracts/api.md` (bagian AI + Blocklist), `detector/CLAUDE.md`, `ai/CLAUDE.md`.

## Definisi sukses MVP
Target awal ini bisa diubah oleh lead:
1. **Tidak ada salah blokir di situs resmi.** Semua domain di `detector/data/brands.json` dan 100 situs populer Indonesia mendapat skor **< 30**.
2. **Scam tertangkap.** ≥ 90% halaman scam di eval set mendapat skor **≥ 50**, dan ≥ 70% mendapat skor **≥ 80**.
3. **Cepat.** `analyzeLocal` < 50 ms. `POST /analyze` < 8 detik (p95). Layer 3 tetap menjawab walaupun LLM sedang down.
4. **Alasan bisa dimengerti orang tua, dalam 2 bahasa.** Setiap sinyal punya `label` (untuk Guardian) dan `labelSimple` (bahasa sederhana, tanpa istilah teknis). Keduanya **wajib dalam English dan Bahasa Indonesia**: `{ "en": "...", "id": "..." }`. Contohnya ada di `contracts/fixtures/`.

## Tugas (kerjakan berurutan, centang kalau PR sudah di-merge)

### M1 · Layer 2: cek nama link (on-device) — `detector/`
- [ ] Buat `detector/data/brands.json` berisi brand yang sering ditiru beserta domain resminya. Minimal: bank (BCA, BRI, Mandiri, BNI, BSI), e-wallet (DANA, OVO, GoPay, ShopeePay), e-commerce (Shopee, Tokopedia, Lazada, Bukalapak), Pos Indonesia, JNE, J&T, instansi pemerintah (Kemensos, DJP, BPJS).
- [ ] Buat sinyal `cheap_tld`, `brand_plus_keyword` (bca-verifikasi), dan `lookalike_domain` (p0stindonesia, typo 1–2 huruf).
- [ ] Siapkan test runner (`node --test` sudah cukup). Satu test per aturan, plus test "domain resmi → tanpa sinyal".
- [ ] Jalankan `detector/scripts/sync-to-extension.sh`, lalu commit `src/` dan `detector.js` bersamaan.
- **Selesai kalau:** semua test lolos, dan domain di fixture `contracts/fixtures/` menghasilkan sinyal layer 2 yang sesuai.
- Branch: `feat/AI-M1-link-name`

### M2 · Eval set — `ai/eval/`
- [ ] Kumpulkan ≥ 50 halaman scam (URL + HTML/teks + label) dan ≥ 50 halaman resmi yang mirip (halaman login bank, checkout e-commerce, dll).
- [ ] Buat skrip eval yang menjalankan detector + `/analyze`, lalu mencetak skor per halaman dan metrik di "Definisi sukses".
- [ ] Data pribadi apa pun di sampel harus disamarkan dulu.
- **Selesai kalau:** skrip bisa dijalankan dengan satu perintah dan hasilnya ditempel di PR.
- Branch: `feat/AI-M2-eval-set`

### M3 · Layer 3: isi halaman & form (server) — `ai/`
- [ ] Buat service `POST /analyze` persis seperti di `contracts/api.md`. Stateless, tanpa log isi halaman.
- [ ] Buat sinyal form sensitif: `asks_pin`, `asks_otp`, `asks_password`, `asks_card`, `asks_cvv`, `asks_ktp`, `asks_selfie_ktp`. Bahan: `snapshot.forms[].fields` (label, name, placeholder, autocomplete). Harus mengenali kata dalam Bahasa Indonesia dan English.
- [ ] Buat sinyal `urgent_language` ("diblokir dalam 24 jam", "klaim sekarang") dan `brand_logo_offsite` (nama brand muncul di `imageAlts`/title, tapi domainnya bukan domain resmi).
- [ ] Buat sinyal `new_domain` lewat lookup RDAP/WHOIS **di server**, bukan di HP, supaya riwayat browsing tidak bocor ke pihak ketiga dari perangkat user. Simpan hasil lookup di cache.
- **Selesai kalau:** `fixtures/blocked-92.json` dan `warning-63.json` bisa direproduksi kira-kira (sinyal sama, skor ±10).
- Branch: `feat/AI-M3-content-forms`

### M4 · Layer 4: reality check (LLM) — `ai/`
- [ ] Buat prompt di `ai/prompts/`. Input: jenis halaman + data yang diminta. Output: apakah permintaannya wajar (contoh di PRD §5: toko meminta alamat itu wajar, halaman "cek hadiah" meminta PIN itu tidak wajar).
- [ ] Output LLM wajib JSON terstruktur, lalu dipetakan ke sinyal `unreasonable_request`.
- [ ] Model bisa diganti lewat `.env`. Pilih model cepat, karena latensi lebih penting. Batas waktu: kalau LLM belum menjawab saat total waktu mendekati 8 detik, kembalikan sinyal layer 3 saja.
- [ ] API key hanya di `.env`. Commit `.env.example`.
- **Selesai kalau:** eval M2 menunjukkan layer 4 mengurangi salah blokir di halaman resmi tanpa menurunkan deteksi scam.
- Branch: `feat/AI-M4-reality-check`

### M5 · Layer 1: database — `ai/` + `detector/`
Desain: [`docs/design/blocklist.md`](../design/blocklist.md). Ringkasnya: daftar diunduh dan disimpan oleh `background.js` (Umar), detector **tidak** melakukan request jaringan.
- [ ] `GET /public-blocklist?since=` di `ai/`: kumpulkan daftar phishing publik di server (pilih sumber yang lisensinya boleh dipakai, catat di `ai/README.md`), ubah ke domain utama, buang domain resmi/allowlist dan situs sah yang hanya disusupi. Bentuk sama dengan `GET /blocklist`: `{ domains: [{ domain, addedAt }], removed?, nextSince }`.
- [ ] Di `detector/`: `await globalThis.ShooLists.match(new URL(snapshot.url).hostname)` → kalau cocok, kembalikan sinyal `db_match` (weight 100, label EN + ID, sumber di `evidence`). Sambil menunggu helper dari Umar, pakai mock `ShooLists` di test.
- [ ] **Jangan** kirim URL yang sedang dibuka ke mana pun.
- **Bergantung pada:** helper `ShooLists` (Umar) dan `GET /blocklist` (Alief). Sambil menunggu, pakai data mock.
- Branch: `feat/AI-M5-database`

### M6 · Kalibrasi bobot
- [ ] Atur bobot semua sinyal sampai target di "Definisi sukses" tercapai di eval set.
- [ ] Tempel tabel hasil eval sebelum/sesudah di PR.
- Branch: `feat/AI-M6-calibration`

### M7 · Deploy `/analyze`
- [ ] Deploy ke URL publik HTTPS, lalu kirim URL-nya ke Umar dan Alief (dipakai untuk `ai.baseURL`).
- [ ] Pasang rate limit sederhana dan batas ukuran body (snapshot maks. ±200 KB).
- Branch: `feat/AI-M7-deploy`

## Bukan tugasmu di MVP
- Deteksi hoaks (layer 5) → Fase 2.
- "AI belajar dari keputusan keluarga" → masih menunggu keputusan PM. Jangan dikerjakan dulu.
- UI apa pun (popup, layar blokir, app).

## Kapan harus tanya Umar
- Butuh sinyal baru yang belum ada di tabel "Known signal ids" → itu perubahan kontrak.
- Butuh field baru di `PageSnapshot` (misalnya screenshot atau HTML mentah).
- Hasil eval tidak bisa mencapai target. Laporkan angkanya, jangan diam-diam menurunkan target.

## Cara lapor
1 tugas = 1 branch = 1 PR, dengan @umarmuhdhor sebagai reviewer. Di PR: centang checkbox di file ini, tulis yang sudah dikerjakan, dan cara mengujinya.
