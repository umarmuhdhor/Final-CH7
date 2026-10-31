# Log fase 26 — Undangan setelah install (PR-03 P1, TODO E4)

- **Model:** Claude Opus 5.5. Sesi track app fase 19–26 (D-alief-C29), 1 Nov 2026.
- **Plan:** `fase-26-deferred-invite.md` (PR #207, branch `docs/alief-plan-19-26`).

## Status per sub-fase

| Sub-fase | Branch | PR | Status |
|---|---|---|---|
| d1 / U6 (tempel link ke kolom kode) | `fix/PR-03-invite-paste` | lihat PR | [r] PR terbuka |
| 26-0 spike | – | – | [ ] |
| 26a app | `feat/PR-03-deferred-invite-app` | – | [ ] |
| 26b backend | `feat/PR-03-deferred-invite-page` | – | bukan track app |

## d1 / U6 — `fix/PR-03-invite-paste` (1 Nov 2026)

Bug d1 di `plan/alief/ref/R8-fase-19-26-lintas.md` §d: setter `ConnectModel.code` (`ConnectModel.swift:60-65` di `main` aa976af) memfilter digit dari seluruh teks. Link `https://shoo-api.afindo-mi01.workers.dev/j/482193` yang ditempel jadi `014821` (digit `01` dari `mi01` ikut), lalu `code_invalid`. Seluruh pesan undangan dari `FamilyCodeModel.inviteText` juga jadi `014821`.

Perbaikan = U6 fase 26, dipisah jadi PR kecil (R8 §a baris 0), tanpa menunggu spike:

- Baru `Features/Pairing/InvitePaste.swift`: `InvitePaste.code(inText:)`. Teks dipecah per spasi/baris baru; tiap token ≤ 512 byte dipotong mulai dari `https://`/`http://` (untuk `Link:https://…` atau Markdown `[x](https://…)`), tanda baca/simbol di ujung dibuang, lalu `DeepLink(url:)` harus memberi `.join` dengan skema `https` (atau `http` ke Worker lokal di Debug, `DeepLink.isLocalWorker`). Token pertama yang lolos menang. `shoo://` tidak diterima di sini (hanya link halaman `/j/`).
- `ConnectModel.code`: teks yang semuanya digit tetap jalur lama. Ada non-digit → `InvitePaste.code(inText:)` dulu; tidak ada link undangan kita → filter digit lama (sama dengan `main`, juga untuk link asing; dicatat di komentar). Hasil hanya mengisi kolom, join tetap butuh tap Hubungkan (T11).
- Tidak ada perubahan tampilan (kolom yang sama, hanya isi hasil tempel yang berbeda), jadi gerbang UI/screenshot tidak berlaku. Tidak ada akses pasteboard baru, tidak ada log isi teks.
- 26a nanti menambah `InvitePaste.code(from:)` (ketat, K4) + `InvitePasteboard` ke file yang sama.

### Test

- `Tests/InvitePasteTests.swift` (baru, suite `InvitePasteTests`): 7 kasus link dalam teks → `482193`, 8 kasus tanpa link undangan → `nil`, token > 512 byte dilewati.
- `Tests/PairingTests.swift` `ConnectModelTests`: `pastedInviteLinkGivesItsCode` (4 kasus), `pastedInviteMessageGivesItsCode` (pesan EN + ID → `482193`, sebelumnya `014821`), `foreignLinkFallsBackToTheDigits`.

### Hasil verifikasi

Simulator sendiri "Shoo Track App 19-26" (iPhone 17, iOS 26.5, `D0936FB9-5C36-49B1-B57F-9D71814DC090`), Xcode lokal, 1 Nov 2026:

| Perintah | Hasil |
|---|---|
| `xcodebuild test … -only-testing:ShooAppTests/InvitePasteTests -only-testing:ShooAppTests/ConnectModelTests -only-testing:ShooAppTests/DeepLinkTests -only-testing:ShooAppTests/FamilyCodeModelTests` (sebelum perbaikan review) | 30 test / 4 suite lulus |
| `xcodebuild test … -only-testing:ShooAppTests -only-testing:ShooAppUITests/PairingUITests` (akhir) | `ShooAppTests` 468 test / 44 suite lulus (8,6 s); `PairingUITests` 6/6 lulus (92,8 s); `TEST SUCCEEDED` |

### Review

- `ecc:swift-reviewer`: 0 kritis/tinggi. Sedang 1 (link menempel teks lain, mis. `Link:https://…` → tetap `014821`) → diperbaiki (potong dari skema) + 2 kasus test. Sedang 2 (link asing jatuh ke filter digit, `https://evil.example/j/111111 482193` → `111111`) → dipertahankan sesuai U6 ("tidak ada → filter digit lama"), sekarang tertulis di komentar `InvitePaste.code(inText:)`; hanya mengisi kolom, tidak join. Rendah: kasus `http://shoo-api…` → `014821` rapuh (bergantung `AppConfig.apiBaseURL`) → dihapus.

### Privasi Apple (D-alief-40, SECURITY §3)

| Butir | Hasil |
|---|---|
| P8 pasteboard | Tidak ada baca pasteboard baru; teks sudah ditempel pengguna sendiri ke `TextField` |
| Log | Tidak ada log baru |
| Data keluar | Tidak berubah: hanya 6 digit ke `POST /family/join` setelah tap |
| P1–P7, P9–P13 | Tidak tersentuh |
