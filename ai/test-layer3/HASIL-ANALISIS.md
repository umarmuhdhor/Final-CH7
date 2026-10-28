# Hasil analisis layer 3 (form + konten + umur domain)

Lingkup: hanya layer 3. `localSignals` kosong (bobot kata versi quiet). Skor = jumlah bobot, maks 100. Tertangkap = skor ≥ 30.

## 1. Ringkasan

| pola dominan | jumlah situs | tertangkap L3 (≥30) | lolos |
|---|---:|---:|---:|
| PASSWORD | 10 | 8 | 2 |
| OTP | 11 | 6 | 5 |
| PIN | 3 | 3 | 0 |
| LAIN_TANPA_FORM | 1 | 0 | 1 |
| **total dianalisis** | **25** | **17** | **8** |

- 3 situs meminta PIN
- 14 situs meminta OTP
- 13 situs meminta password
- 0 situs meminta kartu / CVV / KTP / selfie-KTP
- 13 situs meminta data di luar rule form (nama, HP, user/corp ID, username, email, token bank)
- 18 situs mengirim data ke Telegram (`api.telegram.org/sendMessage`)
- 1 situs tanpa form
- 0 situs scam tidak bisa dianalisis
- **0 dari 6** situs legit yang meminta data ikut kena L3. 3 situs legit password-only skor 15 (L03, L05, L10) — sama pola lolos dengan scam Instagram/DHL. 3 landing tanpa form data (L06–L08). 1 landing PMB hanya search (L04). Host PPDB pemda tetap tidak ketemu.

Tiga temuan utama:

1. **Login bank kloning tertangkap.** Password + logo brand (BNI/BRI/BSI) + kadang OTP. PIN sendirian (bobot 35) cukup. 01–04, 06–09, 17–18, 21, 23–25 kena.
2. **OTP-only lemah.** Keyword harus ada di atribut field, bukan di heading. 05 kotak OTP tanpa `name`/`id`/`placeholder`. 14 dan 15 pakai `code1` + "Kode Pendaftaran", bukan "kode verifikasi" — skor 0. 10 dan 19 kena `asks_otp` 25 lalu **lolos** karena 25 < 30 dan host bersama/tua tidak kasih `new_domain`.
3. **4 situs tertangkap hanya karena umur domain** (08, 12, 13, 16). Tanpa `new_domain` tertangkap turun 17 → 13. Login Instagram (20) dan DHL (22) password-only di host bersama/tua: skor 15, lolos.

## 2. Metode

- Sumber scam: `ai/test-layer2/dataset.md`, 25 baris tabel, id 01–25.
- Ambil: `curl -sSL --max-redirs 3 --max-time 15 --max-filesize 2000000` dua UA (iPhone Safari 17, desktop Safari 17). HTML mentah di `/tmp/l3-html`, bukan repo. Parser `python3 -I` + `html.parser` di `/tmp/l3-parser` (folder terpisah dari HTML). JS halaman tidak dijalankan.
- Tanggal ambil scam: 28 Oktober 2026, 11:49 WIB (03:49 UTC). Legit: 28 Oktober 2026, 12:00 WIB (04:00 UTC), daftar disetujui user.
- Snapshot: teks terlihat dari HTML; buang `script`/`style`/`noscript`; maks 20.000 karakter. Field `value` tidak disimpan. Token bot Telegram ditulis `[disamarkan]`.
- Id 06 (Google Sites): form ada di HTML ter-escape dalam embed. Field `user_id` + `pin` dimasukkan ke snapshot, dicatat di `fieldsFromJs`.
- Blogspot 11, 23–25: iPhone dapat HTTP 302 ke `?m=1` (tampilan mobile). Diikuti (redirect otomatis). 23–25 isi sama dengan desktop. 11 isi beda (lihat bagian 9).
- Versi kode: `5227ec5`.
- RDAP: `createRdapClient({ fetch, cache: createMemoryCache(), timeoutMs: 10000 })` + `lookupAgeDays(host akhir)`. Timeout dinaikkan 1500 → 10000 untuk tes ini. Host bersama (blogspot, pages.dev, vercel.app, github.io, cloudfront) menghasilkan umur platform atau `null` — tidak ada sinyal `new_domain` (umur > 90 hari atau gagal).
- Skor: `analyzeSnapshot(snapshot)` + `buildNewDomainSignal(rdapAgeDays)`. Sama dengan `node ai/test-layer3/run.mjs`.
- Kode `LAIN_` baru: **`LAIN_TOKEN`** = field token bank yang bukan keyword OTP/PIN (`Mobile Token`, `Token Lunak`, `Respon KeyBCA`).

## 3. Peta perilaku

### (a) Situs yang meminta X (boleh tumpang tindih)

| kode | n | id |
|---|---:|---|
| PIN | 3 | 06, 07, 09 |
| OTP | 14 | 04, 05, 10, 12, 13, 14, 15, 16, 17, 18, 19, 23, 24, 25 |
| PASSWORD | 13 | 01, 02, 03, 04, 08, 17, 18, 20, 21, 22, 23, 24, 25 |
| KARTU | 0 | — |
| CVV | 0 | — |
| KTP | 0 | — |
| SELFIE_KTP | 0 | — |
| URGENT | 1 | 25 |
| BRAND_TIRUAN | 7 | 01, 02, 03, 04, 05, 18, 21 |
| LAIN_NAMA | 2 | 03, 25 |
| LAIN_HP | 10 | 01, 02, 03, 04, 08, 17, 18, 23, 24, 25 |
| LAIN_EMAIL | 1 | 22 |
| LAIN_REKENING | 7 | 01, 02, 03, 04, 06, 17, 18 |
| LAIN_USERNAME | 1 | 20 |
| LAIN_TOKEN | 4 | 01, 02, 03, 17 |
| LAIN_KIRIM_KE_CHAT | 18 | 01, 02, 03, 04, 05, 06, 09, 10, 12, 13, 14, 15, 16, 17, 18, 23, 24, 25 |
| LAIN_TANPA_FORM | 1 | 11 |

Tidak terlihat: LAIN_ALAMAT, LAIN_TTL, LAIN_SALDO, LAIN_FOTO, LAIN_PEKERJAAN, LAIN_APK, LAIN_BAYAR, LAIN_SHARE, LAIN_PROFIL_IOS. Id 15 menyebut KTP/nama/alamat di teks instruksi, bukan di field halaman ini.

### (b) Pola dominan

| pola | n | % |
|---|---:|---:|
| OTP | 11 | 44% |
| PASSWORD | 10 | 40% |
| PIN | 3 | 12% |
| LAIN_TANPA_FORM | 1 | 4% |
| **jumlah** | **25** | **100%** |

### (c) Kombinasi yang sering

- Login korporat bank + ganti sandi + HP + token/OTP + kirim Telegram: 01–04, 17, 18. Kit yang sama, brand diganti.
- OTP via Telegram + daftar bantuan (laptop, BSU, bibit, sembako): 12–16.
- OTP + password + nomor HP + Telegram, umpan SIM/bansos/kuota di blogspot: 23–25.
- OTP sendirian (tanpa password): 05, 10, 19. Ini yang paling sering lolos.

## 4. Situs per grup

### 4.1 OTP (11 situs) — 6 tertangkap, 5 lolos

| id | host akhir | menyamar | cerita pancingan | yang diminta (field persis) | dikirim ke | semua kode | skor L3 | tertangkap? |
|---|---|---|---|---|---|---|---:|---|
| 05 | kodepembatalanbybni.pages.dev | tidak | pembatalan transaksi BNI, 6 kotak OTP | 6× `input type=text` tanpa name/id/placeholder/label | Telegram `sendMessage` | OTP, BRAND_TIRUAN, LAIN_KIRIM_KE_CHAT | 12 | tidak |
| 10 | storee-dp8iiud7biuu.edgeone.dev | tidak | verifikasi kode Agoda | text `id=inputOtpAsli` | Telegram `sendMessage` | OTP, LAIN_KIRIM_KE_CHAT | 25 | tidak |
| 12 | registers-app15.fkregs-on.com | tidak | pendaftaran via Telegram, umpan laptop | tel `name=otp` `id=otp` ph=`Masukkan kode verifikasi` | `pass.php`; OTP via Telegram | OTP, LAIN_KIRIM_KE_CHAT | 35 | ya |
| 13 | regs-apps14.regnows-dfg.com | tidak | sama, umpan BSU/kemnaker | sama seperti 12 | `pass.php` | OTP, LAIN_KIRIM_KE_CHAT | 35 | ya |
| 14 | pendaftaran-umum04.thems.blog | tidak | kode pendaftaran bibit, via Telegram | tel `code1`–`code5`; hidden `phone_number`; label `Kode Pendaftaran, kami kirim ke Telegram Anda.` | `/auth`, `/completed` | OTP, LAIN_KIRIM_KE_CHAT | 0 | tidak |
| 15 | apply.wozspace.site | tidak | daftar sembako, kode 5 digit Telegram | tel `code1`–`code5`; hidden `name=code` | `/auth`, `/completed` | OTP, LAIN_KIRIM_KE_CHAT | 0 | tidak |
| 16 | registersw-app17.fkregs-on.com | tidak | sama kit 12/13 | sama seperti 12 | `pass.php` | OTP, LAIN_KIRIM_KE_CHAT | 35 | ya |
| 19 | shopeeofficial-refund.vercel.app | tidak | refund Shopee, halaman `otp.html` | text `otp1`–`otp6` | `login.html` | OTP | 25 | tidak |
| 23 | simgratisonine.blogspot.com | tidak | daftar SIM gratis | select jenis SIM; select provinsi; tel `nomor`; tel `otp` ph=`00000`; password `pw` | Telegram `sendMessage` | OTP, PASSWORD, LAIN_HP, LAIN_KIRIM_KE_CHAT | 40 | ya |
| 24 | bantuannbansos2026.blogspot.com | tidak | cek status bansos | select provinsi; tel `nomor`; tel `otp`; password `pw` | Telegram `sendMessage` | OTP, PASSWORD, LAIN_HP, LAIN_KIRIM_KE_CHAT | 40 | ya |
| 25 | gratiskuota60gb.blogspot.com | tidak | klaim kuota 60GB | text `nama` ph=`Nama lengkap anda Sesuai untuk klaim kuota gratis.`; tel `nomor`; tel `otp`; password `pw` | Telegram `sendMessage` | OTP, PASSWORD, URGENT, LAIN_NAMA, LAIN_HP, LAIN_KIRIM_KE_CHAT | 55 | ya |

Pola grup: OTP lewat Telegram adalah modus terbanyak. L3 hanya melihat atribut field. Heading "Verifikasi OTP" atau label "Kode Pendaftaran" tidak cukup. Bobot OTP 25 tidak lolos threshold tanpa sinyal kedua.

Catatan:

1. **05.** Teks: "masukkan 6 digit kode OTP untuk pembatalan transaksi ke rekening SALSA MERRYANI". Title `BNI - Verifikasi` → `brand_logo_offsite` quiet 12 (tidak ada form signal, jadi `asksData=false`). Class CSS `otp-input` tidak dibaca rule. Host `pages.dev` → RDAP umur platform 2247 hari, tidak ada `new_domain`.
2. **10.** Title `Verifikasi Kode — Agoda`. Agoda tidak ada di `brands.json`, jadi title+verifikasi tidak nyala. `edgeone.dev` umur 505 hari, tidak ada `new_domain`.
3. **12/13/16.** Tertangkap karena `asks_otp` 25 + `new_domain` 10 (umur 68 dan 87 hari). Tanpa umur domain, lolos. `location.href` ke jobstreet/kemnaker hanya setelah klik/gagal, tidak diikuti.
4. **14.** Label field = "Kode Pendaftaran…". Rule OTP butuh frasa `kode verifikasi` utuh di atribut yang sama. Title halaman `Verifikasi OTP` bukan field.
5. **15.** Teks instruksi: "Lengkapi data diri sesuai kartu identitas (KTP)". Bukan field. Tidak kena `asks_ktp`.
6. **19.** `asks_otp` 25. `vercel.app` umur platform 2465 hari. Title `OTP - Shopee` tanpa kata aksi (`login`/`verifikasi`/…), brand title tidak nyala.
7. **25.** Satu-satunya `urgent_language`: teks tombol `KLAIM SEKARANG` (frasa persis di daftar).
8. **23–25.** iPhone autocomplete OTP tidak `one-time-code`. Password placeholder `MASUKKAN KATA SANDI` / `KATA LALUAN`.

### 4.2 PASSWORD (10 situs) — 8 tertangkap, 2 lolos

| id | host akhir | menyamar | cerita pancingan | yang diminta (field persis) | dikirim ke | semua kode | skor L3 | tertangkap? |
|---|---|---|---|---|---|---|---:|---|
| 01 | bni-diirect.com | tidak | BNI Direct Cash, login perusahaan | text `companyId`; text `userId`; password `password`; password `newPassword`; password `confirmPassword`; tel `phoneNumber`; password `mobileToken` | Telegram `sendMessage` | PASSWORD, BRAND_TIRUAN, LAIN_REKENING, LAIN_HP, LAIN_TOKEN, LAIN_KIRIM_KE_CHAT | 60 | ya |
| 02 | bni-directbni.com | tidak | sama persis dengan 01, host lain | sama | Telegram `sendMessage` | sama | 60 | ya |
| 03 | qlolla-bybri.com | tidak | QLola BRI, wajib ganti sandi | text `kodePerusahaan`; text `namaBelakang`; password `kataSandi`; password `newPassword`; password `confirmPassword`; tel `phoneNumber`; password `mobileToken` | Telegram `sendMessage` | PASSWORD, BRAND_TIRUAN, LAIN_REKENING, LAIN_NAMA, LAIN_HP, LAIN_TOKEN, LAIN_KIRIM_KE_CHAT | 70 | ya |
| 04 | cusbsi.com | tidak | login BSI Cash Management, wajib ganti sandi | Company ID; User ID; Password; captcha; Kata Sandi Saat Ini; Kata Sandi Baru; tel `phoneNumber`; text `otpCode` | Telegram `sendMessage` | PASSWORD, OTP, BRAND_TIRUAN, LAIN_REKENING, LAIN_HP, LAIN_KIRIM_KE_CHAT | 85 | ya |
| 08 | m-pajak.top | tidak | login M-Pajak / DJP | tel `name=phone`; password `name=password` | `confirm.html` (setelah submit, tidak diambil) | PASSWORD, LAIN_HP | 35 | ya |
| 17 | login-mybca-bisnis.ibcbank-aceh.com | tidak | myBCA Bisnis | text `corpId`; text `userId`; text `keyBca`; tel `otpInput` `autocomplete=one-time-code`; password `passBaru`; password `passBaru2`; tel `nomorHp`; text `inputRespons` | Telegram `sendMessage`; `wa.me` (buka blokir, dicatat tidak diikuti) | PASSWORD, OTP, LAIN_REKENING, LAIN_HP, LAIN_TOKEN, LAIN_KIRIM_KE_CHAT | 50 | ya |
| 18 | www.cuz-bankkbsi.com | tidak | CUZ by BSI, kit sama 04 | sama seperti 04 | Telegram `sendMessage` | PASSWORD, OTP, BRAND_TIRUAN, LAIN_REKENING, LAIN_HP, LAIN_KIRIM_KE_CHAT | 85 | ya |
| 20 | viinwkwk-dot.github.io | tidak | login Instagram ID | text `uname` label=`Nomor telepon, nama pengguna, atau email`; password `passwd` | `admin.html` | PASSWORD, LAIN_USERNAME | 15 | tidak |
| 21 | helpnets.info | tidak | login Microsoft (field `loginfmt` / `i0116` / `i0118`) | email `name=loginfmt` `id=i0116`; password `name=passwd` `id=i0118` | form `method=post` action kosong | PASSWORD, BRAND_TIRUAN | 40 | ya |
| 22 | d33wubrfki0l68.cloudfront.net | tidak | login DHL Express | email `name=email`; password `name=password` | `submit-form.com` (fetch); setelah 5 gagal → dhl.com (tidak diikuti, butuh klik/ulang) | PASSWORD, LAIN_EMAIL | 15 | tidak |

Pola grup: kit cash-management bank hampir identik. `type=password` selalu nyala 15. Logo `BNI Logo` / `BSI Logo` / `Logo QLola … BRI` memicu brand 25. Token bank (`mobileToken`, KeyBCA) tidak masuk rule OTP/PIN.

Catatan:

1. **01/02.** Alt `BNI Logo` + kata `logo` → `brand_logo_offsite` 25. Umur domain 7 hari → `new_domain` 20. Field `mobileToken` type=password, bukan OTP.
2. **03.** Alt `Logo QLola Cash Management BRI`. Umur 6 hari → `new_domain` 30.
3. **08.** Title `M-Pajak • djp` tanpa kata aksi → brand tidak nyala. Tertangkap hanya karena umur 22 hari (+20). Tanpa RDAP skor 15.
4. **17.** Title `myBCA Bisnis` tanpa kata aksi → brand tidak nyala meski `mybca` ada di `brands.json`. `autocomplete=one-time-code` pada OTP: khas iPhone, rule tidak membacanya (sudah kena dari `id=otpInput`).
5. **20.** Title `Instagram` tanpa kata aksi. Meta di `ALT_EXEMPT`, alt `App Store`/`Google Play` bukan logo Instagram. `github.io` → RDAP `null`.
6. **21.** Fingerprint Microsoft (`loginfmt` + `i0116`/`i0118`, `minHits=2`) → `brand_logo_offsite` 25 tanpa `evidence`. Alt `Microsoft` tidak dihitung (`ALT_EXEMPT`).
7. **22.** DHL tidak ada di `brands.json`. `cloudfront.net` umur platform, tidak ada `new_domain`.

### 4.3 PIN (3 situs) — 3 tertangkap

| id | host akhir | menyamar | cerita pancingan | yang diminta (field persis) | dikirim ke | semua kode | skor L3 | tertangkap? |
|---|---|---|---|---|---|---|---:|---|
| 06 | sites.google.com | tidak | pengembalian dana, form di embed Google Sites | text `user_id` ph=`Masukkan USER ID`; password `pin` ph=`Masukkan PIN` (dari HTML ter-escape / JS) | Telegram `sendMessage` | PIN, LAIN_REKENING, LAIN_KIRIM_KE_CHAT | 35 | ya |
| 07 | yaigsjv.1238bll.my.id | tidak | GoPay/Gojek, "Cek WhatsApp, ya" | tel `pin1`–`pin6`; hidden `tarif`,`nohp`,`inp1`–`inp6` | form tanpa action (halaman ini) | PIN | 55 | ya |
| 09 | storee-dp9hsk1cxr2y.edgeone.dev | tidak | PIN akun Agoda | text `id=inputPinAsli` | Telegram `sendMessage` | PIN, LAIN_KIRIM_KE_CHAT | 35 | ya |

Pola grup: kata `pin` di `name`/`id`/`placeholder` langsung 35. Cukup sendirian.

Catatan:

1. **06.** Status `terbuka-kosong`. `curl` tidak melihat `<form>` sungguhan. Field diambil dari embed ter-escape. Tanpa langkah itu skor 0. Token bot di embed **tidak** disalin ke snapshot.
2. **07.** Title Gojek tanpa kata aksi → brand tidak nyala. `asks_pin` dari `name=pin1`. Umur `1238bll.my.id` 18 hari → +20.
3. **09.** Agoda tidak di `brands.json`. Title `Masukkan PIN — Agoda`: `masukkan` ≠ kata aksi `masuk`.

### 4.4 LAIN_TANPA_FORM (1 situs) — lolos

| id | host akhir | menyamar | cerita pancingan | yang diminta (field persis) | dikirim ke | semua kode | skor L3 | tertangkap? |
|---|---|---|---|---|---|---|---:|---|
| 11 | deddydanchika.blogspot.com | **ya** | iPhone: blog "Video Mesum Deddy Dan Chika", "Tidak ada postingan." Desktop: login Facebook | tidak ada (versi iPhone) | tidak terlihat | LAIN_TANPA_FORM | 0 | tidak |

Catatan: **11.** Desktop title `Masuk Facebook`, form POST ke `fesbukbatam.pixub.com/login.php`, field `email` + `pass`. Acuan iPhone (aturan tes). Perlu dicek manual di iPhone Indonesia.

## 5. Tidak bisa dianalisis

Tidak ada. Semua 25 terbuka atau terbuka-kosong.

| id | host | status | penyebab |
|---|---|---|---|
| — | — | — | — |

## 6. Cek layer 3

### Per grup

| grup | n | tertangkap | lolos | lolos id |
|---|---:|---:|---:|---|
| OTP | 11 | 6 | 5 | 05, 10, 14, 15, 19 |
| PASSWORD | 10 | 8 | 2 | 20, 22 |
| PIN | 3 | 3 | 0 | — |
| LAIN_TANPA_FORM | 1 | 0 | 1 | 11 |

### Situs yang lolos

| id | skor | sinyal | alasan |
|---|---:|---|---|
| 14 | 0 | — | kata kunci OTP tidak ada di field (`code1` + "Kode Pendaftaran"); bukan "kode verifikasi" |
| 15 | 0 | — | sama; KTP hanya di teks instruksi |
| 11 | 0 | — | tanpa form (versi iPhone) |
| 05 | 12 | `brand_logo_offsite:12:BNI` | kotak OTP tanpa name/id/label; bobot quiet; `pages.dev` tanpa `new_domain` |
| 20 | 15 | `asks_password:15` | password saja; title brand tanpa kata aksi; `github.io` RDAP `null` |
| 22 | 15 | `asks_password:15` | password saja; DHL tidak di brands; host CDN tua |
| 10 | 25 | `asks_otp:25` | OTP 25 < 30; Agoda tidak di brands; `edgeone.dev` tua |
| 19 | 25 | `asks_otp:25` | OTP 25 < 30; title Shopee tanpa kata aksi; `vercel.app` tua |

Alasan lolos, dari yang terbanyak:

1. **OTP 25 tidak sampai 30** tanpa sinyal kedua, dan host bersama/tua tidak kasih `new_domain` (10, 19).
2. **Keyword OTP tidak di atribut field** (14, 15, 05).
3. **Password 15 sendirian** di host bersama/tua (20, 22).
4. **Tanpa form** (11).
5. **Brand title butuh kata aksi** (`login`/`masuk`/`verifikasi`/…) — Instagram, Shopee, myBCA, M-Pajak, DHL, Agoda gagal dari title.
6. **Brand tidak ada di `brands.json`** (Agoda, DHL).

### Kontribusi `new_domain`

Sinyal nyala di: 01 (7h, +20), 02 (7h, +20), 03 (6h, +30), 04 (21h, +20), 07 (18h, +20), 08 (22h, +20), 12 (68h, +10), 13 (87h, +10), 16 (68h, +10), 17 (53h, +10), 18 (10h, +20).

**Tertangkap hanya karena umur domain:** 08, 12, 13, 16 (4 situs). Tanpa RDAP keempatnya < 30.

Host bersama yang di-lookup sebagai apex platform (tidak berguna): `pages.dev` 2247h, `vercel.app` 2465h, `blogspot.com` 9584h, `sites.google.com`/`google.com` 10634h, `cloudfront.net` 6759h, `edgeone.dev` 505h. `github.io` → `null`.

### Script vs baca kode

Hasil `run.mjs` sama dengan pembacaan `forms.js` / `content.js` / `signals.js`. Tidak ada selisih.

`asks_cvv` tidak muncul bersamaan `asks_card` (aturan #60) — tidak teruji, tidak ada field kartu.

## 7. Situs legit yang meminta data

Ambil 28 Okt 2026. L02–L05, L09, L10 = ganti URL mati. `isOfficialHost` semua `false`. Tidak submit.

| id | host | kategori | yang diminta (field persis) | kode perilaku | skor L3 | kena? |
|---|---|---|---|---|---:|---|
| L01 | sso.undip.ac.id | login kampus | text `identity` ph=`NIM/NIP/username/e-mail official Undip`; hidden `csrf_sso` | LAIN_USERNAME, LAIN_EMAIL | 0 | tidak |
| L02 | www.sekolah.mu | sekolah | `namaLengkap`; `namaInstitusi`; `emailInstitusi`; `noWhatsapp`; `posisi` | LAIN_NAMA, LAIN_EMAIL, LAIN_HP, LAIN_PEKERJAAN | 0 | tidak |
| L03 | pendaftaran.undip.ac.id | PMB kampus | JS: email + password (chunk `login.*.js`) | PASSWORD, LAIN_EMAIL | 15 | tidak |
| L04 | admissions.ugm.ac.id | PMB landing | search `s` saja | — | 0 | tidak |
| L05 | cottonink.co.id | toko | `customer[first_name]`; `customer[last_name]`; `customer[email]`; `customer[password]` | PASSWORD, LAIN_NAMA, LAIN_EMAIL | 15 | tidak |
| L06 | www.loket.com | event | tidak ada form (`terbuka-kosong`) | LAIN_TANPA_FORM | 0 | tidak |
| L07 | kredivo.id | pinjol OJK | checkbox bahasa; Daftar = app | LAIN_TANPA_FORM | 0 | tidak |
| L08 | www.adakami.id | pinjol OJK | form dialog kosong; daftar di app | LAIN_TANPA_FORM | 0 | tidak |
| L09 | oss.go.id | pemda/izin | text ph=`Masukkan NIB` | — (NIB ≠ NIK) | 0 | tidak |
| L10 | wargaklampid-dispendukcapil.surabaya.go.id | dukcapil | label `Username`; `type=password` label `Password` | PASSWORD, LAIN_USERNAME | 15 | tidak |

**0 dari 6** halaman legit yang meminta data kena L3 (≥30). Tiga dapat `asks_password` 15 (L03, L05, L10) lalu **lolos** threshold.

Banding kode:

| kode | di scam | di legit | pembeda? |
|---|---|---|---|
| OTP / PIN / KTP / CVV / kartu / selfie | ya | tidak terlihat | **pembeda bagus** |
| BRAND_TIRUAN | 7 scam | tidak | **pembeda bagus** |
| URGENT | 25 | tidak | **pembeda bagus** |
| LAIN_KIRIM_KE_CHAT (bot Telegram) | 18 scam | tidak | **pembeda bagus** |
| PASSWORD | 13 scam | L03, L05, L10 | **tidak membedakan** — toko, PMB, dukcapil sah juga `type=password`. Bobot 15 < 30 jadi belum salah-tangkap |
| LAIN_USERNAME / LAIN_EMAIL / LAIN_NAMA / LAIN_HP | scam | L01, L02, L05, L10 | **tidak membedakan** |
| `new_domain` | 11 scam muda | 0 (semua >90 hari) | **pembeda bagus** pada sampel ini |
| LAIN_TANPA_FORM | 11 | L06–L08 | tidak membedakan |

NIB (L09) tidak memicu `asks_ktp` (`nik`/`ktp` whole word). Login dukcapil (L10) label `Username`, bukan `NIK` — `asks_ktp` diam. Form PPDB/NIK publik **masih belum ketemu**.

RDAP legit semua tua (2626–11430 hari) → tidak ada `new_domain`.

iPhone vs desktop pengganti: ukuran sama (cottonink 134141, sekolah.mu 94423, klampid 11290, undip 3761). OSS selisih ~1 KB, bukan cloaking.

## 8. Usulan (belum diterapkan)

Jangan diubah di `ai/src/` sampai Umar setuju.

| usulan | situs scam tertolong | risiko legit |
|---|---|---|
| Tambah keyword OTP: `kode pendaftaran`, `kode otp`, dan/atau class/heading `otp` dekat kotak digit | 05, 14, 15 (3 situs, sekarang 0–12) | PPDB/sekolah (L02–L04, L10) gagal dibuka — risiko FP **belum terukur** |
| Naikkan `asks_password` di atas 15 | scam 20/22 tetap 15 | **jangan** — L05 toko + L10 dukcapil + L03 PMB sudah 15. Naik ke 30 = salah-tangkap 3 legit |
| Naikkan `asks_otp` 25→30, atau gate OTP+brand/host-baru | 10, 19 (sekarang 25) | toko/PMB/dukcapil di sampel ini **tidak** minta OTP; risiko FP OTP masih belum terukur di PPDB |
| Kata aksi title longgar: brand di title saja, atau tambah `otp`/`pin` sebagai kata aksi | 19 (Shopee), 17 (myBCA), 08 (djp) | blog "cara cek OTP BCA" bisa false brand; rule sekarang sengaja ketat |
| Tambah brand Agoda, DHL | 09 sudah kena PIN; 10 dan 22 dapat brand | rendah jika domain resmi masuk `brands.json` |
| Sinyal `asks_token` / masukkan `mobile token`, `token lunak`, `keybca` ke OTP atau PIN | 01–03 sudah kena dari password+brand; menambah ketahanan jika logo dihapus | rendah di non-bank; jangan samakan dengan "token" CSRF |
| Sinyal kirim ke `api.telegram.org` | 18 situs scam | form UMKM yang "hubungi admin Telegram" — bedakan embed bot vs tautan `t.me` |
| `autocomplete=one-time-code` → `asks_otp` | 17 sudah kena dari id; berguna untuk 05 jika ditambah | rendah; ini sinyal iPhone asli |

Draf pertanyaan GitHub issue (template Question / proposal, label `question`, assign @umarmuhdhor). **Tidak dibuat.**

1. Bolehkah keyword OTP ditambah (`kode pendaftaran`, `mobile token`, `token lunak`, `keybca`) tanpa id sinyal baru?
2. OTP sendirian 25 tidak mencapai popup 30. Naikkan bobot, atau biarkan layer 2 (`suspicious_link`) yang menutupi host gratis?
3. Title brand tanpa kata aksi: longgarkan, atau tetap ketat (hindari blog "cara cek saldo BCA")?
4. Tambah Agoda dan DHL ke `brands.json`?
5. Apakah embed `api.telegram.org/sendMessage` boleh jadi sinyal L3, atau itu perubahan kontrak?

Sampai dijawab: tidak mengubah rule. Eval ini jadi bukti angka.

## 9. Perbedaan perangkat (iPhone vs desktop)

| id | host | iPhone | desktop | dugaan |
|---|---|---|---|---|
| 11 | deddydanchika.blogspot.com | 200 `?m=1`, title "Video Mesum Deddy Dan Chika", tanpa form, "Tidak ada postingan." | 200, title "Masuk Facebook", form email+password ke `pixub.com` | cloaking per UA, atau blog menampilkan halaman lain ke desktop |

Selain itu: tidak ada yang berbeda isinya. 23–25 iPhone 302 ke `?m=1` lalu isi sama. 06 selisih 575 byte (bootstrap Google Sites), form sama. 01–05, 07–10, 12–22 ukuran iPhone = desktop. Legit L01/L06/L07/L08 iPhone = desktop.

## 10. Keterbatasan

Sampel 25 scam + 10 legit, bukan kesimpulan statistik. Situs berubah cepat. Hanya halaman pertama. 6 URL legit awal mati; diganti (L02–L05, L09, L10). PPDB pemda tetap tidak terbuka. Pinjol/event hanya landing. Form NIK/KTP publik tidak ketemu — L10 dukcapil minta Username+Password, bukan NIK.

Wajib:

(a) `curl` tidak menjalankan JavaScript. Form yang dibangun JS bisa terlewat. Extension di Safari iPhone membaca halaman setelah JS jalan. Id 06 adalah contoh: form PIN hanya di embed ter-escape / JS.

(b) Cloaking per jaringan/negara tidak diuji dari sini. Situs yang tampak jinak mungkin tetap phishing di iPhone korban di Indonesia.

(c) Skor dihitung dengan `analyzeSnapshot` lokal, bukan server sungguhan.

(d) Ini **hanya layer 3**: `localSignals` kosong, bobot kata versi quiet. Di extension, layer 2 ≥ 10 menaikkan ke penuh. Skor L1/L2/L4 dijumlah di tahap lain.

(e) Teks snapshot perkiraan dari HTML, bukan `innerText` Safari.

Perlu dicek manual di iPhone: **11**, **06**, **15**, **08**, **L03** (PMB Undip JS), **L06** (Loket JS).
