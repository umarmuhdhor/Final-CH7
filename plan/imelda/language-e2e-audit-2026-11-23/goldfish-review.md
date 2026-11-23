# Review "Goldfish": user awam dan lansia

Ada dua reviewer dengan konteks segar: subagent baru, tanpa riwayat percakapan, tanpa akses ke kode. Keduanya membaca screenshot E2E secara berurutan.

- Persona: [egm/persona-awam.md](egm/persona-awam.md) dan [egm/persona-lansia.md](egm/persona-lansia.md).
- Pola: `egm-review-loop` dari elephant-goldfish-model, mode *direct dispatch*, satu ronde (lihat [README.md](README.md#metode)).

## Paraphrase

**Awam.** Paham Shoo dengan benar: "penjaga iPhone yang memeriksa situs di Safari, memberi peringatan, dan memblokir situs penipuan". Alur onboarding juga tertangkap: avatar, ekstensi, Safari utama, notifikasi.

Yang tidak bisa dijelaskan:
- layar putih setelah "Tinggalkan halaman";
- arti "gagal" pada cek Safari.

**Lansia.** Menganggap Shoo sebagai "satpam iPhone". Di layar ekstensi dan "Safari default" hanya menekan tombol biru tanpa paham. Layar oranye dikenali sebagai tanda bahaya.

Yang membingungkan:
- apakah sudah aman setelah layar berubah putih;
- siapa "Guardian": dirinya sendiri atau anaknya.

## Temuan gabungan

Tanda ✓ berarti reviewer itu juga menemukan masalah yang sama.

| # | Tingkat | Screenshot | Temuan | Awam | Lansia |
|---|---|---|---|---|---|
| G-01 | 🔴 | [27](screenshots/27-safari-tinggalkan-halaman-about-blank.jpg) | Setelah "Tinggalkan halaman", muncul layar putih `about:blank` tanpa keterangan. User tidak tahu sudah aman atau belum, dan bisa menekan "kembali" lagi. | ✓ | ✓ |
| G-02 | 🔴 | [19](screenshots/19-onboarding-safari-check-gagal.jpg) → [20](screenshots/20-onboarding-yeay-terlindungi.jpg) | Cek Safari gagal tanpa penjelasan. Setelah "Lanjut saja", layar berikutnya malah bilang "berhasil". | ✓ | ✓ |
| G-03 | 🔴 | [24](screenshots/24-safari-popup-situs-mencurigakan.jpg) | "Tetap lanjutkan" sama besarnya dengan "Tinggalkan halaman", dan akibatnya tidak dijelaskan. | | ✓ |
| G-04 | 🔴 | [31](screenshots/31-safari-layar-blokir.jpg) | Di layar blokir, tombol biru utamanya "Tinjau di Shoo". Lansia akan menekan itu, bukan "Kembali ke halaman aman". | | ✓ |
| G-05 | 🔴 | [21](screenshots/21-onboarding-izin-notifikasi.jpg), [22](screenshots/22-beranda-pribadi.jpg), [36](screenshots/36-profil-pribadi.jpg) | "Guardian" tidak dijelaskan, dan dipakai untuk dua pihak: anak ("Guardian-mu") dan orang tua sendiri ("Menjadi Guardian"). | ✓ | ✓ |
| G-06 | 🔴 | [05](screenshots/05-onboarding-step-next.jpg) | Lansia tidak bisa menjelaskan layar ekstensi. Kata "ekstensi" tidak dipahami, gambarnya berbahasa Inggris dan bertuliskan "ad blocking", dan "Izinkan, bukan Tanya" terasa seperti teka-teki. | ✓ | ✓ |
| G-07 | 🟡 | [24](screenshots/24-safari-popup-situs-mencurigakan.jpg), [25](screenshots/25-safari-tanda-kolom-menimpa-label.jpg), [33](screenshots/33-aktivitas-personal.jpg) | Satu situs disebut dengan tiga istilah ("Mencurigakan", "Risiko Tinggi", "Waspada") dan dua format skor ("72/100" dan "72%"). | ✓ | ✓ |
| G-08 | 🟡 | [31](screenshots/31-safari-layar-blokir.jpg), [34](screenshots/34-detail-situs-berbahaya.jpg) | "100/100" terbaca seperti nilai sempurna, dan barnya oranye, bukan merah. | ✓ | ✓ |
| G-09 | 🟡 | [25](screenshots/25-safari-tanda-kolom-menimpa-label.jpg) | Teks "Shoo: jangan masukkan PIN di sini" menimpa label kolom berikutnya. | ✓ | ✓ |
| G-10 | 🟡 | [24](screenshots/24-safari-popup-situs-mencurigakan.jpg) | Alasannya teknis ("banyak titik", ":8080"). Chip menampilkan "nip.io" padahal halamannya bertuliskan BCA. | ✓ | ✓ |
| G-11 | 🟡 | [24](screenshots/24-safari-popup-situs-mencurigakan.jpg) | "Sembunyikan tanda" mudah tersentuh dan tidak ada konfirmasi. | ✓ | ✓ |
| G-12 | 🟡 | [34](screenshots/34-detail-situs-berbahaya.jpg) | "Menurutmu situs ini aman?" muncul setelah Shoo sendiri menyebut situs itu penipuan. User takut salah menekan "Aman". | ✓ | ✓ |
| G-13 | 🟡 | [05](screenshots/05-onboarding-step-next.jpg), [06](screenshots/06-onboarding-data-dikirim.jpg) | Persetujuan "dicek secara online" dan teks soal data yang dikirim terasa memaksa dan menakutkan. | ✓ | ✓ |
| G-14 | 🟡 | [11](screenshots/11-onboarding-toast-shoo-belum-menyala.jpg), [15](screenshots/15-onboarding-cek-dan-lanjutkan.jpg) | Toast menyebut "langkah 02", layar lain "LANGKAH 2 DARI 2", dan "Langkah 1 dari 2" tidak pernah muncul. | ✓ | |
| G-15 | 🟡 | [13](screenshots/13-onboarding-ekstensi-sudah-aktif.jpg), [15](screenshots/15-onboarding-cek-dan-lanjutkan.jpg) | "Default", "App Browser", dan "browser utama" dipakai bercampur dalam satu alur. | ✓ | ✓ |
| G-16 | 🟡 | [22](screenshots/22-beranda-pribadi.jpg) | Teks empty state Beranda tertutup tab bar dan berwarna abu-abu muda. | | ✓ |
| G-17 | 🟢 | [33](screenshots/33-aktivitas-personal.jpg), [36](screenshots/36-profil-pribadi.jpg) | Satu kunjungan tercatat dua kali, jadi angka "2 Diblokir" ikut dobel. Lingkaran ikonnya kosong. | ✓ | ✓ |
| G-18 | 🟢 | [36](screenshots/36-profil-pribadi.jpg), [47](screenshots/47-beranda-guardian-id.jpg) | Tombol "Bagikan undangan" muncul di mode Pribadi. Ikon ⇆ (ganti mode) tidak punya label. | ✓ | |
| G-19 | 🟢 | beberapa | Kata asing atau kaku: "Browsing", "avatar", "Aksesibilitas", "Tema", "terdiri dari maksimal". Tombol lanjut juga punya tiga versi: "Selanjutnya", "Lanjut", "Lanjut saja". | ✓ | ✓ |

Temuan soal wording sudah masuk ke [temuan-bahasa.md](temuan-bahasa.md). Temuan UX (G-01, G-03, G-04, G-09, G-11, G-12, G-16, G-17) dicatat di bagian E2E [README.md](README.md#hasil-e2e-per-alur).
