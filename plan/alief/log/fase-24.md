# Log fase 24 — Privasi data (E7, C22, E6): sisi app

- **Model:** Claude Opus 5.5. Sesi track app fase 19–26 (D-alief-C29), 1 Nov 2026.
- **Plan:** `fase-24-privacy-data.md` (PR #207, branch `docs/alief-plan-19-26`).
- **Keputusan K:** rekomendasi R8 §c (D-alief-C29): K10 (a) mailbox tim gratis, K11 (a) tetap workers.dev, K12 deklarasi lebih (User ID, Product Interaction, Coarse Location, Other Data Types).
- Sub-fase backend (24a, 24c-1) milik sesi track be; log ini hanya sisi app.

## Status per sub-fase (app)

| Sub-fase | Branch | PR | Status |
|---|---|---|---|
| 24c-2 manifest privasi | `fix/E6-app-privacy` | lihat PR | [r] PR terbuka |
| 24c-2 `supportEmail` (bug d2) | – | – | [m] LANGKAH MANUAL 1: mailbox K10 belum ada |
| 24b-1 Keychain bersama | `feat/C22-shared-keychain` | – | [!] terblokir (lihat bawah) |
| 24b-2 | – | – | tertahan (jawaban + PR Umar C22) |

## 24c-2 — manifest privasi (1 Nov 2026)

- `ios/ShooApp/PrivacyInfo.xcprivacy`: tambah `NSPrivacyCollectedDataTypeUserID`, `…ProductInteraction`, `…CoarseLocation`, `…OtherDataTypes`. Semua Linked, tidak Tracking, App Functionality, sama dengan empat tipe lama. Komentar di kepala file menjelaskan isi tiap tipe (dasar: tabel "Inventaris data" fase 24).
- Manifest extension tidak disentuh (milik Umar; pertanyaan E6 no. 2 di PR).
- Test baru `Tests/PrivacyManifestTests.swift`: tracking `false`, domain tracking kosong, tepat 8 tipe, semua Linked + tidak Tracking + App Functionality.
- Tidak ada perubahan tampilan → tanpa screenshot.

VERIFIKASI_24C2

## 24c-2 `supportEmail` — dilewati (bug d2)

`AppConfig.supportEmail = "halo@shoo.id"` (`App/AppConfig.swift:29-30`) tetap. `shoo.id` NXDOMAIN (R8 §d no. 2). Fase 24 K10 meminta mailbox tim yang sudah terbukti menerima email; per 1 Nov 2026 belum ada (`TODO.md` E6/C32 masih `[ ]`, tidak ada entri DECISIONS). Mengganti ke alamat yang belum ada akan mengulang bug yang sama.

### LANGKAH MANUAL

1. [ ] Alief membuat mailbox tim (K10 a, layanan email gratis, bukan alamat pribadi siapa pun) lalu mengirim + menerima satu email uji dari alamat lain. Kredensial di password manager, tidak di repo.
2. [ ] Tulis alamatnya di `log/fase-24.md` (bagian ini). Sesi app berikutnya: `AppConfig.supportEmail` = alamat itu, hapus `TODO(sync:alief)` (`AppConfig.swift:29`), `grep -rn "halo@shoo.id" ios/ShooApp` kosong, screenshot before/after layar Tentang (EN + ID, terang + gelap), PR kecil `fix/E6-app-privacy-contact`. Alamat yang sama dipakai track be untuk `/privacy` + `/support` (24c-1).

## 24b-1 — Keychain bersama: terblokir

Fase 24 langkah 12 mewajibkan spike S1 **di simulator dan di iPhone** (item dengan `kSecAttrAccessGroup = AppGroup.id`, baca balik, `-34018` atau tidak) sebelum kode yang memakai group ditulis, karena hasil iPhone menentukan apakah Umar perlu entitlement `keychain-access-groups` (`project.yml`, milik Umar). Sesi ini tidak punya iPhone fisik. Aturan sesi: "24b-1 hanya kalau tidak butuh iPhone fisik / perubahan `ShooShared`" → **terblokir**. Konstanta service/account K13 juga diusulkan di `ShooShared/AppGroup.swift` (fallback konstanta lokal ada, jadi itu sendiri tidak memblokir).

Yang perlu untuk membuka: Alief menjalankan S1 di iPhone (langkah 12) dan menulis hasilnya di sini; lalu pertanyaan C22 (R8 §b no. 4) ikut di PR 24b-1 bagian `## Questions for Umar`.
