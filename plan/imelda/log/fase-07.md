# Fase 07 — Kalibrasi bobot (M6)

**Status:** `[m]` kalibrasi layer 1-3 selesai sejauh data mengizinkan; **target mandat tidak dinilai** (scam nyata hanya 1) dan **tidak tercapai** pada sampel gabungan (lihat angka). Layer 4 tidak dikalibrasi (belum ada model).
**Branch:** `feat/AI-M6-calibration` dari `feat/AI-M4-reality-check` (stacked). 22 Okt 2026.

## Protokol (ref/R2)
- Data: 50 scam (1 nyata, 49 sintetis), 51 legit (39 nyata, 12 sintetis). Holdout 12 scam + 14 legit (D-imelda-21).
- Tuning memakai bentuk aturan dari sampel TUNING yang terlihat dan alasan struktural (D-imelda-04), bukan domain tertentu. `run.mjs` selalu mencetak TOTAL holdout (bukan per sampel); total itu terlihat di tiap run. Tidak ada perubahan yang dipilih karena angka holdout, tetapi ini diakui: holdout BUKAN lagi bersih sepenuhnya; sebaiknya ditambah sampel nyata baru sebelum dipakai membuktikan target.
- Layer 4 mati (tanpa key) di semua run. Detector (`detector/`) tidak berubah, jadi `sync-to-extension.sh` tidak perlu dijalankan.

## Sebelum / Sesudah (service lokal, `--analyze-url`, RDAP mati)
| Metrik | Target | Sebelum | Sesudah |
|---|---|---|---|
| Legit skor >= 30 (51 sampel; 39 nyata) | 0 | 4/51 (nyata 0/39) | **1/51** (nyata 0/39) |
| Scam >= 50 (semua / nyata 1) | >= 90% | 33/50 = 66% / 0 | 33/50 = 66% / 0 |
| Scam >= 80 (semua / nyata 1) | >= 70% | 20/50 = 40% / 0 | 16/50 = 32% / 0 |
| `analyzeLocal` | < 50 ms | – | p95 1,0 ms, maks 1,9 ms (505 panggilan) |
| `/analyze` lokal | p95 < 8 s | – | p95 2,5 ms, maks 20 ms (jaringan HP dan RDAP/LLM tidak diukur) |
Tuning vs holdout (Sesudah): tuning scam >=50 26/38, >=80 12/38, legit 1/37; holdout scam >=50 7/12, >=80 4/12, legit 0/14. Sebelum: tuning legit 2/37, holdout legit 2/14, scam >=50 7/12 di holdout.

**Target tidak tercapai** (scam >=50: 66% vs 90%; >=80: 32% vs 70%) dan tidak bisa dinilai secara resmi (1 scam nyata). Laporkan ke Umar (TODO C6). Ambang 30/50/80 tidak diubah.

## Perubahan bobot (satu per satu, satu commit)
| # | Perubahan | Alasan | Efek terukur |
|---|---|---|---|
| 1 | `asks_otp`, `asks_card`, `asks_cvv`, `asks_ktp` 30 -> 25 | D-imelda-04: satu sinyal ambigu tidak boleh mencapai ambang popup sendirian (F-04-2). OTP login di situs populer (mis. twitter.com) bernilai 30 | `trap-asuransi-klaim-resmi` 30 -> 25. Scam >=80 turun sedikit |
| 2 | Situs populer (allowlist blocklist) diam di layer 3 seperti brand | Situs populer tidak punya form berbahaya; test baru: semua domain `brands.json` + populer, semua jenis form, skor < 30 | Tidak ada sampel berubah; menutup celah (PIN di twitter.com = 35) |
| 3 | `urgent_language` 15 -> 8 dan `brand_logo_offsite` 25 -> 12 bila tidak ada form sensitif | Kata-kata murah (toko, berita, blog); tanpa form yang meminta data, tidak ada yang dicuri (F-04-3, F-04-4) | legit >=30: 4 -> 1; scam >=50 33 -> 29 |
| 4 | Bobot kata penuh kembali bila layer 1-2 dari extension sudah >= 10 | Domain yang sudah mirip peniruan + logo/kata mendesak = bukti saling menguatkan | scam >=50 29 -> 33 (pulih), legit tetap 1/51 |
| 5 | Review #60: form kartu = SATU permintaan (`asks_card` menyala -> `asks_cvv` dibuang); `asks_card` 25 -> 20 (D-imelda-34) | Checkout kartu biasa di toko kecil non-populer bernilai 50 (kartu 25 + CVV 25) = field dicoret. 2 sampel legit baru (`trap-toko-kopi-kartu-native`, `trap-batik-card-checkout-en`, form kartu native di domain non-populer). Dengan 25 saja, toko `.xyz` = 25 + `cheap_tld` 5 = 30 (popup) | legit >=30: 2/53 -> 1/53; scam >=50 33 -> 31, >=80 16 -> 13 |
| 6 | Review #60: `go.id`, `tokopedia.link` kembali ke `POPULAR` (blocklist tidak pernah menerbitkannya); layer 3 pakai set sendiri `LAYER3_QUIET` = `POPULAR` tanpa public suffix dan shortener. Halaman buatan pengguna di domain populer (`express.adobe.com`, `acrobat.adobe.com`, `paper.dropbox.com`, `*.medium.com`, `gist.github.com`) tidak ikut diam | Satu set dipakai untuk dua tugas berbeda | Tidak ada sampel berubah; test blocklist + layer 3 |

`localSignals` hanya mengubah bobot KATA di halaman milik klien itu sendiri; tidak memengaruhi biaya/LLM atau halaman lain.

**Sesudah review #60** (53 legit, 50 scam, layer 4 mati): legit >=30 1/53 (nyata 0/39, sisa `trap-fintech-kyc-sah`); scam >=50 31/50 = 62%, >=80 13/50 = 26%. Target makin jauh di scam >=80: biaya dari menolak salah blokir checkout kartu (mandat sukses #1).

**Holdout tidak bersih (review #60).** `trap-asuransi-klaim-resmi` (F-04-2) dan `trap-toko-logo-bank-checkout` (F-04-3) ada di holdout (seed `61c5a7da42821cd2`), dan perubahan 1 dan 3 ditulis justru untuk dua sampel itu. Jadi "holdout legit 2/14 -> 0/14" hanya berarti dua sampel yang dibidik sudah diperbaiki; angka holdout legit **tidak dihitung** sebagai bukti. Sebelum klaim target apa pun: pindahkan setiap sampel yang disebut di temuan F-04 ke tuning dan tambah sampel holdout baru.

## Yang tidak bisa diperbaiki oleh bobot
- F-04-1 (`trap-fintech-kyc-sah`, KYC fintech sah, 85): isinya sama dengan scam KTP+selfie+OTP di domain netral. Tidak ada aturan yang memisahkan tanpa menurunkan deteksi; perlu bukti lain (umur domain/RDAP, layer 4, brand). Dilaporkan, bukan ditambal.
- F-04-5 (scam tanpa form: 0-5), F-04-6 (iframe, TODO C1): bukan masalah bobot.
- Daftar scam yang masih < 50: lihat `ai/eval` (sintetis: kurir/telkomsel/loker/investasi); 5 di antaranya hanya punya `asks_otp`/`asks_card` 25.

## Review (`ecc:security-reviewer` + `ecc:typescript-reviewer`)
Diperbaiki (HIGH): kekebalan situs populer meliputi platform hosting (`s3.amazonaws.com`, `googleusercontent.com`, medium...) -> `isOfficialHost` kini menolak semua host di bawah `SHARED_HOSTS` dan host konten-pengguna Microsoft (sway.office.com, onedrive.live.com, sharepoint.com...); `go.id` dan `tokopedia.link` dikeluarkan dari POPULAR; test negatif untuk semua kasus itu; `microsoftonline.com`/`office365.com` dipindah ke POPULAR. Eval setelah perbaikan: sama dengan tabel Sesudah.
Dicatat, tidak diubah: beberapa form sensitif bertumpuk di situs tak dikenal tetap bisa >= 30 (kartu+CVV kini satu sinyal 20, lihat perubahan 5); ambang "layer 1-2 >= 10" masih angka di kode; aturan kata-tanpa-form menurunkan skor scam yang menyembunyikan form (iframe, TODO C1) - angka di tabel sudah memuatnya; `localSignals` hanya mengubah bobot kata untuk halaman klien itu sendiri.

## Verifikasi
- `node --test --test-concurrency=1 detector/test ai/test ai/eval/test ios/ShooExtension/Tests`: 385 lolos, 0 gagal. Tidak ada test dihapus/dilemahkan; dua test yang mengunci bobot lama diperbarui dengan alasan (`forms.test.mjs` bobot R1, `content.test.mjs` bobot tanpa form) dan bobot penuh diuji di `calibration.test.mjs`.

## DoD
- [~] Tabel metrik terisi; target dilaporkan TIDAK tercapai/tidak dinilai.
- [x] Semua domain `brands.json` + 100 situs populer: skor layer 1-3 < 30 untuk login/OTP/PIN/kartu/KTP (test).
- [x] Test lama hijau, tidak dilemahkan. [x] Perubahan bobot tercatat satu per satu.

## LANGKAH MANUAL / keputusan (Imelda, Umar)
- [ ] Umar (C6): lihat angka di atas; target 90%/70% butuh data scam nyata, F-04-5/6 dan layer 4.
- [ ] Tambah scam nyata (min. 50, dibaca tangan sendiri) dan sampel holdout baru sebelum klaim target.
- [ ] Setujui D-imelda-30, D-imelda-31, D-imelda-34.
- [ ] Pindahkan sampel F-04 dari holdout ke tuning + tambah holdout baru (review #60) sebelum klaim target.
