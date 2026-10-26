# Perubahan 01: aturan field merek (layer 3) + daftar merek ke LLM (layer 4)

> 26 Okt 2026, 10.46 · branch lokal `fix/AI-M3-brand-form-fingerprint` (dari `main` @ `a035bb9`) · **belum di-commit, belum di-push**
> Tes dijalankan setelah perubahan selesai (lihat bagian 3): `ai/` 331/331, `detector/` 38/38, extension 151/151 lulus. Eval dan LLM nyata belum dijalankan.
> Diff lengkap: `changes.diff` di folder ini (374 baris, 9 file)
> Latar belakang: `../../../26-oct-2026/01-testing-09.58/` dan `../../../26-oct-2026/04-testing-10.30/` (scam login Microsoft palsu lolos dengan skor 15)

## 1. Ringkasan

| # | Perubahan | Folder | Intinya |
|---|---|---|---|
| 2 | **Aturan sidik jari field** (layer 3) | `ai/src/layer3/` | Form yang meniru form login merek (nama/id field khas) memunculkan `brand_logo_offsite`, bobot 25 |
| 1 | **Daftar merek ke LLM + prompt v3** (layer 4) | `ai/src/layer4/`, `ai/prompts/` | LLM sekarang menerima `brands: ["Microsoft"]` dan prompt menjelaskan cara memakainya |

Efek pada sampel `helpnets[.]info` (diukur offline, tanpa LLM): `brand_logo_offsite` 25 + `asks_password` 15 = **40** (sebelumnya 15, di bawah ambang peringatan 30), dan input LLM berisi `brands: ["Microsoft"]`. Jawaban LLM v3 belum diuji.

## 2. Perubahan per file

### Aturan 2: sidik jari field

| File | Perubahan |
|---|---|
| `ai/src/layer3/fingerprints.js` (**baru**) | Tabel `FIELD_FINGERPRINTS`. Satu entri: Microsoft, `names: ["loginfmt"]`, `ids: ["i0116", "i0118"]`, `minHits: 2` |
| `ai/src/layer3/content.js` | `findBrandForm()`: cocok persis (bukan potongan), huruf besar-kecil diabaikan, butuh **minimal 2 nilai berbeda**. `contentSignals()` memakai form dulu; kalau tidak ada, jatuh ke aturan logo lama. Tetap maksimal satu `brand_logo_offsite` |
| `ai/src/layer3/signals.js` | `buildBrandFormSignal(brandName)`: id `brand_logo_offsite` (id yang sudah ada, **tidak ada PR kontrak**), layer 3, bobot 25 (penuh, tidak "quiet"), label dua bahasa, **tanpa `evidence`** |

Kenapa aturan lama tidak menyala (hasil membaca kode, bukan tebakan):
- `microsoft` ada di `ALT_EXEMPT`, jadi alt "Microsoft" tidak pernah dicocokkan (agar tombol "Sign in with Microsoft" di situs sah tidak ditandai).
- Alt harus memuat kata `logo`; alt di sampel hanya "Microsoft".
- Title "Sign in to your account" tidak menyebut merek.

Pengaman terhadap salah blokir:
- Situs resmi (`login.microsoftonline.com`, `login.live.com`, dll.) tidak kena karena `official = true` (domain dari `brands.json`).
- Satu nilai umum saja (`passwd`) tidak cukup; butuh 2 nilai khas yang berbeda.
- Hanya `loginfmt`, `i0116`, `i0118` yang terdaftar. Merek lain **tidak** kutambah karena nama fieldnya belum kuverifikasi ke halaman aslinya.

### Aturan 1: merek ke LLM

| File | Perubahan |
|---|---|
| `ai/src/layer3/content.js` | `detectBrands(snapshot)` (diekspor): nama merek dari form yang ditiru, title, dan alt gambar. Alt merek yang di-exempt (google, microsoft, apple, meta) tidak dihitung sendirian. 3+ merek berbeda di alt dianggap strip metode bayar dan dilewati. Maks 3 nama, tanpa duplikat |
| `ai/src/layer4/reality.js` | `buildInput()` menambah `brands: detectBrands(snapshot)` (selalu ada, `[]` kalau kosong). Komentar kepala file diperbarui |
| `ai/prompts/reality-check.js` | `PROMPT_VERSION` `v2` → **`v3`**. Deskripsi data menyebut `brands`. Paragraf baru "About brands": merek tampil + form minta password/PIN/OTP/kartu + situs bukan domain merek itu = `reasonable: false`; halaman yang hanya mendaftar bank/dompet sebagai pilihan bayar itu normal; `brands` kosong = abaikan paragraf. Sisanya (aturan data tidak tepercaya, kunci output, "kalau ragu → wajar") tidak diubah |

Input ke LLM sebelum dan sesudah, untuk sampel kita:

```json
// sebelum
{"site":"helpnets.info","title":"Sign in to your account","fields":[...],"rules":["asks_password"]}
// sesudah
{"site":"helpnets.info","title":"Sign in to your account","fields":[...],"brands":["Microsoft"],"rules":["asks_password","brand_logo_offsite"]}
```

Yang **tidak** berubah: tidak ada teks halaman, path URL, atau nilai ketik yang dikirim. Nama merek berasal dari `brands.json` (kata-kata kita sendiri), bukan dari halaman.

### Tes dan dokumen

| File | Perubahan |
|---|---|
| `ai/test/content.test.mjs` | +11 tes (lulus): form Microsoft menyalakan sinyal (bobot 25, tanpa evidence); butuh 2 nilai berbeda; langkah email saja (`loginfmt` + `i0116` di satu field) cukup; cocok persis dan tidak peka huruf; `login.microsoftonline.com` dan `login.live.com` diam, `forms.office.com` tetap kena; form menang atas alt logo (tetap satu sinyal); bobot penuh tanpa `asks_*`; empat tes `detectBrands` |
| `ai/test/layer4.test.mjs` | +3 tes (lulus): `brands: ["Microsoft"]` terkirim tanpa teks atau alt pribadi; kunci `brands` selalu ada (`[]`); prompt v3 menyebut `brands` dan mempertahankan aturan "tidak tepercaya" dan kunci output |
| `ai/README.md` | Baris `brand_logo_offsite`, kolom "What the model sees", dan versi prompt (`v3`) |
| `plan/imelda/log/DECISIONS.md` | `D-imelda-42` (brands ke LLM, prompt v3) dan `D-imelda-43` (sidik jari field), keduanya berstatus **Usulan, belum dievaluasi** |

## 3. Yang belum diverifikasi (penting)

1. **Tes sudah dijalankan (26 Okt, setelah perubahan):** `node --test` di `ai/` 331 lulus dari 331 (317 lama + 14 baru), `detector/` 38/38, `ios/ShooExtension/Tests` 151/151. Tidak ada tes lama yang berubah hasilnya. Ini hanya tes unit dengan LLM palsu; tidak membuktikan kualitas jawaban LLM.
2. **Prompt v3 belum dievaluasi.** Belum ada bukti ia tidak menaikkan salah blokir. Risiko utama: situs sah yang menampilkan merek (login dengan Google/Microsoft, bank di halaman pembayaran) lalu diminta password di form sendiri. Mitigasi di kode: alt merek yang di-exempt tidak dihitung sendirian, dan strip 3+ merek dilewati. Perlu eval dengan sampel legit sebelum dianggap aman.
3. **Daya tangkap aturan sidik jari hanya untuk kit yang menyalin HTML aslinya.** Kit yang menulis form sendiri dengan nama field berbeda tidak tertangkap.
4. **Pengaruh ke sampel `helpnets`:** diukur offline lewat `analyzeSnapshot` dan `buildInput` pada snapshot yang sama: skor layer 3 = 40, lolos gerbang LLM, input memuat `"brands":["Microsoft"]` dan `rules` `["brand_logo_offsite","asks_password"]`. Tetap belum ada panggilan LLM nyata dengan prompt v3.
5. **Kontrak:** `contracts/detector-interface.md` baris 87 menyebut `brand_logo_offsite` sebagai sinyal teks yang `evidence`-nya harus teks di halaman. Sinyal baru tidak punya `evidence` (opsional menurut keputusan A7), jadi extension tidak men-stabilo apa pun untuknya; label tetap tampil. Deskripsi sinyal di tabel kontrak masih "Brand logo on non-official domain" dan bisa diperbarui lewat PR kontrak oleh Umar.

## 4. Yang perlu dikomunikasikan ke Umar (aturan repo)

- Folder `ai/` tercatat milik Umar sejak 23 Okt. Perubahan ini sebaiknya lewat issue/PR yang ia setujui.
- **D-imelda-42 melonggarkan D-imelda-27** (data ke LLM): satu field turunan baru, `brands`. Itu keputusan privasi, perlu persetujuannya.
- Aturan 4 repo (satu branch = satu PRD ID): saat di-commit, sebaiknya dipisah jadi dua branch/PR, `AI-M3` (sidik jari field: `fingerprints.js`, `signals.js`, `content.js` bagian form, tes `brand form`, D-imelda-43) dan `AI-M4` (brands ke LLM: `detectBrands`, `reality.js`, prompt v3, tes layer 4, D-imelda-42). `detectBrands` memakai `findBrandForm`, jadi M4 bergantung pada M3.

## 5. Cara membatalkan

Belum ada commit, jadi semua ada di working tree branch `fix/AI-M3-brand-form-fingerprint`. Untuk kembali bersih:

```bash
cd /Users/imelda/Documents/Swift/Final-CH/Final-CH7 && git checkout -- ai/README.md ai/prompts ai/src ai/test plan/imelda/log/DECISIONS.md && rm ai/src/layer3/fingerprints.js && git checkout main
```

`ai/.env.example` (kosong, bukan dari aku), `ai/testing/`, dan `plan/imelda/log/MORNING.md` tidak ikut perubahan ini dan tidak tersentuh perintah di atas.

## 6. Langkah berikutnya yang kuusulkan

1. Panggilan LLM nyata dengan prompt v3 pada sampel `helpnets` (beberapa kali, karena hasilnya tidak konsisten).
2. Eval dengan sampel legit (login bank asli, e-commerce, halaman dengan tombol "Sign in with Google/Microsoft") untuk mengukur salah blokir prompt v3 sebelum dipakai.
3. Buka issue ke Umar (draf: `../../../26-oct-2026/01-testing-09.58/issue-draft-reasoning.md`, perlu ditambah dua item di atas).
