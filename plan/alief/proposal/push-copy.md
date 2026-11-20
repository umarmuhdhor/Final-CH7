# Usulan: teks push peringatan yang lebih jelas

Status: **diputuskan Alief, 20 Nov 2026. Dibangun di PR umarmuhdhor/Final-CH7#639 (`fix/GD-06-push-copy`).**
Tanggal: 20 Nov 2026 · Area: GD-06 (push ke Guardian), PF-01 (push untuk scan sendiri) · Pemilik: Team App (`backend/`)

## Keputusan

Kata Alief: "untuk notif, persentase nya ilangin aja", "kalo misalnya guardian buka website lalu dia dapet warning, gk usah push notif ke diri sendiri", "jadi notif nya itu cuman muncul ke guardian kalo protected device nge detect".

1. **Opsi A dipilih** (bagian 5 dan 6): kata tingkat di depan, satu tindakan, isi saja (payload tidak berubah).
2. **Persen dihapus dari semua push.** Skor tetap ada di Detail.
3. **Push hanya ke Guardian, dan hanya kalau perangkat Protected mendeteksi situs berisiko atau diblokir.** Push untuk scan sendiri (bagian 5.4 dan 5.5) **dihapus**:
   - Guardian tidak dapat push untuk situs yang dia buka sendiri. Dia sudah melihat popup di Safari.
   - Protected tetap tidak dapat push untuk scan miliknya (memang sudah begitu).
   - Sakelar "Situs berbahaya" dan "Situs diblokir" di Profil → Notifikasi tidak berguna lagi, jadi disembunyikan dari app. Field `notifications.warning` / `notifications.blocked` di API tetap diterima (tidak memecah app lama), tapi tidak dipakai lagi.
4. Sumber push "diri sendiri" yang dicek: hanya `ownPush` di `backend/api/src/services/push/notify.ts`. Tidak ada notifikasi lokal di `ios/ShooApp/` atau `ios/ShooExtension/`.

Teks yang dibangun: tabel "Teks lengkap Opsi A", tiga baris Guardian saja.

## 1. Kenapa

Uji pengguna 20 Nov 2026. Penguji menerima push:

> Shoo memperingatkanmu soal situs berisiko · 38%

Kata penguji:

1. **Angka 38% tidak berarti apa-apa** buat dia. Tinggi? Rendah? Harus apa?
2. Push **tidak bilang apa arti "berisiko"** (kuning) dan **tidak bilang harus berbuat apa**.
3. Popup di halaman sudah memakai warna kuning dan label **"Waspada"**, jadi push terasa **lebih miskin** dari popup.
4. Push tetap **penting**: push membuat dia langsung mengecek. Jadi push tetap ada, hanya perlu lebih jelas.
5. Kalau dia Guardian dan menerima push soal anggota keluarga, **reaksi pertamanya: menelepon** orang itu.

## 2. Keadaan sekarang

Semua teks ada di `backend/api/src/services/push/messages.ts`. Push hanya punya **isi (body)**, tanpa judul.

| Jenis | Siapa menerima | Kapan | Teks sekarang (ID) |
|---|---|---|---|
| Anggota buka situs peringatan | Guardian | scan anggota `warning` (skor 30–79) | `Ibu membuka situs mencurigakan · 41%` |
| Anggota buka situs diblokir | Guardian | scan anggota `blocked` (skor ≥ 80) | `Ibu membuka situs yang diblokir · 92%` |
| Peringatan untuk diri sendiri | Guardian (scan miliknya) | `warning`, kalau sakelar "Situs berbahaya" nyala | `Shoo memperingatkanmu soal situs berisiko · 38%` |
| Blokir untuk diri sendiri | Guardian (scan miliknya) | `blocked`, kalau sakelar "Situs diblokir" nyala | `Shoo memblokir situs berbahaya · 92%` |

Catatan dari kode (`notify.ts`, `routes/scans.ts`):

- Perangkat **Protected tidak pernah** dapat push soal scan miliknya sendiri. Dia sudah melihat popup atau layar blokir. Push "diri sendiri" hanya untuk perangkat Guardian.
- Push Guardian dikirim **per situs**: sekali saat situs pertama kali dibuka, dan sekali lagi saat situs itu pertama kali diblokir (`contracts/api.md`, #241).
- **Jam tenang**: push `warning` ditahan, push `blocked` tetap dikirim.
- Batas: 10 push per 10 menit per penerima.
- Ketuk push → app membuka **Detail** scan itu (`scanId`, GD-06). Di Detail, Guardian melihat alasan, bukti halaman, skor, dan tombol **Aman / Bahaya**.

Push-push lain di file yang sama (pengingat, terputus, anggota keluar, perlindungan mati, ringkasan mingguan) **tidak** dibahas di sini. Keluhan penguji hanya soal push peringatan dan blokir.

### Tingkat yang dilihat pengguna di popup

Dari `ios/ShooExtension/Resources/_locales/id/messages.json` dan `contracts/README.md`:

| Skor | Status | Warna | Label di popup | Nasihat di popup |
|---|---|---|---|---|
| 30–49 | `warning` | kuning | **Waspada** | "Hati-hati sebelum memasukkan data pribadi di sini." |
| 50–79 | `warning` | oranye | **Risiko Tinggi** · "Situs Mencurigakan!" | "Jangan masukkan PIN, OTP, password, atau nomor kartu di halaman ini." |
| ≥ 80 | `blocked` | merah | "Halaman ini diblokir" | Tombol "Kembali ke halaman aman" / "Tinjau di Shoo" |

Jadi push bisa memakai **kata yang sama** dengan popup. Kata itu sudah dilihat pengguna, dan warnanya sudah mereka kenal.

## 3. Data yang sudah ada saat push dibuat

Saat `POST /scans` membuat push, backend sudah tahu:

| Data | Ada? | Boleh masuk push? |
|---|---|---|
| Nama pemilik perangkat (`owner.name`, mis. "Ibu") | Ya | Ya, sudah dipakai sekarang |
| `status` (`warning` / `blocked`) | Ya | Ya |
| `score` (30–100) | Ya | Ya, sudah dipakai sekarang |
| Bahasa penerima (`id` / `en`) | Ya | Dipakai untuk memilih teks |
| `scanId` | Ya | Sudah ada di payload, untuk membuka Detail |
| `domain` dan URL situs | Ya | **Tidak.** `plan/alief/SECURITY.md` T9 dan P10: push hanya nama + kata kerja + skor, tanpa URL/domain, karena layar kunci bisa dilihat orang lain |
| Batas tingkat 2 (`secondWarning`, 50) | **Tidak** | Backend hanya punya `warnAt` dan `blockAt` (`GET /config/public`). Untuk memisahkan "Waspada" dan "Risiko tinggi", backend harus memakai 50 dari tabel `contracts/README.md` |
| Nomor telepon anggota | **Tidak** | Shoo tidak menyimpan nomor telepon (data minimum). Tombol "Telepon Ibu" langsung di push **tidak mungkin** tanpa menambah data pribadi baru |

**Bentuk payload sekarang** (`contracts/api.md` "Push payloads", `apns.ts`):

```json
{ "aps": { "alert": { "body": "…" }, "sound": "default" }, "scanId": "…" }
```

- **Mengubah teks `body` saja** tidak mengubah bentuk JSON. Tidak perlu ubah kontrak. Hanya contoh teks di `contracts/api.md` yang jadi usang (lihat bagian 7).
- **Menambah `aps.alert.title`, `subtitle`, `thread-id`, `category`, atau `interruption-level`** mengubah bentuk payload. Itu perlu issue ke lead (aturan 7 di `CLAUDE.md`) dan menunggu jawaban.

## 4. Batas di iOS

- **Tanpa judul**, iOS menampilkan nama app ("Shoo") sebagai baris tebal di atas isi. **Dengan judul**, judul menggantikan baris tebal itu, dan app dikenali dari ikonnya. (Perlu dicek di simulator sebelum dibangun.)
- **Judul** dan **subjudul**: masing-masing satu baris, dipotong dengan "…" kalau terlalu panjang. Di iPhone 6,1" dengan ukuran teks standar, satu baris kira-kira 35–40 huruf.
- **Isi** di layar kunci dan banner: dipotong setelah sekitar **4 baris** (kira-kira 110–140 huruf). Teks lengkap baru terlihat kalau notifikasi ditekan lama atau dibuka.
- **Ukuran teks besar** (Dynamic Type): lebih sedikit huruf per baris. Jadi **hal terpenting harus ada di 30–40 huruf pertama.**
- **Tumpukan notifikasi**: kalau beberapa push menumpuk, hanya yang paling atas yang terbaca. Satu lagi alasan untuk menaruh kata kunci di depan.
- **"Tampilkan Pratinjau: Saat Terbuka"**: di banyak iPhone isi push disembunyikan sampai HP dibuka. Yang terlihat hanya "Shoo" + "Notifikasi". Ini pengaturan pengguna, Shoo tidak bisa mengubahnya.
- Batas ukuran payload APNs 4 KB, jauh di atas kebutuhan kita.

## 5. Opsi

Tiga pendekatan. Masing-masing diterapkan ke semua jenis push (bagian 5.1–5.5), supaya gayanya seragam.

| | **Opsi A: Isi saja, kata tingkat di depan** | **Opsi B: Judul + isi** | **Opsi C: Tetap ada angka, ditambah kata** |
|---|---|---|---|
| Bentuk | Hanya `body`, seperti sekarang | `title` (tingkat + siapa) + `body` (arti + tindakan) | Hanya `body` |
| Persen | **Hilang dari push.** Tetap ada di Detail | **Hilang dari push.** Tetap ada di Detail | **Tetap**, ditulis "skor risiko 38%" di belakang kata tingkat |
| Tingkat | Kata dari popup di depan: Waspada / Risiko tinggi / Diblokir | Kata tingkat di judul (baris tebal) | Kata tingkat di depan |
| Tindakan | Satu kalimat tindakan + "Ketuk untuk …" | Sama, di isi | Hanya "Ketuk untuk lihat alasannya" |
| Ubah kontrak/payload? | **Tidak** | **Ya.** Tambah `aps.alert.title` | **Tidak** |
| Kerja | `messages.ts` + `notify.ts` (kirim tingkat), tes backend | Sama + `apns.ts` + `PushMessage.title` + issue ke lead dulu | `messages.ts` + `notify.ts`, tes backend |

Kenapa persen dibuang di A dan B: penguji bilang angka itu tidak berarti. Kata tingkat (Waspada / Risiko tinggi / Diblokir) memberi informasi yang sama dalam bahasa biasa, dan cocok dengan warna popup. Angka tetap bisa dilihat di Detail ("Skor risiko"), tempat ada penjelasannya.

Contoh di bawah memakai nama anggota **"Ibu"**. Nama sebenarnya diambil dari nama perangkat anggota.

### 5.1 Guardian · anggota membuka situs **Waspada** (kuning, 30–49)

Situs **belum diblokir**. Anggota masih bisa mengetik data di sana. Jadi Guardian perlu bertindak cepat.

**Opsi A**
> Waspada: Ibu membuka situs mencurigakan. Ingatkan Ibu jangan isi data pribadi. Ketuk untuk lihat alasannya.

- "Waspada" = tingkat kuning, sama dengan popup.
- "Ibu membuka situs mencurigakan" = siapa dan apa yang terjadi.
- "Ingatkan Ibu jangan isi data pribadi" = tindakan. Cocok dengan reaksi penguji (menelepon), tanpa butuh nomor telepon.
- "Ketuk untuk lihat alasannya" = apa yang ada di balik ketukan (alasan dan bukti di Detail).

**Opsi B**
> **Waspada: Ibu buka situs mencurigakan**
> Situs ini belum diblokir. Ingatkan Ibu jangan isi data pribadi. Ketuk untuk lihat alasannya.

- Judul tebal: tingkat + siapa. Terbaca walau isinya terpotong.
- "Situs ini belum diblokir" = menjelaskan kenapa harus bertindak sekarang.
- Sisanya sama dengan Opsi A.

**Opsi C**
> Waspada · Ibu membuka situs mencurigakan, skor risiko 38%. Ketuk untuk lihat alasannya.

- Sama dengan sekarang, ditambah kata "Waspada" dan "skor risiko". Angka tetap ada, tapi tetap tidak bilang harus berbuat apa.

### 5.2 Guardian · anggota membuka situs **Risiko tinggi** (oranye, 50–79)

Situs belum diblokir, tapi popup sudah mencoret kolom PIN, OTP, password, dan kartu.

**Opsi A**
> Risiko tinggi: Ibu membuka situs yang mungkin penipuan. Telepon Ibu, minta jangan isi PIN atau OTP. Ketuk untuk detail.

- "Risiko tinggi" = tingkat oranye, sama dengan popup.
- "mungkin penipuan" = arti tingkat ini dalam kata biasa.
- "Telepon Ibu, minta jangan isi PIN atau OTP" = tindakan yang jelas dan mendesak. Data yang disebut sama dengan yang dicoret popup.
- "Ketuk untuk detail" = lebih pendek, karena kalimat tindakannya lebih panjang.

**Opsi B**
> **Risiko tinggi: Ibu buka situs penipuan?**
> Situs ini belum diblokir. Telepon Ibu sekarang, minta jangan isi PIN, OTP, atau password. Ketuk untuk detail.

**Opsi C**
> Risiko tinggi · Ibu membuka situs mencurigakan, skor risiko 64%. Ketuk untuk lihat alasannya.

### 5.3 Guardian · situs anggota **Diblokir** (merah, ≥ 80)

Shoo sudah menutup halaman. Anggota aman, dan layar blokirnya bilang "Link terkirim ke <nama Guardian>". Halaman baru bisa dibuka kalau Guardian menandainya aman. Jadi tindakannya: **cek dan putuskan**, bukan panik. Push ini tetap dikirim saat jam tenang.

**Opsi A**
> Diblokir: Shoo menutup situs berbahaya yang dibuka Ibu. Ibu aman. Ketuk untuk cek dan putuskan apakah situs ini aman.

- "Diblokir" = tingkat merah, sama dengan layar blokir.
- "Shoo menutup situs berbahaya yang dibuka Ibu" = apa yang terjadi, dan bahwa Shoo sudah bertindak.
- "Ibu aman" = menenangkan. Tidak perlu menelepon dengan panik.
- "Ketuk untuk cek dan putuskan apakah situs ini aman" = tindakan Guardian (tombol Aman / Bahaya di Detail). Anggota mungkin sedang menunggu jawaban.

**Opsi B**
> **Diblokir: situs berbahaya di HP Ibu**
> Shoo sudah menutupnya, Ibu aman. Ketuk untuk cek dan putuskan apakah situs ini aman.

**Opsi C**
> Diblokir · Ibu membuka situs berbahaya, skor risiko 92%. Ketuk untuk lihat alasannya.

### 5.4 Diri sendiri (perangkat Guardian) · **peringatan** (30–79)

> **Dihapus (keputusan Alief):** tidak ada push untuk scan sendiri. Teks di 5.4 dan 5.5 disimpan sebagai catatan saja.

Ini push yang dilihat penguji. Penerima baru saja melihat popup di Safari, jadi push ini pengingat dan catatan. Kata tingkat harus sama dengan popup yang barusan dia lihat.

**Opsi A**

30–49:
> Waspada: situs yang kamu buka mencurigakan. Jangan isi data pribadi di sana. Ketuk untuk lihat alasannya.

50–79:
> Risiko tinggi: situs yang kamu buka mungkin penipuan. Jangan isi PIN, OTP, atau password. Ketuk untuk lihat alasannya.

- Kata tingkat = sama dengan popup.
- "situs yang kamu buka" = jelas soal situs mana, tanpa menyebut domain di layar kunci.
- "Jangan isi …" = nasihat yang sama dengan popup, dalam satu kalimat.

**Opsi B**

30–49:
> **Waspada: situs mencurigakan**
> Situs yang baru kamu buka belum diblokir. Jangan isi data pribadi di sana. Ketuk untuk lihat alasannya.

50–79:
> **Risiko tinggi: mungkin penipuan**
> Situs yang baru kamu buka belum diblokir. Jangan isi PIN, OTP, atau password. Ketuk untuk lihat alasannya.

**Opsi C**
> Waspada · Shoo memperingatkanmu soal situs mencurigakan, skor risiko 38%. Ketuk untuk lihat alasannya.

### 5.5 Diri sendiri (perangkat Guardian) · **Diblokir** (≥ 80)

**Opsi A**
> Diblokir: Shoo menutup situs berbahaya yang kamu buka. Ketuk untuk lihat alasannya.

- Tidak ada tindakan wajib. Shoo sudah menutup halaman. Push ini memberi tahu kenapa halaman tiba-tiba tertutup.

**Opsi B**
> **Diblokir: situs berbahaya**
> Shoo sudah menutup situs yang kamu buka. Ketuk untuk lihat alasannya.

**Opsi C**
> Diblokir · Shoo memblokir situs berbahaya, skor risiko 92%. Ketuk untuk lihat alasannya.

### 5.6 Tambahan yang dipertimbangkan, tidak diusulkan sekarang

| Ide | Kenapa tidak sekarang |
|---|---|
| Tombol "Telepon Ibu" di push | Shoo tidak menyimpan nomor telepon. Menambah nomor = data pribadi baru (melanggar data minimum di `SECURITY.md`) |
| Menyebut domain situs | Dilarang SECURITY T9/P10: layar kunci bisa dilihat orang lain |
| `interruption-level: time-sensitive` untuk push Diblokir ke Guardian | Butuh capability baru di `ios/project.yml` (milik lead) dan ubah payload. Bisa diusulkan terpisah nanti kalau push blokir sering terlewat |
| `thread-id` per anggota (push dikelompokkan per orang) | Ubah payload. Manfaatnya kecil karena push sudah dibatasi per situs |

## 6. Rekomendasi: **Opsi A** (dipilih)

Alasan:

1. **Menjawab semua keluhan penguji.** Kata tingkat menggantikan persen yang tidak berarti. Setiap push bilang arti tingkat itu dan apa yang harus dilakukan. Untuk Guardian, tindakannya cocok dengan reaksi pertama penguji: menghubungi anggota.
2. **Sama dengan popup.** Waspada / Risiko tinggi / Diblokir adalah kata yang sudah dilihat pengguna, dengan warna yang sudah mereka kenal. Push tidak lagi terasa "lebih miskin".
3. **Tanpa ubah kontrak.** Bentuk payload tetap. Pekerjaan hanya di `backend/` (milik Team App): bisa dibangun tanpa menunggu lead.
4. **Aman untuk layar kunci.** Tidak ada domain, URL, atau angka yang bisa disalahartikan orang lain yang melihat layar.
5. **Kata terpenting di depan.** "Waspada:", "Risiko tinggi:", "Diblokir:" ada di 15 huruf pertama, jadi tetap terbaca walau isi terpotong, teks besar, atau push menumpuk.

Opsi B lebih rapi (judul tebal), tapi butuh ubah payload dan menunggu lead. Bisa jadi langkah kedua kalau Opsi A terbukti masih kurang di uji berikutnya. Opsi C paling kecil, tapi tetap tidak bilang harus berbuat apa, jadi keluhan nomor 2 tidak terjawab.

### Teks lengkap Opsi A (ID + EN)

| Jenis | Bahasa Indonesia | English |
|---|---|---|
| Guardian · Waspada (30–49) | `Waspada: {nama} membuka situs mencurigakan. Ingatkan {nama} jangan isi data pribadi. Ketuk untuk lihat alasannya.` | `Be careful: {name} opened a suspicious site. Remind {name} not to enter personal details. Tap to see why.` |
| Guardian · Risiko tinggi (50–79) | `Risiko tinggi: {nama} membuka situs yang mungkin penipuan. Telepon {nama}, minta jangan isi PIN atau OTP. Ketuk untuk detail.` | `High risk: {name} opened a site that may be a scam. Call {name} and ask them not to enter a PIN or OTP. Tap for details.` |
| Guardian · Diblokir (≥ 80) | `Diblokir: Shoo menutup situs berbahaya yang dibuka {nama}. {nama} aman. Ketuk untuk cek dan putuskan apakah situs ini aman.` | `Blocked: Shoo closed a dangerous site {name} opened. {name} is safe. Tap to check it and decide if it's safe.` |
| Sendiri · Waspada (30–49) | `Waspada: situs yang kamu buka mencurigakan. Jangan isi data pribadi di sana. Ketuk untuk lihat alasannya.` | `Be careful: the site you opened looks suspicious. Don't enter personal details there. Tap to see why.` |
| Sendiri · Risiko tinggi (50–79) | `Risiko tinggi: situs yang kamu buka mungkin penipuan. Jangan isi PIN, OTP, atau password. Ketuk untuk lihat alasannya.` | `High risk: the site you opened may be a scam. Don't enter a PIN, OTP or password. Tap to see why.` |
| Sendiri · Diblokir (≥ 80) | `Diblokir: Shoo menutup situs berbahaya yang kamu buka. Ketuk untuk lihat alasannya.` | `Blocked: Shoo closed a dangerous site you opened. Tap to see why.` |

Extension Safari hanya punya teks Indonesia (`_locales/id`). Label EN mengikuti `chrome/README.md` ("Be careful" untuk Waspada). "High risk" untuk 50–79 adalah usulan; cek dengan label EN di app saat membangun.

Baris "Sendiri" di tabel ini **tidak dibangun** (keputusan nomor 3).

### Yang dibangun

1. `messages.ts`: ganti `TEXT` dengan tiga teks Guardian di atas, hapus `OWN`. Kunci baru: `warning1` (30–49), `warning2` (50–79), `blocked`. Persen tidak dipakai lagi.
2. `notify.ts`: pilih tingkat dari `status` + `score` (`warning` dan skor < 50 → `warning1`, `warning` dan skor ≥ 50 → `warning2`, `blocked` → `blocked`). Hapus `ownPush`; `routes/scans.ts` hanya mengirim push Guardian.
3. App: sembunyikan bagian "Peringatan" (sakelar "Situs berbahaya" dan "Situs diblokir") di Profil → Notifikasi.
4. Tes: `backend/api/test/push-messages.test.ts`, `push-apns.test.ts`, `push-deliver.test.ts`, `settings.test.ts`; `backend/API.md`; cek juga `routes/support.ts` dan `ios/ShooApp/UITests/LivePushUITests.swift` yang menyebut teks push lama.
5. Cek di simulator: teks terpotong di mana pada layar kunci, dengan ukuran teks standar dan besar, dan dengan nama anggota yang panjang. Lampirkan screenshot sebelum/sesudah di PR.
6. Branch: `fix/GD-06-push-copy`.

## 7. Issue

Alief memutuskan tidak lewat issue ("kita aja yang kerjain gk usah issue"). Dua issue yang sempat dibuka (#634 contoh teks push di kontrak, #635 batas tingkat 50) sudah ditutup. Isinya dikerjakan di PR #639:

- Contoh teks push di `contracts/api.md` diperbarui di PR #639 (bentuk JSON tetap). Umar diminta review karena file itu milik lead.
- Batas tingkat: backend memakai 50 (`SECOND_WARNING` di `messages.ts`), sama dengan tabel `contracts/README.md`. Kalau suatu saat `secondWarning` bisa diubah admin, push dan popup bisa berbeda kata untuk skor di sekitar batas itu.
- `plan/alief/SECURITY.md` T9/P10 diperbarui: tanpa skor.

## 8. Hal kecil yang ketemu, di luar usulan ini

- Popup memakai dua label berbeda untuk 50–79: mini card **"Risiko Tinggi"**, live score card **"Bahaya"** (`pill_status_danger`). Tag di Activity app memakai **"Waspada"** untuk semua `warning` (30–79). Sebaiknya satu kata per tingkat di semua tempat. Itu milik lead (extension) dan Team App (Activity), jadi perlu dibahas terpisah.
