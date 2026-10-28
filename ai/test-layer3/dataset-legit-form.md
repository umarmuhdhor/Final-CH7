# Dataset legit yang meminta data (uji salah-tangkap layer 3)

Syarat: halaman publik (tanpa login), `isOfficialHost(host) === false`. Bank/brand resmi tidak dipakai.

**Status: diambil 28 Okt 2026.** L02–L05, L09, L10 diganti karena URL awal mati (DNS/SSL/429). PPDB pemda tetap tidak ketemu host yang buka.

| id | url | label | batch | note |
|---|---|---|---|---|
| L01 | https://sso.undip.ac.id/ | legit | usulan-b | login kampus UNDIP |
| L02 | https://www.sekolah.mu/ | legit | ganti-mati | sekolah: form hubungi institusi (nama, HP, email). Ganti `pmb.unnes.ac.id` (DNS) |
| L03 | https://pendaftaran.undip.ac.id/ | legit | ganti-mati | PMB Undip, form login di JS (`email`+`password`). Ganti `spmb.jabarprov.go.id` (DNS) |
| L04 | https://admissions.ugm.ac.id/v26/ | legit | ganti-mati | landing PMB UGM (hanya search). Ganti `ppdb.jakarta.go.id` (SSL). **Bukan PPDB** — host PPDB tetap mati |
| L05 | https://cottonink.co.id/account/register | legit | ganti-mati | daftar akun toko fashion; minta password. Ganti erigostore (406/429) |
| L06 | https://www.loket.com/ | legit | usulan-b | event; landing JS tanpa form |
| L07 | https://www.kredivo.com/ | legit | usulan-b | pinjol OJK; landing, daftar di app |
| L08 | https://www.adakami.id/ | legit | usulan-b | pinjol OJK; landing, daftar di app |
| L09 | https://oss.go.id/ | legit | ganti-mati | pemda/izin: field `Masukkan NIB`. Ganti `ssw.bandung.go.id` (DNS) |
| L10 | https://wargaklampid-dispendukcapil.surabaya.go.id/app/login | legit | ganti-mati | login dukcapil Surabaya (Klampid): Username + Password. Ganti form dukcapil Bandung (DNS) |
