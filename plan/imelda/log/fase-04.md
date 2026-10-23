# Fase 04 — Data eval set 50+50 (M2)

**Status:** `[~]` kode, data, test, review selesai. Menunggu izin Imelda untuk push/PR. Jumlah sampel terpenuhi (50 scam, 51 legit), tetapi **scam nyata hanya 1**, jadi target mandat belum bisa dibuktikan (lihat Deviasi).
**Branch:** `feat/AI-M2-eval-data` dari `origin/main` (PR #44 dan #50 masih OPEN saat fase ini dikerjakan). Tanggal: 22 Okt 2026.

## Keputusan (LANGKAH 0)
D-imelda-19..22 di `log/DECISIONS.md`: sumber scam campuran tanpa feed berlisensi tak jelas; komposisi 50+50 sesuai usulan; holdout 30% ber-seed; legit nyata >= 60%, scam nyata sebisanya.
Cek lisensi (halaman resmi, 22 Okt 2026): OpenPhish melarang distribusi dan karya turunan tanpa izin tertulis; PhishTank tidak mencantumkan lisensi (merujuk EULA Cisco); URLhaus = URL malware, tanpa lisensi tertulis di halaman. Tidak satu pun dipakai.

## Rencana (dijalankan)
1. Test dulu: pemeriksa penyamaran, validasi korpus, holdout, SSRF guard, ringkasan run.mjs.
2. Implementasi alat; hardening `capture.mjs` (redirect diperiksa per hop, host privat ditolak).
3. `ai/eval/data/PLAN.md` (kebutuhan per kategori).
4. 45 scam sintetis + 8 trap legit sintetis ditulis tangan; 35 halaman legit publik di-capture (URL disetujui Imelda, GET statis lewat `capture.mjs`, JSON saja, tanpa HTML mentah).
5. Imelda membaca 39 sampel nyata dan menjalankan `mark-redacted.mjs` sendiri.
6. Eval, verifikasi, review, perbaikan temuan.

## File diubah (hanya `ai/eval/**` dan `plan/imelda/**`)
Baru: `corpus.mjs`, `tools/{check-redaction,check-corpus,assign-holdout,mark-redacted,safe-url,patterns,is-main}.mjs`, `test/corpus.test.mjs`, `data/{PLAN.md,HOLDOUT.json,legit/real.json,legit/traps.json,scam/synthetic.json}`.
Diubah: `lib.mjs`, `run.mjs`, `tools/{capture,snapshot}.mjs`, `data/{legit,scam}/seed.json` (tag disesuaikan taksonomi), `README.md`, `plan/imelda/{fixbug.md,log/DECISIONS.md}`.
Tidak disentuh: `contracts/`, `ios/`, `backend/`, `detector/`, `ai/src/`.

## Hasil
Service lokal: `/analyze` dari cabang `feat/AI-M3-content` (#50) diekstrak ke scratchpad dan dijalankan di `localhost:8787` (RDAP mati; `new_domain` tidak diukur). Keluaran asli `node ai/eval/run.mjs --analyze-url http://localhost:8787`:

```
samples: 50 scam, 51 legit
scam   flagged >=30: 40/50   >=50: 33/50   >=80: 20/50
legit  flagged >=30: 4/51    >=50: 1/51    >=80: 1/51

TARGETS (mandate)            real only   all samples  target     (real: 1 scam, 39 legit)
  scam   score >= 50         0%          66%          90%
  scam   score >= 80         0%          40%          70%
  legit  score >= 30         0           4            0 pages
  -> not judged: fewer than 50 real samples per class (synthetic samples cannot back a claim)

REAL vs SYNTHETIC
  real       scam 0/1 >=50, 0/1 >=80 | legit 0/39 flagged
  synthetic  scam 33/49 >=50, 20/49 >=80 | legit 4/12 flagged
HOLDOUT vs TUNING
  holdout    scam 7/12 >=50, 5/12 >=80 | legit 2/14 flagged
  tuning     scam 26/38 >=50, 15/38 >=80 | legit 2/37 flagged
```
Per kategori (scam >=50 / >=80): bank 8/10, 7/10 · e-wallet 7/8, 5/8 · courier 3/8, 1/8 · prize 6/8, 3/8 · government 5/8, 4/8 · apple 2/4, 0/4 · other 2/4, 0/4. `clean-domain-scam` 7/15 >=50, `lookalike-brand` 22/27, `credential-iframe` 0/2. Legit: bank-login 0/9, checkout 0/12, official-gov 0/8, popular 0/10 flagged; `lookalike-trap` 4/12 flagged. `analyzeLocal` rata-rata 0,18 ms, maks 0,48 ms.

**False positive (legit >= 30)**: semuanya sintetis, kasus sulit yang disengaja. `trap-fintech-kyc-sah` 95 (`asks_selfie_ktp`+`asks_ktp`+`asks_otp`), `trap-asuransi-klaim-resmi` 30 (`asks_ktp` saja), `trap-toko-logo-bank-checkout` 40 (`brand_logo_offsite`+`urgent_language`), `trap-berita-waspada-penipuan` 40 (sama). 0 dari 39 halaman legit nyata terkena.
**Scam < 50 (17)**: lphone-login 39 (iframe), tiga fixture URL-saja 29, `synthetic-p0stindonesia` 25 (URL-saja), dan sintetis tanpa kolom form di domain netral (`syn-loker-admin-online` 0, `syn-investasi-kripto-profit` 0, `syn-cimb-octo-limit` 0, `syn-samsat-pajak-kendaraan` 5, `syn-sicepat-apk` 5) serta yang hanya satu sinyal 30-35 (`syn-linkaja-hadiah`, `syn-anteraja-alamat`, `syn-tiki-nomor-resi`, `syn-telkomsel-poin`, `syn-etilang-denda`, `syn-ninja-ganti-rugi`).
Temuan lengkap di `fixbug.md` F-04-1..7. Tidak ada aturan atau bobot yang diubah.

## Verifikasi (keluaran asli)
- `node --test ai/ detector/test ai/eval/test ios/ShooExtension/Tests` -> `tests 194, pass 194, fail 0`. (`ai/` di cabang ini hanya berisi `eval/`; test service ada di #44/#50.)
- `node ai/eval/tools/check-redaction.mjs` -> `101 samples checked, 0 finding(s), 0 load error(s)`.
- `node ai/eval/tools/check-corpus.mjs` -> `corpus complete` + `WARNING only 1 real scam sample(s)`.
- `gitleaks detect --log-opts origin/main..HEAD` -> `no leaks found`. Sempat 1 positif palsu (JWT contoh di fixture test); fixture dirakit saat runtime dan 7 commit lokal yang belum di-push ditulis ulang agar literalnya tidak ada di riwayat.
- `git ls-files ai/eval/data`: terbesar `legit/real.json` 101 KB, `scam/synthetic.json` 64 KB; 0 file `.html`; 0 nama file berisi token/secret/password/credential/apikey/.p8.

## DoD
- [~] >= 50 scam dan >= 50 legit, tiap sampel berlabel, bersumber, bertanggal: **50 dan 51**. Nyata: legit 39/51 (76%, batas 60% terpenuhi); scam 1/50.
- [x] Penyamaran: pemeriksa 0 temuan di seluruh data + 45 test alat; 39 sampel nyata dibaca dan di-set `redacted` oleh Imelda (agent tidak mengisi flag).
- [x] Sinyal layer 3 bisa menyala: sampel baru membawa title/text/forms/imageAlts; trap fase 03 ada (logo bank di checkout, "diskon terakhir hari ini", "dikirim dalam 24 jam", blog "Cara cek saldo BCA", Sign in with Google, ikon share, github.io/blogspot, KYC sah). 6 halaman nyata kosong (JS), lihat F-04-7.
- [x] `run.mjs` satu perintah; angka asli di atas.
- [x] Holdout 26/101 terkunci dengan seed `61c5a7da42821cd2` (`HOLDOUT.json`), belum dipakai untuk tuning. Catatan: sebelum flag penyembunyian ada, run pertama saya menampilkan semua baris, termasuk 2 FP holdout (`trap-toko-logo-bank-checkout`, `trap-asuransi-klaim-resmi`) yang lalu tercatat di fixbug F-04-2/3. Belum ada tuning, tapi sampel itu sudah "terlihat".
- [x] security-reviewer dan code-reviewer dijalankan; CRITICAL 0; HIGH ditutup (lihat bawah).

## Temuan review
**security-reviewer** (0 CRITICAL, 2 HIGH, 3 MEDIUM, 7 LOW):
- HIGH `action` form tidak disamarkan (token `p_auth` sungguhan di sampel Mandiri) -> **ditutup**: capture memakai `redactSrc`, pemeriksa memeriksa URL action, data dibersihkan; test.
- HIGH batas 1500 karakter tidak mencakup `imageAlts` (judul berita 3,8-4,4 ribu karakter per halaman) + atribusi Wikipedia -> **ditutup**: alt dibatasi 10 x 80, atribusi CC BY-SA di `source`, README menyebut "tanpa lisensi dari situs, kutipan terbatas" (risiko diterima Imelda, D-imelda-22).
- MEDIUM regex lolos format Indonesia (email `[at]`, fullwidth, telepon rumah, NIK bertitik, digit Arab) -> **ditutup**: `patterns.mjs` bersama + `fold()` NFKC; test.
- MEDIUM `mark-redacted` tidak membuktikan manusia yang membaca -> **tidak ditutup penuh**: `--ids` kosong diperbaiki; skema `reviewedHash` dicatat sebagai langkah lanjut (Deviasi).
- MEDIUM SSRF: ruang IPv6 (compat, NAT64, 6to4, site-local), TEST-NET, `localhost.` -> **ditutup**; DNS rebinding (pinning koneksi) -> **tidak diambil**, dicatat di README.
- LOW: tanpa prompt injection di data; `--file` menerima path apa pun (dipakai pemilik); UA mobile Safari tanpa cek robots.txt (keputusan didokumentasikan: GET tunggal untuk pengukuran); email commit.
**code-reviewer** (0 CRITICAL, 2 HIGH, 5 MEDIUM, 6 LOW):
- HIGH verdict target memakai sampel sintetis -> **ditutup**: verdict hanya dari sampel nyata (perlu 50 nyata per kelas, jika tidak "not judged"); `check-corpus` melaporkan 60% nyata legit dan WARNING scam nyata.
- HIGH `--strict` lolos tanpa verdict; `/analyze` gagal di tengah run ditelan -> **ditutup**: `--strict` keluar 2 bila tidak dinilai; kegagalan dihitung (`remoteFailures`), sinyal cacat (id/layer/weight) ditandai gagal; test dengan server HTTP palsu.
- MEDIUM guard `main` diam bila lewat symlink -> **ditutup** (`isMain` + test symlink); holdout terbuka tiap run -> **ditutup** (`--show-holdout`); komposisi lintas kelas -> **ditutup** (per kelas + tepat satu tag kategori); IPv6 -> ditutup; URL non-http dilewati pemeriksa -> ditutup.
- LOW: opsi tanpa nilai kini keluar 2; trailing dot; `readSeed` mengabaikan `fraction` (tetap 0,3, tidak berdampak).

## Deviasi
1. **Scam nyata hanya 1** (D-imelda-19). 49 scam sintetis tidak boleh mendukung klaim target; target mandat `scam >= 50: 90%` dan `>= 80: 70%` tidak bisa dinilai sampai ada >= 50 scam nyata dengan lisensi jelas atau izin tertulis (mis. OpenPhish) -> TODO A4.
2. Holdout scam seluruhnya sintetis (12/12), sehingga belum bisa mengukur recall nyata.
3. `mark-redacted` tetap flag biasa; tidak ada bukti di repo bahwa manusia yang menjalankannya. `reviewedHash` belum dibuat.
4. Pinning koneksi DNS di `capture.mjs` tidak dibuat (butuh undici/Agent kustom).
5. Data nyata diubah setelah Imelda membaca (hanya pengurangan: token `p_auth`, nomor telepon kantor pemerintah, query iframe `lphone-login`, alt dipangkas; flag `redacted` tetap).
6. D-imelda-19..22 ditulis di `DECISIONS.md` versi `main` (berhenti di D-08); D-09..18 ada di #44/#50, akan ada konflik kecil saat merge.
7. TDD: perbaikan iframe (`redactSrc`) ditulis bersamaan dengan test-nya, bukan test-gagal-dulu; sisanya melihat merah dulu.

## Catatan handoff
- Fase 07 (kalibrasi): tuning hanya pada sampel non-holdout; lihat holdout sekali di akhir. Mulai dari F-04-1..5. KYC sah, klaim asuransi, dan toko dengan logo bank adalah kasus sulit yang disengaja (jangan "disetel agar hilang" tanpa melihat dampak recall).
- Fase 06 (LLM): scam di domain netral tanpa form (F-04-5) hanya bisa ditangkap layer 4 atau sinyal teks baru.
- Untuk menutup deviasi 1: butuh sumber scam nyata berlisensi (tanya OpenPhish/Komdigi) atau izin tertulis; setelah itu `capture.mjs --file` (HTML disimpan sekali di luar repo).
- Menunggu Umar: TODO C1 (iframe), C10 (evidence alt).
