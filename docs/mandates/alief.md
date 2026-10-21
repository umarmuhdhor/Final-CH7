# Mandat — Alief (Team App + Backend)

> Dari: Umar (lead) · Untuk: Alief (@aliefauzan) dan Claude-nya
> Cara pakai: di Claude Code, ketik `/mandate`. Claude akan membaca file ini, memilih tugas berikutnya yang belum dicentang, lalu mulai kerja.

## Peran
Kamu memegang **semua yang dilihat user di app** dan **server yang menyimpan data keluarga**. Extension Safari (popup, layar blokir) dikerjakan Umar. Skor dan alasan deteksi dibuat Imelda. Tugasmu menampilkan hasilnya, menghubungkan keluarga, dan meneruskan keputusan Safe / Not safe.

| Boleh diedit | Jangan disentuh |
|---|---|
| `ios/ShooApp/`, `backend/` | `contracts/`, `ios/project.yml`, `ios/ShooShared/`, `ios/ShooExtension/`, `ios/ShooLiveActivity/`, `detector/`, `ai/` |

Wajib dibaca sebelum mulai: PRD bagian 5, 8, 9, dan 10 (link di `docs/README.md`), `contracts/api.md`, `contracts/app-group-keys.md`, `contracts/fixtures/`, `ios/ShooApp/CLAUDE.md`, `backend/CLAUDE.md`.

Setup: `brew install xcodegen`, lalu `cd ios && xcodegen && open Shoo.xcodeproj`. Ulangi `xcodegen` setiap habis pull atau setelah membuat folder baru.

## Definisi sukses MVP
1. Semua requirement **P0** di PRD bagian 8.1–8.4 dan 8.6 lolos kriteria "Selesai kalau".
2. Keluarga bisa terhubung lewat kode 4 digit atau QR, lalu Guardian menerima push ketika orang tuanya membuka situs berbahaya.
3. Saat Guardian menekan **It's safe**, layar blokir di HP orang tua langsung terbuka (EX-06), tanpa layar konfirmasi.
4. Semua teks tersedia dalam English (default) dan Bahasa Indonesia. Teks alasan deteksi sudah dikirim Imelda dalam 2 bahasa, jadi cukup pilih sesuai bahasa app: `signal.label.text(for: languageCode)`. Jangan diterjemahkan sendiri.

## Tugas

### Spike · di iPhone sendiri (minggu 1)
Signing ke akun Apple-mu: `cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig`, isi Team ID + bundle ID + App Group milikmu, lalu `cd ios && xcodegen`. File itu di-gitignore, `project.yml` tidak perlu diubah. Kalau Xcode menolak capability App Groups (biasanya karena akun gratis / Personal Team), lapor ke Umar.
- [ ] **S1 · Deteksi extension On/Off** → isi `docs/spikes/extension-status.md`. Heartbeat sudah jalan (`content.js` → `background.js` → `SafariWebExtensionHandler` → App Group), cukup tes di device. Usulkan window Active ke Umar (nilainya di `AppGroup.extensionActiveWindow`, milik Umar).
- [ ] **S2 · Buka pengaturan extension** → isi `docs/spikes/open-extension-settings.md`. Kode tes boleh di `ios/ShooApp/`. Jangan pakai `App-prefs:` (risiko ditolak App Review).

### Fase A · UI dari fixtures, tanpa menunggu backend
Pakai `contracts/fixtures/*.json` sebagai data palsu lewat satu protocol/repository. Di Fase C, cukup implementasinya yang diganti, view-nya tidak perlu diubah.

- [ ] **Fondasi:** struktur navigasi (tab Shield / Activity), protocol `ShooRepository` + `MockRepository` yang membaca fixtures, String Catalog EN + ID. Branch: `feat/APP-foundation`
- [ ] **ON-01** Splash interaktif 3 slide, ada tombol Skip
- [ ] **ON-02** Isi nama (1–20 karakter) + avatar acak
- [ ] **ON-03** Pilih mode Guardian / Protected (permanen)
- [ ] **ON-04** Turn on extension: ilustrasi letak switch, tombol Turn on, cek status saat kembali ke app, link "Still can't? Watch video" (PiP). Mulai dengan fallback PRD §10, sempurnakan dari hasil S1 + S2.
- [ ] **ON-05** Izin notifikasi + pengingat di Home kalau ditolak
- [ ] **DT-01 s.d. DT-06** Layar Detail: ring skor, label, link & waktu, 1–3 bukti (`labelSimple` untuk Protected), tombol validasi khusus Guardian, catatan "Verified scam by / Marked safe by"
- [ ] **PR-04, PR-05** Shield + Activity untuk Protected
- [ ] **GD-01, GD-02, GD-03, GD-05** Shield Guardian, toggle Family mode, Shield Family, Activity Family
- [ ] **PF-01** Profile (nama, avatar, bahasa, status extension)

Status extension Active/Off cukup baca `AppGroup.Key.extensionLastSeenAt`. Contohnya sudah ada di `ContentView.swift`.
Layout dan copy final mengikuti designer. Wireframe di PRD bagian 7 hanya referensi.

### Fase B · Backend — `backend/`
Stack bebas (saran: Supabase). Tulis cara setup di `backend/README.md`. Bentuk JSON **wajib** sama dengan `contracts/api.md`.
- [x] **Devices:** `POST /devices`, `PATCH /devices/me`, auth token per perangkat (tanpa login)
- [x] **Family:** `POST /family/code` (4 digit, berlaku 60 detik, batas jumlah percobaan), `POST /family/join`, `GET/DELETE /family/members`, `DELETE /family/guardian`, maks. 3 orang per guardian
- [x] **Scans:** `POST /scans` (+ upload screenshot), `GET /scans` dengan filter + cursor, `GET /scans/{id}`
- [x] **Verdicts:** `POST /verdicts` (berlaku per domain), `GET /verdicts?domain=`
- [x] **Blocklist:** `GET /blocklist` (dibutuhkan Imelda untuk layer 1, jadi kerjakan lebih awal kalau bisa)
- [x] **Push (APNs):** dikirim saat device Protected memanggil `POST /scans`. Payload sesuai `contracts/api.md`.
- [x] **Retensi:** data scan + screenshot otomatis dihapus setelah 14 hari
- [x] **Keamanan:** Guardian hanya bisa melihat data perangkat yang terhubung dengannya. Kode join dibatasi jumlah percobaannya.

### Fase C · Sambungkan app ke backend
- [ ] `ApiRepository` menggantikan `MockRepository`
- [ ] Setelah onboarding, tulis key sesi ke App Group (`contracts/app-group-keys.md`) supaya extension bisa memanggil API
- [ ] **GD-04** Family code: QR + kode yang berganti tiap 60 detik + hitung mundur + "Copy invite link" + daftar terhubung (x/3)
- [ ] **PR-01, PR-02** Connect lewat Scan QR / Enter code → layar "You're protected by …"
- [ ] **PR-03** Link undangan `shoo://join?code=1234` membuka app dengan kode terisi (P0). Deferred deep link setelah install = P1.
- [ ] **GD-06** Tap push → buka Detail sesuai `scanId`
- [ ] **GD-07** Tombol It's safe / Not safe langsung berlaku, tanpa konfirmasi

### Ditahan dulu
- **Live Activity lewat push:** kalau spike Dynamic Island memutuskan jalur push-to-start, nanti ada endpoint tambahan. Umar akan memberi kabar.

## Bukan tugasmu
Popup warning, highlight, dan layar blokir di Safari (Umar). Skor, sinyal, dan teks alasan (Imelda). Hoaks (Fase 2).

## Kapan harus tanya Umar
- Butuh capability baru di Xcode (**Push Notifications**, Associated Domains, dll). Itu diatur di `project.yml`, jadi minta Umar yang menambahkannya.
- Butuh field atau endpoint baru, atau bentuk JSON berbeda dari `contracts/` → itu perubahan kontrak.
- Butuh model baru di `ShooShared/`.

## Cara lapor
1 ID PRD (atau 1 kelompok kecil ID yang berkaitan) = 1 branch = 1 PR, dengan @umarmuhdhor sebagai reviewer. Contoh branch: `feat/ON-02-name`, `feat/BE-family-code`. Di PR: centang checkbox di file ini, sertakan screenshot untuk perubahan UI, dan tulis cara mengujinya.
