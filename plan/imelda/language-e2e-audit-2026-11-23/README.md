# Audit bahasa + E2E Shoo iOS — 23 Nov 2026

Audit ini mencakup dua hal untuk app Shoo dan Safari Web Extension-nya:
1. Teks Bahasa Indonesia dan Inggris.
2. Uji end-to-end di iOS Simulator.

Kode yang diaudit: `origin/main` @ `265063f4`, build Release untuk simulator. Audit dikerjakan Claude atas permintaan Imelda. **Kode app tidak diubah.** Semua perbaikan di log ini berupa saran.

| File | Isi |
|---|---|
| [temuan-bahasa.md](temuan-bahasa.md) | Tabel temuan: 47 Bahasa Indonesia + 13 Bahasa Inggris. Tiap baris berisi layar, teks, masalah, saran, tingkat, dan file:baris. |
| [goldfish-review.md](goldfish-review.md) | Hasil reviewer berkonteks segar dengan persona user awam dan lansia (19 temuan gabungan). |
| [egm/](egm/) | File persona yang dipakai reviewer goldfish. |
| [screenshots/](screenshots/) | 43 screenshot E2E. Indeksnya ada [di bawah](#daftar-screenshot). |

## Ringkasan

### 5 temuan teratas

1. **Bahasa ekstensi tidak ikut pengaturan app.**
   - Profil › Bahasa bilang "Peringatan di Safari dan notifikasi ikut memakai bahasa ini".
   - Kenyataannya, ekstensi selalu Bahasa Indonesia. Tidak ada `_locales/en`, dan kodenya memakai `const lang = "id"`.
   - Bukti: app diset English, tapi layar blokir tetap Bahasa Indonesia ([39](screenshots/39-block-screen-app-english-tetap-id.jpg)).
   - Detail di ID-01. Tingkat: **tinggi**.
2. **Satu tingkat bahaya punya banyak nama.**
   - Untuk skor 72, situs disebut "Situs Mencurigakan!", "Risiko Tinggi", "Bahaya", dan "Waspada".
   - Formatnya juga berganti-ganti antara "72/100" dan "72%".
   - Reviewer membaca "100/100" sebagai nilai sempurna, bukan bahaya maksimal.
   - Detail di ID-02 dan ID-11. Tingkat: **tinggi**.
3. **"Guardian" tidak dijelaskan, dan dipakai untuk dua pihak.**
   - Kata yang sama dipakai untuk anak ("Guardian-mu") dan untuk orang tua sendiri ("Menjadi Guardian").
   - Satu kartu diberi empat label: "JADI GUARDIAN", "MODE GUARDIAN", "Menjadi Guardian", dan "Pengguna pengawas".
   - Persona lansia menandainya 🔴.
   - Detail di ID-03 s.d. ID-05. Tingkat: **tinggi**.
4. **Onboarding bilang "berhasil" padahal belum.**
   - Cek Safari gagal tanpa penjelasan, lalu layar berikutnya menulis "Yeay, kamu berhasil lebih terlindungi!" ([19](screenshots/19-onboarding-safari-check-gagal.jpg) → [20](screenshots/20-onboarding-yeay-terlindungi.jpg)).
   - App juga menulis "Kamu Terlindungi!" saat izin "All Websites" untuk ekstensi masih "Ask". Dalam keadaan itu Shoo belum memeriksa situs apa pun ([30](screenshots/30-ekstensi-masih-ask-tapi-app-bilang-terlindungi.jpg)).
   - Detail di ID-17 dan bagian E2E. Tingkat: **tinggi**.
5. **Istilah tidak konsisten di alur utama.**
   - Kata kerja dan status: Aktifkan/Nyalakan, Aktif/Nyala/menyala, Mati/Tidak aktif (ID-06).
   - Kata benda: password/kata sandi (ID-07), link/tautan (ID-08), situs/web/website (ID-09).
   - Gambar contoh di langkah ekstensi berbahasa Inggris dan bertuliskan "Smart ad blocking for a cleaner web", sehingga Shoo terkesan seperti pemblokir iklan ([05](screenshots/05-onboarding-step-next.jpg)).
   - Tingkat: **sedang**.

### Kenapa ekstensi tidak ikut bahasa app

Ini bukan bug kode. Penyebabnya adalah keputusan produk yang teks app-nya tidak ikut diperbarui.

| Tanggal | Apa yang terjadi | Bukti |
|---|---|---|
| 21 Okt 2026 | Kontrak menetapkan ekstensi mengikuti **bahasa iPhone**, bukan bahasa app. App Group tidak punya key bahasa. | `contracts/app-group-keys.md` "Language" (commit `168611a6`) |
| 28 Okt 2026 | Profil › Bahasa mendapat catatan "Warnings in Safari and notifications use this language too." Catatan ini **sudah tidak akurat sejak awal**, karena ekstensi mengikuti bahasa iPhone, bukan app. | `ios/ShooApp/Features/Profile/ProfilePages.swift:1234` (commit `234501f2`) |
| 18 Nov 2026 | PM memutuskan ekstensi selalu Bahasa Indonesia. `_locales/en` dihapus, `default_locale: "id"`, dan JS memakai `const lang = "id"`. Ekstensi tidak punya pengaturan bahasa, sedangkan Safari memilih `_locales` dari bahasa iPhone. Satu-satunya cara agar selalu Bahasa Indonesia adalah hanya mengirim `id`. | commit `5d484e8e`, kontrak diperbarui |
| sekarang | Catatan di Profil tidak diubah, jadi masih menjanjikan "Peringatan di Safari … ikut memakai bahasa ini". Bagian notifikasinya **benar**, karena push memakai `devices.language` dari app. | ID-01 |

**Yang perlu dilakukan** (pilih satu):

- **A. Ikuti keputusan PM.** Disarankan. Sekitar 15 menit, oleh Team App (Alief).
  1. Ganti catatan di `ProfilePages.swift:1234` dan key-nya di `Localizable.xcstrings:6576`.
     - ID: "Notifikasi ikut memakai bahasa ini. Peringatan di Safari selalu dalam Bahasa Indonesia."
     - EN: "Notifications use this language too. Warnings in Safari are always in Bahasa Indonesia."
  2. Hapus key lama yang `stale` ("Shoo and its alerts use this language.").
- **B. Ekstensi ikut bahasa app.** Sekitar 1 hari kerja. Butuh keputusan PM dan pengerjaan Lead.
  1. PM membatalkan keputusan 18 Nov.
  2. Lead menambah key `app.language` di kontrak App Group. App menulis key ini saat bahasa diganti, dan `getSession` mengembalikan `language`.
  3. Ekstensi memuat teks EN/ID sendiri, misalnya `strings.js` berisi `{ id: {...}, en: {...} }`. `browser.i18n` tidak bisa dipakai karena selalu mengikuti bahasa iPhone. `popup.js`, `pill.js`, `marks.js`, dan `blocked-page.js` memilih bahasa dari sesi, dengan fallback `id`. Label sinyal memakai `label[lang]`, yang sudah tersedia dalam dua bahasa.
  4. Ulangi di `chrome/` dan ubah tes `manifest.test.mjs`. Tes ini sekarang memastikan hanya locale `id` yang dikirim.

Jalur A sudah cukup untuk menghapus klaim yang salah. Jalur B hanya perlu jika tim ingin user berbahasa Inggris melihat peringatan dalam bahasa Inggris. Keduanya diajukan lewat GitHub issue (aturan 7):
- A ke Alief.
- B ke Umar dan PM.

### Lainnya

- **Pairing berhasil, tapi ada satu masalah keamanan wording.** Konfirmasi "Gabung dengan keluarga ini?" tidak menyebut nama Guardian, padahal ada tombol "Bukan keluarga saya" ([55](screenshots/55-17e-konfirmasi-gabung.jpg)). Lihat bagian [Pairing](#pairing-2-perangkat--berhasil-diuji-ulang-setelah-izin-diberikan). Tingkat: **tinggi**.
- **Anda vs kamu:** sudah konsisten. Semua teks untuk user di `origin/main` memakai "kamu". "Anda" hanya muncul sebagai kutipan teks halaman penipu.
- **Slide 3 onboarding** ("Jauh di mata, tetap saling menjaga.") belum ada di `main`. Slide itu masih di branch `feat/ON-01-onboarding-connected`, jadi tidak diuji.
- **Bahasa Inggris** umumnya baik. Temuan terbesarnya:
  - typo "stays **on on**" (EN-01)
  - tiga versi judul "Protect …" (EN-02)
  - push mingguan "Your week for you" (EN-04)
- **String Catalog:** 252 dari 824 key ditandai `stale`, padahal sebagian masih tampil di app (ID-30).

## Metode

### 1. Pengumpulan teks

| Sumber | Cara |
|---|---|
| `ios/ShooApp/Resources/Localizable.xcstrings` (824 key) dan `InfoPlist.xcstrings` | Di-parse dengan skrip Python menjadi tabel key / EN / ID / status. Key `stale` ikut dibaca, karena sebagian masih tampil (misalnya slide onboarding). |
| String hardcoded di SwiftUI | `grep` kata-kata Indonesia di `*.swift`, tanpa `Tests/`, `Fixtures/`, dan `MockScenarios`. Tidak ditemukan string untuk user di luar preview/mock. |
| `ios/ShooExtension/Resources/_locales/id/messages.json` dan JS UI (`popup.js`, `pill.js`, `marks.js`, `blocked-page.js`) | Dibaca langsung. Hanya ada locale `id`. |
| `ios/ShooLiveActivity/` | Folder ini tidak ada di `main`. Live Activity sudah dihapus (#555). |
| Push (`backend/api/src/services/push/messages.ts`), halaman web (`join-page.ts`, `safari-check.ts`, `privacy.ts`, `terms.ts`, `support.ts`), dan teks alasan deteksi (`detector/src/detector.js`, `ai/src/layer3/*.js`, `ai/src/layer4/reality.js`) | Dikumpulkan subagent read-only (Explore). Kutipan di tabel temuan sudah dicek ulang di file aslinya. |

Patokan penilaian:
- ejaan dan imbuhan menurut KBBI/PUEBI;
- konsistensi istilah;
- kejelasan untuk user awam dan lansia;
- kesetaraan makna EN↔ID.

### 2. Tool E2E: elephant-goldfish-model (EGM)

**Cara repo diperlakukan.** Repo EGM di-clone ke folder kosong di scratchpad, bukan di repo Shoo (commit `8b1553f5`, 22 Nov 2026). Isinya dibaca dulu sebelum apa pun dipakai. Plugin tidak diinstal, dan tidak ada kode dari repo itu yang dijalankan.

**Isi dan fungsi EGM.**
- EGM adalah plugin berbasis prompt untuk Claude Code, Codex, Antigravity, dan sejenisnya.
- Isinya skill markdown (`egm-brainstorm`, `egm-draft`, `egm-review`, `egm-review-loop`, `egm-drift-report`, dan lainnya) serta persona reviewer di `agents/*.md`.
- Satu-satunya kode Python/JS di repo itu adalah tes dan skrip rilis.
- Idenya membagi dua peran:
  - **Elephant**: agen utama yang memegang konteks proyek dan menulis spesifikasi.
  - **Goldfish**: subagent baru tanpa riwayat percakapan, yang membaca dokumen dengan "mata segar" untuk menemukan asumsi yang tidak tertulis.
- EGM tidak butuh API key, karena memakai subagent dari harness.

**Kenapa EGM tidak bisa dipakai langsung untuk E2E app iOS.**
- EGM dibuat untuk me-review **dokumen**: spesifikasi desain, README, rencana PR. EGM tidak menjalankan app.
- EGM tidak bisa menyentuh simulator, menekan tombol, atau mengambil screenshot.
- Persona bawaannya (design critic, comprehension, zoom-out, dan lainnya) ditujukan untuk engineer, bukan pengguna akhir.

**Cara EGM tetap diterapkan.**
- Polanya meniru `egm-review-loop` mode *direct dispatch*.
- "Dokumen" yang di-review adalah urutan screenshot dari E2E manual di simulator.
- Dua persona Goldfish ditulis khusus untuk audit ini: [awam](egm/persona-awam.md) dan [lansia](egm/persona-lansia.md). Strukturnya mengikuti `agents/comprehension.md` di EGM: paraphrase dulu, lalu temuan 🔴/🟡/🟢.
- Masing-masing persona dijalankan sebagai subagent baru yang read-only, tanpa akses ke kode dan tanpa riwayat percakapan.
- Hanya satu ronde. EGM biasanya mengulang review sampai dua ronde berturut-turut bersih, tapi itu tidak dilakukan karena audit ini tidak boleh mengubah teks app.
- Hasilnya ada di [goldfish-review.md](goldfish-review.md).

**Cara menjalankan ulang.**
1. Clone `https://github.com/google/elephant-goldfish-model` ke folder kosong. Tidak perlu install apa pun.
2. Ambil screenshot alur baru ke `screenshots/`.
3. Untuk tiap persona di `egm/`, jalankan subagent baru dengan prompt: "Baca persona `<path>`, read-only, buka screenshot berurutan `<daftar>`, balas sesuai format persona."
4. Gabungkan temuan kedua persona, lalu putuskan mana yang diterima dan mana yang ditolak (langkah `egm-resolve`).

### 3. Build dan lingkungan uji

- `git fetch origin main`: worktree sudah berada di `265063f4`.
- `ios/Config/Local.xcconfig` disalin dari checkout utama (file ini gitignored).
- `cd ios && xcodegen generate`.
- `xcodebuild -scheme Shoo -configuration Release -sdk iphonesimulator` → **BUILD SUCCEEDED**. Release dipilih karena Debug mematikan layer 3–4 dan public blocklist.
- Simulator: iPhone 17 Pro, iOS 26.5, bahasa iPhone English. App tetap mulai dalam Bahasa Indonesia, sesuai `AppLanguage.defaultLanguage`.
- **Situs scam uji:** halaman "BCA" palsu buatan sendiri, berisi form rekening, PIN, OTP, kartu, KTP, dan CVV.
  - Disajikan dengan `python -m http.server` di `127.0.0.1:8799`, lalu dibuka lewat `*.127.0.0.1.nip.io`.
  - Halaman ini tidak dipublikasikan.
- **Akun uji** "Bu Sri" terdaftar di backend produksi (`shoo-api…workers.dev`) sebagai Guardian. Kode undangannya 083442 dan kedaluwarsa dalam 30 menit.

## Hasil E2E per alur

### Onboarding: slide dan profil — ✅ berhasil

Screenshot [01](screenshots/01-onboarding-slide1.jpg)–[04](screenshots/04-onboarding-name-filled.jpg).

- **Yang janggal:**
  - Slide 2 versi ID terpotong di tengah kalimat, karena tidak ada `\n`.
  - Petunjuk di layar profil terasa kaku.
  - Hanya ada 2 slide, karena slide 3 belum di-merge.
- **Saran:** ID-21, ID-22, ID-19.

### Onboarding: aktifkan ekstensi — ⚠️ berhasil, tapi sulit

Screenshot [05](screenshots/05-onboarding-step-next.jpg)–[13](screenshots/13-onboarding-ekstensi-sudah-aktif.jpg).

- **Yang janggal:**
  - Gambar contoh berbahasa Inggris dan salah konteks: menyebut "content blockers" dan "ad blocking", dengan ikon tapak kaki.
  - Tombol "Aktifkan Ekstensi" membuka **halaman utama Pengaturan**, bukan Safari › Ekstensi ([08](screenshots/08-pengaturan-terbuka-di-halaman-utama.jpg)). User harus mencari sendiri: Apps › Safari › Extensions.
  - Instruksi menyebut label iOS dalam Bahasa Indonesia ("Semua Situs Web", "Izinkan", "Tanya"). iPhone uji berbahasa Inggris, jadi labelnya "All Websites", "Allow", "Ask". App selalu mulai dalam Bahasa Indonesia, apa pun bahasa iPhone-nya.
  - Tap pertama pada kotak centang setelah sheet ditutup tidak tercatat ([07](screenshots/07-onboarding-centang-pertama-tidak-masuk.jpg)).
  - "Langkah 1 dari 2" tidak pernah tampil, padahal "Langkah 2 dari 2" tampil.
- **Saran:**
  - Pakai gambar Safari › Ekstensi › Shoo yang asli, versi ID.
  - Tulis jalur lengkapnya di langkah 02.
  - Tulis label dua bahasa, misalnya "Semua Situs Web (All Websites)".
  - Tampilkan "Langkah 1 dari 2".

### Onboarding: cek ekstensi — ❌ status salah

Screenshot [11](screenshots/11-onboarding-toast-shoo-belum-menyala.jpg), [30](screenshots/30-ekstensi-masih-ask-tapi-app-bilang-terlindungi.jpg).

- **Yang janggal:**
  - App menganggap ekstensi aktif hanya dari toggle "Allow Extension".
  - Izin "All Websites" = "Ask" tidak dicek, sehingga app menulis "Kamu Terlindungi!" padahal Shoo belum berjalan di situs mana pun.
  - Setelah izin diubah ke Allow, peringatan langsung berfungsi.
- **Saran:**
  - Tampilkan "Terlindungi" hanya setelah ada heartbeat `allSites == true`.
  - Sebelum itu, tampilkan "Shoo baru aktif di sebagian situs" (string ini sudah ada).
  - Cek ulang di HP asli, karena perilaku simulator bisa berbeda.

### Onboarding: Safari default — ⚠️ gagal di simulator, tapi bisa dilewati

Screenshot [14](screenshots/14-onboarding-jadikan-safari-default.jpg)–[20](screenshots/20-onboarding-yeay-terlindungi.jpg).

- **Yang janggal:**
  - "Cek & lanjutkan" membuka `join.shoo.ai.id/safari-check` ([16](screenshots/16-halaman-safari-check-hampir-selesai.jpg)).
  - Setelah kembali ke app, spinner berputar ±20 detik, lalu muncul "Coba lagi / Masih gagal? Lanjut saja" **tanpa penjelasan** ([19](screenshots/19-onboarding-safari-check-gagal.jpg)).
  - Masalah ini terulang di iPhone 17e yang hanya punya build ini ([52](screenshots/52-17e-cek-safari-gagal-tanpa-app-lama.jpg)), jadi penyebabnya **bukan** app Shoo lama. Perlu dicek di HP asli.
  - Setelah "Lanjut saja", layar berikutnya tetap bilang "Yeay, kamu berhasil…".
- **Saran:**
  - Sebutkan apa yang gagal, misalnya "Safari belum jadi browser utama" atau "Shoo belum terdeteksi di Safari".
  - Jangan pakai kata "berhasil" setelah user melewati cek.

### Izin notifikasi — ✅ berhasil

Screenshot [21](screenshots/21-onboarding-izin-notifikasi.jpg).

- **Yang janggal:** teks menyebut "Guardian-mu" kepada user Pribadi.
- **Saran:** ID-20.

### Beranda Pribadi — ✅ berhasil

Screenshot [22](screenshots/22-beranda-pribadi.jpg), [23](screenshots/23-beranda-pribadi-empty-state.jpg).

- **Yang janggal:**
  - Teks empty state tertutup tab bar sebelum di-scroll.
  - Memakai "web", bukan "situs".
- **Saran:** beri ruang di bawah untuk tab bar. ID-09.

### Peringatan situs scam (skor 50–79) — ✅ muncul, ⚠️ wording dan layout

Screenshot [24](screenshots/24-safari-popup-situs-mencurigakan.jpg), [25](screenshots/25-safari-tanda-kolom-menimpa-label.jpg).

- **Yang janggal:**
  - Tiga istilah untuk satu tingkat bahaya.
  - Contoh port ":8080" ditulis apa adanya.
  - Label "Shoo: jangan masukkan PIN di sini" **menimpa label kolom berikutnya** ("Kode OTP").
  - Tombol "Tetap lanjutkan" sama menonjolnya dengan tombol yang aman.
- **Saran:**
  - ID-02 dan ID-28.
  - Beri jarak antara tanda dan label kolom.
  - Ubah "Tetap lanjutkan" menjadi tombol teks kecil (keputusan Lead).

### Tinggalkan halaman — ❌ membingungkan

Screenshot [27](screenshots/27-safari-tinggalkan-halaman-about-blank.jpg).

- **Yang janggal:** jika situs scam adalah halaman pertama di tab, user berakhir di layar putih `about:blank`. Kedua persona goldfish menandainya 🔴.
- **Saran:** arahkan ke halaman aman Shoo ("Kamu sudah keluar dari situs berbahaya"), atau tutup tab.

### Layar blokir (skor ≥80) — ✅ berhasil

Screenshot [31](screenshots/31-safari-layar-blokir.jpg).

- **Yang janggal:**
  - Bar skor berwarna oranye, padahal tamengnya merah.
  - "100/100" terbaca seperti nilai bagus.
  - Tombol utamanya "Tinjau di Shoo", bukan "Kembali ke halaman aman".
- **Catatan:**
  - Host `*.nip.io` diblokir di layer 1 dengan alasan "Ada di daftar umum situs penipuan", karena `nip.io` ada di public blocklist.
  - Pada kunjungan berikutnya muncul "Shoo sudah pernah memblokir situs ini di HP ini".
- **Saran:** ID-11, ID-16.

### Detail dari layar blokir — ⚠️ artefak lingkungan

- **Yang janggal:** dialog "Open in Shoo?" membuka **app Shoo lain** yang terpasang di simulator, bukan build ini.
- **Saran:** ini bukan bug produk. Ulangi di simulator bersih.

### Aktivitas — ⚠️ berhasil, tapi ada data dobel

Screenshot [33](screenshots/33-aktivitas-personal.jpg).

- **Yang janggal:**
  - Satu kunjungan muncul sebagai **dua baris identik**, dan statistik Profil ikut menjadi "2 Diblokir".
  - Lingkaran ikon kosong.
- **Saran:** Lead/Alief perlu mengecek apakah `POST /scans` terkirim dua kali.

### Detail — ✅ berhasil

Screenshot [34](screenshots/34-detail-situs-berbahaya.jpg), [35](screenshots/35-detail-alasan-terdeteksi.jpg).

- **Yang janggal:**
  - "Diakses" dipakai di sini, "Dibuka" di tempat lain.
  - Label "Penilaian Risiko Shoo" dan "Jenis tanda:".
  - "Menurutmu situs ini aman?" membuat user takut salah menekan "Aman".
  - Tombol kembali sekali tidak merespons.
- **Saran:** ID-12 dan ID-23. Tambahkan penjelasan bahwa jawaban di pertanyaan itu tidak membuka situs.

### Profil dan pengaturan — ✅ berhasil

Screenshot [36](screenshots/36-profil-pribadi.jpg)–[38](screenshots/38-profil-bahasa.jpg), [40](screenshots/40-profile-en.jpg).

- **Yang berfungsi:** ganti bahasa langsung berlaku di app.
- **Yang janggal:**
  - Klaim bahwa peringatan Safari ikut ganti bahasa itu salah ([39](screenshots/39-block-screen-app-english-tetap-id.jpg)).
  - Label "MODE GUARDIAN" tidak sama dengan "JADI GUARDIAN" di Beranda.
  - "Bagikan undangan" muncul di mode Pribadi.
- **Saran:** ID-01, ID-04.

### Jadi Guardian dan kode undangan — ✅ berhasil (sisi Guardian)

Screenshot [41](screenshots/41-become-guardian-en.jpg), [42](screenshots/42-beranda-guardian-en-kode-undangan.jpg), [44](screenshots/44-toast-guardian-mode-on-en.jpg), [46](screenshots/46-profil-guardian-id.jpg), [47](screenshots/47-beranda-guardian-id.jpg).

- **Yang berfungsi:** kode 6 angka dan QR langsung muncul, berlaku 30 menit.
- **Yang janggal:**
  - Versi EN punya tiga variasi judul "Protect …".
  - "Undang Keluarga" vs "Undang keluarga".
- **Saran:** EN-02, ID-13.

### Halaman undangan web — ✅ tampil

Screenshot [43](screenshots/43-halaman-undangan-web-en.jpg).

- **Yang janggal:**
  - Bahasa halaman mengikuti bahasa iPhone (Accept-Language), bukan bahasa app si pengundang. Karena iPhone uji berbahasa Inggris, halaman tampil dalam English.
  - Bubble Shoo menutupi judul.
  - `shoo.ai.id/j/<kode>` → 404. Link undangan yang benar memakai `join.shoo.ai.id`.
- **Saran:** ID-42, dan pertimbangkan `?lang=id` di link undangan.

### Pairing 2 perangkat — ✅ berhasil (diuji ulang setelah izin diberikan)

Perangkat: iPhone 17e sebagai "Ibu" (dilindungi, onboarding baru, Bahasa Indonesia) dan iPhone 17 Pro sebagai "Bu Sri" (Guardian). Keduanya memakai build `origin/main`, dan app Shoo lama sudah dihapus.

- **Alurnya:**
  1. Guardian menampilkan kode undangan 132 988 ([53](screenshots/53-guardian-kode-undangan-id.jpg)).
  2. Di HP Ibu: Profil › "Punya kode undangan?" › isi 6 angka ([54](screenshots/54-17e-hubungkan-ke-guardian.jpg)).
  3. Muncul konfirmasi "Gabung dengan keluarga ini?" ([55](screenshots/55-17e-konfirmasi-gabung.jpg)), lalu layar "Berhasil Terhubung dengan Bu Sri!" ([56](screenshots/56-17e-berhasil-terhubung.jpg)).
  4. Beranda Ibu menampilkan "Terhubung dengan Bu Sri" ([57](screenshots/57-17e-beranda-dilindungi.jpg)). Beranda Guardian menampilkan "Keluarga Terlindungi!" dengan "Ibu · Ekstensi aktif" ([58](screenshots/58-guardian-setelah-pairing.jpg)).
  5. Ibu membuka situs scam uji, dan halamannya diblokir 99/100 ([59](screenshots/59-17e-blokir-terkirim-ke-guardian.jpg)). Setelah Guardian menarik layar untuk refresh, muncul kartu "Keluarga Dalam Ancaman" yang berisi situs itu ([60](screenshots/60-guardian-terima-situs-berbahaya-ibu.jpg)).
- **Yang sudah baik untuk lansia:**
  - Layar blokir di HP Ibu cuma punya satu tombol ("Kembali ke halaman aman"), tanpa "Tinjau di Shoo".
  - Alasannya memakai `labelSimple` dengan bahasa awam, misalnya "Meminta PIN rahasia kamu".
- **Yang janggal:**
  - **Konfirmasi gabung tidak menyebut nama Guardian** ([55](screenshots/55-17e-konfirmasi-gabung.jpg)). Tombolnya "Bukan keluarga saya", tapi user tidak bisa tahu keluarga siapa, karena nama "Bu Sri" baru muncul *setelah* bergabung. Ini juga celah keamanan: penipu bisa mengirim kode undangannya sendiri. Saran: judul "Gabung dengan keluarga **Bu Sri**?" (string `Connected to %@` sudah ada, data nama perlu tersedia sebelum join). Tingkat: **tinggi**.
  - Di layar yang sama tertulis "**Scan** QR" di subjudul dan "**Pindai** QR" di tab ([54](screenshots/54-17e-hubungkan-ke-guardian.jpg)). Pilih "Pindai".
  - Beranda Ibu menampilkan "Kamu Terlindungi!" sekaligus tautan "**Selesaikan pengaturan**" ([57](screenshots/57-17e-beranda-dilindungi.jpg)). User jadi bertanya: sudah terlindungi atau belum? Tautan muncul karena cek Safari default dilewati.
  - Beranda Guardian **tidak memperbarui diri sendiri**. Kartu baru muncul setelah ditarik ke bawah (push tidak ada di simulator, jadi perlu dicek di HP asli).
  - Judul "Keluarga Dalam Ancaman" terlalu dramatis, dan tamengnya tetap hijau/teal (EN-10).
  - Tombol "Aman / Bahaya" di kartu **tertutup tab bar** ([60](screenshots/60-guardian-terima-situs-berbahaya-ibu.jpg)).
  - Nama ditulis kapital semua ("IBU") di kartu, padahal di tempat lain "Ibu".
  - Contoh ":8080" muncul lagi di alasan (ID-28).
- **Cek Safari default gagal juga di HP bersih** ([52](screenshots/52-17e-cek-safari-gagal-tanpa-app-lama.jpg)). Ini terjadi di iPhone 17e yang hanya punya satu app Shoo, jadi penyebabnya **bukan** app lama. Perlu dicek di HP asli. Kalau di sana juga gagal, ini bug Team App.

### Batasan uji

- **Ada app Shoo lain di simulator** (`com.shoo.app`, kemungkinan build lama) di samping build ini (`com.imeldamayanti.shoo`). Akibatnya:
  - Safari menampilkan dua ekstensi "Shoo".
  - Peringatan pertama ([24](screenshots/24-safari-popup-situs-mencurigakan.jpg), [25](screenshots/25-safari-tanda-kolom-menimpa-label.jpg)) dan layar blokir [28](screenshots/28-blokir-dari-ekstensi-lama-tombol-buka-shoo.jpg) berasal dari **ekstensi lama**.
  - Deep link `shoo://` membuka app lama.
  - Setelah ekstensi lama dimatikan, layar blokir [31](screenshots/31-safari-layar-blokir.jpg) dan [39](screenshots/39-block-screen-app-english-tetap-id.jpg) dipastikan berasal dari build ini.
  - Teks popup untuk skor 50–79 sama di `_locales` kedua build, jadi temuan wording tetap berlaku. Layout label di kolom perlu dicek ulang dengan build ini.
  - App lama tidak dihapus, karena bukan milik sesi ini.
- **Uji ulang setelah app lama dihapus (permintaan Imelda).**
  - `com.shoo.app` di-uninstall dari simulator, jadi tinggal build ini (`origin/main` @ `265063f4`; main belum bergerak).
  - Hasil uji ulang:
    - [48](screenshots/48-blokir-build-baru-layer3.jpg): halaman BCA tiruan di `*.lvh.me` diblokir 100/100 dengan alasan layer 3 "Tampilan halaman ini seperti tiruan situs lain".
    - [49](screenshots/49-blokir-form-pembayaran-polos-layer3.jpg): **halaman "Konfirmasi Pembayaran" polos** di `*.localtest.me` juga diblokir 100/100 oleh layer 3. Halaman ini tanpa merek, tanpa kalimat mendesak, hanya berisi kolom nama, PIN, OTP, dan catatan. Kemungkinan ini false positive model impersonation. Perlu dicek Team AI (`ai/src/layer3/model/impersonation.js`), lihat ID-48.
    - [50](screenshots/50-safari-peringatan-build-baru.jpg) dan [51](screenshots/51-safari-tanda-kolom-build-baru.jpg): halaman BCA di `*.localhost` (hanya layer 1–2) mendapat skor 49. Judul popup-nya "Situs Mencurigakan!", tapi kartu kecilnya "Waspada", jadi ID-02 terkonfirmasi di build ini.
  - Di skor 49, kolom tidak diberi tanda. Akibatnya, temuan "tanda menimpa label" ([25](screenshots/25-safari-tanda-kolom-menimpa-label.jpg), dari ekstensi lama) **belum bisa dibuktikan ulang** di build ini. Pembuktiannya butuh halaman dengan skor 50–79.
  - Host `*.nip.io` dan `*.sslip.io` langsung diblokir layer 1 karena ada di public blocklist. Untuk uji lokal, pakai `*.lvh.me`, `*.localtest.me`, atau `*.localhost` (yang terakhir tanpa layer 3–4).
- **Tidak ada uji di iPhone fisik**, sesuai batasan tugas.
- **Push tidak diterima**, karena simulator tidak terhubung ke APNs. Teks push diaudit dari kode.
- **Halaman privasi, ketentuan, dan bantuan** diaudit dari kode, tidak dibuka di simulator.

## Saran tindak lanjut

Semua perbaikan berada di luar `plan/imelda/`, jadi dikerjakan oleh pemilik foldernya. Ajukan lewat GitHub issue sesuai aturan 7 di `CLAUDE.md`, satu topik per issue.

1. **Lead (Umar):**
   - ekstensi tidak ikut bahasa app: tambah `_locales/en`, atau ubah teks Profil (ID-01);
   - satu istilah per tingkat skor di popup, bubble, dan app (ID-02, ID-11);
   - tujuan "Tinggalkan halaman" saat tab tidak punya riwayat, dan urutan tombol di layar blokir;
   - label di kolom form yang menimpa label halaman.
2. **Team App (Alief):**
   - status "Terlindungi" padahal izin situs masih "Ask";
   - cek Safari gagal tanpa penjelasan;
   - baris Aktivitas dobel;
   - wording di [temuan-bahasa.md](temuan-bahasa.md) bagian A1, A2, dan B;
   - sinkronisasi String Catalog (ID-30).
3. **Alasan deteksi** (ID-28, ID-29, ID-44, ID-45, ID-47, EN-12):
   - `ai/` dipegang Imelda;
   - `detector/` sekarang dipegang Lead.

## Daftar screenshot

| File | Isi |
|---|---|
| [01](screenshots/01-onboarding-slide1.jpg), [02](screenshots/02-onboarding-slide2.jpg) | Slide onboarding |
| [03](screenshots/03-onboarding-name.jpg), [04](screenshots/04-onboarding-name-filled.jpg) | Atur profil |
| [05](screenshots/05-onboarding-step-next.jpg) | Langkah Aktifkan Ekstensi (gambar berbahasa Inggris, "ad blocking") |
| [06](screenshots/06-onboarding-data-dikirim.jpg) | Sheet "Data yang dikirim" |
| [07](screenshots/07-onboarding-centang-pertama-tidak-masuk.jpg) | Tap pertama pada kotak centang tidak tercatat |
| [08](screenshots/08-pengaturan-terbuka-di-halaman-utama.jpg) | Pengaturan terbuka di halaman utama |
| [09](screenshots/09-pengaturan-dua-ekstensi-shoo.jpg), [10](screenshots/10-pengaturan-detail-ekstensi-shoo.jpg) | Pengaturan Safari: dua ekstensi, dan deskripsi ekstensi |
| [11](screenshots/11-onboarding-toast-shoo-belum-menyala.jpg) | Toast "Shoo belum menyala" |
| [12](screenshots/12-onboarding-tombol-jadi-selanjutnya.jpg), [13](screenshots/13-onboarding-ekstensi-sudah-aktif.jpg) | Ekstensi terdeteksi |
| [14](screenshots/14-onboarding-jadikan-safari-default.jpg), [15](screenshots/15-onboarding-cek-dan-lanjutkan.jpg) | Jadikan Safari default |
| [16](screenshots/16-halaman-safari-check-hampir-selesai.jpg) | Halaman web safari-check |
| [17](screenshots/17-onboarding-cek-safari-loading.jpg), [19](screenshots/19-onboarding-safari-check-gagal.jpg) | Cek Safari: loading, lalu gagal |
| [20](screenshots/20-onboarding-yeay-terlindungi.jpg) | "Yeay, kamu berhasil…" |
| [21](screenshots/21-onboarding-izin-notifikasi.jpg) | Izin notifikasi |
| [22](screenshots/22-beranda-pribadi.jpg), [23](screenshots/23-beranda-pribadi-empty-state.jpg) | Beranda Pribadi |
| [24](screenshots/24-safari-popup-situs-mencurigakan.jpg), [25](screenshots/25-safari-tanda-kolom-menimpa-label.jpg) | Popup 72/100 dan label di kolom form (ekstensi lama) |
| [27](screenshots/27-safari-tinggalkan-halaman-about-blank.jpg) | Setelah "Tinggalkan halaman" |
| [28](screenshots/28-blokir-dari-ekstensi-lama-tombol-buka-shoo.jpg) | Layar blokir dari ekstensi lama |
| [30](screenshots/30-ekstensi-masih-ask-tapi-app-bilang-terlindungi.jpg) | Izin ekstensi masih "Ask" |
| [31](screenshots/31-safari-layar-blokir.jpg) | Layar blokir (build ini) |
| [33](screenshots/33-aktivitas-personal.jpg) | Aktivitas: baris dobel |
| [34](screenshots/34-detail-situs-berbahaya.jpg), [35](screenshots/35-detail-alasan-terdeteksi.jpg) | Detail |
| [36](screenshots/36-profil-pribadi.jpg)–[38](screenshots/38-profil-bahasa.jpg) | Profil, pengaturan, bahasa |
| [39](screenshots/39-block-screen-app-english-tetap-id.jpg) | App diset English, layar blokir tetap Bahasa Indonesia |
| [40](screenshots/40-profile-en.jpg)–[42](screenshots/42-beranda-guardian-en-kode-undangan.jpg), [44](screenshots/44-toast-guardian-mode-on-en.jpg), [45](screenshots/45-profile-guardian-en.jpg) | Alur Guardian (EN) |
| [43](screenshots/43-halaman-undangan-web-en.jpg) | Halaman undangan web |
| [46](screenshots/46-profil-guardian-id.jpg), [47](screenshots/47-beranda-guardian-id.jpg) | Guardian (ID) |
| [48](screenshots/48-blokir-build-baru-layer3.jpg), [49](screenshots/49-blokir-form-pembayaran-polos-layer3.jpg) | Uji ulang tanpa app lama: blokir layer 3 (termasuk form polos) |
| [50](screenshots/50-safari-peringatan-build-baru.jpg), [51](screenshots/51-safari-tanda-kolom-build-baru.jpg) | Uji ulang: peringatan 49/100 ("Mencurigakan" vs "Waspada") |
| [52](screenshots/52-17e-cek-safari-gagal-tanpa-app-lama.jpg) | Cek Safari gagal di HP bersih |
| [53](screenshots/53-guardian-kode-undangan-id.jpg)–[56](screenshots/56-17e-berhasil-terhubung.jpg) | Pairing: kode, isi kode, konfirmasi gabung, berhasil |
| [57](screenshots/57-17e-beranda-dilindungi.jpg), [58](screenshots/58-guardian-setelah-pairing.jpg) | Beranda Ibu dan Guardian setelah pairing |
| [59](screenshots/59-17e-blokir-terkirim-ke-guardian.jpg), [60](screenshots/60-guardian-terima-situs-berbahaya-ibu.jpg) | Ibu kena blokir, Guardian menerima kartu |
