# Draft presentasi Shoo: apa yang kita deteksi dan gimana caranya

Draft buat poin 0 sampai 6. Isinya diambil dari kode yang aktif di `main` per 19 Nov 2026 (commit `5a62eb94`).
Tiap poin ada dua bagian: **Slide** (yang ditulis di layar) dan **Naskah** (yang diomongin).

Perkiraan waktu kalau totalnya 10 menit ada di judul tiap poin. Sesuaikan kalau durasinya beda.

---

## 0. Masalahnya apa (± 1 menit)

**Slide**
- Link scam datang lewat WhatsApp, SMS, dan media sosial: "hadiah", "undian", "bansos", "verifikasi akun BCA", "paket tertahan".
- Halamannya meniru bank atau e-wallet, lalu meminta PIN, OTP, nomor kartu, atau foto KTP.
- Korbannya sering orang tua yang nggak bisa membedakan situs asli dan palsu.

**Naskah**
> Hampir semua orang pernah dapat link "selamat, Anda menang undian" atau "akun Anda akan diblokir". Begitu diklik, halamannya mirip banget sama BCA atau DANA, terus minta PIN atau OTP. Yang paling sering kena itu orang tua kita. Shoo dibuat buat berdiri di antara link itu dan orang yang membukanya. Shoo itu ekstensi Safari di iPhone yang membaca halaman dan memberi peringatan sebelum data dimasukkan.

---

## 1. Apa yang kita deteksi (± 2 menit)

**Slide**: Shoo melihat empat hal.

1. **Alamatnya**
   - Domain tiruan brand: salah ketik (`p0stindonesia`), huruf Cyrillic yang mirip Latin (`bcа.co.id`), punycode.
   - Brand + kata umpan: `bca-verifikasi`, `kodepembatalanbybni`.
   - Kata pancingan di nama situs: `program-hadiah-...blogspot.com`, `undian-...`.
   - Link yang dibentuk aneh: alamat IP mentah, `user@` sebelum host, nama file acak, link di dalam link, hosting gratis + kata umpan.
   - Domain baru: umur di bawah 7 hari dapat bobot paling berat.
   - Sudah ada di daftar scam: daftar milik Shoo dan daftar publik Phishing.Database.
2. **Form-nya**: apa yang diminta halaman.
   - PIN, OTP, nomor kartu, CVV, NIK/KTP, selfie + KTP, password.
   - **Termasuk form yang disembunyikan.** Banyak halaman scam sudah memuat semua langkahnya di HTML dari awal, lalu menyembunyikan langkah berikutnya (misalnya form OTP) sampai korban klik "lanjut". Shoo membaca semua kolom, kelihatan atau nggak.
   - Kolom yang nggak dibungkus `<form>` sama sekali (halaman yang dibangun pakai `div` + JavaScript).
   - Form di dalam iframe dari situs yang sama.
3. **Isi teksnya**
   - Bahasa ancaman atau tenggat waktu: "akun Anda akan diblokir dalam 24 jam", "klaim sekarang", "terakhir hari ini".
   - Logo atau nama brand di situs yang bukan milik brand itu.
   - Form login Microsoft yang disalin (nama kolomnya sama persis dengan aslinya).
4. **Halaman yang berubah setelah dibuka**: form login yang baru muncul belakangan, langkah kedua yang tadinya disembunyikan, atau situs yang ganti alamat tanpa reload.

**Naskah**
> Yang kita deteksi bukan cuma "situs ini ada di daftar hitam atau nggak". Kita lihat empat hal.
>
> Pertama alamatnya. Penipu suka bikin domain yang mirip: huruf o diganti nol, atau huruf a diganti huruf Cyrillic yang bentuknya sama persis di layar. Ada juga yang terang-terangan: `bca-verifikasi`, atau blogspot dengan nama `program-hadiah`.
>
> Kedua, form-nya: halaman itu minta apa. Situs berita nggak punya alasan buat minta PIN atau foto selfie sambil pegang KTP.
>
> Nah, ini yang menarik: banyak halaman scam yang **menyembunyikan form-nya**. Halaman pertama cuma minta nomor HP. Form OTP dan PIN-nya sebenarnya udah ada di halaman dari awal, cuma disembunyikan, dan baru dimunculkan setelah korban klik "lanjut". Scanner yang cuma melihat tampilan di layar bakal bilang halaman itu aman. Shoo membaca semua kolom di halaman, termasuk yang tersembunyi, kolom yang nggak pakai tag form, dan form di dalam iframe.
>
> Ketiga, isi teksnya: kalimat yang menekan kayak "akun diblokir dalam 24 jam", atau logo bank di situs yang bukan punya bank itu.
>
> Keempat, halaman yang berubah. Kalau ada form baru yang muncul, Shoo mengecek ulang, jadi skornya bisa naik saat itu juga.

---

## 2. Gimana cara deteksinya (± 3 menit)

**Slide**: 5 lapis. Tiap lapis menambah skor 0 sampai 100.

| Lapis | Jalan di | Yang dicek | Contoh bobot |
|---|---|---|---|
| 1. Daftar scam | iPhone | Domain ada di daftar Shoo atau daftar publik (± 14 MB, disimpan di HP) | ketemu = langsung 100 |
| 2. Alamat & link | iPhone | Tiruan brand, bedah URL, cek form versi offline | tiruan huruf 25 · brand + umpan 14 · link aneh 10 sampai 100 |
| 3. Aturan + model | Server | Aturan form & teks, umur domain (RDAP), model machine learning peniru brand | PIN 35 · OTP 30 · KTP 30 · domain < 7 hari 30 · model 40 (warn) / 80 (block) |
| 4. Cek nalar (LLM) | Server | "Wajar nggak halaman jenis ini minta data ini?" | ditambah sampai total minimal 80 |
| 5. Guardian & admin | App + backend | Keluarga atau admin menandai situs aman / tidak aman | aman = 0 · tidak aman = 100 |

**Naskah**

> Cara kerjanya berlapis, dari yang paling murah dan cepat sampai yang paling mahal.
>
> **Lapis 1 dan 2 jalan di iPhone.** Daftar situs scam kita simpan di HP, sekitar 14 MB, dan diperbarui tiap jam (daftar Shoo) dan tiap 6 jam (daftar publik). Jadi waktu ngecek, alamat yang dibuka **nggak dikirim ke mana pun**. Kalau ketemu, langsung skor 100 dan diblok.
>
> Lapis 2 membedah alamat. Ada 25 brand yang kita kenal, misalnya BCA, BRI, DANA, dan Pos Indonesia. Kita cek apakah alamatnya meniru salah satunya, termasuk huruf Cyrillic yang menyamar. Terus seluruh URL dibedah per bagian: pakai alamat IP mentah, ada `@` buat menyembunyikan host, nama file acak, atau hosting gratis dengan kata kayak "pengembalian" dan "pembatalan". Tiap bagian punya skor dan semuanya dijumlah.
>
> Lapis 2 juga punya cek form versi kecil buat jaga-jaga kalau HP lagi offline. Tapi cek ini cuma jalan kalau alamatnya udah mencurigakan, biar halaman checkout yang sah nggak ikut kena.
>
> **Lapis 3 di server.** Yang dikirim ke sini cuma bentuk halaman: judul, teks yang kelihatan, nama kolom form, dan teks alt gambar. Isi ketikan user nggak pernah dikirim. Di sini ada tiga hal:
> 1. Aturan kata kunci buat form dan teks, dalam bahasa Indonesia dan Inggris. Teksnya dinormalkan dulu: karakter tak terlihat dibuang dan huruf Cyrillic dikembalikan ke Latin, jadi trik "huruf menyamar" nggak lolos.
> 2. Umur domain lewat RDAP. Yang dikirim ke RDAP cuma nama domainnya.
> 3. **Model machine learning** yang dilatih buat mengenali halaman peniru brand. Modelnya ringan (TF-IDF + logistic regression + gradient boosting), jalan di server tanpa GPU. Ditambah aturan tegas: kalau situs meniru brand **dan** minta login, PIN, OTP, atau kartu, langsung diblok.
>
> **Lapis 4 itu LLM**, dan cuma dipanggil buat kasus abu-abu, yaitu skor 30 sampai 79. Di bawah 30 jelas aman, di atas 80 jelas diblok, jadi nggak perlu buang biaya. LLM-nya ditanya satu hal: "halaman jenis ini wajar nggak minta data ini?" Contohnya, situs promo yang minta PIN ATM itu nggak wajar. LLM nggak pernah melihat teks halaman atau alamat lengkapnya, cuma nama domain, judul, label kolom, dan nama brand. LLM juga cuma bisa **menambah** skor, nggak pernah menurunkan.
>
> **Lapis 5 itu manusia.** Guardian (keluarga) atau admin bisa menandai situs aman atau tidak aman. Keputusan manusia selalu menang dari skor mesin.

**Slide tambahan (opsional): kenapa form tersembunyi tetap ketahuan**
- Shoo membaca **semua kolom di DOM**, bukan cuma yang kelihatan di layar.
- Shoo mengawasi perubahan halaman (`MutationObserver`): kalau sebuah langkah dimunculkan lewat `style`, `class`, `hidden`, atau `open`, halaman dicek ulang.
- Cek ulang jalan setelah halaman diam 1,5 detik, paling sering sekali tiap 8 detik, maksimal 6 kali per halaman. Skornya cuma bisa naik.
- Halaman nggak bisa mengakali pembacanya: trik kayak `<form name="querySelectorAll">` yang bisa bikin scanner crash sudah ditangani, dan peringatan Shoo nggak bisa disembunyikan oleh halaman.

---

## 3. Habis terdeteksi, terus apa (± 1,5 menit)

**Slide**

| Skor | Yang terjadi |
|---|---|
| 0–29 | Nggak ada apa-apa. Browsing jalan normal. |
| 30–49 | Peringatan pertama muncul. Kalimat yang mencurigakan di-highlight. |
| 50–79 | Peringatan kedua. Kolom PIN/OTP/kartu/KTP/password dicoret dengan tulisan "jangan masukkan PIN di sini". |
| 80–100 | Halaman diblok, diganti layar blokir. |

**Naskah**
> Hasil semua lapis jadi satu skor 0 sampai 100. Di bawah 30 user nggak diganggu sama sekali. Dari 30 muncul peringatan dan kalimat yang mencurigakan di-highlight. Kalau user tap highlight-nya, muncul alasan singkat kenapa kalimat itu ditandai. Dari 50, kolom sensitif dicoret, tapi masih bisa diisi, karena keputusannya tetap di tangan user. Dari 80, halaman diblok.
>
> Skornya naik bertahap. Lapis di HP selesai duluan, jadi peringatan bisa muncul sebelum server menjawab. Situs yang pernah diblok diingat di HP selama 14 hari, jadi waktu dibuka lagi langsung ke layar blokir tanpa dicek ulang.

---

## 4. Privasi (± 1 menit)

**Slide**
- Isi ketikan user **nggak pernah** keluar dari HP. Kolom chat atau email yang lagi diketik juga dilewati.
- Cek daftar scam jalan di HP. Alamat yang dibuka nggak dikirim.
- Halaman dengan skor di bawah 30 nggak pernah sampai ke backend.
- Server menganalisis halaman tanpa menyimpannya.
- RDAP cuma menerima nama domain. LLM nggak melihat teks halaman atau alamat lengkap. Email dan deretan angka disamarkan dulu.
- Yang disimpan cuma halaman dengan skor ≥ 30, sebagai bukti buat Guardian, selama 14 hari, dan tanpa isi ketikan.

**Naskah**
> Aplikasi yang membaca semua halaman yang kita buka itu sensitif, jadi privasi kita desain dari awal. Yang paling penting: apa yang user ketik nggak pernah keluar dari HP. Browsing biasa yang skornya di bawah 30 juga nggak pernah sampai ke server kita. Yang disimpan cuma halaman yang memang mencurigakan, buat jadi bukti ke Guardian, dan dihapus setelah 14 hari.

---

## 5. Fitur keluarga / Guardian (± 1 menit)

**Slide**
- Protected (orang tua) dan Guardian (anak/keluarga) dipasangkan di app.
- Kalau halaman kena skor ≥ 30, Guardian dapat notifikasi beserta salinan halamannya.
- Guardian memutuskan: **Aman** (peringatan hilang) atau **Tidak aman** (diblok).
- Kalau peringatan masih terbuka, keputusan Guardian langsung berlaku di HP Protected tanpa perlu reload.
- Protected nggak bisa menghapus tanda peringatan. Guardian bisa.

**Naskah**
> Mesin bisa salah, makanya ada Guardian. Waktu orang tua membuka halaman yang mencurigakan, anaknya dapat notifikasi dan bisa lihat salinan halamannya. Kalau anaknya bilang "ini aman", peringatannya hilang. Kalau dia bilang "ini penipuan", halamannya langsung diblok di HP orang tua, bahkan kalau halamannya masih terbuka. Di popup, orang tua juga lihat tulisan "link sudah dikirim ke [nama Guardian]", jadi mereka tahu ada yang bantu mengecek.

---

## 6. Akurasi (± 1 menit)

**Slide**: uji di halaman phishing Indonesia yang baru dan belum pernah dilihat model (856 halaman).

| Versi | Scam tertangkap | Salah tanda di situs sah |
|---|---|---|
| Aturan kata kunci saja | 2% | 0,2% |
| + model ML + umur domain | ± 67 sampai 69% | 0,25% (data global), 1,5% (situs Indonesia) |
| + aturan alamat (brand & kata pancingan di nama situs) | **87,6%** | 0,3% (44 dari 17.410), situs Indonesia ± 1,5% (12 dari 805) |

Catatan jujur:
- Data scam segar didominasi kit blogspot "hadiah" dan "undian", jadi angka 87,6% kemungkinan terlalu optimis untuk jenis scam lain.
- Phishing global berbahasa Inggris baru 19,2%. Fokus kita sekarang bahasa Indonesia.
- Situs kecil yang sah di hosting gratis (vercel, netlify, sites.google.com) kadang ikut ditandai. Ini celah terbesar yang tersisa.
- Angka di atas cuma lapis 3. Lapis 1, 2, 4, dan 5 bekerja di atasnya.

**Naskah**
> Kita ukur di 856 halaman phishing Indonesia yang baru dan belum pernah dilihat model. Aturan kata kunci saja cuma menangkap 2%. Setelah ditambah model machine learning dan umur domain, naik ke sekitar 69%. Dengan aturan alamat yang terbaru, jadi 87,6%. Salah tandanya tetap rendah: 44 dari 17.410 halaman sah.
>
> Kita juga mau jujur soal batasannya. Data scam kita banyak berisi jenis "hadiah" di blogspot, jadi buat jenis scam lain angkanya kemungkinan lebih rendah. Situs kecil yang sah di hosting gratis kadang masih ikut ditandai. Karena itu ada lapis Guardian: kalau mesinnya salah, keluarga bisa membetulkan.

---

## Cek dulu sebelum presentasi

- [ ] Durasi dan audiens: kalau audiensnya non-teknis, slide tambahan di poin 2 dan nama model di lapis 3 bisa dibuang.
- [ ] Angka di poin 6 diambil dari `ai/test-layer3/v7-.../HASIL-AKHIR-tanpa-LLM.md` dan `v9-2026-11-18-alamat-login-block/HASIL.md`. Konfirmasi ke Imelda kalau ada angka yang lebih baru.
- [ ] Siapin contoh nyata buat poin 1, misalnya screenshot halaman scam yang form OTP-nya tersembunyi lalu ketahuan.
