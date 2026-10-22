# Fixbug — tracker perbaikan dari eval (Imelda)

Dipakai setelah setiap run eval besar (fase 04 dan 07) atau laporan salah deteksi dari tim. Satu temuan = satu test yang gagal dulu = satu commit = satu branch `fix/AI-<ID>-<slug>` (beberapa temuan kecil yang berkaitan boleh satu PR).

## Aturan

- Urutan: **false positive di situs resmi dulu**, lalu scam yang lolos, lalu kelambatan, lalu kosmetik.
- Mulai dari test yang mereproduksi temuan (sampel eval + test aturan). `superpowers:systematic-debugging` sebelum mengubah kode.
- Perbaikan yang butuh perubahan bobot lintas sinyal → jangan tambal satu sampel; kumpulkan dan kerjakan di fase 07 dengan tabel sebelum/sesudah.
- Jangan menambah pengecualian per domain ("kalau `x.com` jangan"). Perbaiki aturannya, atau tambahkan brand ke `brands.json`.
- Temuan di luar folder kita (snapshot, pipeline, ambang, kontrak) → tulis di "Diteruskan" dengan isi pesan untuk Umar/Alief (TODO §C). Jangan diperbaiki sendiri.

## Prioritas

| Prio | Definisi | Contoh |
|---|---|---|
| P0 | Situs resmi terblokir (skor ≥ 80) atau data pribadi bocor lewat server | Domain bank resmi skor 85; URL muncul di log |
| P1 | Situs resmi terkena peringatan (30–79); scam populer lolos (< 30) | Toko resmi skor 35; kampanye scam kurir skor 12 |
| P2 | Alasan membingungkan, `labelSimple` pakai istilah teknis, latensi lewat anggaran | "TLD" tampil ke orang tua |
| P3 | Kosmetik/dokumen | Typo di label |

## Tracker

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| F-04-1 | P1 | Layer 3 `asks_*` | Halaman KYC fintech sah meminta KTP, selfie KTP, OTP: skor 95 (`asks_selfie_ktp`+35, `asks_ktp`+30, `asks_otp`+30). Sampel `trap-fintech-kyc-sah` (sintetis, kasus sulit disengaja) | [ ] | | [ ] fase 07 |
| F-04-2 | P1 | Layer 3 `asks_ktp` | Form klaim asuransi sah meminta foto KTP: skor 30, tepat di ambang popup, hanya dari satu sinyal (`asks_ktp`+30). Sampel `trap-asuransi-klaim-resmi`. Melawan D-imelda-04 (satu sinyal tidak boleh mencapai 30) | [ ] | | [ ] fase 07 |
| F-04-3 | P1 | Layer 3 `brand_logo_offsite`+`urgent_language` | Toko dengan alt "Logo BCA"/"Logo Mandiri" dan "Diskon terakhir hari ini" skor 40 (25+15). Sampel `trap-toko-logo-bank-checkout`. Risiko yang dicatat D-imelda-17 | [ ] | | [ ] fase 07 |
| F-04-4 | P1 | Layer 3 `brand_logo_offsite`+`urgent_language` | Artikel berita tentang penipuan bank (alt "Logo BRI", teks mengutip "diblokir dalam 24 jam") skor 40. Sampel `trap-berita-waspada-penipuan` | [ ] | | [ ] fase 07 |
| F-04-5 | P1 | Recall layer 3 | Scam di domain netral tanpa kolom form (chat/transfer saja): skor 0-5. `syn-loker-admin-online`, `syn-investasi-kripto-profit`, `syn-cimb-octo-limit`, `syn-samsat-pajak-kendaraan`, `syn-sicepat-apk`. Layer 3 tidak punya sinyal teks untuk biaya di muka / jaminan untung / minta chat WhatsApp | [ ] | | [ ] fase 06 (layer 4) |
| F-04-5-note | – | Layer 4 | F-04-5 (scam tanpa kolom form, skor 0-5) bukan kasus layer 4: gerbang menuntut form + skor >= 15, jadi LLM tidak dipanggil. Butuh model asli dan keputusan gerbang (A5) untuk dinilai; tidak dikerjakan tanpa LLM | – | – | [m] fase 06 / A5 |
| F-04-6 | P2 | Snapshot | Form login di iframe tidak terlihat: `lphone-login` 39, `syn-find-my-iphone-hilang` 25. Menunggu jawaban Umar (TODO C1) | [ ] | | [ ] tunggu Umar |
| F-04-7 | P2 | Data | 6 halaman nyata (BRI, BTN, BNI, Shopee, BPJS, Kemenkeu) kosong di snapshot statis (halaman JS): hanya menguji layer 1-2; legit nyata efektif 33 untuk layer 3 | [ ] | | [ ] catatan |

## Diteruskan ke tim lain

| ID | Ke | Isi singkat | Status |
|---|---|---|---|
| | | | |
