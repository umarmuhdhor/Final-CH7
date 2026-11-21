# Fase 29 — Kerjakan hasil goldfish 21 Nov + notif dan maskot Shoo

| Field | Nilai |
|---|---|
| Track | app (sebagian kecil backend). Dikerjakan berurutan, satu sub-fase per branch dan PR |
| Branch | 29-0 `docs/alief-fase-29-goldfish` (file ini + laporan + resep maskot) · 29a–29h di bawah. ID PRD tiap branch dicek di `docs/README.md` sebelum branch dibuat |
| Prasyarat | 29a (aset maskot) sebelum sub-fase lain yang memakai maskot. 29b (komponen dialog) sebelum 29c dan butir dialog di 29d |
| Urutan | 29-0 → 29a → 29b → 29c → 29d → 29e → 29f → 29g → 29h (issue Lead bisa kapan saja) |
| Requirement | Hard rule CLAUDE.md 1–7: hanya `ios/ShooApp/` dan `backend/`, kontrak tidak berubah, satu branch = satu PRD ID, pertanyaan ke Lead lewat issue |
| Aturan Alief | Tanpa push langsung ke `main`. PR yang mengubah UI wajib menyertakan screenshot simulator sebelum/sesudah. Subagent dijalankan satu per satu. Secret dari Keychain, tidak pernah dicetak |

## Sumber

- Laporan: `plan/alief/qa/goldfish-21nov.md`. Bagian "Keputusan Alief setelah review Figma" adalah keputusan terbaru.
- Figma file `6PgxbrY0LSkcdaJ5u4YBJP`, halaman High Fidelity:
  - Kartu elephant–goldfish: frame `2423:4227`. Isinya per kartu: Sekarang, lalu Usulan.
  - Dialog Shoo: kartu `2428:12706`.
  - Semua notif: frame "alief notif" `2431:12760`, 9 bagian.
  - 23 pose maskot: frame "alief maskot" `2431:12759`.
- Resep maskot: `plan/alief/ref/maskot-generate.md`. Termasuk cara memasang Shoo yang mengintip di atas sheet (2 lapis).

Ditolak atau tidak dikerjakan: **F4** (kartu dihapus) dan **F7** (pesan undangan tetap).

## 29a · Aset maskot

- [ ] Export 23 rect `Maskot Shoo · <pose>` dari frame `2431:12759` sebagai PNG transparan.
  - Sumber cadangan: `owl/gen/fixed/<pose>.png` di scratchpad sesi 24386bf6. Folder ini bisa hilang.
- [ ] Masukkan ke `Assets.xcassets/Mascot/`.
  - Perkecil ke tinggi maksimal sekitar 600 px supaya ukuran app tidak bengkak.
  - Cek total ukuran aset.
- [ ] Pecah pose `peek` jadi 2 gambar: `peek` (badan) dan `peek-hands` (hanya jari, baris 812 ke bawah). Caranya ada di resep.
- [ ] Beri nama yang jelas di Swift, misalnya `enum Mascot { case think, wave, … }`.

## 29b · Komponen dialog Shoo

- [ ] Buat komponen `ShooDialog`:
  - layar diredupkan;
  - maskot mengintip di atas kartu;
  - judul dan isi;
  - tombol utama: hijau untuk aman, biru untuk netral, merah untuk hapus;
  - tombol kedua dengan outline;
  - posisi di tengah layar;
  - VoiceOver dan Reduce Motion.
- [ ] Ganti `alert`/`confirmationDialog` berikut. Figma: kartu `2428:12706` dan "alief notif" bagian 1.
  - [ ] Putuskan koneksi (Kaget). Termasuk **F10**: isi dialog menjelaskan akibatnya. Cek dulu perilaku aslinya.
  - [ ] Hapus akun (Nangis).
  - [ ] Ganti kode undangan (Mikir).
  - [ ] Notifikasi mati (Tidur).
  - [ ] Semua error aksi di Profil: "Gagal menyimpan" (Maaf), satu tombol "Oke".

## 29c · Konfirmasi tandai aman dan gabung keluarga

- [ ] **F1 + C1** (blocker), tandai aman:
  - dialog "Yakin tandai aman?" (Mikir);
  - di sheet: "Berlaku untuk semua HP keluargamu. Tidak bisa diubah sampai {tanggal}";
  - ringkasan setelah ditandai aman ditulis sebagai orang ketiga di scan milik orang lain.
- [ ] **F2** (blocker): dialog "Gabung dengan keluarga {nama}?" (Melambai) sebelum terhubung.
  - Muncul setelah kode benar dan juga setelah QR terbaca.
  - Isinya: apa yang dilihat Guardian, dan hanya Guardian yang bisa memutus koneksi.
  - Termasuk riwayat yang dihapus (B14).
- [ ] **V5**: tombol simpan di sheet tandai aman abu-abu dan mati sampai alasan dipilih, dengan teks "Pilih minimal satu alasan".

## 29d · Onboarding

- [ ] **F6**: lanjutkan dari langkah yang belum selesai.
  - Yang sudah diketahui: sudah daftar = `settings.mode` terisi dan `onboardingCompleted` false. Status ekstensi dari `ExtensionStatus.nextStep`.
  - Ekstensi belum menyala atau belum "Izinkan" untuk semua situs: ke Aktifkan Ekstensi.
  - Ekstensi sudah menyala: ke Jadikan Safari Default. Simpan tanda setelah langkah ini selesai, karena browser default tidak bisa dibaca.
- [ ] **F6**: layar sukses menampilkan dialog Shoo "Nyalakan notifikasi?" (Nunjuk). Izin iOS baru muncul setelah tombol "Nyalakan".
- [ ] **F3**: kembali dari Pengaturan tanpa perubahan, tampilkan toast di posisi notif iOS (di atas, 8 pt di bawah status bar):
  - A "Shoo belum menyala" (Tidur);
  - B "Shoo baru aktif di sebagian situs" (Tap di sini).
- [ ] **F5**: di sheet "Nyalakan Shoo" di Home, "Buka pengaturan Safari" jadi tombol utama dan "Buka Safari" jadi link kecil.

## 29e · Kata-kata dan status

- [x] **C2** (PR #655): satu nama untuk tiap peran (Guardian / Dilindungi). Tidak ada lagi "Terawasi", "Pantau", atau "Penjaga".
- [x] **C3** (PR #653): status anggota pakai "Ekstensi aktif" / "Ekstensi tidak aktif". "Terhubung" hanya berarti sudah bergabung.
  - Di detail anggota, kartu "Yang perlu dicek di HP {nama}" berisi 3 poin, dengan tombol "Ingatkan {nama}". Figma: kolom C3 "Usulan · detail anggota".
- [x] **C9, C10** (PR #655):
  - label "Dijaga Budi";
  - judul bagian "Akun Tertaut";
  - "Belum terlindungi penuh" kalau baru sebagian situs.
- [x] **C4 + F9** (PR #655): kalimat perkenalan Guardian.
- [x] **C5** (PR #656): satu pertanyaan "Menurutmu situs ini aman?". Nama filter disamakan dengan label.
- [x] **C6** (PR #656): sheet "Data yang dikirim" dibuat lebih simpel, dengan kalimat penyimpanan setelah Shoo dihapus.
- [x] **C8** (PR #656): "berlaku 29 menit lagi". Detik hanya muncul di menit terakhir.
- [x] **C11** (PR #655): "kamu" di semua teks Indonesia.
- [x] **C12** (PR #656): "Tidak ada salinan halaman ini" dipindah ke bagian salinan.
- [x] **F11** (PR #655): kalimat tambahan di notifikasi ganti mode.

## 29f · Home dan Profil

- [x] **F8** (PR #663): kartu "Punya kode undangan?" di Profil Pribadi, di bawah kartu Mode Guardian.
- [x] **F12** (PR #663): hapus kartu Mode Terawasi di Guardian Home yang belum punya anggota.
- [x] **V3** pilihan A (PR #663):
  - kartu "Scam Terbaru" bisa ditekan dan membuka sheet modus;
  - visual di sheet: contoh SMS link palsu, lalu situs palsu yang meminta PIN.
- [x] **V8** (PR #663): label "Ditandai aman" tetap di bawah teks, ikonnya centang. Ukuran:
  - jarak 8 pt dari teks di atasnya;
  - tinggi 24 pt;
  - teks 13 pt;
  - ikon 12 pt;
  - padding kiri-kanan 8 pt, jarak ikon-teks 4 pt;
  - radius 12 pt.
- [ ] **V10**: Home kosong pakai maskot Detektif dengan teks "Shoo lagi berjaga. Kalau ada web mencurigakan, akan muncul di sini."
  - Menunggu aset `magnifier` dari 29a masuk main. Dikerjakan di PR kecil setelah #663.
- [x] **V1, V2, V6, V7, V9** (PR #663): perbaikan kecil sesuai kolom "Cara memperbaiki" di laporan.
  - V7 tanpa perubahan kode: di ujung scroll, isi Home sudah lewat bilah tab (bilah tab sistem masuk safe area).
- **V4** tidak jadi (Alief, 22 Nov): pill "Terhubung" tetap oranye.

## 29g · Notif lain dengan maskot ("alief notif")

- [ ] Toast di Home (7), bagian 2.
  - **Tanya Alief dulu:** app sekarang memakai kartu putih ala notif iOS (`HomeNoticeToast.swift`), sedangkan Figma memakai kartu gradien dengan maskot.
- [ ] Toast kecil "Tersalin" / "Terkirim", bagian 8.
- [ ] Banner di Home dengan maskot (2), bagian 4.
- [ ] Sheet:
  - Shoo mengintip dan memegang tepi sheet: badan di belakang tepi, jari di depan, bayangan tipis;
  - dipakai di Matikan Shoo, Tandai aman, Data yang dikirim, dan Modus penipuan.
- [ ] Pesan error kode undangan (9), bagian 6.
- [ ] Kartu memuat / gagal memuat (8), bagian 7.
- [ ] Empty state (8), bagian 9. "Belum ada aktivitas" pakai pose Duduk.

## 29h · Ke Lead (issue, bukan kode)

- [x] (#649) Ekstensi Safari dengan maskot: popup Waspada / Risiko tinggi, halaman diblokir, dan tanda isian. Ini bagian 5 "alief notif". Milik Lead (`ios/ShooExtension`).
- [x] (#650) Push dengan gambar maskot. Butuh Notification Service Extension, yaitu target baru di `project.yml`.
- [x] (#651) Kirim `allSites` ke backend supaya status anggota bisa membedakan penyebabnya. Ini perubahan kontrak.

## Riwayat

- 21 Nov 2026: dibuat dari sesi review Figma bersama Alief (sesi 24386bf6).
- 22 Nov 2026: 29e di PR #653, #655, #656; 29h jadi issue #649, #650, #651; 29f di PR #663 (tanpa V10). V4 tidak jadi.
