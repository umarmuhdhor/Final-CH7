# Temuan bahasa: Shoo iOS (app + Safari Web Extension)

Audit tanggal 23 Nov 2026 atas kode `origin/main` @ `265063f4`. Ringkasan dan metode ada di [README.md](README.md).

Cara membaca kolom:
- **Lokasi** memakai path dari root repo. Untuk `Localizable.xcstrings`, nomor baris menunjuk ke baris key-nya. `_locales` artinya `ios/ShooExtension/Resources/_locales/id/messages.json`.
- **Tingkat** punya tiga nilai:
  - **tinggi**: bisa membuat user salah paham soal keamanan atau salah tekan.
  - **sedang**: membingungkan atau tidak konsisten di alur utama.
  - **rendah**: ejaan, gaya, atau kerapian.
- **(stale)** artinya key ditandai `stale` di String Catalog (lihat ID-30). Key seperti ini bisa saja masih tampil di layar. Contohnya slide onboarding dan "Atur Profilmu", yang statusnya `stale` tapi muncul di app.

---

## A. Bahasa Indonesia

### A1. Istilah dan konsistensi

| # | Layar | Teks sekarang | Masalah | Saran | Tingkat | Lokasi |
|---|---|---|---|---|---|---|
| ID-01 | Profil › Bahasa | "Peringatan di Safari dan notifikasi ikut memakai bahasa ini." | **Tidak benar.** Ekstensi selalu Bahasa Indonesia (`const lang = "id"`, hanya ada `_locales/id`). Saat app diset English, layar blokir tetap Bahasa Indonesia ([39](screenshots/39-block-screen-app-english-tetap-id.jpg)). | Ubah menjadi "Notifikasi ikut memakai bahasa ini. Peringatan di Safari selalu dalam Bahasa Indonesia." Pilihan lain: tambah `_locales/en`, tapi itu keputusan Lead (lewat issue). | tinggi | `Localizable.xcstrings:6576`; `ios/ShooExtension/Resources/popup.js:90`, `pill.js:100`, `marks.js:114`, `blocked-page.js:99` |
| ID-02 | Popup Safari, kartu kecil, bubble, Aktivitas | Satu rentang skor (50–79) punya beberapa nama: judul "Situs Mencurigakan!", status kartu "Risiko Tinggi", status bubble "Bahaya", tab Aktivitas "Waspada". | Satu situs bisa terlihat seperti punya beberapa tingkat bahaya ([24](screenshots/24-safari-popup-situs-mencurigakan.jpg), [25](screenshots/25-safari-tanda-kolom-menimpa-label.jpg)). Kedua reviewer goldfish menandai ini. | Pakai satu kata per tingkat di semua tempat: 30–49 = "Waspada", 50–79 = "Mencurigakan", ≥80 = "Berbahaya/Diblokir". | tinggi | `_locales`:5, 6, 45; `Localizable.xcstrings` `detail.status.warning`, `detail.title.suspicious` |
| ID-03 | Beranda, Profil, Detail, notifikasi | "Guardian" tidak diterjemahkan dan tidak pernah dijelaskan. Huruf kapitalnya juga campur: "Guardian-mu" / "guardian keluarga". Di HP orang tua, kartu besar "Menjadi Guardian" malah mengajak mereka jadi penjaga. | Lansia tidak tahu siapa "Guardian", apakah dirinya atau anaknya (goldfish lansia #4, 🔴). | Jelaskan sekali saat pertama muncul: "Guardian (keluarga yang ikut menjagamu)". Tulis selalu dengan G besar. Untuk user yang kemungkinan dilindungi, tonjolkan "Punya kode dari keluargamu?" daripada "Menjadi Guardian". | tinggi | `Localizable.xcstrings:2603`, `:2254`, `:642` |
| ID-04 | Kartu ajakan Guardian | Kartu yang sama berlabel "JADI GUARDIAN" di Beranda dan "MODE GUARDIAN" di Profil, dengan tombol "Menjadi Guardian". | Satu kartu punya tiga sebutan, dan "jadi" vs "menjadi" beda ragam. | Label "JADI GUARDIAN" dan tombol "Jadi Guardian". | sedang | `Localizable.xcstrings:80`, `:3579`, `:2254` |
| ID-05 | Profil (status akun) | EN "Guardian user" diterjemahkan "Pengguna pengawas". | "Pengawas" bermakna supervisor atau mandor, bertentangan dengan nada "menjaga". | "Pengguna Guardian" | sedang | `Localizable.xcstrings:7428` |
| ID-06 | Seluruh app + ekstensi | Ada beberapa kata untuk satu keadaan: **Aktifkan/Nyalakan**, **Aktif/Nyala/menyala**, **Mati/Tidak aktif**. Contoh: "Aktifkan Ekstensi" di samping "Nyalakan ekstensi Shoo"; "Shoo Aktif" di samping "Shoo belum menyala". | User mengira itu langkah atau keadaan yang berbeda (goldfish awam #5). | Pakai satu pasang di semua tempat: tombol **Nyalakan/Matikan**, status **Aktif/Mati**. | sedang | `Localizable.xcstrings:6323`, `:6365`, `:1392`, `:3333`, `:3354`, `:4825`, `:8067` |
| ID-07 | Ekstensi vs app | Ekstensi memakai "password", app memakai "Kata sandi". | Bahasa campur dalam satu alur. | "kata sandi" di semua tempat. | sedang | `_locales`:9, 27, 32 |
| ID-08 | App, web, alasan detektor | **link** dan **tautan** dipakai bergantian, misalnya "Pindai melalui kode QR atau kirim dengan tautan" di samping "Salin link". | Tidak konsisten. | Pakai "link" (lebih dikenal) di semua tempat. | rendah | `Localizable.xcstrings:5148`; `detector/src/detector.js:350-354` |
| ID-09 | App | **situs**, **web**, dan **website** dipakai bergantian: "Kalau ada **web** mencurigakan", "Menurut %@ **website** ini berbahaya!" | Tidak konsisten. | "situs" | rendah | `Localizable.xcstrings:702`, `:2002`, `:2036` |
| ID-10 | Ekstensi vs app | "HP" dan "iPhone" dipakai bergantian: "di HP ini" (layar blokir) vs "iPhone ini belum terlindungi". | Tidak konsisten, tapi masih bisa dipahami. | Pilih satu, atau tetapkan aturan: "iPhone" untuk perangkat sendiri, "HP" untuk perangkat keluarga. | rendah | `_locales`:21 |
| ID-11 | Popup, blokir, Detail | Skor ditulis "72/100" di satu tempat dan "72%" di tempat lain. Judulnya juga beda: "Penilaian Risiko Shoo" / "Skor risiko". Selain itu, 100/100 tampil dengan bar oranye. | Kedua goldfish membaca "100/100" sebagai nilai sempurna (artinya bagus). | "Skor bahaya 100/100" atau "Risiko sangat tinggi". Pakai satu format, dan bar merah untuk skor ≥80. | sedang | `Localizable.xcstrings:7213`; `_locales`:35 |
| ID-12 | Detail | "Diakses hari ini" (Detail) vs "Dibuka %@" (daftar). EN "Opened by" diterjemahkan "Profil yang mengakses". | Dua kata untuk hal yang sama. "Profil yang mengakses" kaku, dan "Diakses" terdengar aneh untuk situs yang diblokir. | "Dibuka" di semua tempat, dan "Dibuka oleh". | sedang | `Localizable.xcstrings:4513`, `:7230` |
| ID-13 | Beranda, Profil, Detail | Huruf kapital tidak konsisten: "Undang Keluarga"/"Undang keluarga", "Coba Lagi"/"Coba lagi", "Lihat Semua"/"Lihat semua", "Hapus Akun"/"Hapus akun", "Kamu Menandai ini Aman". | Gaya tidak seragam. | Pakai sentence case untuk tombol dan judul: "Undang keluarga", "Coba lagi". | rendah | `Localizable.xcstrings:3755`/`:3786`, `:6303`/`:8157`, `:5234`/`:6544`, `:3012`/`:3022`, `:7179` |
| ID-14 | Onboarding ekstensi | Langkah 01 memakai "**tekan** Aktifkan Ekstensi", langkah 03 memakai "**Ketuk** Semua Situs Web". | Dua kata kerja untuk aksi yang sama. | "Ketuk" di semua tempat. | rendah | `Localizable.xcstrings:8883`, `:6065` |
| ID-15 | Keluarga | "Hanya %@ yang bisa **memutus hubunganmu**." dan "**Hubungan keluarga diputus**". | Bisa dibaca sebagai putus hubungan keluarga sungguhan. | "…memutus koneksimu di Shoo." dan "Koneksi keluarga di Shoo diputus". | sedang | `Localizable.xcstrings:7598`, `:7977` |
| ID-16 | Layar blokir | Tombol utama "Tinjau di Shoo". | "Tinjau" terlalu formal. Karena tombolnya biru, lansia akan menekannya padahal yang ia perlukan adalah kembali ke tempat aman (goldfish lansia #3). | "Lihat alasannya di Shoo". Jadikan "Kembali ke halaman aman" tombol utama (catatan UX untuk Lead). | sedang | `_locales`:18 |

### A2. Kalimat kaku, salah ejaan, atau terasa terjemahan mesin

| # | Layar | Teks sekarang | Masalah | Saran | Tingkat | Lokasi |
|---|---|---|---|---|---|---|
| ID-17 | Onboarding selesai | "Yeay, kamu berhasil lebih terlindungi!" | "Yeay" tidak baku, dan frasa "berhasil lebih terlindungi" janggal. Layar ini juga tetap muncul setelah cek Safari gagal ([19](screenshots/19-onboarding-safari-check-gagal.jpg) → [20](screenshots/20-onboarding-yeay-terlindungi.jpg)). | "Hore, Shoo siap menjagamu!" Jika user melewati cek, tampilkan "Shoo aktif di Safari. Jadikan Safari browser utama nanti dari Profil." | sedang | `Localizable.xcstrings:6722` |
| ID-18 | Onboarding ekstensi, langkah 04 | "Kembali ke aplikasi Shoo dan terima perlindungan" | Tidak ada titik di akhir, padahal langkah lain bertitik. "Terima perlindungan" terasa seperti terjemahan "get protected". | "Kembali ke Shoo. Selesai, kamu terlindungi." | sedang | `Localizable.xcstrings:792` |
| ID-19 | Atur profil | "*Nama harus terdiri dari maksimal 20 karakter" | Kaku. Aturan yang sama juga ditulis dengan dua cara lain ("1 sampai 20 karakter", "Pakai paling banyak 20 karakter."). | "Maksimal 20 huruf", dipakai di ketiga tempat. | rendah | `Localizable.xcstrings:1434`, `:1868`, `:6408` |
| ID-20 | Izin notifikasi | "Biar Shoo bisa kabari kamu saat situs berbahaya diblokir atau Guardian-mu mengingatkan." | "Biar … kabari" tidak baku. Kata "Guardian" juga muncul sebelum pernah dijelaskan. | "Supaya Shoo bisa mengabarimu saat situs berbahaya diblokir." | rendah | `Localizable.xcstrings:642` |
| ID-21 | Slide 1 | "Browsing lebih tenang, diiringi rasa aman." | Memakai kata Inggris "Browsing", dan "diiringi" terasa kaku. | "Jelajah internet lebih tenang dan aman." | rendah | `Localizable.xcstrings:2336` (stale) |
| ID-22 | Slide 2 | "Tampak asli, belum tentu aman. Biar Shoo yang cek." | Versi EN punya `\n`, versi ID tidak, sehingga baris terpotong di tengah ("aman. Biar"). | Tambahkan `\n` setelah "aman." | rendah | `Localizable.xcstrings:5126` |
| ID-23 | Detail › Alasan | "Jenis tanda: Penipuan yang sudah dikenal" | "Jenis tanda" janggal. | "Kategori: …" | rendah | `Localizable.xcstrings:5602` |
| ID-24 | Ringkasan, blokir | "Kami memblokir otomatis halaman ini." | Urutan kata janggal. | "Kami otomatis memblokir halaman ini." | rendah | `Localizable.xcstrings:8646`; `_locales`:16 |
| ID-25 | Detail (judul) | "Situs Sudah Ditandai Blokir!" | Frasa "Ditandai Blokir" janggal. | "Situs Ditandai Berbahaya!" | rendah | `Localizable.xcstrings:7162` |
| ID-26 | Tandai aman | "Bisa diubah lagi setelah Shoo belajar mingguan, %@." / "…sampai Shoo belajar mingguan." | "Belajar mingguan" tidak jelas maksudnya bagi user. | "Bisa diubah lagi mulai %@." | sedang | `Localizable.xcstrings:8307`, `:8327` |
| ID-27 | Alasan deteksi | "Akhiran murah yang sering dipakai situs penipuan" dan label "Akhiran alamat murah" | User awam tidak paham "akhiran murah". | "Alamat berakhiran .xyz/.site yang sering dipakai penipu" (sebutkan TLD-nya). | sedang | `Localizable.xcstrings:8377`, `:5629` |
| ID-28 | Popup, layar blokir | "…ada angka aneh setelah nama situs (seperti :8080)" | Contoh ":8080" selalu muncul, padahal port halaman uji adalah :8799. Kalimatnya juga teknis (kedua goldfish). | Tampilkan port yang sebenarnya atau hapus contohnya. Kalimat pertama untuk awam: "Alamat situs ini aneh dan bukan alamat resmi." | sedang | `detector/src/detector.js:345` |
| ID-29 | Alasan deteksi | "Formulir meminta PIN atau **kode sandi**" | "Kode sandi" mudah tertukar dengan "kata sandi". | "Formulir meminta PIN" | sedang | `detector/src/detector.js:535` |
| ID-30 | String Catalog | 252 dari 824 key berstatus `stale`, termasuk teks yang masih tampil (slide onboarding, "Atur Profilmu"). | Penerjemah bisa melewatkan teks ini, atau dev menghapusnya karena dikira tidak dipakai. | Buka dan build sekali di Xcode supaya status tersinkron, lalu hapus key yang benar-benar mati. | sedang | `ios/ShooApp/Resources/Localizable.xcstrings` |
| ID-31 | Sheet matikan Shoo | "Shoo mati, perlindungan berhenti. Keluarga tak lagi mendapat peringatan." | Memakai "tak" di sini, padahal di tempat lain "tidak". | "Kalau Shoo dimatikan, perlindungan berhenti dan keluargamu tidak lagi mendapat peringatan." | rendah | `Localizable.xcstrings:7758` |
| ID-32 | Keluarga | "Status Keluarga :" | Ada spasi sebelum titik dua (PUEBI). | "Status keluarga:" | rendah | `Localizable.xcstrings:3473` (stale) |
| ID-33 | Belum diterjemahkan | "Disconnect?", "Protected", "Refresh Kode", "Proteksi saya…" | Kata Inggris masih muncul di versi ID. | "Putuskan koneksi?", "Dilindungi", "Perbarui kode", "Lindungi saya dan orang terdekat" | sedang | `Localizable.xcstrings:3161`, `:4759`, `:4928`, `:4686` (stale) |
| ID-34 | Statistik | "Hari jadi guardian" | "Hari jadi" berarti ulang tahun. | "Hari sebagai Guardian" | rendah | `Localizable.xcstrings:2979` (stale) |
| ID-35 | Batas daftar | "Batas pendaftaran" | Kalimatnya belum lengkap. | "Batas pendaftaran tercapai" | rendah | `Localizable.xcstrings:270` |
| ID-36 | Kode kedaluwarsa | "Kode kedaluwarsa, minta kode baru dan coba lagi." | Tidak menyebut kepada siapa meminta kode, padahal versi EN menyebut "your guardian". | "Kodenya sudah kedaluwarsa. Minta kode baru ke Guardian-mu." | rendah | `Localizable.xcstrings:6128` |
| ID-37 | Sheet "Data yang dikirim" | Subjudul "Saat cek online menyala." | Kalimatnya menggantung. "Nama kolom formulir" dan "skor" juga teknis. Kalimat hapus akun membuat bingung data mana yang tetap disimpan (kedua goldfish). | "Ini yang dikirim saat cek online menyala." Kalimat hapus akun: "Kalau kamu hapus akun, namamu ikut terhapus. Yang tersisa hanya alamat situs penipu." | sedang | `Localizable.xcstrings:722` dan key "The address and a copy of the page are kept for 14 days…" |
| ID-38 | Pengaturan iOS › Ekstensi | Deskripsi: "Memblokir situs penipuan. Situs yang diblokir terbuka setelah dicek keluarga." | Tidak benar untuk mode Pribadi ([10](screenshots/10-pengaturan-detail-ekstensi-shoo.jpg)), dan deskripsinya hanya ada dalam Bahasa Indonesia. | "Shoo memeriksa situs yang kamu buka dan memblokir situs penipuan." | sedang | `_locales`:3 |
| ID-39 | Persetujuan onboarding | "Saya setuju halaman dicek secara online." | Tidak jelas halaman mana yang dicek. Karena tombol terkunci sampai kotak dicentang, user merasa dipaksa setuju (goldfish awam #9). | "Saya setuju Shoo mengirim isi halaman yang saya buka untuk dicek. Ketikan saya tidak dikirim." | sedang | key "I agree to pages being checked online." |

### A3. Teks backend dan detektor (dikumpulkan subagent, lalu dicek di file)

| # | Layar | Teks sekarang | Masalah | Saran | Tingkat | Lokasi |
|---|---|---|---|---|---|---|
| ID-40 | Push ke Guardian | "Perlindungan ${m} mati: Shoo tidak berjalan di Safari **sejak sehari**" | "Sejak sehari" tidak gramatikal, dan tidak ada titik di akhir. | "…selama sehari." atau "…sejak kemarin." | sedang | `backend/api/src/services/push/messages.ts:56` |
| ID-41 | Push | Push scan diakhiri titik, push keluarga ("${g} berhenti melindungimu") tidak. | Tanda baca tidak konsisten. | Semua push diakhiri titik. | rendah | `messages.ts:43-45` |
| ID-42 | Halaman undangan web | "Bergabung **ke** keluarga di Shoo"; "masukkan kode ini di app" (huruf kecil di awal); "Setelah **install**…" di samping tombol "**Unduh**". | Ragam campur. | "Bergabung dengan keluarga di Shoo"; "Masukkan kode…"; tombol "Pasang" + "Setelah memasang Shoo…" | sedang | `backend/api/src/routes/join-page.ts:52-66` |
| ID-43 | Halaman cek Safari | "Kembali ke Shoo untuk **lihat** hasilnya." Instruksi izinnya juga satu kalimat panjang penuh panah. | Kurang imbuhan, dan instruksinya sulit diikuti (goldfish awam #7). | "untuk melihat hasilnya". Pecah instruksi menjadi langkah bernomor. | rendah | `backend/api/src/routes/safari-check.ts:40-43` |
| ID-44 | Alasan kurir | "Pesan palsu paket **gagal kirim**"; "**Bilang** paketmu tertahan supaya kamu bayar…" | Kurang imbuhan dan terlalu slang. | "…paket gagal dikirim"; "Mengaku paketmu tertahan agar kamu membayar…" | sedang | `ai/src/layer3/courier.js:85-86` |
| ID-45 | Alasan alamat | "tanda **strip** (-)" | Istilah KBBI adalah "tanda hubung". | "tanda hubung (-)" | rendah | `detector/src/detector.js:340`, `:342` |
| ID-46 | Halaman bantuan | "**terlanjur**" | Bentuk baku: "telanjur". | "telanjur" | rendah | `backend/api/src/routes/support.ts:182` |
| ID-48 | Layar blokir (layer 3) | "Tampilan halaman ini seperti tiruan situs lain." muncul pada form pembayaran polos tanpa merek ([49](screenshots/49-blokir-form-pembayaran-polos-layer3.jpg)) | Kalimat ini tidak menyebut situs mana yang ditiru, jadi user tidak bisa mengeceknya sendiri. Halaman itu juga diblokir 100/100, kemungkinan karena false positive. | Kalau ada merek yang ditiru, sebutkan ("…seperti tiruan situs BCA"). Kalau tidak ada: "Halaman ini mirip halaman login palsu." Ambang model juga perlu dicek. | sedang | `ai/src/layer3/model/impersonation.js:473-474` |
| ID-47 | Alasan layer 4 | "Halaman seperti ini biasanya tidak meminta **data itu**" | Tidak jelas data apa yang dimaksud. | Sebutkan datanya, misalnya "…tidak meminta PIN". | sedang | `ai/src/layer4/reality.js:119-120` |

---

## B. Bahasa Inggris

| # | Layar | Teks sekarang | Masalah | Saran | Tingkat | Lokasi |
|---|---|---|---|---|---|---|
| EN-01 | Hapus anggota | "Shoo stays **on on** %@'s iPhone. …" | Typo: "on" ditulis dua kali. | "Shoo stays on for %@ on their iPhone. …" | sedang | `Localizable.xcstrings:8953` |
| EN-02 | Banyak layar | "Protect your loved ones" / "Protect the people close to you" / "Protect the people closest to you" | Ada tiga versi untuk judul yang sama. | Pakai satu: "Protect the people closest to you". | sedang | `Localizable.xcstrings:4717`, `:4697`, `:4707` |
| EN-03 | Kartu Guardian | "BECOME A GUARDIAN" vs "GUARDIAN MODE" untuk kartu yang sama. "family **guardian**" ditulis kecil, padahal di tempat lain "Guardian". | Tidak konsisten. | Satu label untuk kartu itu, dan selalu "Guardian" dengan G besar. | sedang | `Localizable.xcstrings:80`, `:3579`, `:2603` |
| EN-04 | Push mingguan | "Your week: no dangerous sites for **you**." / "Your week **for you and your family**: …" | Frasa "Your week for you" janggal. | "This week: no dangerous sites for you and your family." | sedang | `backend/api/src/services/push/messages.ts:73-74` |
| EN-05 | Onboarding selesai | "Yeay, you're better protected now!" | "Yeay" bukan kata bahasa Inggris. | "You're protected!" | rendah | `Localizable.xcstrings:6722` |
| EN-06 | Slide 1 | "Browse calmer, feeling safe." | Tidak gramatikal. | "Browse with peace of mind." | rendah | `Localizable.xcstrings:2336` |
| EN-07 | Detail › Alasan | "Sign:" | Ambigu: bisa dibaca sebagai tanda tangan atau perintah "sign". | "Type:" | rendah | `Localizable.xcstrings:5602` |
| EN-08 | Lepas Guardian | "%@ won't be protected by you anymore." | Kalimat pasif yang kaku. | "You'll stop protecting %@." | rendah | `Localizable.xcstrings:1537` |
| EN-09 | Label alasan | "Rushing words", "Cheap address ending" | Tidak jelas maksudnya. | "Pressure to act fast", "Cheap domain ending (like .xyz)" | rendah | `Localizable.xcstrings:5799`, `:5629` |
| EN-10 | Judul Guardian | "Family under threat" / "Family in danger" / "Under watch!" | Ada tiga variasi, dan nadanya dramatis. | Satu kalimat netral, misalnya "Your family needs a look". | rendah | `Localizable.xcstrings:872`, `:902`, `:6397` |
| EN-11 | Guardian intro | "You'll see the sites blocked or warned about on their phones." | Frasa "warned about" menggantung. | "You'll see which sites Shoo blocked or flagged on their phones." | rendah | `ios/ShooApp/Features/Onboarding/GuardianIntroView.swift` (key "Help look after the people closest to you…") |
| EN-12 | Label alasan | "the name is strung together with many dashes"; "a made-up word-and-number front part" | Kaku. | "the name has many dashes"; "a random word-and-number prefix" | rendah | `detector/src/detector.js:340-341` |
| EN-13 | Status | "You're not protected yet" / "Not fully protected yet" / "Protection off" | Ada tiga status yang mirip tanpa penjelasan bedanya. | Pakai dua saja: "Not protected" dan "Partly protected". | rendah | `Localizable.xcstrings:6871`, `:6882`, `:4825` |

**Kesetaraan makna EN↔ID.** Selain ID-36 dan ID-12, terjemahannya setara. Versi ID sedikit lebih santai, sesuai nada "kamu".

**"Anda" vs "kamu".** Semua teks user di `origin/main` (app, ekstensi, push, web) memakai "kamu". "Anda" hanya muncul di teks halaman penipu yang dikutip sebagai bukti, dan itu disengaja. Pertanyaan FAQ di `support.ts` memakai "saya", dan itu wajar.
