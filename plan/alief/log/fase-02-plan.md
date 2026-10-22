# Rencana fase 02 — Onboarding ON-01 … ON-05

> Ditulis agent track app (22 Okt 2026), dari "Langkah kerja" `fase-02-onboarding.md`. Branch `feat/ON-01-05-onboarding`, stacked on #14.
> `ecc:planner` tidak dipanggil terpisah: langkah kerja fase sudah rinci; rencana disusun langsung oleh agent sesi ini.

## Arsitektur

- `OnboardingModel` (`@Observable`, `@MainActor`): `step` = `splash → name → mode → greeting → (connect, Protected saja) → turnOnExtension → notifications → done`. Tidak ada transisi mundur ke `mode` setelah registrasi. Kalau app ditutup setelah registrasi (`settings.mode != nil`, onboarding belum selesai) → mulai lagi di `turnOnExtension`.
- `NameRule.validate(_:)`: trim spasi/baris baru, hitung grapheme (`String.count`), 1–20.
- Registrasi: `AppEnvironment.register(name:mode:)` → `repository.registerDevice` → `settings.chooseMode(_:)` (sekali saja; `mode` jadi `private(set)`). `finishOnboarding()` → `onboardingCompleted = true`. Swap `MockRepository` di `completeOnboarding` dihapus: mock sudah menjawab sebagai mode yang didaftarkan.
- `ExtensionStatus` lewat closure di `AppEnvironment` (`extensionStatus()`), DEBUG `-UITestExtensionActive YES` → selalu Active (tidak menulis App Group asli).
- `NotificationPermission` (protocol): `status()`, `request()`; implementasi `UNUserNotificationCenter`; DEBUG `-UITestNotifications granted|denied` → palsu (tanpa alert sistem di UI test). Granted → `registerForRemoteNotifications()` (token dikirim fase 15).
- `ExtensionSettingsOpener`: iOS 26.2+ `SFSafariSettings.openExtensionsSettings(forIdentifiers: [bundleId + ".extension"])` (API dicek di header SDK 27.1), gagal/di bawah 26.2 → `UIApplication.openSettingsURLString`. Tidak ada `App-prefs:`.
- `TutorialVideoPlayer`: `AVPlayerViewController` full screen, `allowsPictureInPicturePlayback`, `AVAudioSession .playback/.moviePlayback`, delegate restore. Placeholder `Resources/onboarding-tutorial-placeholder.mp4` (ffmpeg, beberapa detik).
- `NotificationReminderBanner` (Components): tampil di Shield kalau izin `denied`/`notDetermined` dan mode Guardian; tombol buka Settings notifikasi.

## Langkah (test dulu)

| # | Langkah | Test |
|---|---|---|
| 1 | `NameRule` | `OnboardingTests`: 0/21 ditolak, 1/20 diterima, trim, emoji = 1 grapheme |
| 2 | `AppSettings.chooseMode` sekali | `AppSettingsTests` |
| 3 | `OnboardingModel` + `AppEnvironment.register/finishOnboarding` | urutan Guardian/Protected, error registrasi, resume setelah registrasi, ON-04 Off tetap / Active lanjut, izin ditolak tetap selesai |
| 4 | Views ON-01..05 + Connect placeholder + banner | `OnboardingUITests`: Skip, alur Guardian penuh, Protected lewat Connect, tidak ada Back setelah mode, video membuka player, banner saat ditolak |
| 5 | String Catalog EN + ID untuk semua teks baru | `LocalizationTests.everyCatalogKeyHasAnIndonesianTranslation` |
| 6 | Gerbang UI `qa/img/ui-02/`, review swift + a11y + P1–P13, log, PR | – |
