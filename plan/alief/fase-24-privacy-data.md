# Fase 24 — Privasi & siklus data: hapus device tidak aktif, token di Keychain bersama, kontak + label privasi (E7, C22, E6)

| Field | Nilai |
|---|---|
| Track | c (backend + app, tiga bagian yang saling lepas) |
| Branch | 24a-1 `feat/E7-inactive-devices` (backend: langkah retensi baru, mode `dry_run`, index, test) · 24a-2 `feat/E7-inactive-devices-on` (ubah var ke `delete` + teks `/privacy`, setelah K1–K4 dijawab dan ≥ 7 run dry-run bersih) · 24b-1 `feat/C22-shared-keychain` (app: item Keychain di access group bersama + migrasi, App Group tetap ditulis) · 24b-2 `feat/C22-drop-app-group-token` (app berhenti menulis `device.token`, **hanya setelah** issue C22 dijawab dan kontrak + handler Umar merge) · 24c-1 `fix/E6-privacy-contact` (backend: kontak `/privacy`, halaman `/support`) · 24c-2 `fix/E6-app-privacy` (app: `supportEmail`, privacy manifest). Semua dari `origin/main` saat mulai |
| Prasyarat | 24a: sebaiknya setelah fase 20b merge (20b menulis ulang `cron/retention.ts` jadi satu store, `fase-20-screenshot-sunset.md:94`) dan 21a (tabel `ops_jobs`, `fase-21-monitoring.md:76`); kalau belum, rebase biasa, langkah baru berdiri sendiri. 24b-2: jawaban issue C22 + PR Umar (`contracts/app-group-keys.md`, `ios/ShooExtension/SafariWebExtensionHandler.swift`) merge. 24c: jawaban Alief K10–K12. Tidak ada yang menunggu fase lain |
| Urutan | 24c-2 butir `supportEmail` dulu (alamat sekarang tidak ada, lihat cek C16 di bawah) → 24a-1 (TDD) → kirim issue C22 + issue E6 → 24b-1 → 24c-1 → 24c-2 sisa → (setelah jawaban) 24a-2, 24b-2 |
| Requirement | TODO E7 (review fase 12: security L + database M7 "device tidak aktif", `log/fase-12.md:54-55,163`), TODO C22 (review security fase 13, `log/fase-13.md:67,109`), TODO E6, SECURITY §3 P2 (label privasi), P3, P4 (Keychain), P6 (log), P12 (kebijakan privasi), P13 (hapus = hilang), `ARCHITECTURE.md` §3 (Free: CPU 10 ms per Cron, 50 subrequest) |
| Model + reviewer ECC | Opus 5.5 · 24a: `ecc:database-reviewer` → `ecc:typescript-reviewer` → `ecc:security-reviewer`; 24b: `ecc:swift-reviewer` → `ecc:security-reviewer`; 24c: `ecc:security-reviewer` (teks privasi + manifest). Berurutan, tidak paralel |
| Fase berikutnya | Tidak ada yang menunggu fase 24. Fase 16 (TestFlight eksternal) butuh 24c selesai (P12) |

## Tujuan

**24a — device tidak aktif (E7).** Baris `devices` tidak pernah dihapus kecuali lewat `DELETE /devices/me` (`routes/devices.ts:181-199`) atau ganti mode (`:153-175`). Retensi harian hanya menghapus scan, objek, kode, percobaan join, push log, dan counter (`cron/retention.ts:97-139`). Akibatnya nama, avatar, token APNs, model iPhone, zona waktu, hitungan blokir, link keluarga, dan verdict Guardian dari orang yang sudah berhenti memakai Shoo (atau menghapus app tanpa "Delete account") tersimpan tanpa batas. Kebijakan privasi mengakuinya: "Devices that stop using Shoo are not deleted automatically yet." (`routes/privacy.ts:42`, ID `:101`). Registrasi yang ditinggal di tengah onboarding juga menumpuk (global sampai 1000/hari, `http/rateLimit.ts:15`).

**24b — token di plist App Group (C22).** App menyimpan token di Keychain `AfterFirstUnlockThisDeviceOnly` (`Data/Keychain.swift:16`), tetapi kontrak mewajibkan salinan teks biasa `device.token` di App Group (`contracts/app-group-keys.md:13`), yang ditulis di `SessionStore.save` (`Data/SessionStore.swift:56`) dan dibaca extension (`ios/ShooExtension/SafariWebExtensionHandler.swift:40`). Plist App Group ikut backup iPhone dan bisa dipulihkan ke iPhone lain; app sudah menolak salinan itu kalau Keychain kosong (`App/AppEnvironment.swift:208-227`, D-alief-C03), tetapi extension tetap memakainya sampai app dibuka. C22 masih **draf, belum pernah dikirim** ke Umar (`TODO.md` baris C22, status `[ ]`). Fase ini mengirimnya.

**24c — kontak + domain + label privasi (E6).** `GET /privacy` masih berisi placeholder kontak (`routes/privacy.ts:11-12`, dipakai `:72` dan `:131`). App menautkan "Contact us" ke `halo@shoo.id` (`App/AppConfig.swift:29-30`, `Features/Profile/ProfilePages.swift:1364-1365`), padahal `dig shoo.id SOA` (31 Okt 2026) = **NXDOMAIN**: domain itu tidak terdaftar, jadi email pengguna gagal terkirim, dan siapa pun yang mendaftarkan `shoo.id` bisa menerima email pengguna. URL kebijakan privasi wajib sebelum TestFlight eksternal / App Store (P12). Jawaban App Privacy di App Store Connect harus cocok dengan manifest dan dengan data yang benar-benar disimpan backend; belum ada inventaris data tertulis.

**Hasil akhir.**
- Retensi harian menghapus device (dan seluruh datanya, lewat jalur hapus yang sama dengan `DELETE /devices/me`) yang tidak aktif lebih lama dari ambang K1, dengan aturan keluarga K3, diawali mode `dry_run` yang hanya menghitung. Kebijakan privasi menyebut aturannya.
- Token device ada di satu item Keychain yang bisa dibaca app dan extension; salinan teks biasa di App Group hilang setelah Umar setuju.
- Alamat kontak yang benar-benar ada di `/privacy`, `/support`, dan app; URL kebijakan privasi + support siap untuk App Store Connect; tabel inventaris data yang menjadi sumber jawaban App Privacy, cocok dengan `PrivacyInfo.xcprivacy`.

## Bacaan wajib

- `plan/alief/SECURITY.md` §3 P2, P3, P4, P12, P13; `plan/alief/ARCHITECTURE.md` §3.
- `plan/alief/log/fase-12.md:54-55,163` (asal E7), `plan/alief/log/fase-13.md:67,77,109` (asal C22), `log/DECISIONS.md` D-alief-C03 (`:578`).
- `plan/alief/fase-20-screenshot-sunset.md` (perubahan `retention.ts`), `plan/alief/fase-21-monitoring.md` K2 (`ops_jobs`).
- Backend: `src/cron/retention.ts`, `src/db/repo/{devices,tombstones,verdicts}.ts`, `src/http/auth.ts`, `src/routes/{devices,privacy,terms}.ts`, `src/index.ts`, `src/env.ts`, `wrangler.jsonc`, `db/supabase/migrations/20261021130000_init.sql`, `test/{retention,privacy,devices-me,log-hygiene}.test.ts`.
- App: `ios/ShooApp/Data/{Keychain,SessionStore}.swift`, `App/{AppEnvironment,AppConfig,DeepLink}.swift`, `Features/Profile/ProfilePages.swift:1310-1370`, `PrivacyInfo.xcprivacy`, `Tests/{SessionStoreTests,AppEnvironmentSessionTests}.swift`, `.github/workflows/ios-app.yml:39-48`.
- Milik lead (baca saja): `contracts/app-group-keys.md`, `ios/ShooShared/AppGroup.swift`, `ios/ShooExtension/{SafariWebExtensionHandler.swift,PrivacyInfo.xcprivacy,CLAUDE.md}`, `Resources/{background,lists,last-seen}.js`, `ios/project.yml:50-60,106-109`.
- Docs Apple (dibaca sebelum mulai, catat tanggal di log): "Sharing access to keychain items among a collection of apps" (access group dari `keychain-access-groups`, App ID, **dan** App Groups), "App privacy details on the App Store", App Store Connect Help "App information" (Privacy Policy URL, Support URL).

## Cek kelayakan (diverifikasi terhadap `origin/main` 2720b13, 31 Okt 2026)

| # | Butir | Bisa? | Temuan dari kode (file:baris) | Tindakan |
|---|---|---|---|---|
| C1 | Sinyal aktivitas server | Ya | `devices.last_seen_at not null default now()` (`init.sql:21`). Setiap request ber-token lewat `requireDevice` → `touchLastSeen` kalau > 5 menit (`http/auth.ts:42`, `db/repo/devices.ts:22-25`). Rute ber-token: `/blocklist`, `/devices/me*`, `/family/*`, `/scans*`, `/verdicts` (`routes/*.ts`, `grep requireDevice`) | `last_seen_at` = satu-satunya ukuran (K2) |
| C2 | Heartbeat extension | Ya, sudah tercakup | Extension mengunduh `GET /blocklist` tiap jam (`ShooExtension/Resources/lists.js:8`) dan `PATCH /devices/me { extensionLastSeenAt }` maks 1×/jam (`last-seen.js:40-44`, `ShooExtension/CLAUDE.md:17`); keduanya ber-token, jadi ikut menggeser `last_seen_at`. `ext_last_seen_at` diisi waktu dari klien (`routes/devices.ts:106-110`, `greatest` di `db/repo/devices.ts:92-94`), hanya bisa lewat request yang sudah menggeser `last_seen_at` | Tidak dipakai sebagai syarat tambahan |
| C3 | Push tidak menggeser `last_seen_at` | Ya | Guardian menerima push scan dan push cron (`cron/notifications.ts:56-87`) tanpa memanggil API. Guardian yang hanya membaca notifikasi terlihat "tidak aktif" | Aturan keluarga (K3) |
| C4 | Jalur hapus device | Ya, dipakai ulang | `deleteDevice` (`db/repo/devices.ts:155-173`): `family_links` dua sisi (`:159`), verdict milik/dibuat device + hitung ulang blocklist (`:160`, `verdicts.ts:119-137`), scan dikunci urut id lalu dihapus `returning` path (`:163-166`), device (`:167`), path ditombstone di transaksi yang sama (`:170`). Cascade FK menghapus `family_codes`, `join_attempts`, `push_log` (`init.sql:34,42,105`). Token APNs ada di baris `devices` (`init.sql:17`), jadi ikut hilang. Route menambah retry deadlock (`routes/devices.ts:187-193`) + hapus objek di `waitUntil` (`:197`) | 24a memanggil `deleteDevice` dengan cek ulang ambang di dalam transaksi (K7) |
| C5 | Objek R2/Storage device lama | Ya, hampir selalu kosong | Device yang tidak mengirim request ≥ K1 hari tidak membuat scan (POST `/scans` ber-token) → scan-nya sudah dihapus retensi 14 hari (`retention.ts:162,229`). Sisa path tetap ditombstone dan dihapus langkah tombstone run berikutnya (tombstone baru baru jatuh tempo setelah 10 menit, `tombstones.ts:17,48`); link sudah 404 karena baris hilang (P13) | Tidak memanggil store dari langkah baru |
| C6 | Anggaran Cron Free | Ya, ukur | 10 ms CPU + 50 subrequest per Cron (`ARCHITECTURE.md:62`). CPU retensi dengan 40 panggilan R2 belum terukur (`fase-21-monitoring.md:19`). Hitungan subrequest koneksi Hyperdrive **belum terverifikasi** (`log/fase-12.md:55` L6). `deleteDevice` = ±8 statement dalam satu transaksi | Batas per run (K6), satu SELECT kandidat, mode `dry_run` dulu |
| C7 | Index | Perlu | Tidak ada index pada `devices.last_seen_at` (`grep "create index" migrations`). Baris device sedikit sekarang, tetapi bisa tumbuh 1000/hari | Migrasi add-only `devices_last_seen` |
| C8 | Device yang dihapus kembali | Ya, sudah ditangani app | Token mati → 401 → `handleUnauthorized` → `markSessionExpired` → `SessionStore.clear()` + layar "Session expired" (`AppEnvironment.swift:229-245`, D-alief-C03). Extension tidak punya penanganan 401 (`grep 401 Resources/*.js` = 0 hasil di jalur API), jadi terus mengirim token mati sampai app dibuka; tiap request = `findByTokenHash` + `hitLight` + `hit` (`http/auth.ts:17-33`) | Risiko kecil (R3), usulan opsional ke Umar |
| C9 | Teks + test privasi | Ya | `privacy.ts:42` (EN) dan `:101` (ID); `test/privacy.test.ts:14` mengharuskan frasa "not deleted automatically" | 24a-2 ganti teks + test |
| C10 | Token di App Group | Ya | `SessionStore.save` menulis Keychain dulu lalu `device.token` App Group (`SessionStore.swift:52-63`); `clear()` menghapus keduanya (`:93-99`); handler extension membaca `device.token` dari App Group (`SafariWebExtensionHandler.swift:36-55`); JS menyimpan balasan `getSession` (termasuk token) hanya di memori selama 30 s (`background.js:14,29-42`), tidak di `storage.local`, dan tidak pernah memberikannya ke halaman lain (`ShooExtension/CLAUDE.md:24`) | Bentuk pesan native tidak berubah, hanya sumber token di Swift; perubahan sesi terlihat extension ≤ 30 s |
| C11 | Item Keychain sekarang | Ya | Query tanpa `kSecAttrAccessGroup` (`Keychain.swift:18-26`) → item masuk access group default app (App ID). `service` = bundle id app (`SessionStore.swift:129`); di extension `Bundle.main.bundleIdentifier` = `<bundle>.extension` (`project.yml:112`), jadi service itu **tidak** cocok dari extension | Service/account tetap (konstanta) + access group bersama |
| C12 | Entitlement Keychain sharing | Ya, kemungkinan tanpa entitlement baru | App dan extension sudah punya `com.apple.security.application-groups: [$(SHOO_APP_GROUP)]` (`project.yml:53,109`). Docs Apple "Sharing access to keychain items…" (dibaca 31 Okt 2026): nama App Group boleh dipakai sebagai access group Keychain "without adding them to the Keychain access groups entitlement", tanpa prefix team, dan tidak pernah menjadi group default (default tetap App ID). Jadi `kSecAttrAccessGroup = AppGroup.id` cukup secara dokumen. **Belum terverifikasi** di simulator (CI menandatangani ad-hoc supaya Keychain jalan, `ios-app.yml:39-48`) dan di iPhone | Spike S1 sebelum 24b-1 |
| C13 | Simulator test Keychain | Ya, cek | Test memakai service acak per test (`SessionStoreTests.swift:8-18`). Dengan access group, error `-34018` (entitlement hilang) mungkin muncul di CI | S1 menjalankan test dengan access group di simulator + perintah CI yang sama |
| C14 | Kontak placeholder | Ya | `privacy.ts:11-12`; `terms.ts` tanpa kontak (`grep CONTACT` = 0 hasil) | 24c-1 |
| C15 | URL kebijakan privasi | Ya | `GET /privacy` EN/ID statis (`privacy.ts`), dibuka app lewat `page("privacy")` (`ProfilePages.swift:1314-1318,1346`) dan dipakai cek extension (`Features/Onboarding/ExtensionSetup.swift:54`). URL publik: `https://shoo-api.afindo-mi01.workers.dev/privacy` (`AppConfig.swift:12`) | Siap dipakai di App Store Connect (`?lang=id` untuk lokalisasi ID) |
| C16 | Alamat dukungan app | **Rusak** | `supportEmail = "halo@shoo.id"` (`AppConfig.swift:30`), `shoo.id` NXDOMAIN (dig 31 Okt 2026) | Ganti segera ke mailbox K10 (24c-2, kecil) |
| C17 | Pindah domain | Bisa, luas | Host workers.dev tertanam di `AppConfig.swift:12,28`, `DeepLink.swift:16`, `Shoo.entitlements:9` (dari `project.yml:58-60`, komentar "Moves to our own domain later (TODO E6)"), `wrangler.jsonc:24` (`INVITE_BASE_URL`), `MockRepository.swift:167` | K11: tidak pindah sekarang |
| C18 | Manifest privasi | Ya, sebagian | App: Name, BrowsingHistory, OtherUserContent, DeviceID, semua linked, bukan tracking, App Functionality (`ios/ShooApp/PrivacyInfo.xcprivacy`). Extension: `NSPrivacyCollectedDataTypes` kosong, alasan di komentar `:3-5` (dideklarasikan sekali di app). Model iPhone/versi iOS, zona waktu, waktu terakhir aktif, hitungan blokir disimpan backend (`profile_redesign.sql:7-11`, `notification_settings.sql:20`) tetapi tidak dideklarasikan | K12 |
| C19 | Data layanan AI (lead) | Sebagian | `/privacy` menyebut ringkasan ke penyedia LLM tidak disimpan dan cache RDAP 7 hari (`privacy.ts:59,62-65`); `ai/src/rdap/cache.js:71` menyimpan domain + tanggal registrasi di KV. Log/penyimpanan lain di `ai/` **belum terverifikasi** | Pertanyaan di issue E6 |

## Peta dampak (semua sisi)

| Sisi | File | Ubah | Sub-fase | Isi |
|---|---|---|---|---|
| Backend | `src/cron/retention.ts` | Tambah | 24a-1 | Langkah `inactive_devices` (setelah `rate_limit_hits`, sebelum log `:141`), `RetentionResult.inactiveDevices`, `inactiveCandidates`, opsi test `inactiveMode`, `inactiveMax`, `now` |
| Backend | `src/db/repo/devices.ts` | Tambah | 24a-1 | `inactiveDeviceIds(sql, cutoffs, limit)` (SELECT kandidat, aturan K3/K4) + opsi `onlyIfInactiveBefore` di `deleteDevice` |
| Backend | `src/env.ts`, `test/env.d.ts` (`Cloudflare.Env`), `wrangler.jsonc` | Tambah | 24a-1 / 24a-2 | Var `INACTIVE_DEVICES` = `off` \| `dry_run` \| `delete` (default kode: `off`; `wrangler.jsonc`: `dry_run` di 24a-1, `delete` di 24a-2) |
| DB | `db/supabase/migrations/<YYYYMMDDHHMMSS>_inactive_devices.sql` + pgTAP | Tambah | 24a-1 | `create index devices_last_seen on devices(last_seen_at)` (add-only) |
| Backend | `src/routes/privacy.ts` | Ganti | 24a-2, 24c-1 | Kalimat device tidak aktif (EN/ID), `CONTACT`, tanggal "Last updated" |
| Backend | `src/routes/support.ts` (baru) + `app.ts` | Tambah | 24c-1 | `GET /support` EN/ID statis memakai `legalPage` (`privacy.ts:150`): kontak, cara hapus data, link `/privacy` |
| Backend test | `test/{retention,privacy,support,log-hygiene}.test.ts` | Ganti/Tambah | 24a, 24c-1 | Lihat Langkah kerja |
| App | `Data/Keychain.swift`, `Data/SessionStore.swift`, `App/AppEnvironment.swift` | Ganti | 24b-1, 24b-2 | `accessGroup`, service tetap, salin item lama ke item bersama (item lama tetap ditulis/dibaca sebagai cadangan), (24b-2) hapus item lama + berhenti menulis `device.token` |
| App | `App/AppConfig.swift:29-30`, `PrivacyInfo.xcprivacy` | Ganti | 24c-2 | Mailbox K10, tipe data K12 |
| App test | `Tests/{SessionStoreTests,AppEnvironmentSessionTests,KeychainMigrationTests}.swift` | Ganti/Tambah | 24b | Lihat Langkah kerja |
| Extension / kontrak | `contracts/app-group-keys.md:13,31`, `ShooExtension/SafariWebExtensionHandler.swift:40`, `ios/ShooShared/AppGroup.swift` (konstanta Keychain), mungkin `ios/project.yml` | **Usulan saja** | issue C22 | Dikerjakan Umar |
| Extension | `Resources/*.js` penanganan 401 | **Usulan saja, opsional** | issue terpisah (R3) | Umar |
| CI | tidak ada | — | — | Deploy lewat `backend.yml` seperti biasa (migrasi dulu, `:74-84`) |
| Privasi | `/privacy`, App Store Connect App Privacy | Ganti | 24a-2, 24c | Teks + label |
| Biaya Free | Cron | Kecil | 24a | 1 SELECT/hari + ≤ K6 transaksi; tanpa panggilan store; tanpa Cron Trigger baru (tetap 2 dari 5) |
| Biaya | domain / email | $0 kalau K10 = a, K11 = a | 24c | Domain sendiri = biaya tahunan (di luar Free) |
| Dokumen | `plan/alief/log/fase-24.md`, `DECISIONS.md`, `TODO.md` (E6, E7, C22), `SECURITY.md` P2/P12 | Ganti | close-out | Lewat PR docs |

## Keputusan

**K1 — Ambang tidak aktif (perlu jawaban Alief).** Pilihan: (a) 90 hari, (b) 180 hari, (c) 365 hari. **Rekomendasi (a) 90 hari.** Alasan: data minimum (P13); retensi scan 14 hari sudah jauh lebih pendek, jadi yang tersisa setelah 90 hari hanya profil + link keluarga + verdict; orang yang kembali hanya perlu onboarding ulang (D-alief-C03), riwayat 14 hari-nya memang sudah hilang. Dengan cloud hidup sejak ±21 Okt 2026, penghapusan pertama paling cepat ±19 Jan 2027, apa pun modenya.

**K2 — Apa yang dihitung aktif.** `last_seen_at` saja (C1, C2). `ext_last_seen_at` tidak menambah informasi (selalu datang lewat request ber-token) dan nilainya dari klien. Push yang diterima tidak dihitung (tidak ada sinyal server yang bisa dipercaya bahwa push dibaca).

**K3 — Aturan keluarga (perlu jawaban Alief).** Pilihan: (a) per device, sendiri-sendiri; (b) keluarga sebagai satu unit: device dalam keluarga dihapus hanya kalau **semua** anggota keluarga (Guardian + semua Protected-nya) tidak aktif ≥ K1; device tanpa keluarga dinilai sendiri; (c) seperti (b) tetapi Protected tidak aktif di keluarga aktif tetap dihapus. **Rekomendasi (b).** Alasan: Guardian yang hanya membaca push (C3) masih dilayani; Protected yang jarang membuka Safari tetap terlihat Guardian sebagai "extension mati" (`db/repo/families.ts:61`, push "Perlindungan mati" `notifications.ts:56-87`) dan Guardian bisa menghapusnya sendiri (GD-04). Menghapus anggota diam-diam dari keluarga yang aktif membingungkan Guardian. Kunci keluarga = `coalesce(l.guardian_id, d.id)` (satu Guardian per Protected, `init.sql:25`).

**K4 — Registrasi yang tidak pernah dipakai (perlu jawaban Alief).** Device tanpa keluarga yang `last_seen_at` masih dalam 1 jam dari `created_at` (tidak pernah memanggil API lagi setelah `POST /devices`, misalnya onboarding ditinggal). Pilihan: (a) ambang sama dengan K1; (b) 30 hari. **Rekomendasi (b).** Alasan: tidak ada data pengguna yang berguna, dan baris ini yang paling cepat menumpuk (1000/hari global). 30 hari tetap memberi waktu untuk app yang baru dipasang tetapi belum dibuka lagi.

**K5 — Pemberitahuan (perlu jawaban Alief).** Pilihan: (a) tidak ada push, cukup kebijakan privasi; (b) push peringatan ke device itu sendiri 7 hari sebelum hapus (kolom baru `inactive_warned_at`, teks EN/ID, kuota 40 push/run bersama cron notifikasi, `notifications.ts:16`); (c) push ke Guardian. **Rekomendasi (a).** Alasan: dengan K3 = (b) tidak ada anggota aktif yang perlu diberi tahu; push (b) butuh token APNs yang mungkin sudah mati dan menambah state + teks; yang hilang hanya profil yang bisa dibuat ulang. (c) tidak relevan kalau K3 = (b).

**K6 — Batas per run.** Maks **50 device per run**, satu transaksi `deleteDevice` per device, berhenti di error pertama (sisa → besok, `backlog = true`). Alasan: CPU cron 10 ms belum terukur (C6); jumlah kandidat nyata 0 sampai Jan 2027. Angka dinaikkan hanya setelah `wrangler tail` cron menunjukkan `outcome: ok`.

**K7 — Cek ulang di dalam transaksi.** `deleteDevice(sql, id, { onlyIfInactiveBefore })` mulai dengan `select set_config('lock_timeout', '3s', true)` (sekarang `deleteDevice` tidak memasang `lock_timeout`, `devices.ts:155-173`, jadi tanpa ini `55P03` tidak pernah muncul dan cron bisa menunggu kunci; retensi scan memakai 3 s, `retention.ts:155,250`), lalu `select 1 from devices where id = $1 and last_seen_at < $cutoff for update`; tidak ada baris → lewati (device kembali di antara SELECT dan DELETE). Aturan keluarga dicek ulang dengan query yang sama di transaksi. Urutan kunci baru (baris `devices` lebih dulu) diperiksa `ecc:database-reviewer` terhadap `touchLastSeen` (satu UPDATE autocommit) dan `joinFamily`; deadlock `40P01`/`55P03` → lewati device itu, tidak retry (besok dicoba lagi).

**K8 — Mode bertahap.** Var `INACTIVE_DEVICES`: `off` (default kode), `dry_run` (hanya menghitung kandidat), `delete`. 24a-1 men-deploy `dry_run`. 24a-2 mengubah ke `delete` setelah ≥ 7 run dry-run dengan `failed: 0` dan angka kandidat masuk akal (LANGKAH MANUAL 3). Log hanya hitungan: `{"event":"inactive_devices","mode","candidates","deleted","skipped","failed"}` (P6; tanpa id, karena id device ada di path objek). `candidates` = `count(*)` SQL kandidat tanpa batas (mode `dry_run` dan `delete`), bukan jumlah yang dibatasi K6. Hitungan **hanya di log**: `ops_jobs` fase 21 menyimpan `failed`/`backlog` saja (`fase-21-monitoring.md:279`); langkah ini yang gagal masuk `failed` lewat `step`. `backlog = true` hanya di mode `delete` saat batas K6 tercapai (dry-run tidak menyalakan alert `retention_backlog` fase 21).

**K9 — Penanganan 401 di extension (usulan opsional ke Umar).** Device yang dihapus lalu dipakai lagi hanya lewat Safari tetap mengirim token mati tiap jam (C8). Usulan: extension berhenti memanggil API setelah 401 sampai `getSession` mengembalikan token lain. Issue terpisah, prioritas rendah; sampai dijawab: app membersihkan sesi saat dibuka (D-alief-C03), counter `auth_fail_all` 1000/10 menit (`rateLimit.ts:46`) cukup besar untuk volume ini.

**K10 — Mailbox kontak (perlu jawaban Alief).** Pilihan: (a) alamat tim baru di layanan email gratis (mis. Gmail khusus tim, bukan alamat pribadi siapa pun); (b) Cloudflare Email Routing di domain sendiri (butuh K11 = b); (c) alamat pribadi Alief. **Rekomendasi (a)** sekarang, (b) kalau domain dibeli. (c) ditolak: alamat pribadi tidak boleh di halaman publik. Alief yang membuat mailbox dan memberi alamatnya; satu alamat untuk `/privacy`, `/support`, `AppConfig.supportEmail`, dan App Store Connect.

**K11 — Domain (perlu jawaban Alief, dan Umar kalau b).** Pilihan: (a) tetap `shoo-api.afindo-mi01.workers.dev` untuk Privacy Policy URL + Support URL; (b) beli domain, zone di Cloudflare, Workers Custom Domain, workers.dev tetap hidup sebagai alias. **Rekomendasi (a)** untuk TestFlight eksternal: $0, tidak ada perubahan app/entitlement. (b) menyentuh `AppConfig`, `DeepLink.inviteHosts`, `INVITE_BASE_URL`, AASA, dan `associated-domains` di `project.yml` (milik Umar) → fase sendiri kalau dipilih. Catatan: `.id` butuh identitas pemohon (persyaratan PANDI, **belum terverifikasi**), dan biaya domain di luar Free.

**K12 — Jawaban App Privacy (perlu jawaban Alief, isian di App Store Connect oleh pemegang akun).** Dasar: tabel inventaris di bawah. Rekomendasi: deklarasikan Name, Browsing History, Other User Content, Device ID (seperti P2) **ditambah** Identifiers › User ID (id device acak = id akun, karena Shoo tanpa login), Usage Data › Product Interaction (waktu terakhir aktif + hitungan blokir/peringatan yang dilihat Guardian), Location › Coarse Location (zona waktu) dan Other Data Types (model iPhone + versi iOS, bahasa, pengaturan notifikasi); semua Linked, App Functionality, tidak untuk tracking. Alasan: lebih aman mendeklarasikan lebih dari kurang; label yang kurang = alasan penolakan review. Dasar (docs "App privacy details", dibaca 31 Okt 2026): User ID = "assigned user ID … account ID", Device ID = "other device-level ID" (token APNs), Coarse Location = lokasi "with lower resolution than a latitude and longitude with three or more decimal places" (zona waktu tidak dari Location Services, jadi Coarse Location adalah pilihan hati-hati, bukan kewajiban pasti; Alief boleh memilih Other Data Types). Manifest app ditambah tipe yang sama (24c-2); manifest extension tetap kosong (dideklarasikan sekali di app, komentar `ShooExtension/PrivacyInfo.xcprivacy:3-5`), konfirmasi Umar di issue E6.

**K13 — Bentuk Keychain bersama (pertanyaan ke Umar, issue C22).** Rekomendasi: access group = `AppGroup.id` (tanpa entitlement baru, C12), service + account tetap (`"shoo.device-session"` / `"device-session"`, konstanta di `ShooShared` milik Umar; sampai ada, konstanta lokal di `Keychain.swift` yang nilainya sama), aksesibilitas tetap `AfterFirstUnlockThisDeviceOnly`; item lama app (service = bundle id, group default) tetap ditulis sampai 24b-2 supaya revert 24b-1 tidak memutus sesi. Handler membaca Keychain dulu, `device.token` App Group hanya sebagai cadangan untuk iPhone yang belum membuka app setelah update (app dan extension selalu satu bundle, jadi versi selalu sama; yang berbeda hanya apakah migrasi app sudah jalan). Catatan: target Live Activity juga punya App Group (`project.yml:135`), jadi ikut bisa membaca item; tidak membaca token hari ini.

## Inventaris data (draf, sumber jawaban App Privacy)

Diverifikasi ke skema `main` 31 Okt. "Linked" = bisa dihubungkan ke device/akun. Tidak ada yang dipakai untuk tracking, iklan, atau dijual. Data yang hanya tinggal di iPhone (Keychain, App Group, pengaturan app) tidak termasuk "collected" menurut Apple.

| Data | Disimpan di | Retensi | Linked? | Tracking? | Kategori App Store | Di manifest app? |
|---|---|---|---|---|---|---|
| Nama depan (`devices.name`) | Supabase Postgres (Singapura) | Sampai Delete account; setelah 24a: tidak aktif ≥ K1 | Ya | Tidak | Contact Info › Name | Ya |
| Avatar (`avatar_id`, pilihan 1–12) | Postgres | Sama | Ya | Tidak | Bukan tipe data (pilihan preset) | — |
| Id device acak + hash token (`devices.id`, `token_hash`) | Postgres | Sama | Ya | Tidak | Identifiers › User ID + Device ID (K12) | Device ID ya; User ID **tidak** → 24c-2 |
| Token APNs (`apns_token`) | Postgres; dikirim ke Apple | Sama | Ya | Tidak | Identifiers › Device ID | Ya (lewat Device ID, P2) |
| Model iPhone + versi iOS utama (`device_model`, `os_version`) | Postgres | Sama | Ya | Tidak | Other Data Types (K12) | **Tidak** → 24c-2 |
| Bahasa, zona waktu, pengaturan notifikasi + jam tenang | Postgres | Sama | Ya | Tidak | Other Data Types; zona waktu = Coarse Location (K12, pilihan hati-hati) | **Tidak** → 24c-2 |
| Terakhir aktif app/extension, tanggal daftar, total blokir/peringatan (`last_seen_at`, `ext_last_seen_at`, `created_at`, `blocked_total`, `warning_total`, `summary_sent_on`) | Postgres | Sama | Ya | Tidak | Usage Data › Product Interaction (K12) | **Tidak** → 24c-2 |
| Halaman berisiko skor ≥ 30: `https://host/path`, domain, judul, URL ikon, skor, alasan, waktu (`scans`) | Postgres | 14 hari (`retention.ts:162,229`) | Ya | Tidak | Browsing History | Ya |
| Salinan halaman (HTML gzip) | Cloudflare R2 privat | 14 hari, ≤ 15 hari kalau dipakai ulang, lifecycle 17 hari | Ya | Tidak | Other User Content | Ya |
| Ikon situs (salinan favicon) | R2 (baru) / Supabase Storage (lama) | Bersama scan, ≤ 15 hari | Ya | Tidak | Browsing History (bagian halaman yang ditandai) | Ya |
| Screenshot (build lama) | Supabase Storage | ≤ 15 hari; hilang setelah fase 20 | Ya | Tidak | Other User Content | Ya |
| Link keluarga (`family_links`: Guardian, Protected, pengaturan notifikasi anggota) | Postgres | Sampai putus / Delete account / 24a | Ya | Tidak | Bagian fungsi akun, tanpa kategori khusus (belum terverifikasi) | — |
| Keputusan Guardian (`verdicts`: domain, Safe/Not safe, nama Guardian, waktu) | Postgres | Sampai putus / Delete account / 24a (tidak ikut retensi 14 hari, D-alief-14) | Ya | Tidak | Browsing History | Ya |
| Kode keluarga (`family_codes`) | Postgres | Mati 30 menit, dihapus ≤ 1 hari | Ya (Guardian) | Tidak | Bukan data pengguna | — |
| Percobaan join (`join_attempts`: device, hash IP) | Postgres | 1 hari | Ya | Tidak | Keamanan; IP tidak disimpan mentah | — |
| Counter rate limit (`rate_limit_hits`: hash berkunci IP/device) | Postgres | 1 hari | Tidak | Tidak | Keamanan | — |
| Catatan push (`push_log`: tujuan, scan, hasil, waktu; tanpa isi) | Postgres | 14 hari | Ya | Tidak | Operasional | — |
| Tombstone objek (`storage_tombstones`: path berisi id device + scan) | Postgres | Sampai objek terhapus | Ya (lewat id) | Tidak | Operasional | — |
| Blocklist (`blocklist_entries`: domain, jumlah keluarga) | Postgres | Permanen | Tidak | Tidak | Bukan data pengguna | — |
| Ringkasan halaman ke penyedia LLM (domain, judul, nama field) | Tidak disimpan Shoo (`privacy.ts:62-65`) | — | Tidak | Tidak | Browsing History (pihak ketiga atas nama kita) | Tercakup |
| Cache umur domain RDAP (domain + tanggal registrasi) | KV layanan AI (lead) | 7 hari | Tidak | Tidak | Bukan data pengguna | — |
| Log Worker (event JSON, tanpa URL: `invocation_logs: false`, `wrangler.jsonc:11`) | Cloudflare Workers Logs | Sesuai retensi Cloudflare | Tidak (tanpa id/token, P6) | Tidak | — | — |

## Output

- 24a-1: langkah retensi `inactive_devices` (mode `dry_run` di cloud), `inactiveDeviceIds`, opsi cek ulang di `deleteDevice`, migrasi index + pgTAP, test.
- 24a-2: `INACTIVE_DEVICES: "delete"`, teks `/privacy` EN/ID, `privacy.test.ts` diperbarui.
- 24b-1: `KeychainItem.accessGroup`, item sesi di access group bersama dengan service tetap, salinan dari item lama (item lama tetap, jadi revert aman), test. App Group `device.token` tetap ditulis.
- 24b-2: app tidak lagi menulis `device.token` dan item lama, dan menghapus keduanya setelah item bersama terbaca; test `saveWritesEveryContractKey` + `onlyContractKeysAreWritten` mengikuti kontrak baru.
- 24c-1: `CONTACT` nyata, `GET /support`, test.
- 24c-2: `AppConfig.supportEmail` nyata, `PrivacyInfo.xcprivacy` ditambah tipe K12, `plutil -lint` lulus.
- Issue C22 (Umar) dan issue E6 (Umar) terkirim; issue K9 opsional.
- `log/fase-24.md`: hasil spike S1, angka dry-run, jawaban K, tabel inventaris final (dipindah ke `SECURITY.md` P2 lewat PR docs).

## Langkah kerja

### 24a-1 — langkah retensi, dry-run (TDD)

1. **Merah — kandidat.** `test/retention.test.ts` tambah `describe("inactive devices (E7)")` dengan device yang `last_seen_at` dimundurkan lewat SQL:
   - device tanpa keluarga 91 hari → kandidat; 89 hari → bukan;
   - registrasi tak terpakai (`last_seen_at = created_at`, 31 hari) → kandidat (K4 = b); yang sama 29 hari → bukan;
   - Guardian 200 hari + satu Protected aktif kemarin → keduanya bukan kandidat (K3 = b);
   - Guardian 91 hari + semua Protected 91 hari → semua kandidat;
   - Protected 91 hari, Guardian aktif → bukan kandidat.
   Fungsi uji: `inactiveDeviceIds(sql, { inactiveDays, unusedDays }, limit)`.
2. **Hijau.** `db/repo/devices.ts`: satu SELECT. Sketsa (diuji, bukan final):
   ```sql
   select d.id from devices d left join family_links l on l.protected_id = d.id   -- root keluarga = coalesce(l.guardian_id, d.id)
   where d.last_seen_at < now() - make_interval(days => ${inactiveDays})          -- index devices_last_seen
     and not exists (select 1 from devices g                                     -- Guardian (atau device itu sendiri) aktif
       where g.id = coalesce(l.guardian_id, d.id) and g.last_seen_at >= now() - make_interval(days => ${inactiveDays}))
     and not exists (select 1 from family_links m join devices p on p.id = m.protected_id   -- Protected lain di keluarga aktif
       where m.guardian_id = coalesce(l.guardian_id, d.id) and p.last_seen_at >= now() - make_interval(days => ${inactiveDays}))
   union                                                                            -- K4: registrasi tak terpakai, tanpa keluarga
   select d.id from devices d
   where d.last_seen_at < now() - make_interval(days => ${unusedDays}) + interval '1 hour'   -- redundan, agar index terpakai
     and d.created_at < now() - make_interval(days => ${unusedDays}) and d.last_seen_at < d.created_at + interval '1 hour'
     and not exists (select 1 from family_links f where f.protected_id = d.id or f.guardian_id = d.id)
   order by 1 limit ${limit}
   ```
   Catatan: Guardian tidak pernah punya baris `family_links` sebagai Protected, jadi root-nya = id-nya sendiri; satu Guardian per Protected (`init.sql:25`). Hitungan `candidates` = `select count(*) from (<SQL yang sama tanpa order/limit>) c` (K8). Cek `EXPLAIN` memakai `devices_last_seen`, PK `devices`, `family_links_guardian` (`init.sql:30`) dan PK `family_links`.
3. **Merah — mode.** Test: `inactiveMode: "off"` → tidak ada query kandidat, hasil 0; `"dry_run"` → `inactiveCandidates = n` (hitungan penuh walau `inactiveMax` lebih kecil, `backlog` tetap `false`), tidak ada yang terhapus, log `{"event":"inactive_devices","mode":"dry_run","candidates":n,...}` tanpa id (tambah ke `test/log-hygiene.test.ts`); `"delete"` → device + scan + verdict + link + push_log + join_attempts hilang, path ditombstone, blocklist `families` dihitung ulang (pola test hapus di `test/devices-me.test.ts`).
4. **Hijau.** `retention.ts`: `await step("inactive_devices", …)` setelah `rate_limit_hits` (`:130-139`). Mode dari `env.INACTIVE_DEVICES` (nilai tak dikenal = `off`, gagal tertutup), batas `opts.inactiveMax ?? 50` (K6). `env.ts` + `wrangler.jsonc` vars: `"INACTIVE_DEVICES": "dry_run"`.
5. **Merah — balapan.** Test: device kandidat, lalu `touchLastSeen` sebelum hapus → dilewati (`skipped = 1`), datanya utuh. Test: Protected keluarga kandidat, Guardian menjadi aktif di antara SELECT dan hapus → Protected dilewati.
6. **Hijau.** `deleteDevice(sql, id, opts?)`: dengan `onlyIfInactiveBefore`, transaksi diawali `lock_timeout` 3 s + cek ulang (K7) termasuk `max(last_seen_at)` keluarga; tanpa opsi = perilaku sekarang (test `DELETE /devices/me` tetap hijau tanpa diubah). Error 40P01/55P03 → `skipped`, lanjut device berikut; error lain → hentikan langkah, lempar seperti langkah lain (`retention.ts:81-88`).
7. **Migrasi.** `<YYYYMMDDHHMMSS>_inactive_devices.sql` (format seperti `20261029100000_page_replicas.sql`): `create index devices_last_seen on devices(last_seen_at);` + pgTAP `has_index`. `supabase test db` hijau.
8. **Review** `ecc:database-reviewer` (urutan kunci K7, rencana query) → `ecc:typescript-reviewer` → `ecc:security-reviewer` (log, gagal tertutup). Perbaiki, PR, merge, deploy lewat CI.

### 24a-2 — hidupkan hapus (setelah K1–K4 dijawab + LANGKAH MANUAL 3)

9. **Merah.** `privacy.test.ts:14`: ganti frasa "not deleted automatically" dengan frasa baru (mis. "90 days" sesuai K1) untuk EN dan ID; tanggal "29 October 2026" / "29 Oktober 2026" yang dikunci `privacy.test.ts:23,31` ikut diganti ke tanggal baru (juga di 24c-1).
10. **Hijau.** `privacy.ts:42,101`: EN "If no device in your family uses Shoo for 90 days, those devices and all their data are deleted automatically. A device that was registered but never used again is deleted after 30 days." (sesuaikan K1/K3/K4), ID setara; perbarui "Last updated". `wrangler.jsonc`: `"INACTIVE_DEVICES": "delete"`.
11. Review `ecc:security-reviewer` (teks = perilaku). PR, merge, deploy CI.

### 24b-1 — Keychain bersama, sisi app

12. **Spike S1 (lokal, tanpa commit).** Di simulator dan iPhone D-device: tulis item dengan `kSecAttrAccessGroup = AppGroup.id`, baca balik, baca atribut `kSecAttrAccessGroup`; jalankan `SessionStoreTests` dengan perintah CI (`ios-app.yml:44-48`). Catat: berhasil / `-34018`. Kalau gagal tanpa `keychain-access-groups` → tulis di issue C22 (Umar perlu entitlement) dan 24b-1 menunggu.
13. **Kirim issue C22** (teks di bawah) sebelum menulis kode yang memakai group.
14. **Merah.** `SessionStoreTests`: `tokenIsInTheSharedAccessGroup` (atribut `kSecAttrAccessGroup` = group uji), `tokenIsStoredThisDeviceOnly` tetap. Test baru `KeychainMigrationTests`: item lama (tanpa group, service = bundle id) → setelah `migrateLegacySession()` token ada di item baru **dan item lama tetap**; tidak ada item lama → tidak berubah; tulis ke group gagal (item bersama dengan access group yang bukan milik host test → `errSecMissingEntitlement` -34018; kalau S1 menunjukkan simulator ad-hoc tidak menolak group asing, pakai seam kecil: `SessionStore` menerima item bersama sebagai parameter yang di test dibuat selalu melempar) → `readToken` tetap mengembalikan token lama dan `checkStoredSession` tidak memanggil `clear()`; Keychain terkunci (`errSecInteractionNotAllowed`) → tidak menghapus apa pun, coba di peluncuran berikut; `clear()` menghapus kedua item.
15. **Hijau.** `KeychainItem` dapat `accessGroup: String?` (dimasukkan ke `query` kalau ada). `deviceSession` = service tetap K13 + `accessGroup: AppGroup.id`; `legacyDeviceSession` = definisi sekarang (`SessionStore.swift:129`). 24b-1 **menyalin, tidak memindah**: `save` menulis item bersama lalu item lama (gagal tulis item bersama = lempar, seperti sekarang); `readToken` membaca item bersama, lalu item lama kalau item bersama tidak ada; `clear()` menghapus keduanya. Error migrasi apa pun selain "tidak ada item" = tetap memakai item lama dan dicoba lagi peluncuran berikut, **tidak pernah** `clear()` (tanpa ini `-34018` membuat `checkStoredSession` menganggap sesi hilang, `AppEnvironment.swift:220-224`, dan semua pengguna lama dipaksa onboarding ulang). Query tanpa `kSecAttrAccessGroup` mencocokkan semua group app (docs Apple, 31 Okt 2026), aman karena service item lama (bundle id) berbeda dari `shoo.device-session`. `checkStoredSession` (`AppEnvironment.swift:211`, dipanggil saat start `:120`, sebelum request apa pun) memanggil migrasi sebelum `readToken`. App Group `device.token` **tetap** ditulis (kontrak belum berubah).
16. **Merah/hijau** `AppEnvironmentSessionTests`: restore backup (Keychain kosong, App Group penuh) tetap → "Session expired" + App Group dibersihkan.
17. Review `ecc:swift-reviewer` → `ecc:security-reviewer`. PR (tanpa perubahan UI → tanpa screenshot), merge.

### 24b-2 — buang token dari App Group (setelah jawaban + PR Umar merge)

18. **Merah.** `onlyContractKeysAreWritten` dan `saveWritesEveryContractKey` (`SessionStoreTests.swift:27` mengunci `deviceToken`) mengikuti kontrak baru (tanpa `device.token`); test baru: peluncuran dengan item bersama + `device.token` lama di App Group + item Keychain lama → key dan item lama dihapus.
19. **Hijau.** `SessionStore.save` tidak menulis `device.token` maupun item lama; `checkStoredSession` menghapus keduanya setelah item bersama terbaca; `appKeys` tetap memuat key itu untuk `clear()` selama satu rilis. Komentar `SessionStore.swift:5-8` diperbarui.
20. Review berurutan, PR, merge. Uji di iPhone: extension tetap memblokir dan mengirim scan setelah app diperbarui (LANGKAH MANUAL 5).

### 24c — kontak, support, label

21. **24c-2 butir pertama (kecil, segera setelah K10).** `AppConfig.supportEmail` = mailbox K10; hapus `TODO(sync:alief)` (`AppConfig.swift:29`). Test UI/unit yang mengunci alamat lama (`grep -rn "halo@shoo.id" ios/ShooApp`) ikut diganti. Nilai tampil di baris "Contact us" (`ProfilePages.swift:1364`) = perubahan UI → PR memuat screenshot before/after layar Tentang dari simulator "Shoo QA SE" `483B28B6-913A-4C3A-8A4C-0C7219022682`.
22. **Merah.** `privacy.test.ts`: kontak = mailbox K10 di EN dan ID, tidak ada lagi "coming before public release". `support.test.ts`: `GET /support` 200, `?lang=id`, header keamanan sama dengan `/privacy` (`test/security-headers.test.ts`), memuat mailbox + "Delete account" + link `/privacy`.
23. **Hijau.** `privacy.ts:11-12` `CONTACT` = mailbox; `routes/support.ts` memakai `legalPage` + `pageLanguage`; daftarkan di `app.ts`.
24. **Hijau 24c-2.** `PrivacyInfo.xcprivacy` tambah tipe K12; `plutil -lint`. Archive → Generate Privacy Report (LANGKAH MANUAL 7) cocok dengan tabel inventaris.
25. **Kirim issue E6** (teks di bawah). Review `ecc:security-reviewer`. PR backend dan app terpisah.

### Teks issue C22 (template Question, label `question`, assignee Umar)

Judul: `C22: token device dari App Group ke Keychain bersama`

> Konteks: `contracts/app-group-keys.md:13` menaruh `device.token` sebagai teks biasa di plist App Group. Plist itu ikut backup iPhone (tidak `ThisDeviceOnly`) dan bisa dipulihkan ke iPhone lain; app sendiri hanya memakai Keychain `AfterFirstUnlockThisDeviceOnly` dan membuang salinan App Group kalau Keychain kosong (D-alief-C03), tetapi extension memakai salinan itu sampai app dibuka. Bentuk pesan `getSession` tidak berubah; JS extension tidak perlu diubah.
>
> Usulan: token di satu item Keychain dengan `kSecAttrAccessGroup = AppGroup.id`. Menurut docs Apple, App Group sudah termasuk access group Keychain, jadi tidak perlu entitlement baru. Hasil spike saya: <S1>.
>
> Pertanyaan:
> 1. Setuju access group = `AppGroup.id`? Atau Umar lebih suka `keychain-access-groups` eksplisit di `project.yml` (app + extension)?
> 2. Boleh service/account tetap `"shoo.device-session"` / `"device-session"` sebagai konstanta di `ios/ShooShared/AppGroup.swift` (mis. `AppGroup.Keychain`)? Service sekarang = bundle id app, yang berbeda dari bundle id extension.
> 3. `sessionReply()` (`SafariWebExtensionHandler.swift:36-55`) membaca Keychain dulu, `device.token` App Group hanya cadangan untuk iPhone yang belum membuka app setelah update. Setuju?
> 4. Kontrak: baris `device.token` menjadi "deprecated, cadangan saja; app menghapusnya setelah token ada di Keychain bersama", lalu dihapus satu rilis kemudian?
> 5. Helper baca Keychain untuk extension: Umar tulis di `ShooExtension/`, atau `KeychainItem` dipindah ke `ShooShared/` (saya kirim isinya)?
>
> Sampai dijawab: app menulis token ke item bersama **dan** tetap menulis `device.token` (24b-1); tidak ada perubahan perilaku extension. Tidak mendesak untuk MVP.

### Teks issue E6 (template Question, label `question`, assignee Umar)

Judul: `E6: App Privacy App Store Connect + data extension/AI`

> Konteks: sebelum TestFlight eksternal / App Store kita butuh Privacy Policy URL, Support URL, dan jawaban App Privacy yang cocok dengan manifest. Draf inventaris data: `plan/alief/fase-24-privacy-data.md` (tabel "Inventaris data").
>
> Pertanyaan:
> 1. Layanan AI (`ai/`) menyimpan atau me-log apa pun per request selain cache RDAP (domain + tanggal, 7 hari)? Kalau ya: apa, berapa lama, terhubung ke device?
> 2. Manifest extension tetap tanpa `NSPrivacyCollectedDataTypes` (dideklarasikan sekali di manifest app)?
> 3. Siapa mengisi App Privacy, Privacy Policy URL, Support URL di App Store Connect (akun Umar, B8)? Usulan isian: <K12>, URL `https://shoo-api.afindo-mi01.workers.dev/privacy` dan `/support`.
> 4. Domain: kita tetap di workers.dev untuk TestFlight eksternal (K11). Kalau nanti pindah domain, `associated-domains` di `project.yml` perlu diubah. Ada keberatan?
>
> Sampai dijawab: `/privacy` dan `/support` hidup dengan mailbox tim; manifest app ditambah tipe data; tidak ada isian App Store Connect.

## LANGKAH MANUAL

1. [ ] Alief menjawab K1, K3, K4, K5 (24a), K10, K11, K12 (24c) di `log/fase-24.md`.
2. [ ] Alief membuat mailbox tim (K10) dan mencoba kirim + terima satu email dari alamat lain. Kredensial mailbox di password manager, tidak di repo.
3. [ ] Setelah 24a-1 ter-deploy: 7 run cron berturut-turut, tiap hari baca `wrangler tail` (atau Workers Logs) event `retention` (`failed: 0`) dan `inactive_devices` (`mode: dry_run`); bandingkan `candidates` dengan query baca saja di Supabase SQL editor:
   `select count(*) from (<SQL kandidat langkah 2 tanpa order/limit, ${inactiveDays} = 90, ${unusedDays} = 30>) c;` (harus sama dengan `candidates`) plus `select count(*) filter (where last_seen_at < now() - interval '90 days') as over_k1, count(*) as total from devices;` (batas atas tanpa aturan keluarga; hanya angka, tanpa id).
   Catat `cpuTime` cron dari tail.
4. [ ] Alief mengirim issue C22 dan E6 (dan K9 kalau setuju) lewat `gh issue create` dengan template Question; nomor issue dicatat di `TODO.md` C22/E6 lewat PR docs.
5. [ ] Setelah 24b-1 dan 24b-2: pasang build di iPhone yang sudah onboarded dengan build lama, **jangan buka app**, buka Safari → extension tetap memakai sesi (cadangan App Group); lalu buka app sekali → `device.token` hilang dari App Group, tunggu > 30 s (cache sesi extension, `background.js:14`), muat halaman baru → extension tetap jalan.
6. [ ] Pemegang akun App Store Connect (Umar, B8) mengisi Privacy Policy URL (EN, dan `?lang=id` untuk lokalisasi ID), Support URL, App Privacy sesuai K12. Screenshot isian disimpan di `plan/alief/qa/img/` tanpa data pribadi.
7. [ ] Xcode → Archive → Generate Privacy Report; bandingkan dengan tabel inventaris; simpan PDF di scratchpad, ringkasan di log.

## Verifikasi

```bash
(cd backend/db && supabase start && supabase test db)
pnpm -C backend/api run typecheck
pnpm -C backend/api exec vitest run retention devices-me privacy support log-hygiene security-headers
pnpm -C backend/api test
grep -rn "TODO(sync:alief)" backend/api/src/routes/privacy.ts ios/ShooApp/App/AppConfig.swift   # kosong setelah 24c
grep -rn "halo@shoo.id\|not deleted automatically" backend/api ios/ShooApp                      # kosong setelah 24a-2 + 24c-2
plutil -lint ios/ShooApp/PrivacyInfo.xcprivacy
(cd ios && xcodegen) && SIM_ID=483B28B6-913A-4C3A-8A4C-0C7219022682 && xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,id=$SIM_ID" -only-testing:ShooAppTests/SessionStoreTests -only-testing:ShooAppTests/KeychainMigrationTests -only-testing:ShooAppTests/AppEnvironmentSessionTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=   # "Shoo QA SE" iOS 26.5; flag ad-hoc = CI (ios-app.yml:48); ulangi tanpa empat flag terakhir (signing tim lokal)
curl -s https://shoo-api.afindo-mi01.workers.dev/privacy | grep -c "<mailbox K10>"   # setelah deploy 24c-1
curl -s -o /dev/null -w "%{http_code}\n" "https://shoo-api.afindo-mi01.workers.dev/support?lang=id"   # 200
```

## Kriteria selesai (DoD)

- [ ] 24a-1 merge + deploy CI; 7 run dry-run `failed: 0`; angka `candidates` sama dengan hitungan SQL kandidat di Supabase (LANGKAH MANUAL 3) dan ≤ `over_k1` + registrasi tak terpakai.
- [ ] Test retensi baru hijau: aturan K1/K3/K4, mode `off`/`dry_run`/`delete`, balapan (dilewati), hapus lengkap (scan, verdict + hitung ulang blocklist, link, push_log, join_attempts, tombstone).
- [ ] Log `inactive_devices` hanya hitungan (`log-hygiene` hijau).
- [ ] 24a-2: `INACTIVE_DEVICES = delete`; `/privacy` EN/ID menyebut aturan yang sama dengan kode.
- [ ] Issue C22 terkirim dengan hasil S1; 24b-1 merge; token di item bersama dengan `AfterFirstUnlockThisDeviceOnly` (test atribut); salinan item lama teruji, termasuk gagal tulis group (sesi tetap, tanpa "Session expired").
- [ ] 24b-2 merge hanya setelah kontrak + handler Umar merge; uji iPhone LANGKAH MANUAL 5 lulus.
- [ ] Tidak ada `TODO(sync:alief)` kontak tersisa; `halo@shoo.id` tidak ada di `backend/api` dan `ios` (grep Verifikasi); mailbox K10 terbukti menerima email.
- [ ] `GET /support` dan `/privacy` hidup di cloud dengan mailbox nyata (EN/ID).
- [ ] Manifest app memuat tipe K12; Privacy Report cocok dengan tabel inventaris; issue E6 terkirim.
- [ ] `log/fase-24.md`, `DECISIONS.md` (K1, K3, K4, K5, K10–K13), `TODO.md` (E6, E7 → selesai; C22 → nomor issue), `SECURITY.md` P2 (tabel inventaris) lewat PR docs.

## Risiko & rollback

- **R1 — Menghapus orang yang masih memakai Shoo.** Penyebab: aturan keluarga salah atau `last_seen_at` tidak bergeser di suatu jalur. Mitigasi: dry-run ≥ 7 hari, cek ulang di transaksi (K7), batas 50/run, test K3. Rollback: PR satu baris `INACTIVE_DEVICES: "off"` lewat CI (atau ubah var di dashboard sebagai darurat, lalu samakan `wrangler.jsonc`). Data yang sudah terhapus **tidak kembali** (P13, sengaja); pengguna onboarding ulang.
- **R2 — CPU cron.** Langkah baru + 40 panggilan R2 di run yang sama. Mitigasi: langkah terakhir, batas K6, tanpa panggilan store; error langkah tidak menghentikan langkah lain (`retention.ts:81-88`). Kalau tail menunjukkan `exceededCpu`: turunkan `inactiveMax` atau pindah ke cron notifikasi jam-an (tanpa Cron Trigger baru).
- **R3 — Extension dengan token mati.** Device yang dihapus lalu dipakai lewat Safari tanpa membuka app → 401 tiap jam (C8). Dampak: sedikit beban `auth_fail_all`; perlindungan lapis 1 tetap dari daftar yang tersimpan. Mitigasi: K9.
- **R4 — Keychain access group gagal di CI/iPhone.** `-34018` → sesi tidak tersimpan → onboarding gagal. Mitigasi: S1 sebelum kode; `save` tetap Keychain-dulu (`SessionStore.swift:52-54`), jadi gagal = tidak ada sesi setengah. Migrasi yang gagal tidak pernah membersihkan sesi: app tetap memakai item lama (langkah 15). Rollback: revert 24b-1; build lama membaca item lama, yang tetap ditulis sampai 24b-2, jadi sesi tidak putus. Item bersama yang tertinggal hanya bisa dibaca app/extension sendiri (`ThisDeviceOnly`) dan dihapus `clear()` build berikutnya.
- **R5 — Extension kehilangan token setelah update.** Kalau 24b-2 merge sebelum handler membaca Keychain. Mitigasi: urutan Prasyarat + LANGKAH MANUAL 5; app dan extension satu bundle.
- **R6 — Label privasi kurang.** Review App Store menolak atau label menyesatkan. Mitigasi: K12 mendeklarasikan lebih, Privacy Report, issue E6 untuk data AI.
- **R7 — Konflik dengan fase 20/21.** Semua mengubah `retention.ts`. Mitigasi: langkah baru di fungsi sendiri, satu `step(...)` di akhir; rebase setelah 20b/21a. Kalau fase 25c (Durable Object verdict) sudah merge: device yang dihapus cron juga harus memicu `close` socket seperti `DELETE /devices/me` (`fase-25-realtime-verdict.md:69,226`), atau dicatat sebagai dampak kosong (DO device itu tidak menerima event lagi).

## Catatan handoff

- E7 dan E6 berstatus "perlu keputusan Alief" di `TODO.md:106-107`; jangan mulai 24a-2 sebelum K1/K3/K4 tertulis di log.
- `last_seen_at` hanya bergeser kalau sudah > 5 menit (`devices.ts:23-24`); test yang memundurkan waktu harus menulis kolom langsung lewat SQL.
- `deleteDevice` tanpa opsi baru harus tetap sama persis: dipakai `DELETE /devices/me` dan `POST /devices/me/protected` (`routes/devices.ts:169,172,185`).
- Penghapusan nyata pertama paling cepat ±Jan 2027 (K1 = 90 hari); dry-run akan menunjukkan 0 sampai saat itu, kecuali registrasi tak terpakai (K4 = 30 hari, mulai ±21 Nov 2026).
- C22 tidak mendesak untuk MVP (`TODO.md` C22). Yang mendesak dari fase ini: alamat `halo@shoo.id` yang tidak ada (C16) — kerjakan 24c-2 butir 21 lebih dulu begitu K10 dijawab.
- Hal yang belum terverifikasi: App Group sebagai access group Keychain di simulator ad-hoc + iPhone (S1; secara dokumen sudah benar, docs Apple 31 Okt); subrequest Hyperdrive dan CPU langkah baru di cron; kategori Apple final untuk zona waktu dan model iPhone (K12 memilih deklarasi lebih); aturan PANDI `.id`; log/penyimpanan layanan AI.
- Rujukan masuk dari fase lain: fase 20 merujuk baris 7 (Prasyarat) dan 292 (R7), fase 21 merujuk baris 98 (K8); jaga isi di nomor baris itu kalau file ini diubah.

## Riwayat verifikasi

- Ronde 1 (31 Okt 2026): 17 temuan (0 kritis, 0 tinggi, 4 sedang, 13 rendah); diperbaiki: 24b-1 menyalin token ke item bersama tanpa menghapus item lama, `readToken` jatuh ke item lama, error migrasi tidak pernah `clear()` (sebelumnya `-34018` memaksa semua pengguna lama onboarding ulang lewat `AppEnvironment.swift:220-224`, dan "revert 24b-1" memutus sesi karena item lama sudah dihapus) + test gagal-group + R4 + DoD; dry-run menghitung SQL kandidat penuh dan query manual = bentuk hitung SQL yang sama (DoD lama tidak bisa tercapai karena aturan keluarga + batas 50); K8 disamakan dengan fase 21 K2 (hitungan hanya di log, `backlog` hanya mode `delete`); Verifikasi `xcodegen` + UDID "Shoo QA SE" + flag ad-hoc CI; rendah: screenshot before/after 24c-2, SQL kandidat ramah index, `lock_timeout` 3 s di K7, tanggal di `privacy.test.ts:23,31`, `test/env.d.ts`, cache sesi 30 s di C10 + LANGKAH MANUAL 5, docs Apple Keychain (App Group tanpa entitlement, query tanpa group) di C12/langkah 15, definisi App Privacy (User ID, Coarse Location) di K12 + inventaris, `saveWritesEveryContractKey`, lingkup grep `halo@shoo.id`, nama migrasi, fase 25c di R7, "cek C16"; semua di baris yang sama, jadi rujukan fase 20 (`:7,292`) dan fase 21 (`:98`) tetap tepat; dicatat tanpa diubah: tidak ada.
- Ronde 2 (31 Okt 2026): bagian yang diubah dibaca ulang (C10, C12, K7, K8, K12, K13, inventaris, Output, langkah 2–7, 9, 14–15, 18–19, 21, LANGKAH MANUAL 3/5, Verifikasi, DoD, R4, R7, handoff) + SQL kandidat dicek terhadap lima kasus test langkah 1; 1 temuan rendah (test gagal-group bergantung pada simulator ad-hoc menolak access group asing, belum pasti), diperbaiki dengan cadangan seam; 0 kritis/tinggi/sedang. Baris 7, 98, 292 tetap. Belum terverifikasi: App Group sebagai access group di simulator ad-hoc + iPhone (S1), subrequest Hyperdrive + CPU langkah baru di cron, kategori Apple final zona waktu/model iPhone, aturan PANDI `.id`, log/penyimpanan layanan AI.
